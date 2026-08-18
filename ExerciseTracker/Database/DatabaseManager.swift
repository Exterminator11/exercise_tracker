import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()
    
    let dbQueue: DatabaseQueue
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let databaseURL = documentsPath.appendingPathComponent("ExerciseTracker.sqlite")
        
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            try AppDatabaseMigrator.shared.migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    // Internal initializer for testing
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    func read<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }
    
    func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
    
    func inTransaction<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        var result: T?
        try dbQueue.inTransaction(.immediate) { db in
            result = try block(db)
            return .commit
        }
        return result!
    }
}

extension DatabaseManager {
    func fetchInitialState() throws -> (plans: [Plan], selectedPlan: Plan?, inProgressSession: WorkoutSession?) {
        try inTransaction { db in
            // Older app versions could leave a fully checked-off workout marked
            // in progress if the app was terminated before the final status write.
            // It is a completed workout, not a resume candidate.
            try db.execute(sql: """
                UPDATE workout_sessions
                SET status = ?, completed_at = COALESCE(completed_at, ?)
                WHERE status = ?
                  AND EXISTS (SELECT 1 FROM exercise_logs el WHERE el.session_id = workout_sessions.id)
                  AND NOT EXISTS (
                    SELECT 1 FROM exercise_logs el
                    WHERE el.session_id = workout_sessions.id AND el.completed = 0
                  )
                """, arguments: [SessionStatus.completed.rawValue, Date(), SessionStatus.inProgress.rawValue])
            // Clean up legacy duplicate sessions. A completed instance of the
            // same workout day that finished after this session started proves
            // this older in-progress row is stale, while a newly started repeat
            // remains resumable because its started_at is later.
            try db.execute(sql: """
                DELETE FROM workout_sessions
                WHERE status = ?
                  AND EXISTS (
                    SELECT 1 FROM workout_sessions completed
                    WHERE completed.workout_day_id = workout_sessions.workout_day_id
                      AND completed.status = ?
                      AND completed.completed_at >= workout_sessions.started_at
                  )
                """, arguments: [SessionStatus.inProgress.rawValue, SessionStatus.completed.rawValue])
            let plans = try self.fetchPlanSummaries(in: db)
            let selectedPlan = try plans.first.flatMap { try self.fetchPlanWithDays(in: db, id: $0.id!) }
            let inProgressSession = try WorkoutSession
                .filter(WorkoutSession.Columns.status == SessionStatus.inProgress.rawValue)
                .order(WorkoutSession.Columns.started_at.desc, WorkoutSession.Columns.id.desc)
                .fetchOne(db)
            return (plans, selectedPlan, inProgressSession)
        }
    }

    func fetchPlan() throws -> Plan? {
        try read { db in
            try Plan.fetchOne(db, sql: "SELECT * FROM plans ORDER BY created_at DESC LIMIT 1")
        }
    }
    
    func fetchPlanWithDays() throws -> Plan? {
        try read { db in
            try self.fetchMostRecentPlanWithDays(in: db)
        }
    }

    func fetchPlanWithDays(_ planId: Int64) throws -> Plan? {
        try read { db in
            try self.fetchPlanWithDays(in: db, id: planId)
        }
    }

    func fetchPlanSummaries() throws -> [Plan] {
        try read { db in
            try self.fetchPlanSummaries(in: db)
        }
    }

    func fetchAllPlansWithDays() throws -> [Plan] {
        try read { db in
            try self.fetchAllPlansWithDays(in: db)
        }
    }
    
    func createPlan(name: String, daysPerWeek: Int) throws -> Plan {
        try write { db in
            var plan = Plan(id: nil, name: name, daysPerWeek: daysPerWeek, createdAt: Date())
            try plan.insert(db)
            return plan
        }
    }

    func importWorkoutPlan(_ importedPlan: ImportedWorkoutPlan) throws -> Plan {
        let trainingDays = importedPlan.trainingDays
        guard !trainingDays.isEmpty else { throw WorkoutPlanImportError.noTrainingDays }

        return try inTransaction { db in
            var plan = Plan(
                id: nil,
                name: importedPlan.metadata.name,
                daysPerWeek: trainingDays.count,
                createdAt: Date()
            )
            try plan.insert(db)

            for (dayIndex, entry) in trainingDays.enumerated() {
                var day = WorkoutDay(
                    id: nil,
                    planId: plan.id!,
                    dayNumber: dayIndex + 1,
                    name: entry.session.sessionName
                )
                try day.insert(db)

                for exercise in (entry.session.exercises ?? []).sorted(by: { $0.order < $1.order }) {
                    let target = exercise.target
                    var savedExercise = Exercise(
                        id: nil,
                        workoutDayId: day.id!,
                        name: exercise.name,
                        sets: max(1, exercise.sets),
                        reps: max(1, target.reps),
                        targetDescription: target.description,
                        position: max(0, exercise.order - 1)
                    )
                    try savedExercise.insert(db)
                }
            }
            return plan
        }
    }
    
