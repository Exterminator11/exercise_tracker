import SwiftUI

struct RootView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            NavigationStack(path: $appState.navigationPath) {
                Group {
                    if appState.isLoading {
                        ProgressView("Loading Workout Plan…")
                    } else if appState.plan != nil {
                        HomeView()
                    } else {
                        PlanCreationChoiceView()
                    }
                }
                .navigationDestination(for: PlanSetupStep.self) { step in
                    switch step {
                    case .dayConfig(let dayIndex, let totalDays):
                        PlanSetupDayConfigView(dayIndex: dayIndex, totalDays: totalDays)
                    case .exerciseEdit(let dayIndex, let totalDays, let exercise):
                        ExerciseEditView(dayIndex: dayIndex, totalDays: totalDays, exercise: exercise) { _ in }
                    }
                }
                .navigationDestination(for: WorkoutRoute.self) { route in
                    switch route {
                    case .activeWorkout: ActiveWorkoutView()
                    case .history: HistoryView()
                    case .workoutDetail(let sessionId): WorkoutDetailView(sessionId: sessionId)
                    case .editPlan: EditPlanView()
                    case .createPlan: PlanCreationChoiceView()
                    case .manualPlan: PlanSetupDayCountView()
                    }
                }
                .sheet(item: $appState.resumeCandidate) { (session: WorkoutSession) in
                    ResumeWorkoutSheet(appState: appState, session: session)
                }
            }
            .dynamicTypeSize(.xSmall ... .xLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

enum PlanSetupStep: Hashable {
    case dayConfig(dayIndex: Int, totalDays: Int)
    case exerciseEdit(dayIndex: Int, totalDays: Int, exercise: Exercise?)
}

enum WorkoutRoute: Hashable {
    case activeWorkout
    case history
    case workoutDetail(sessionId: Int64)
    case editPlan
    case createPlan
    case manualPlan
}

struct ResumeWorkoutSheet: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("WorkoutMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                
                Text("Workout in Progress")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("You have an incomplete \(session.dayName) workout from \(session.startedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 12) {
                    Button("Resume Workout") {
                        appState.resumeSession(session)
                        appState.navigationPath.append(WorkoutRoute.activeWorkout)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    
                    Button("Discard & Start Fresh") {
                        try? appState.discardSession(session)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.red)
                }
                .padding(.top)
            }
            .padding()
            .navigationTitle("Resume?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
