import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var completedCount = 0
    @State private var nextWorkoutDay: WorkoutDay?
    @State private var showingDayPicker = false
    
    var body: some View {
        ScrollView {
                    VStack(spacing: 24) {
                        if let plan = appState.plan {
                            CurrentPlanCard(plan: plan) {
                                appState.navigationPath.append(WorkoutRoute.editPlan)
                            }

                            if appState.plans.count > 1 {
                                SavedPlansSection(
                                    plans: appState.plans,
                                    selectedPlanId: plan.id,
                                    onSelect: { selectedPlan in
                                        appState.selectPlan(selectedPlan)
                                        loadData()
                                    }
                                )
                            }
                            
                            if let nextDay = nextWorkoutDay {
                                NextWorkoutCard(day: nextDay) {
                                    showingDayPicker = true
                                }
                            }
                            
                            StatsCard(completedCount: completedCount)
                            
                            ActionButtons()
                        } else {
                            ContentUnavailableView(
                                "No Workout Plan",
                                systemImage: "list.bullet.clipboard",
                                description: Text("Create a workout plan to get started")
                            )
                            .frame(maxWidth: .infinity, minHeight: 320)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            .navigationTitle("Exercise Tracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            appState.navigationPath.append(WorkoutRoute.history)
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                }
            }
        .onAppear {
                loadData()
            }
        .onChange(of: appState.plan?.id) { _, _ in
            loadData()
        }
        .sheet(isPresented: $showingDayPicker) {
            WorkoutDayPickerSheet(
                days: appState.plan?.workoutDays ?? [],
                suggestedDayId: nextWorkoutDay?.id,
                onSelect: { day in
                    showingDayPicker = false
                    startWorkout(for: day)
                }
            )
            .presentationDetents([.medium])
        }
    }
    
    private func loadData() {
        do {
            completedCount = try DatabaseManager.shared.fetchCompletedWorkoutsCount()
            if let plan = appState.plan {
                nextWorkoutDay = try DatabaseManager.shared.fetchNextWorkoutDay(for: plan)
            }
        } catch {
            print("Failed to load home data: \(error)")
        }
    }
    
    private func startWorkout(for day: WorkoutDay) {
        do {
            if try appState.startNewSession(for: day) {
                appState.navigationPath.append(WorkoutRoute.activeWorkout)
            }
        } catch {
            print("Failed to start workout: \(error)")
        }
    }
    
}

struct WorkoutDayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let days: [WorkoutDay]
    let suggestedDayId: Int64?
    let onSelect: (WorkoutDay) -> Void

    var body: some View {
        NavigationStack {
            List(days) { day in
                Button {
                    onSelect(day)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.name)
                                .font(.headline)
                            Text("\(day.exercises?.count ?? 0) exercises")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if day.id == suggestedDayId {
                            Text("Suggested")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled((day.exercises ?? []).isEmpty)
            }
            .navigationTitle("Choose Workout Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CurrentPlanCard: View {
    let plan: Plan
    let onEdit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("WorkoutMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected Plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.name)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Spacer()
            }
            
            HStack(spacing: 16) {
                Label("\(plan.daysPerWeek) days/week", systemImage: "calendar")
                Label("\(plan.workoutDays?.count ?? 0) configured", systemImage: "checkmark.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button(action: onEdit) {
                Label("Edit or Delete Plan", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SavedPlansSection: View {
    let plans: [Plan]
    let selectedPlanId: Int64?
    let onSelect: (Plan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Plans")
                .font(.headline)

            ForEach(plans) { plan in
                Button {
                    onSelect(plan)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(plan.daysPerWeek) days per week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if plan.id == selectedPlanId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NextWorkoutCard: View {
    let day: WorkoutDay
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Workout")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(day.name)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Spacer()
            }
            
            Text("\(day.exercises?.count ?? 0) exercises")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: action) {
                Text("BEGIN PLAN")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatsCard: View {
    let completedCount: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(completedCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Workouts Completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green.gradient)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ActionButtons: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 12) {
            Button {
                appState.navigationPath.append(WorkoutRoute.history)
            } label: {
                Label("Workout History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.blue)
            
            Button {
                appState.beginPlanSetup()
            } label: {
                Label("Create New Plan", systemImage: "plus.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.green)
        }
    }
}
