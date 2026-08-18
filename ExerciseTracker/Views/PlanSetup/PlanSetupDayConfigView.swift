import SwiftUI

struct PlanSetupDayConfigView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let dayIndex: Int
    let totalDays: Int
    
    @State private var dayName: String
    @State private var exercises: [Exercise] = []
    @State private var showingAddExercise = false
    @State private var editingExercise: Exercise?
    
    init(dayIndex: Int, totalDays: Int) {
        self.dayIndex = dayIndex
        self.totalDays = totalDays
        _dayName = State(initialValue: "Day \(dayIndex)")
    }
    
    var isFirstDay: Bool { dayIndex == 1 }
    var isLastDay: Bool { dayIndex == totalDays }
    
    var body: some View {
        ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Day \(dayIndex) of \(totalDays)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Configure \(dayName)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            TextField("Day Name", text: $dayName)
                                .textInputAutocapitalization(.words)
                                .font(.title3)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 20)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Exercises")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    editingExercise = nil
                                    showingAddExercise = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            if exercises.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "plus.circle.dashed")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.tertiary)
                                    Text("No Exercises Yet")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Text("Add your first exercise for \(dayName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                    Button {
                                        showingAddExercise = true
                                    } label: {
                                        Label("Add Exercise", systemImage: "plus")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .padding(.horizontal, 40)
                                }
                                .padding(.vertical, 40)
                                .frame(maxWidth: .infinity)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 20)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(exercises.indices, id: \.self) { index in
                                        let exercise = exercises[index]
                                        ExerciseRowView(
                                            exercise: exercise,
                                            position: index + 1,
                                            onTap: { editingExercise = exercise },
                                            onDelete: { deleteExercise(at: index) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .navigationTitle("Day \(dayIndex)")
                .navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !isFirstDay {
                            Button("Back") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if isLastDay {
                            Button("Save Plan") { savePlan() }
                                .fontWeight(.semibold)
                                .disabled(exercises.isEmpty)
                        } else {
                            Button("Next") { goToNextDay() }
                                .fontWeight(.semibold)
                                .disabled(exercises.isEmpty)
                        }
                    }
                }
            .sheet(isPresented: $showingAddExercise) {
                NavigationStack {
                    ExerciseEditView(dayIndex: dayIndex, totalDays: totalDays, exercise: nil) { newExercise in
                        var ex = newExercise
                        ex.workoutDayId = 0
                        ex.position = exercises.count
                        exercises.append(ex)
                        updatePositions()
                        showingAddExercise = false
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingExercise) { exercise in
                NavigationStack {
                    ExerciseEditView(dayIndex: dayIndex, totalDays: totalDays, exercise: exercise) { updatedExercise in
                        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                            exercises[index] = updatedExercise
                        }
                        editingExercise = nil
                    }
                }
                .presentationDetents([.medium, .large])
            }
    }
    
    private func updatePositions() {
        for (index, _) in exercises.enumerated() {
            exercises[index].position = index
        }
    }
    
    private func deleteExercise(at index: Int) {
        exercises.remove(at: index)
        updatePositions()
    }
    
    private func goToNextDay() {
        appState.setupDayNames[dayIndex] = dayName
        appState.setupDays[dayIndex] = exercises
        appState.navigationPath.append(PlanSetupStep.dayConfig(dayIndex: dayIndex + 1, totalDays: totalDays))
    }
    
    private func savePlan() {
        do {
            appState.setupDayNames[dayIndex] = dayName
            appState.setupDays[dayIndex] = exercises
            let planName = totalDays == 1 ? "1 Day Plan" : "\(totalDays) Day Plan"
            let plan = try DatabaseManager.shared.createPlan(name: planName, daysPerWeek: totalDays)
            
            for i in 1...totalDays {
                let name = appState.setupDayNames[i] ?? "Day \(i)"
                let day = try DatabaseManager.shared.createWorkoutDay(planId: plan.id!, dayNumber: i, name: name)

                for exercise in appState.setupDays[i] ?? [] {
                    _ = try DatabaseManager.shared.createExercise(
                        workoutDayId: day.id!,
                        name: exercise.name,
                        sets: exercise.sets,
                        reps: exercise.reps,
                        position: exercise.position
                    )
                }
            }
            
            appState.loadPlan(preferredPlanId: plan.id)
            appState.navigationPath.removeLast(appState.navigationPath.count)
            appState.setupDays.removeAll()
            appState.setupDayNames.removeAll()
        } catch {
            print("Failed to save plan: \(error)")
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise
    let position: Int
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(position).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(exercise.sets) × \(exercise.reps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
