import Foundation
import GRDB

// Custom snake_case conversion for GRDB column naming
private func snakeCaseForEncoding(_ key: CodingKey) -> String {
    let string = key.stringValue
    var result = ""
    for (index, char) in string.enumerated() {
        if char.isUppercase {
            if index > 0 {
                result.append("_")
            }
            result.append(char.lowercased())
        } else {
            result.append(char)
        }
    }
    return result
}

private func snakeCaseForDecoding(_ string: String) -> CodingKey {
    var result = ""
    for (index, char) in string.enumerated() {
        if char == "_" {
            continue
        }
        let prevChar = index > 0 ? string[string.index(string.startIndex, offsetBy: index - 1)] : " "
        if prevChar == "_" {
            result.append(char.uppercased())
        } else {
            result.append(char)
        }
    }
    return AnyCodingKey(stringValue: result)!
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct Plan: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var daysPerWeek: Int
    var createdAt: Date
    var workoutDays: [WorkoutDay]?

    static let databaseTableName = "plans"
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .custom { snakeCaseForEncoding($0) }
    }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { snakeCaseForDecoding($0) }
    }
    static let workoutDays = hasMany(WorkoutDay.self, using: ForeignKey(["plan_id"]))
    
    enum Columns: String, ColumnExpression {
        case id, name, days_per_week, created_at
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["days_per_week"] = daysPerWeek
        container["created_at"] = createdAt
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct WorkoutDay: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var planId: Int64
    var dayNumber: Int
    var name: String
    var exercises: [Exercise]?

    static let databaseTableName = "workout_days"
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .custom { snakeCaseForEncoding($0) }
    }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { snakeCaseForDecoding($0) }
    }
    static let plan = belongsTo(Plan.self, using: ForeignKey(["plan_id"]))
    static let exercises = hasMany(Exercise.self, using: ForeignKey(["workout_day_id"]))
    
    enum Columns: String, ColumnExpression {
        case id, plan_id, day_number, name
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["plan_id"] = planId
        container["day_number"] = dayNumber
        container["name"] = name
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct Exercise: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var workoutDayId: Int64
    var name: String
    var sets: Int
    var reps: Int
    var targetDescription: String? = nil
    var position: Int

    static let databaseTableName = "exercises"
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .custom { snakeCaseForEncoding($0) }
    }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { snakeCaseForDecoding($0) }
    }
    static let workoutDay = belongsTo(WorkoutDay.self, using: ForeignKey(["workout_day_id"]))
    
    enum Columns: String, ColumnExpression {
        case id, workout_day_id, name, sets, reps, target_description, position
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct WorkoutSession: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var workoutDayId: Int64
    var dayName: String
    var startedAt: Date
    var completedAt: Date?
    var status: SessionStatus
    var exerciseLogs: [ExerciseLog]?
    // Loaded only for history list rows; not persisted on workout_sessions.
    var exerciseCount: Int?

    static let databaseTableName = "workout_sessions"
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .custom { snakeCaseForEncoding($0) }
    }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { snakeCaseForDecoding($0) }
    }
    static let workoutDay = belongsTo(WorkoutDay.self, using: ForeignKey(["workout_day_id"]))
    static let exerciseLogs = hasMany(ExerciseLog.self, using: ForeignKey(["session_id"]))
    
    enum Columns: String, ColumnExpression {
        case id, workout_day_id, day_name, started_at, completed_at, status
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["workout_day_id"] = workoutDayId
        container["day_name"] = dayName
        container["started_at"] = startedAt
        container["completed_at"] = completedAt
        container["status"] = status
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum SessionStatus: String, Codable, DatabaseValueConvertible, Hashable {
    case inProgress = "in_progress"
    case completed = "completed"
}

struct PersonalBest: Hashable {
    let weight: Double?
    let durationSeconds: Int?

    init?(weight: Double?, durationSeconds: Int?) {
        guard weight != nil || durationSeconds != nil else { return nil }
        self.weight = weight
        self.durationSeconds = durationSeconds
    }
}

struct ExerciseHistory: Hashable {
    let personalBest: PersonalBest
    let latestWeight: Double?
    let latestDurationSeconds: Int?
}

struct ExerciseLog: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var sessionId: Int64
    var exerciseId: Int64
    var exerciseName: String
    var plannedSets: Int
    var plannedReps: Int
    var targetDescription: String? = nil
    var weight: Double?
    var notes: String?
    var completed: Bool

    static let databaseTableName = "exercise_logs"
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .custom { snakeCaseForEncoding($0) }
    }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { snakeCaseForDecoding($0) }
    }
    static let session = belongsTo(WorkoutSession.self, using: ForeignKey(["session_id"]))
    static let exercise = belongsTo(Exercise.self, using: ForeignKey(["exercise_id"]))
    
    enum Columns: String, ColumnExpression {
        case id, session_id, exercise_id, exercise_name, planned_sets, planned_reps, target_description, weight, notes, completed
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The record for one set within an exercise. Keeping these separate from the
/// exercise log lets each set have its own weight and note.
struct SetLog: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var exerciseLogId: Int64
    var setNumber: Int
    var weight: Double?
    var durationSeconds: Int?
    var notes: String?

    static let databaseTableName = "set_logs"
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .custom { snakeCaseForEncoding($0) }
    }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { snakeCaseForDecoding($0) }
    }

    enum Columns: String, ColumnExpression {
        case id, exercise_log_id, set_number, weight, duration_seconds, notes
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["exercise_log_id"] = exerciseLogId
        container["set_number"] = setNumber
        container["weight"] = weight
        container["duration_seconds"] = durationSeconds
        container["notes"] = notes
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
