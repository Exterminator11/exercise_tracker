import SwiftUI

struct ActiveWorkoutView: View {
    enum FocusedField: Hashable {
        case weight(Int64)
        case notes(Int64)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var exerciseLogs: [ExerciseLog] = []
    @State private var setLogsByExerciseLogId: [Int64: [SetLog]] = [:]
    @State private var expandedLogId: Int64?
    @State private var showingFinishConfirmation = false
    @State private var exerciseHistory: [String: ExerciseHistory] = [:]
    @State private var dirtySetLogIDs: Set<Int64> = []
    @State private var persistenceWorkItem: DispatchWorkItem?
    @FocusState private var focusedField: FocusedField?
    
    var session: WorkoutSession? {
        appState.currentSession ?? appState.inProgressSession
    }
    
    var completedCount: Int {
        exerciseLogs.filter { $0.completed }.count
    }
    
    var allCompleted: Bool {
        !exerciseLogs.isEmpty && completedCount == exerciseLogs.count
    }
    
    var body: some View {
        Group {
                Group {
                    if let session = session {
                        VStack(spacing: 0) {
                            SessionHeader(session: session, completedCount: completedCount, totalCount: exerciseLogs.count)
                            
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(exerciseLogs) { log in
                                        ExerciseTrackingRow(
                                            log: log,
                                            history: exerciseHistory[normalizedName(log.exerciseName)],
                                            isExpanded: expandedLogId == log.id,
                                            onToggleExpand: {
                                                withAnimation(.spring(response: 0.3)) {
                                                    expandedLogId = expandedLogId == log.id ? nil : log.id
                                                }
                                            },
                                            setLogs: setLogsByExerciseLogId[log.id ?? -1] ?? [],
                                            onSetWeightChange: updateSetWeight,
                                            onSetDurationChange: updateSetDuration,
                                            onSetNotesChange: updateSetNotes,
                                            onCompleteToggle: { completed in
                                                updateLogCompletion(log, completed: completed)
                                            },
                                            focusedField: $focusedField
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            
                            FinishWorkoutButton(
                                isEnabled: allCompleted || !exerciseLogs.isEmpty,
                                allCompleted: allCompleted,
                                onTap: { showingFinishConfirmation = true }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    } else {
                        ContentUnavailableView("No Active Session", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
                .navigationTitle(session?.dayName ?? "Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Exit") {
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                            persistWorkoutChanges()
                        }
                    }
                }
                .alert("Finish Workout?", isPresented: $showingFinishConfirmation) {
                    if allCompleted {
                        Button("Finish", role: .destructive) {
                            finishWorkout()
                        }
                    } else {
                        Button("Finish Anyway", role: .destructive) {
                            finishWorkout()
                        }
                        Button("Complete All First", role: .cancel) {}
                    }
                } message: {
                    if allCompleted {
                        Text("Mark this workout as complete?")
                    } else {
                        Text("\(exerciseLogs.count - completedCount) exercise\(exerciseLogs.count - completedCount == 1 ? "" : "s") not completed. Finish anyway?")
                    }
                }
                .onAppear {
                    loadData()
                }
                .onChange(of: focusedField) { oldValue, newValue in
                    if oldValue != nil && oldValue != newValue {
                persistWorkoutChanges()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .inactive || newPhase == .background {
                        persistWorkoutChanges()
                    }
                }
                .onDisappear { persistWorkoutChanges() }
        }
    }
    
    private func loadData() {
        guard let session = session else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let (_, logs) = try DatabaseManager.shared.fetchSessionWithLogs(session.id!) else { return }
                let orderedLogs = logs.sorted { $0.id! < $1.id! }
                let setLogs = try DatabaseManager.shared.fetchSetLogs(forSessionId: session.id!)
                let names = Array(Set(orderedLogs.map { self.normalizedName($0.exerciseName) }))
                let history = try DatabaseManager.shared.fetchExerciseHistory(forExerciseNames: names)
                DispatchQueue.main.async {
                    exerciseLogs = orderedLogs
                    setLogsByExerciseLogId = Dictionary(grouping: setLogs, by: \.exerciseLogId)
                    exerciseHistory = history
                }
            } catch { print("Failed to load workout: \(error)") }
        }
    }
    
    private func updateSetWeight(_ setLog: SetLog, weight: Double?) {
        guard var setLogs = setLogsByExerciseLogId[setLog.exerciseLogId],
              let index = setLogs.firstIndex(where: { $0.id == setLog.id }) else { return }
        setLogs[index].weight = weight
        setLogsByExerciseLogId[setLog.exerciseLogId] = setLogs
        if let id = setLog.id { dirtySetLogIDs.insert(id) }
        schedulePersistence()
    }

    private func updateSetNotes(_ setLog: SetLog, notes: String?) {
        guard var setLogs = setLogsByExerciseLogId[setLog.exerciseLogId],
              let index = setLogs.firstIndex(where: { $0.id == setLog.id }) else { return }
        setLogs[index].notes = notes?.isEmpty == true ? nil : notes
        setLogsByExerciseLogId[setLog.exerciseLogId] = setLogs
        if let id = setLog.id { dirtySetLogIDs.insert(id) }
        schedulePersistence()
    }

    private func updateSetDuration(_ setLog: SetLog, durationSeconds: Int?) {
        guard var setLogs = setLogsByExerciseLogId[setLog.exerciseLogId],
              let index = setLogs.firstIndex(where: { $0.id == setLog.id }) else { return }
        setLogs[index].durationSeconds = durationSeconds
        setLogsByExerciseLogId[setLog.exerciseLogId] = setLogs
        if let id = setLog.id { dirtySetLogIDs.insert(id) }
        schedulePersistence()
    }
    
    private func updateLogCompletion(_ log: ExerciseLog, completed: Bool) {
        guard let index = exerciseLogs.firstIndex(where: { $0.id == log.id }) else { return }
        exerciseLogs[index].completed = completed
        try? DatabaseManager.shared.updateExerciseLog(exerciseLogs[index])
    }

    private func persistWorkoutChanges() {
        persistenceWorkItem?.cancel()
        persistenceWorkItem = nil
        let changedSetLogs = setLogsByExerciseLogId.values
            .flatMap { $0 }
            .filter { log in log.id.map(dirtySetLogIDs.contains) ?? false }
        guard !changedSetLogs.isEmpty else { return }
        let savedIDs = changedSetLogs.compactMap(\.id)
        DispatchQueue.global(qos: .utility).async {
            guard (try? DatabaseManager.shared.updateWorkoutLogs([], setLogs: changedSetLogs)) != nil else { return }
            DispatchQueue.main.async { dirtySetLogIDs.subtract(savedIDs) }
        }
    }

    private func schedulePersistence() {
        persistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { persistWorkoutChanges() }
        persistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350), execute: workItem)
    }
    
    private func finishWorkout() {
        do {
            focusedField = nil
            let changedSetLogs = setLogsByExerciseLogId.values.flatMap { $0 }.filter { $0.id.map(dirtySetLogIDs.contains) ?? false }
            try DatabaseManager.shared.updateWorkoutLogs([], setLogs: changedSetLogs)
            dirtySetLogIDs.removeAll()
            try appState.completeSession()
            dismiss()
        } catch {
            print("Failed to finish workout: \(error)")
        }
    }

    private func normalizedName(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

struct SessionHeader: View {
    let session: WorkoutSession
    let completedCount: Int
    let totalCount: Int
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.dayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(completedCount) / \(totalCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            ProgressView(value: Double(completedCount), total: Double(max(totalCount, 1)))
                .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}

struct ExerciseTrackingRow: View {
    let log: ExerciseLog
    let history: ExerciseHistory?
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let setLogs: [SetLog]
    let onSetWeightChange: (SetLog, Double?) -> Void
    let onSetDurationChange: (SetLog, Int?) -> Void
    let onSetNotesChange: (SetLog, String?) -> Void
    let onCompleteToggle: (Bool) -> Void
    let focusedField: FocusState<ActiveWorkoutView.FocusedField?>.Binding
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    Image(systemName: log.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(log.completed ? .green : .secondary)
                        .contentTransition(.symbolEffect)
                        .animation(.spring(response: 0.3), value: log.completed)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let history {
                            Text("PB: \(formatPersonalBest(history.personalBest))  ·  Latest: \(formatLatest(history))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                        Text("\(log.plannedSets) × \(log.targetDescription ?? "\(log.plannedReps) reps")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .animation(.spring(response: 0.3), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 16) {
                    ForEach(setLogs) { setLog in
                        SetTrackingRow(
                            setLog: setLog,
                            isTimedExercise: log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Plank") == .orderedSame,
                            focusedField: focusedField,
                            onWeightChange: onSetWeightChange,
                            onDurationChange: onSetDurationChange,
                            onNotesChange: onSetNotesChange
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    if isNewPersonalBest {
                        Label("New PB", systemImage: "trophy.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                    }

                    Button {
                        focusedField.wrappedValue = nil
                        onCompleteToggle(!log.completed)
                    } label: {
                        HStack {
                            Image(systemName: log.completed ? "checkmark.circle.fill" : "circle")
                            Text(log.completed ? "Mark Incomplete" : "Mark Complete")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(log.completed ? .orange : .green)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3), value: isExpanded)
        .animation(.spring(response: 0.3), value: log.completed)
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(format: "%.0f lb", weight) : String(format: "%.1f lb", weight)
    }
    private func formatPersonalBest(_ best: PersonalBest) -> String {
        if let duration = best.durationSeconds, log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Plank") == .orderedSame { return "\(duration) sec" }
        return best.weight.map(formatWeight) ?? "—"
    }
    private var isNewPersonalBest: Bool {
        guard log.completed else { return false }
        if log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Plank") == .orderedSame {
            return (setLogs.compactMap(\.durationSeconds).max() ?? 0) > (history?.personalBest.durationSeconds ?? 0)
        }
        return (setLogs.compactMap(\.weight).max() ?? 0) > (history?.personalBest.weight ?? 0)
    }
    private func formatLatest(_ history: ExerciseHistory) -> String {
        if log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Plank") == .orderedSame {
            return history.latestDurationSeconds.map { "\($0) sec" } ?? "—"
        }
        return history.latestWeight.map(formatWeight) ?? "—"
    }
}

struct SetTrackingRow: View {
    let setLog: SetLog
    let isTimedExercise: Bool
    let focusedField: FocusState<ActiveWorkoutView.FocusedField?>.Binding
    let onWeightChange: (SetLog, Double?) -> Void
    let onDurationChange: (SetLog, Int?) -> Void
    let onNotesChange: (SetLog, String?) -> Void

    @State private var weightText = ""
    @State private var durationText = ""
    @State private var notesText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set \(setLog.setNumber)")
                .font(.headline)

            HStack(spacing: 8) {
                TextField(isTimedExercise ? "Seconds" : "Weight", text: isTimedExercise ? $durationText : $weightText)
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: .weight(setLog.id!))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: isTimedExercise ? durationText : weightText) { _, newValue in
                        let filtered = newValue.filter { "0123456789.".contains($0) }
                        if filtered != newValue {
                            if isTimedExercise { durationText = filtered } else { weightText = filtered }
                        } else {
                            if isTimedExercise { onDurationChange(setLog, Int(filtered)) } else { onWeightChange(setLog, Double(filtered)) }
                        }
                    }
                Text(isTimedExercise ? "sec" : "lb")
                    .foregroundStyle(.secondary)
            }

            TextField("Notes (optional)", text: $notesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2, reservesSpace: true)
                .focused(focusedField, equals: .notes(setLog.id!))
                .onChange(of: notesText) { _, newValue in
                    onNotesChange(setLog, newValue.isEmpty ? nil : newValue)
                }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if let weight = setLog.weight {
                weightText = weight.rounded() == weight
                    ? String(format: "%.0f", weight)
                    : String(format: "%.1f", weight)
            }
            if let duration = setLog.durationSeconds { durationText = String(duration) }
            notesText = setLog.notes ?? ""
        }
    }
}

struct FinishWorkoutButton: View {
    let isEnabled: Bool
    let allCompleted: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: allCompleted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                Text(allCompleted ? "FINISH WORKOUT" : "FINISH WORKOUT")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .tint(allCompleted ? .green : .orange)
        .disabled(!isEnabled)
    }
}