    func updatePlan(_ plan: Plan) throws {
        try write { db in
            try plan.update(db)
        }
    }
    
    func deletePlan(_ plan: Plan) throws {
        guard let id = plan.id else { return }
        try inTransaction { db in
            // A running workout belongs to the editable plan, unlike completed
            // sessions which are retained as history snapshots.
            try db.execute(sql: """
                DELETE FROM exercise_logs
                WHERE session_id IN (
                    SELECT ws.id
                    FROM workout_sessions ws
                    JOIN workout_days wd ON wd.id = ws.workout_day_id
                    WHERE wd.plan_id = ? AND ws.status = ?
                )
                """, arguments: [id, SessionStatus.inProgress.rawValue])
            try db.execute(sql: """
                DELETE FROM workout_sessions
                WHERE id IN (
                    SELECT ws.id
                    FROM workout_sessions ws
                    JOIN workout_days wd ON wd.id = ws.workout_day_id
                    WHERE wd.plan_id = ? AND ws.status = ?
                )
                """, arguments: [id, SessionStatus.inProgress.rawValue])
            try db.execute(sql: "DELETE FROM plans WHERE id = ?", arguments: [id])
        }
    }
    
    func createWorkoutDay(planId: Int64, dayNumber: Int, name: String) throws -> WorkoutDay {
        try write { db in
            var day = WorkoutDay(id: nil, planId: planId, dayNumber: dayNumber, name: name)
            try day.insert(db)
            return day
        }
    }
    
    func updateWorkoutDay(_ day: WorkoutDay) throws {
        try write { db in
            try day.update(db)
        }
    }
    
    func deleteWorkoutDay(_ day: WorkoutDay) throws {
        try write { db in
            if let id = day.id {
                try db.execute(sql: "DELETE FROM workout_days WHERE id = ?", arguments: [id])
            }
        }
    }
    
    func createExercise(workoutDayId: Int64, name: String, sets: Int, reps: Int, targetDescription: String? = nil, position: Int) throws -> Exercise {
        try write { db in
            var exercise = Exercise(id: nil, workoutDayId: workoutDayId, name: name, sets: sets, reps: reps, targetDescription: targetDescription, position: position)
            try exercise.insert(db)
            return exercise
        }
    }
    
    func updateExercise(_ exercise: Exercise) throws {
        try write { db in
            try exercise.update(db)
        }
    }
    
    func deleteExercise(_ exercise: Exercise) throws {
        try write { db in
            if let id = exercise.id {
                try db.execute(sql: "DELETE FROM exercises WHERE id = ?", arguments: [id])
            }
        }
    }
    
    func reorderExercises(_ exercises: [Exercise]) throws {
        try write { db in
            for (index, exercise) in exercises.enumerated() {
                var ex = exercise
                ex.position = index
                try ex.update(db)
            }
        }
    }
    
    func createWorkoutSession(workoutDayId: Int64, dayName: String, exercises: [Exercise]) throws -> WorkoutSession {
        try write { db in
            var session = WorkoutSession(
                id: nil,
                workoutDayId: workoutDayId,
                dayName: dayName,
                startedAt: Date(),
                completedAt: nil,
                status: .inProgress
            )
            try session.insert(db)
            
            for exercise in exercises {
                var log = ExerciseLog(
                    id: nil,
                    sessionId: session.id!,
                    exerciseId: exercise.id!,
                    exerciseName: exercise.name,
                    plannedSets: exercise.sets,
                    plannedReps: exercise.reps,
                    targetDescription: exercise.targetDescription,
                    weight: nil,
                    notes: nil,
                    completed: false
                )
                try log.insert(db)

                for setNumber in 1...exercise.sets {
                var setLog = SetLog(
                        id: nil,
                        exerciseLogId: log.id!,
                    setNumber: setNumber,
                    weight: nil,
                    durationSeconds: nil,
                    notes: nil
                    )
                    try setLog.insert(db)
                }
            }
            
            return session
        }
    }
    
    func fetchInProgressSession() throws -> WorkoutSession? {
        try read { db in
            try WorkoutSession
                .filter(WorkoutSession.Columns.status == SessionStatus.inProgress.rawValue)
                .order(WorkoutSession.Columns.started_at.desc, WorkoutSession.Columns.id.desc)
                .fetchOne(db)
        }
    }
    
    func fetchSessionWithLogs(_ sessionId: Int64) throws -> (WorkoutSession, [ExerciseLog])? {
        try read { db in
            guard let session = try WorkoutSession.fetchOne(db, key: sessionId) else { return nil }
            let logs = try ExerciseLog
                .filter(ExerciseLog.Columns.session_id == sessionId)
                .fetchAll(db)
            return (session, logs)
        }
    }
    
