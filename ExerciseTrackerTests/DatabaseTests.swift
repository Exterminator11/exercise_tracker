import Foundation
import XCTest
import GRDB
@testable import ExerciseTracker

final class DatabaseTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var databaseManager: DatabaseManager!
    
    override func setUp() {
        super.setUp()
        dbQueue = try! DatabaseQueue()
        try! AppDatabaseMigrator.shared.migrate(dbQueue)
        databaseManager = DatabaseManager(dbQueue: dbQueue)
    }
    
    override func tearDown() {
        dbQueue = nil
        databaseManager = nil
        super.tearDown()
    }
    
    // MARK: - Plan Tests
    
    func testCreatePlan() throws {
        let plan = try databaseManager.createPlan(name: "Test Plan", daysPerWeek: 4)
        
        XCTAssertNotNil(plan.id)
        XCTAssertEqual(plan.name, "Test Plan")
        XCTAssertEqual(plan.daysPerWeek, 4)
    }
    
    func testFetchPlan() throws {
        let created = try databaseManager.createPlan(name: "Fetch Test", daysPerWeek: 3)
        let fetched = try databaseManager.fetchPlan()
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, created.id)
        XCTAssertEqual(fetched?.name, "Fetch Test")
    }
    
    func testUpdatePlan() throws {
        var plan = try databaseManager.createPlan(name: "Original", daysPerWeek: 2)
        plan.name = "Updated"
        try databaseManager.updatePlan(plan)
        
        let fetched = try databaseManager.fetchPlan()
        XCTAssertEqual(fetched?.name, "Updated")
    }
    
    func testDeletePlan() throws {
        let plan = try databaseManager.createPlan(name: "To Delete", daysPerWeek: 1)
        try databaseManager.deletePlan(plan)
        
        let fetched = try databaseManager.fetchPlan()
        XCTAssertNil(fetched)
    }

    func testDeletePlanPreservesCompletedHistoryAndDiscardsInProgressWorkout() throws {
        let plan = try databaseManager.createPlan(name: "To Delete", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Upper")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)

        let completedSession = try databaseManager.createWorkoutSession(
            workoutDayId: day.id!,
            dayName: day.name,
            exercises: [exercise]
        )
        var completedLog = try XCTUnwrap(databaseManager.fetchSessionWithLogs(completedSession.id!)?.1.first)
        completedLog.weight = 135
        completedLog.notes = "Strong"
        completedLog.completed = true
        try databaseManager.updateExerciseLog(completedLog)
        try databaseManager.completeSession(completedSession.id!)

        _ = try databaseManager.createWorkoutSession(
            workoutDayId: day.id!,
            dayName: day.name,
            exercises: [exercise]
        )

        try databaseManager.deletePlan(plan)

        XCTAssertNil(try databaseManager.fetchPlan())
        XCTAssertNil(try databaseManager.fetchInProgressSession())
        let history = try databaseManager.fetchCompletedSessions()
        XCTAssertEqual(history.map(\.id), [completedSession.id])
        let (_, savedLogs) = try XCTUnwrap(databaseManager.fetchSessionDetail(completedSession.id!))
        XCTAssertEqual(savedLogs.count, 1)
        XCTAssertEqual(savedLogs.first?.exerciseName, "Bench Press")
        XCTAssertEqual(savedLogs.first?.weight, 135)
        XCTAssertEqual(savedLogs.first?.notes, "Strong")
    }
    
    // MARK: - WorkoutDay Tests
    
    func testCreateWorkoutDay() throws {
        let plan = try databaseManager.createPlan(name: "Day Plan", daysPerWeek: 2)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Upper A")
        
        XCTAssertNotNil(day.id)
        XCTAssertEqual(day.planId, plan.id)
        XCTAssertEqual(day.dayNumber, 1)
        XCTAssertEqual(day.name, "Upper A")
    }
    
    func testUpdateWorkoutDay() throws {
        let plan = try databaseManager.createPlan(name: "Day Plan", daysPerWeek: 2)
        var day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Original")
        day.name = "Updated"
        try databaseManager.updateWorkoutDay(day)
        
        let fetched = try databaseManager.fetchPlanWithDays()
        XCTAssertEqual(fetched?.workoutDays?.first?.name, "Updated")
    }
    
    // MARK: - Exercise Tests
    
    func testCreateExercise() throws {
        let plan = try databaseManager.createPlan(name: "Exercise Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        XCTAssertNotNil(exercise.id)
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(exercise.sets, 3)
        XCTAssertEqual(exercise.reps, 8)
        XCTAssertEqual(exercise.position, 0)
    }
    
    func testUpdateExercise() throws {
        let plan = try databaseManager.createPlan(name: "Exercise Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        var exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Original", sets: 3, reps: 8, position: 0)
        exercise.name = "Updated"
        exercise.sets = 4
        exercise.reps = 10
        try databaseManager.updateExercise(exercise)
        
        let fetched = try databaseManager.fetchPlanWithDays()
        let fetchedExercise = fetched?.workoutDays?.first?.exercises?.first
        XCTAssertEqual(fetchedExercise?.name, "Updated")
        XCTAssertEqual(fetchedExercise?.sets, 4)
        XCTAssertEqual(fetchedExercise?.reps, 10)
    }
    
    func testDeleteExercise() throws {
        let plan = try databaseManager.createPlan(name: "Exercise Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "To Delete", sets: 3, reps: 8, position: 0)
        try databaseManager.deleteExercise(exercise)
        
        let fetched = try databaseManager.fetchPlanWithDays()
        XCTAssertEqual(fetched?.workoutDays?.first?.exercises?.count, 0)
    }
    
    func testReorderExercises() throws {
        let plan = try databaseManager.createPlan(name: "Exercise Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex1 = try databaseManager.createExercise(workoutDayId: day.id!, name: "First", sets: 3, reps: 8, position: 0)
        let ex2 = try databaseManager.createExercise(workoutDayId: day.id!, name: "Second", sets: 3, reps: 8, position: 1)
        let ex3 = try databaseManager.createExercise(workoutDayId: day.id!, name: "Third", sets: 3, reps: 8, position: 2)
        
        var exercises = [ex1, ex2, ex3]
        exercises.swapAt(0, 2) // Third, Second, First
        try databaseManager.reorderExercises(exercises)
        
        let fetched = try databaseManager.fetchPlanWithDays()
        let fetchedExercises = fetched?.workoutDays?.first?.exercises
        XCTAssertEqual(fetchedExercises?[0].name, "Third")
        XCTAssertEqual(fetchedExercises?[1].name, "Second")
        XCTAssertEqual(fetchedExercises?[2].name, "First")
        XCTAssertEqual(fetchedExercises?[0].position, 0)
        XCTAssertEqual(fetchedExercises?[1].position, 1)
        XCTAssertEqual(fetchedExercises?[2].position, 2)
    }
    
    // MARK: - Session Tests
    
    func testCreateWorkoutSession() throws {
        let plan = try databaseManager.createPlan(name: "Session Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex1 = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        let ex2 = try databaseManager.createExercise(workoutDayId: day.id!, name: "Squat", sets: 4, reps: 6, position: 1)
        
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex1, ex2])
        
        XCTAssertNotNil(session.id)
        XCTAssertEqual(session.workoutDayId, day.id)
        XCTAssertEqual(session.dayName, "Day 1")
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertNil(session.completedAt)
    }

    func testWorkoutSessionCreatesASetLogForEveryPlannedSet() throws {
        let plan = try databaseManager.createPlan(name: "Set Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Squat", sets: 3, reps: 5, position: 0)

        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        let logs = try XCTUnwrap(databaseManager.fetchSessionWithLogs(session.id!)?.1)
        let setLogs = try databaseManager.fetchSetLogs(forSessionId: session.id!)

        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(setLogs.map(\.setNumber), [1, 2, 3])
        XCTAssertEqual(setLogs.map(\.exerciseLogId), [logs[0].id, logs[0].id, logs[0].id])
    }

    func testSetLogsPersistTheirOwnWeightAndNotes() throws {
        let plan = try databaseManager.createPlan(name: "Set Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 2, reps: 8, position: 0)
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])

        var setLogs = try databaseManager.fetchSetLogs(forSessionId: session.id!)
        setLogs[0].weight = 135
        setLogs[0].notes = "Warm-up"
        setLogs[1].weight = 155
        setLogs[1].notes = "Hard but clean"
        try databaseManager.updateSetLog(setLogs[0])
        try databaseManager.updateSetLog(setLogs[1])

        let savedSetLogs = try databaseManager.fetchSetLogs(forSessionId: session.id!)
        XCTAssertEqual(savedSetLogs.map(\.weight), [135, 155])
        XCTAssertEqual(savedSetLogs.map(\.notes), ["Warm-up", "Hard but clean"])
    }

    func testSetLogsPersistDurationSeconds() throws {
        let plan = try databaseManager.createPlan(name: "Core", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Core")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Plank", sets: 1, reps: 1, position: 0)
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        var setLog = try XCTUnwrap(databaseManager.fetchSetLogs(forSessionId: session.id!).first)
        setLog.durationSeconds = 45
        try databaseManager.updateSetLog(setLog)
        XCTAssertEqual(try databaseManager.fetchSetLogs(forSessionId: session.id!).first?.durationSeconds, 45)
    }

    func testDiscardSessionRemovesResumeCandidate() throws {
        let plan = try databaseManager.createPlan(name: "Session", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Row", sets: 1, reps: 8, position: 0)
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        try databaseManager.discardSession(session.id!)
        XCTAssertNil(try databaseManager.fetchInProgressSession())
        XCTAssertNil(try databaseManager.fetchSessionWithLogs(session.id!))
    }

    func testImportWorkoutPlanCreatesTrainingDaysAndTargets() throws {
        let json = """
        {
          "program_metadata": { "name": "Imported Split", "days_per_week": 2 },
          "schedule": {
            "monday": {
              "session_name": "Upper",
              "type": "lifting",
              "exercises": [
                { "order": 1, "exercise": "Press", "sets": 3, "rep_range": [8, 12] }
              ]
            },
            "wednesday": { "session_name": "Rest", "type": "recovery" },
            "friday": {
              "session_name": "Core",
              "type": "lifting",
              "exercises": [
                { "order": 1, "exercise": "Plank", "sets": 2, "duration_seconds_range": [30, 60], "metric_type": "time" }
              ]
            }
          }
        }
        """
        let imported = try JSONDecoder().decode(ImportedWorkoutPlan.self, from: Data(json.utf8))
        let plan = try databaseManager.importWorkoutPlan(imported)
        let savedPlan = try XCTUnwrap(databaseManager.fetchPlanWithDays())

        XCTAssertEqual(plan.name, "Imported Split")
        XCTAssertEqual(savedPlan.workoutDays?.map(\.name), ["Upper", "Core"])
        XCTAssertEqual(savedPlan.workoutDays?.first?.exercises?.first?.targetDescription, "8–12 reps")
        XCTAssertEqual(savedPlan.workoutDays?.last?.exercises?.first?.targetDescription, "30–60 sec")
    }

    func testDeleteCompletedSessionRemovesItsLogsAndKeepsOtherHistory() throws {
        let plan = try databaseManager.createPlan(name: "History Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Row", sets: 2, reps: 10, position: 0)

        let deletedSession = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        let keptSession = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        try databaseManager.completeSession(deletedSession.id!)
        try databaseManager.completeSession(keptSession.id!)

        try databaseManager.deleteCompletedSession(deletedSession.id!)

        XCTAssertNil(try databaseManager.fetchSessionDetail(deletedSession.id!))
        XCTAssertTrue(try databaseManager.fetchSetLogs(forSessionId: deletedSession.id!).isEmpty)
        XCTAssertEqual(try databaseManager.fetchCompletedSessions().map(\.id), [keptSession.id])
    }
    
    func testFetchInProgressSession() throws {
        let plan = try databaseManager.createPlan(name: "Session Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        let fetched = try databaseManager.fetchInProgressSession()
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, session.id)
    }
    
    func testCompleteSession() throws {
        let plan = try databaseManager.createPlan(name: "Session Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        try databaseManager.completeSession(session.id!)
        
        let inProgress = try databaseManager.fetchInProgressSession()
        XCTAssertNil(inProgress)
        
        let completed = try databaseManager.fetchCompletedSessions()
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.id, session.id)
        XCTAssertNotNil(completed.first?.completedAt)
    }

    func testCompletedSessionsIncludeExerciseCountForHistory() throws {
        let plan = try databaseManager.createPlan(name: "History", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let first = try databaseManager.createExercise(workoutDayId: day.id!, name: "Press", sets: 1, reps: 8, position: 0)
        let second = try databaseManager.createExercise(workoutDayId: day.id!, name: "Row", sets: 1, reps: 8, position: 1)
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [first, second])
        try databaseManager.completeSession(session.id!)

        XCTAssertEqual(try databaseManager.fetchCompletedSessions().first?.exerciseCount, 2)
    }

    func testInitialLoadRepairsFullyCheckedInProgressWorkout() throws {
        let plan = try databaseManager.createPlan(name: "Repair", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Row", sets: 1, reps: 8, position: 0)
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        var log = try XCTUnwrap(databaseManager.fetchSessionWithLogs(session.id!)?.1.first)
        log.completed = true
        try databaseManager.updateExerciseLog(log)

        let initial = try databaseManager.fetchInitialState()
        XCTAssertNil(initial.inProgressSession)
        XCTAssertEqual(try databaseManager.fetchCompletedSessions().first?.id, session.id)
    }

    func testInitialLoadRemovesStaleDuplicateAfterSameDayCompletes() throws {
        let plan = try databaseManager.createPlan(name: "Cleanup", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Lower A + Abs")
        let exercise = try databaseManager.createExercise(workoutDayId: day.id!, name: "Squat", sets: 1, reps: 5, position: 0)
        let stale = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        let completed = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [exercise])
        try databaseManager.completeSession(completed.id!)

        _ = try databaseManager.fetchInitialState()
        XCTAssertNil(try databaseManager.fetchSessionWithLogs(stale.id!))
        XCTAssertNil(try databaseManager.fetchInProgressSession())
    }
    
    // MARK: - ExerciseLog Tests
    
    func testUpdateExerciseLog() throws {
        let plan = try databaseManager.createPlan(name: "Log Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        let logs = try databaseManager.fetchSessionWithLogs(session.id!)
        
        guard let log = logs?.1.first else {
            XCTFail("No exercise log found")
            return
        }
        
        var updatedLog = log
        updatedLog.weight = 135.0
        updatedLog.notes = "Felt good"
        updatedLog.completed = true
        try databaseManager.updateExerciseLog(updatedLog)
        
        let fetchedLogs = try databaseManager.fetchSessionWithLogs(session.id!)
        let fetchedLog = fetchedLogs?.1.first
        XCTAssertEqual(fetchedLog?.weight, 135.0)
        XCTAssertEqual(fetchedLog?.notes, "Felt good")
        XCTAssertTrue(fetchedLog?.completed ?? false)
    }
    
    // MARK: - Previous Weight Tests
    
    func testPreviousWeight() throws {
        let plan = try databaseManager.createPlan(name: "Weight Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        // First session
        let session1 = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        var log1 = try databaseManager.fetchSessionWithLogs(session1.id!)?.1.first!
        log1!.weight = 135.0
        log1!.completed = true
        try databaseManager.updateExerciseLog(log1!)
        try databaseManager.completeSession(session1.id!)
        
        // Second session
        let session2 = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        let previousWeight = try databaseManager.fetchPreviousWeight(forExerciseId: ex.id!)
        
        XCTAssertEqual(previousWeight, 135.0)
        
        // Complete second session with new weight
        var log2 = try databaseManager.fetchSessionWithLogs(session2.id!)?.1.first!
        log2!.weight = 140.0
        log2!.completed = true
        try databaseManager.updateExerciseLog(log2!)
        try databaseManager.completeSession(session2.id!)
        
        // Third session should see 140.0
        let session3 = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        let previousWeight2 = try databaseManager.fetchPreviousWeight(forExerciseId: ex.id!)
        XCTAssertEqual(previousWeight2, 140.0)
    }
    
    func testNoPreviousWeightForNewExercise() throws {
        let plan = try databaseManager.createPlan(name: "Weight Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "New Exercise", sets: 3, reps: 8, position: 0)
        
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        let previousWeight = try databaseManager.fetchPreviousWeight(forExerciseId: ex.id!)
        
        XCTAssertNil(previousWeight)
    }

    func testPersonalBestMatchesExerciseNameAcrossDays() throws {
        let plan = try databaseManager.createPlan(name: "PB", daysPerWeek: 2)
        let firstDay = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "A")
        let secondDay = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 2, name: "B")
        let firstExercise = try databaseManager.createExercise(workoutDayId: firstDay.id!, name: "Bench Press", sets: 1, reps: 5, position: 0)
        let secondExercise = try databaseManager.createExercise(workoutDayId: secondDay.id!, name: " bench press ", sets: 1, reps: 5, position: 0)
        let session = try databaseManager.createWorkoutSession(workoutDayId: firstDay.id!, dayName: firstDay.name, exercises: [firstExercise])
        let log = try XCTUnwrap(databaseManager.fetchSessionWithLogs(session.id!)?.1.first)
        var setLog = try XCTUnwrap(databaseManager.fetchSetLogs(forSessionId: session.id!).first)
        setLog.weight = 185
        try databaseManager.updateSetLog(setLog)
        var completeLog = log; completeLog.completed = true
        try databaseManager.updateExerciseLog(completeLog)
        try databaseManager.completeSession(session.id!)
        _ = secondExercise
        let history = try databaseManager.fetchExerciseHistory(forExerciseNames: ["bench press"])["bench press"]
        XCTAssertEqual(history?.personalBest.weight, 185)
        XCTAssertEqual(history?.latestWeight, 185)
    }
    
    // MARK: - History Immutability Tests
    
    func testHistoryImmutabilityAfterPlanEdit() throws {
        let plan = try databaseManager.createPlan(name: "Immutability Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        // Create and complete a session
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        var log = try databaseManager.fetchSessionWithLogs(session.id!)?.1.first!
        log!.weight = 135.0
        log!.completed = true
        try databaseManager.updateExerciseLog(log!)
        try databaseManager.completeSession(session.id!)
        
        // Now modify the plan - change exercise to 4 sets x 10 reps
        var updatedEx = ex
        updatedEx.sets = 4
        updatedEx.reps = 10
        try databaseManager.updateExercise(updatedEx)
        
        // Verify history still shows original 3x8
        let detail = try databaseManager.fetchSessionDetail(session.id!)
        XCTAssertNotNil(detail)
        let historyLog = detail?.1.first
        XCTAssertEqual(historyLog?.plannedSets, 3)
        XCTAssertEqual(historyLog?.plannedReps, 8)
        XCTAssertEqual(historyLog?.exerciseName, "Bench Press")
    }
    
    func testHistoryImmutabilityAfterDayRename() throws {
        let plan = try databaseManager.createPlan(name: "Immutability Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Original Name")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        let session = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        var log = try databaseManager.fetchSessionWithLogs(session.id!)?.1.first!
        log!.completed = true
        try databaseManager.updateExerciseLog(log!)
        try databaseManager.completeSession(session.id!)
        
        // Rename the day
        var updatedDay = day
        updatedDay.name = "New Name"
        try databaseManager.updateWorkoutDay(updatedDay)
        
        // Verify history still shows original day name
        let detail = try databaseManager.fetchSessionDetail(session.id!)
        XCTAssertEqual(detail?.0.dayName, "Original Name")
    }
    
    // MARK: - Statistics Tests
    
    func testCompletedWorkoutsCount() throws {
        let plan = try databaseManager.createPlan(name: "Stats Plan", daysPerWeek: 1)
        let day = try databaseManager.createWorkoutDay(planId: plan.id!, dayNumber: 1, name: "Day 1")
        let ex = try databaseManager.createExercise(workoutDayId: day.id!, name: "Bench Press", sets: 3, reps: 8, position: 0)
        
        // Initially 0
        XCTAssertEqual(try databaseManager.fetchCompletedWorkoutsCount(), 0)
        
        // Create and complete one session
        let session1 = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        var log1 = try databaseManager.fetchSessionWithLogs(session1.id!)?.1.first!
        log1!.completed = true
        try databaseManager.updateExerciseLog(log1!)
        try databaseManager.completeSession(session1.id!)
        
        XCTAssertEqual(try databaseManager.fetchCompletedWorkoutsCount(), 1)
        
        // Create another session but don't complete it
        let session2 = try databaseManager.createWorkoutSession(workoutDayId: day.id!, dayName: day.name, exercises: [ex])
        // Leave it in_progress
        
        XCTAssertEqual(try databaseManager.fetchCompletedWorkoutsCount(), 1)
        
        // Complete second session
        var log2 = try databaseManager.fetchSessionWithLogs(session2.id!)?.1.first!
        log2!.completed = true
        try databaseManager.updateExerciseLog(log2!)
        try databaseManager.completeSession(session2.id!)
        
        XCTAssertEqual(try databaseManager.fetchCompletedWorkoutsCount(), 2)
    }
}
