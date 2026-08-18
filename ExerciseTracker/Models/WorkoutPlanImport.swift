import Foundation

struct ImportedWorkoutPlan: Decodable {
    struct Metadata: Decodable {
        let name: String
        let daysPerWeek: Int

        enum CodingKeys: String, CodingKey {
            case name
            case daysPerWeek = "days_per_week"
        }
    }

    struct Session: Decodable {
        let sessionName: String
        let type: String
        let exercises: [Exercise]?

        enum CodingKeys: String, CodingKey {
            case sessionName = "session_name"
            case type, exercises
        }
    }

    struct Exercise: Decodable {
        let order: Int
        let name: String
        let sets: Int
        let repRange: [Int]?
        let durationSecondsRange: [Int]?
        let metricType: String?

        enum CodingKeys: String, CodingKey {
            case order, sets
            case name = "exercise"
            case repRange = "rep_range"
            case durationSecondsRange = "duration_seconds_range"
            case metricType = "metric_type"
        }

        var target: (reps: Int, description: String) {
            if let durationSecondsRange, !durationSecondsRange.isEmpty {
                let values = durationSecondsRange.sorted()
                let description = values.count > 1
                    ? "\(values[0])–\(values[values.count - 1]) sec"
                    : "\(values[0]) sec"
                return (values.last ?? 1, description)
            }
            let values = (repRange ?? [1]).sorted()
            let description = values.count > 1
                ? "\(values[0])–\(values[values.count - 1]) reps"
                : "\(values[0]) reps"
            return (values.last ?? 1, description)
        }
    }

    let metadata: Metadata
    let schedule: [String: Session]

    enum CodingKeys: String, CodingKey {
        case metadata = "program_metadata"
        case schedule
    }

    var trainingDays: [(weekday: String, session: Session)] {
        let weekdayOrder = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return weekdayOrder.compactMap { weekday in
            guard let session = schedule[weekday],
                  session.type == "lifting",
                  !(session.exercises ?? []).isEmpty else { return nil }
            return (weekday, session)
        }
    }
}

enum WorkoutPlanImportError: LocalizedError {
    case noTrainingDays

    var errorDescription: String? {
        switch self {
        case .noTrainingDays:
            return "The file does not contain any lifting sessions with exercises."
        }
    }
}