    func updateExerciseLog(_ log: ExerciseLog) throws {
        try write { db in
            try log.update(db)
        }
    }

    func fetchSetLogs(forSessionId sessionId: Int64) throws -> [SetLog] {
        try read { db in
            try SetLog.fetchAll(db, sql: """
                SELECT sl.*
                FROM set_logs sl
                JOIN exercise_logs el ON el.id = sl.exercise_log_id
                WHERE el.session_id = ?
                ORDER BY sl.exercise_log_id, sl.set_number
                """, arguments: [sessionId])
        }
    }

    func updateSetLog(_ setLog: SetLog) throws {
        try write { db in
            try setLog.update(db)
        }
    }

    func updateWorkoutLogs(_ exerciseLogs: [ExerciseLog], setLogs: [SetLog]) throws {
        try inTransaction { db in
            for log in exerciseLogs {
                try log.update(db)
            }
            for setLog in setLogs {
                try setLog.update(db)
            }
        }
    }
    
    func completeSession(_ sessionId: Int64) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE workout_sessions SET status = ?, completed_at = ? WHERE id = ?",
                arguments: [SessionStatus.completed.rawValue, Date(), sessionId]
            )
        }
    }

    func discardSession(_ sessionId: Int64) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM workout_sessions WHERE id = ? AND status = ?", arguments: [sessionId, SessionStatus.inProgress.rawValue])
        }
    }

    func deleteCompletedSession(_ sessionId: Int64) throws {
        try inTransaction { db in
            try db.execute(sql: """
                DELETE FROM set_logs
                WHERE exercise_log_id IN (
                    SELECT id FROM exercise_logs WHERE session_id = ?
                )
                """, arguments: [sessionId])
            try db.execute(sql: "DELETE FROM exercise_logs WHERE session_id = ?", arguments: [sessionId])
            try db.execute(
                sql: "DELETE FROM workout_sessions WHERE id = ? AND status = ?",
                arguments: [sessionId, SessionStatus.completed.rawValue]
            )
        }
    }
    
    func fetchCompletedSessions(limit: Int? = nil, offset: Int = 0) throws -> [WorkoutSession] {
        try read { db in
            var request = WorkoutSession
                .filter(WorkoutSession.Columns.status == SessionStatus.completed.rawValue)
                .order(WorkoutSession.Columns.completed_at.desc, WorkoutSession.Columns.id.desc)
            if let limit {
                request = request.limit(limit, offset: offset)
            }
            var sessions = try request.fetchAll(db)
            let ids = sessions.compactMap(\.id)
            guard !ids.isEmpty else { return sessions }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let counts = try Row.fetchAll(db, sql: """
                SELECT session_id, COUNT(*) AS exercise_count
                FROM exercise_logs
                WHERE session_id IN (\(placeholders))
                GROUP BY session_id
                """, arguments: StatementArguments(ids))
            let countBySessionID = Dictionary(uniqueKeysWithValues: counts.map { row in
                (row["session_id"] as Int64, row["exercise_count"] as Int)
            })
            for index in sessions.indices {
                sessions[index].exerciseCount = countBySessionID[sessions[index].id!] ?? 0
            }
            return sessions
        }
    }
    
    func fetchLastCompletedSession() throws -> WorkoutSession? {
        try read { db in
            try WorkoutSession
                .filter(WorkoutSession.Columns.status == SessionStatus.completed.rawValue)
                .order(WorkoutSession.Columns.completed_at.desc)
                .fetchOne(db)
        }
    }
    
    func fetchPreviousWeight(forExerciseId exerciseId: Int64) throws -> Double? {
        try read { db in
            try Double.fetchOne(db, sql: """
                SELECT COALESCE(sl.weight, el.weight)
                FROM exercise_logs el
                JOIN workout_sessions ws ON ws.id = el.session_id
                LEFT JOIN set_logs sl ON sl.exercise_log_id = el.id
                WHERE el.exercise_id = ?
                  AND el.completed = 1
                  AND COALESCE(sl.weight, el.weight) IS NOT NULL
                  AND ws.status = ?
                ORDER BY ws.completed_at DESC, ws.id DESC, sl.set_number DESC
                LIMIT 1
                """, arguments: [exerciseId, SessionStatus.completed.rawValue])
        }
    }

    func fetchExerciseHistory(forExerciseNames names: [String]) throws -> [String: ExerciseHistory] {
        guard !names.isEmpty else { return [:] }
        return try read { db in
            let placeholders = Array(repeating: "?", count: names.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                WITH matching_sets AS (
                    SELECT lower(trim(el.exercise_name)) AS exercise_name,
                           sl.weight,
                           sl.duration_seconds,
                           ROW_NUMBER() OVER (
                               PARTITION BY lower(trim(el.exercise_name))
                               ORDER BY ws.completed_at DESC, ws.id DESC, sl.set_number DESC
                           ) AS recency_rank
                    FROM exercise_logs el
                    JOIN workout_sessions ws ON ws.id = el.session_id
                    LEFT JOIN set_logs sl ON sl.exercise_log_id = el.id
                    WHERE ws.status = ? AND el.completed = 1
                      AND lower(trim(el.exercise_name)) IN (\(placeholders))
                )
                SELECT exercise_name,
                       MAX(weight) AS max_weight,
                       MAX(duration_seconds) AS max_duration,
                       MAX(CASE WHEN recency_rank = 1 THEN weight END) AS latest_weight,
                       MAX(CASE WHEN recency_rank = 1 THEN duration_seconds END) AS latest_duration
                FROM matching_sets
                GROUP BY exercise_name
                """, arguments: StatementArguments([SessionStatus.completed.rawValue] + names))
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                let name: String = row["exercise_name"]
                let weight: Double? = row["max_weight"]
                let duration: Int? = row["max_duration"]
                guard let best = PersonalBest(weight: weight, durationSeconds: duration) else { return nil }
                let latestWeight: Double? = row["latest_weight"]
                let latestDuration: Int? = row["latest_duration"]
                return (name, ExerciseHistory(personalBest: best, latestWeight: latestWeight, latestDurationSeconds: latestDuration))
            })
        }
    }
    
    func fetchCompletedWorkoutsCount() throws -> Int {
        try read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_sessions WHERE status = ?", arguments: [SessionStatus.completed.rawValue]) ?? 0
        }
    }
    
    func fetchSessionDetail(_ sessionId: Int64) throws -> (WorkoutSession, [ExerciseLog])? {
        try read { db in
            guard let session = try WorkoutSession.fetchOne(db, key: sessionId) else { return nil }
            let logs = try ExerciseLog
                .filter(ExerciseLog.Columns.session_id == sessionId)
                .fetchAll(db)
            return (session, logs)
        }
    }
    
    func fetchNextWorkoutDay(for plan: Plan) throws -> WorkoutDay? {
        let lastSession = try fetchLastCompletedSession()
        
        if let lastSession = lastSession,
           let days = plan.workoutDays,
           let lastDay = days.first(where: { $0.id == lastSession.workoutDayId }) {
            let nextDayNumber = (lastDay.dayNumber % plan.daysPerWeek) + 1
            return days.first { $0.dayNumber == nextDayNumber }
        }
        
        return plan.workoutDays?.first { $0.dayNumber == 1 }
    }
}

private extension DatabaseManager {
    func fetchMostRecentPlanWithDays(in db: Database) throws -> Plan? {
        guard let id = try fetchPlanSummaries(in: db).first?.id else { return nil }
        return try fetchPlanWithDays(in: db, id: id)
    }

    func fetchPlanSummaries(in db: Database) throws -> [Plan] {
        try Plan.fetchAll(db, sql: "SELECT * FROM plans ORDER BY created_at DESC, id DESC")
    }

    func fetchPlanWithDays(in db: Database, id: Int64) throws -> Plan? {
        guard var plan = try Plan.fetchOne(db, key: id) else { return nil }
        var days = try WorkoutDay
            .filter(WorkoutDay.Columns.plan_id == id)
            .order(WorkoutDay.Columns.day_number)
            .fetchAll(db)
        let dayIds = days.compactMap(\.id)
        let exercisesByDay = Dictionary(grouping: try Exercise.filter(dayIds.contains(Exercise.Columns.workout_day_id)).fetchAll(db), by: \.workoutDayId)
        for dayIndex in days.indices {
            days[dayIndex].exercises = (exercisesByDay[days[dayIndex].id!] ?? [])
                .sorted { $0.position < $1.position }
        }
        plan.workoutDays = days
        return plan
    }

    func fetchAllPlansWithDays(in db: Database) throws -> [Plan] {
        var plans = try Plan.fetchAll(db, sql: "SELECT * FROM plans ORDER BY created_at DESC, id DESC")
        let daysByPlan = Dictionary(grouping: try WorkoutDay.fetchAll(db), by: \.planId)
        let exercisesByDay = Dictionary(grouping: try Exercise.fetchAll(db), by: \.workoutDayId)
        for planIndex in plans.indices {
            var days = daysByPlan[plans[planIndex].id!] ?? []
            days.sort { $0.dayNumber < $1.dayNumber }
            for dayIndex in days.indices {
                days[dayIndex].exercises = (exercisesByDay[days[dayIndex].id!] ?? [])
                    .sorted { $0.position < $1.position }
            }
            plans[planIndex].workoutDays = days
        }
        return plans
    }
}
