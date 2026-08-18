import SwiftUI

struct ExerciseEditView: View {
    @Environment(\.dismiss) private var dismiss
    let dayIndex: Int
    let totalDays: Int
    let exercise: Exercise?
    let onSave: (Exercise) -> Void
    
    @State private var name: String
    @State private var sets: Int
    @State private var reps: Int
    @State private var showingDeleteConfirmation = false
    
    private var isEditing: Bool { exercise != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && sets > 0 && reps > 0 }
    
    init(dayIndex: Int, totalDays: Int, exercise: Exercise?, onSave: @escaping (Exercise) -> Void) {
        self.dayIndex = dayIndex
        self.totalDays = totalDays
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
                            workoutDayId: exercise?.workoutDayId ?? 0,
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
                Text("This will permanently remove \"\(exercise?.name ?? "")\" from this workout day.")
        }
    }

}
