import Foundation
import GRDB

struct AppDatabaseMigrator {
    static let shared = AppDatabaseMigrator()
    
    var migrator = DatabaseMigrator()
    
    private init() {
        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "plans") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("days_per_week", .integer).notNull()
                t.column("created_at", .datetime).notNull()
            }
            
            try db.create(table: "workout_days") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("plan_id", .integer).notNull().references("plans", onDelete: .cascade)
                t.column("day_number", .integer).notNull()
                t.column("name", .text).notNull()
            }
            try db.create(index: "idx_workout_days_plan_id", on: "workout_days", columns: ["plan_id"])
            
            try db.create(table: "exercises") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("workout_day_id", .integer).notNull().references("workout_days", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("sets", .integer).notNull()
                t.column("reps", .integer).notNull()
                t.column("position", .integer).notNull()
            }
            try db.create(index: "idx_exercises_workout_day_id", on: "exercises", columns: ["workout_day_id"])
            
            try db.create(table: "workout_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("workout_day_id", .integer).notNull().references("workout_days", onDelete: .restrict)
                t.column("day_name", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("completed_at", .datetime)
                t.column("status", .text).notNull()
            }
            try db.create(index: "idx_workout_sessions_workout_day_id", on: "workout_sessions", columns: ["workout_day_id"])
            try db.create(index: "idx_workout_sessions_status", on: "workout_sessions", columns: ["status"])
            try db.create(index: "idx_workout_sessions_completed_at", on: "workout_sessions", columns: ["completed_at"])
            
            try db.create(table: "exercise_logs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer).notNull().references("workout_sessions", onDelete: .cascade)
                t.column("exercise_id", .integer).notNull().references("exercises", onDelete: .restrict)
                t.column("exercise_name", .text).notNull()
                t.column("planned_sets", .integer).notNull()
                t.column("planned_reps", .integer).notNull()
                t.column("weight", .double)
                t.column("notes", .text)
                t.column("completed", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_exercise_logs_session_id", on: "exercise_logs", columns: ["session_id"])
            try db.create(index: "idx_exercise_logs_exercise_id", on: "exercise_logs", columns: ["exercise_id"])
        }

        // Workout history is a snapshot. It must survive when the editable plan
        // that originally created it is removed.
        migrator.registerMigration("v2_preserve_history_after_plan_deletion") { db in
            try db.execute(sql: """
                CREATE TABLE workout_sessions_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    workout_day_id INTEGER NOT NULL,
                    day_name TEXT NOT NULL,
                    started_at DATETIME NOT NULL,
                    completed_at DATETIME,
                    status TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO workout_sessions_new
                SELECT id, workout_day_id, day_name, started_at, completed_at, status
                FROM workout_sessions
                """)

            try db.execute(sql: """
                CREATE TABLE exercise_logs_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id INTEGER NOT NULL,
                    exercise_id INTEGER NOT NULL,
                    exercise_name TEXT NOT NULL,
                    planned_sets INTEGER NOT NULL,
                    planned_reps INTEGER NOT NULL,
                    weight DOUBLE,
                    notes TEXT,
                    completed BOOLEAN NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: """
                INSERT INTO exercise_logs_new
                SELECT id, session_id, exercise_id, exercise_name, planned_sets, planned_reps, weight, notes, completed
                FROM exercise_logs
                """)

            try db.execute(sql: "DROP TABLE exercise_logs")
            try db.execute(sql: "DROP TABLE workout_sessions")
            try db.execute(sql: "ALTER TABLE workout_sessions_new RENAME TO workout_sessions")
            try db.execute(sql: "ALTER TABLE exercise_logs_new RENAME TO exercise_logs")
            try db.execute(sql: "CREATE INDEX idx_workout_sessions_workout_day_id ON workout_sessions(workout_day_id)")
            try db.execute(sql: "CREATE INDEX idx_workout_sessions_status ON workout_sessions(status)")
            try db.execute(sql: "CREATE INDEX idx_workout_sessions_completed_at ON workout_sessions(completed_at)")
            try db.execute(sql: "CREATE INDEX idx_exercise_logs_session_id ON exercise_logs(session_id)")
            try db.execute(sql: "CREATE INDEX idx_exercise_logs_exercise_id ON exercise_logs(exercise_id)")
        }

        migrator.registerMigration("v3_add_set_logs") { db in
            try db.create(table: "set_logs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("exercise_log_id", .integer).notNull().references("exercise_logs", onDelete: .cascade)
                t.column("set_number", .integer).notNull()
                t.column("weight", .double)
                t.column("notes", .text)
            }
            try db.create(index: "idx_set_logs_exercise_log_id", on: "set_logs", columns: ["exercise_log_id"])

            // Preserve the old one-weight/one-note records by placing them on
            // the first set, while adding blank records for the remaining sets.
            try db.execute(sql: """
                WITH RECURSIVE set_numbers(number) AS (
                    SELECT 1
                    UNION ALL
                    SELECT number + 1 FROM set_numbers WHERE number < 100
                )
                INSERT INTO set_logs (exercise_log_id, set_number, weight, notes)
                SELECT id,
                       number,
                       CASE WHEN number = 1 THEN weight END,
                       CASE WHEN number = 1 THEN notes END
                FROM exercise_logs
                JOIN set_numbers ON number <= planned_sets
                """)
        }

        migrator.registerMigration("v4_add_exercise_target_descriptions") { db in
            try db.alter(table: "exercises") { t in
                t.add(column: "target_description", .text)
            }
            try db.alter(table: "exercise_logs") { t in
                t.add(column: "target_description", .text)
            }
        }

        migrator.registerMigration("v5_add_set_durations") { db in
            try db.alter(table: "set_logs") { t in
                t.add(column: "duration_seconds", .integer)
            }
        }
    }
    
    func migrate(_ writer: some DatabaseWriter) throws {
        try migrator.migrate(writer)
    }
}
