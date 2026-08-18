import Foundation
import SwiftUI
import Observation

@MainActor @Observable
final class AppState {
    var plan: Plan?
    var plans: [Plan] = []
    var currentSession: WorkoutSession?
    var inProgressSession: WorkoutSession?
    var resumeCandidate: WorkoutSession?
    var isLoading = true
    var navigationPath = NavigationPath()
    var setupDays: [Int: [Exercise]] = [:]
    var setupDayNames: [Int: String] = [:]
    
    init() {}

    func loadInitialData() {
        guard isLoading else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try DatabaseManager.shared.fetchInitialState()
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let initialState):
                    self.plans = initialState.plans
                    self.plan = initialState.selectedPlan
                    self.inProgressSession = initialState.inProgressSession
                    self.resumeCandidate = initialState.inProgressSession
                case .failure(let error):
                    print("Failed to load app data: \(error)")
                }
                self.isLoading = false
            }
        }
    }
    
    func loadPlan(preferredPlanId: Int64? = nil) {
        do {
            plans = try DatabaseManager.shared.fetchPlanSummaries()
            let selectedPlanId = preferredPlanId ?? plan?.id
            let selectedSummary = plans.first(where: { $0.id == selectedPlanId }) ?? plans.first
            plan = try selectedSummary.flatMap { try DatabaseManager.shared.fetchPlanWithDays($0.id!) }
        } catch {
            print("Failed to load plan: \(error)")
        }
    }
    
    func checkForInProgressSession() {
        do {
            inProgressSession = try DatabaseManager.shared.fetchInProgressSession()
        } catch {
            print("Failed to check for in-progress session: \(error)")
        }
    }
    
    func clearInProgressSession() {
        inProgressSession = nil
        currentSession = nil
        resumeCandidate = nil
    }
    
    func startNewSession(for day: WorkoutDay) throws -> Bool {
        if let existing = try DatabaseManager.shared.fetchInProgressSession() {
            inProgressSession = existing
            resumeCandidate = existing
            return false
        }
        guard plan != nil else { return false }
        guard let exercises = day.exercises, !exercises.isEmpty else {
            throw NSError(domain: "ExerciseTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "This workout day has no exercises."])
        }
        
        let session = try DatabaseManager.shared.createWorkoutSession(
            workoutDayId: day.id!,
            dayName: day.name,
            exercises: exercises
        )
        currentSession = session
        inProgressSession = session
        resumeCandidate = nil
        return true
    }
    
    func resumeSession(_ session: WorkoutSession) {
        currentSession = session
        inProgressSession = session
        resumeCandidate = nil
    }
    
    func completeSession() throws {
        guard let session = currentSession else { return }
        try DatabaseManager.shared.completeSession(session.id!)
        currentSession = nil
        inProgressSession = nil
        resumeCandidate = nil
        loadPlan()
    }

    func discardSession(_ session: WorkoutSession) throws {
        try DatabaseManager.shared.discardSession(session.id!)
        clearInProgressSession()
    }
    
    func deletePlan() throws {
        guard let plan = plan else { return }
        try DatabaseManager.shared.deletePlan(plan)
        loadPlan()
        currentSession = nil
        inProgressSession = nil
        resumeCandidate = nil
        navigationPath = NavigationPath()
    }

    func beginPlanSetup() {
        setupDays.removeAll()
        setupDayNames.removeAll()
        navigationPath.append(WorkoutRoute.createPlan)
    }

    func importPlan(from data: Data) throws {
        let importedPlan = try JSONDecoder().decode(ImportedWorkoutPlan.self, from: data)
        let plan = try DatabaseManager.shared.importWorkoutPlan(importedPlan)
        loadPlan(preferredPlanId: plan.id)
        navigationPath = NavigationPath()
    }

    func selectPlan(_ selectedPlan: Plan) {
        loadPlan(preferredPlanId: selectedPlan.id)
    }
}
