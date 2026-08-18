import SwiftUI

struct EditPlanView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var plan: Plan?
    @State private var planName: String = ""
    @State private var selectedDayIndex = 0
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    
    var body: some View {
        ScrollView {
                    VStack(spacing: 24) {
                        if let plan = plan {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Plan Name")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                TextField("Plan Name", text: $planName)
                                    .textInputAutocapitalization(.words)
                                    .font(.title3)
                                    .padding(16)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                    .task(id: planName) {
                                        guard planName != plan.name else { return }
                                        try? await Task.sleep(for: .milliseconds(600))
                                        guard !Task.isCancelled else { return }
                                        savePlanName(plan, name: planName)
                                    }
                            }
                            .padding(.horizontal, 20)
                            
                            if let days = plan.workoutDays, !days.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Select Day to Edit")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    
                                    Picker("Current Day", selection: $selectedDayIndex) {
                                        ForEach(days.indices, id: \.self) { index in
                                            let day = days[index]
                                            Text("Day \(day.dayNumber): \(day.name)").tag(index)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .padding(16)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal, 20)
                                
                                if selectedDayIndex < days.count {
                                    let day = days[selectedDayIndex]
                                    EditDaySection(day: day, plan: plan)
                                        .id(day.id)
                                }
                            }
                            
                            Spacer(minLength: 100)
                        } else {
                            ContentUnavailableView("No Plan", systemImage: "exclamationmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 320)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .alert("Delete Plan?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deletePlan()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your workout plan and all configuration. Your workout history will be preserved.")
            }
        .scrollDismissesKeyboard(.interactively)
        .alert("Unable to Delete Plan", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "Please try again.")
        }
        .onAppear {
            plan = appState.plan
            planName = appState.plan?.name ?? ""
        }
    }

    private func deletePlan() {
        do {
            try appState.deletePlan()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func savePlanName(_ originalPlan: Plan, name: String) {
        var updatedPlan = originalPlan
        updatedPlan.name = name
        do {
            try DatabaseManager.shared.updatePlan(updatedPlan)
            plan = updatedPlan
            appState.plan = updatedPlan
            if let index = appState.plans.firstIndex(where: { $0.id == updatedPlan.id }) {
                appState.plans[index] = updatedPlan
            }
        } catch {
            print("Failed to update plan name: \(error)")
        }
    }
}

struct EditDaySection: View {
    @Environment(AppState.self) private var appState
    let day: WorkoutDay
    let plan: Plan
    
    @State private var dayName: String
    @State private var exercises: [Exercise] = []
    @State private var showingAddExercise = false
    @State private var editingExercise: Exercise?
    
    init(day: WorkoutDay, plan: Plan) {
        self.day = day
        self.plan = plan
        _dayName = State(initialValue: day.name)
        _exercises = State(initialValue: day.exercises ?? [])
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Day Name")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TextField("Day Name", text: $dayName)
                    .textInputAutocapitalization(.words)
                    .font(.title3)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .task(id: dayName) {
                        guard dayName != day.name else { return }
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled else { return }
                        saveDayName(dayName)
                    }
            }
            .padding(.horizontal, 20)
            
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
                        Text("No Exercises")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Add exercises for \(dayName)")
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
                            EditExerciseRowView(
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
        .sheet(isPresented: $showingAddExercise) {
            NavigationStack {
                EditPlanExerciseEditView(day: day) { newExercise in
                    var ex = newExercise
                    ex.workoutDayId = day.id!
                    ex.position = exercises.count
                    do {
                        let saved = try DatabaseManager.shared.createExercise(
                            workoutDayId: day.id!,
                            name: ex.name,
                            sets: ex.sets,
                            reps: ex.reps,
                            position: ex.position
                        )
                        exercises.append(saved)
                        appState.loadPlan()
                    } catch {
                        print("Failed to add exercise: \(error)")
                    }
                    showingAddExercise = false
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingExercise) { exercise in
            NavigationStack {
                EditPlanExerciseEditView(day: day, exercise: exercise) { updatedExercise in
                    do {
                        try DatabaseManager.shared.updateExercise(updatedExercise)
                        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                            exercises[index] = updatedExercise
                        }
                        appState.loadPlan()
                    } catch {
                        print("Failed to update exercise: \(error)")
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

    private func saveDayName(_ name: String) {
        var updatedDay = day
        updatedDay.name = name
        do {
            try DatabaseManager.shared.updateWorkoutDay(updatedDay)
            guard var activePlan = appState.plan,
                  var days = activePlan.workoutDays,
                  let index = days.firstIndex(where: { $0.id == updatedDay.id }) else { return }
            days[index] = updatedDay
            activePlan.workoutDays = days
            appState.plan = activePlan
        } catch {
            print("Failed to update day name: \(error)")
        }
    }
    
    private func deleteExercise(at index: Int) {
        let exercise = exercises[index]
        do {
            try DatabaseManager.shared.deleteExercise(exercise)
            exercises.remove(at: index)
            updatePositions()
            try DatabaseManager.shared.reorderExercises(exercises)
            appState.loadPlan()
        } catch {
            print("Failed to delete exercise: \(error)")
        }
    }
}

struct EditExerciseRowView: View {
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

struct EditPlanExerciseEditView: View {
    @Environment(\.dismiss) private var dismiss
    let day: WorkoutDay
    let exercise: Exercise?
    let onSave: (Exercise) -> Void
    
    @State private var name: String
    @State private var sets: Int
    @State private var reps: Int
    @State private var showingDeleteConfirmation = false
    
    private var isEditing: Bool { exercise != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && sets > 0 && reps > 0 }
    
    init(day: WorkoutDay, exercise: Exercise? = nil, onSave: @escaping (Exercise) -> Void) {
        self.day = day
        self.exercise = exercise
        self.onSave = onSave
        _name = State(initialValue: exercise?.name ?? "")
        _sets = State(initialValue: exercise?.sets ?? 3)
        _reps = State(initialValue: exercise?.reps ?? 8)
    }
    
    var body: some View {
        ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercise")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            TextField("Exercise Name", text: $name)
                                .textInputAutocapitalization(.words)
                                .font(.title3)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Volume")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Sets")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Button("−") { sets = max(1, sets - 1) }
                                        TextField("Sets", value: $sets, format: .number)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 64)
                                            .textFieldStyle(.roundedBorder)
                                        Button("+") { sets = min(20, sets + 1) }
                                    }
                                }
                                .padding(20)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Reps")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Button("−") { reps = max(1, reps - 1) }
                                        TextField("Reps", value: $reps, format: .number)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 64)
                                            .textFieldStyle(.roundedBorder)
                                        Button("+") { reps = min(50, reps + 1) }
                                    }
                                }
                                .padding(20)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        if isEditing {
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Exercise", systemImage: "trash")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.red)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            .navigationTitle(isEditing ? "Edit Exercise" : "Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let newExercise = Exercise(
                            id: exercise?.id,
                            workoutDayId: day.id!,
                            name: name.trimmingCharacters(in: .whitespaces),
                            sets: sets,
                            reps: reps,
                            position: exercise?.position ?? 0
                        )
                        onSave(newExercise)
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .alert("Delete Exercise?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let ex = exercise {
                        try? DatabaseManager.shared.deleteExercise(ex)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove \"\(exercise?.name ?? "")\" from \(day.name).")
            }
        }
    }
