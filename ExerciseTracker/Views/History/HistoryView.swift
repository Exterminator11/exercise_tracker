import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [WorkoutSession] = []
    @State private var sessionPendingDeletion: WorkoutSession?
    @State private var hasMoreSessions = true
    @State private var isLoadingMore = false
    private let pageSize = 30
    
    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Workouts Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Complete a workout to see it here")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        Button {
                            appState.navigationPath.append(WorkoutRoute.workoutDetail(sessionId: session.id!))
                        } label: {
                            HistoryRowView(session: session)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                sessionPendingDeletion = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            if session.id == sessions.last?.id {
                                loadMoreSessions()
                            }
                        }
                    }
                    if isLoadingMore {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .alert("Delete Workout?", isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { if !$0 { sessionPendingDeletion = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    deleteSelectedSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes this workout and its set weights and notes.")
            }
            .onAppear {
                loadSessions()
            }
    }
    
    private func loadSessions() {
        sessions = []
        hasMoreSessions = true
        loadMoreSessions()
    }

    private func loadMoreSessions() {
        guard hasMoreSessions, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let nextPage = try DatabaseManager.shared.fetchCompletedSessions(limit: pageSize, offset: sessions.count)
            sessions.append(contentsOf: nextPage)
            hasMoreSessions = nextPage.count == pageSize
        } catch {
            print("Failed to load history: \(error)")
        }
        isLoadingMore = false
    }

    private func deleteSelectedSession() {
        guard let session = sessionPendingDeletion, let sessionId = session.id else { return }
        do {
            try DatabaseManager.shared.deleteCompletedSession(sessionId)
            sessions.removeAll { $0.id == sessionId }
        } catch {
            print("Failed to delete workout: \(error)")
        }
        sessionPendingDeletion = nil
    }
}

struct HistoryRowView: View {
    let session: WorkoutSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.dayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(session.completedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 16) {
                Label("\(session.exerciseCount ?? session.exerciseLogs?.count ?? 0) exercises", systemImage: "list.bullet")
                Label("Completed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WorkoutDetailView: View {
    @Environment(AppState.self) private var appState
    let sessionId: Int64
    @State private var session: WorkoutSession?
    @State private var logs: [ExerciseLog] = []
    @State private var setLogsByExerciseLogId: [Int64: [SetLog]] = [:]
    
    var body: some View {
        ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let session = session {
                            HeaderView(session: session)
                            
                            LazyVStack(spacing: 16) {
                                ForEach(logs) { log in
                                    ExerciseDetailRow(log: log, setLogs: setLogsByExerciseLogId[log.id ?? -1] ?? [])
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            ContentUnavailableView("Workout Not Found", systemImage: "exclamationmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 320)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            .navigationTitle("Workout Detail")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadDetail()
            }
    }
    
    private func loadDetail() {
        do {
            if let result = try DatabaseManager.shared.fetchSessionDetail(sessionId) {
                session = result.0
                logs = result.1.sorted { $0.id! < $1.id! }
                let setLogs = try DatabaseManager.shared.fetchSetLogs(forSessionId: sessionId)
                setLogsByExerciseLogId = Dictionary(grouping: setLogs, by: \.exerciseLogId)
            }
        } catch {
            print("Failed to load detail: \(error)")
        }
    }
}

struct HeaderView: View {
    let session: WorkoutSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.dayName)
                .font(.title)
                .fontWeight(.bold)
            
            Text(session.completedAt?.formatted(date: .complete, time: .shortened) ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let completed = session.completedAt {
                let duration = completed.timeIntervalSince(session.startedAt)
                let minutes = Int(duration / 60)
                Text("Duration: \(minutes) min")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }
}

struct ExerciseDetailRow: View {
    let log: ExerciseLog
    let setLogs: [SetLog]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(log.exerciseName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(log.plannedSets) × \(log.targetDescription ?? "\(log.plannedReps) reps")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if setLogs.isEmpty {
                if let weight = log.weight {
                    Label(formatWeight(weight), systemImage: "scalemass")
                        .foregroundStyle(.blue)
                }
                if let notes = log.notes, !notes.isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(setLogs) { setLog in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Set \(setLog.setNumber)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let weight = setLog.weight {
                                Text(formatWeight(weight))
                                    .foregroundStyle(.blue)
                            }
                            if let duration = setLog.durationSeconds {
                                Text("\(duration) sec")
                                    .foregroundStyle(.blue)
                            }
                        }
                        if let notes = setLog.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f lb", weight)
        } else {
            return String(format: "%.1f lb", weight)
        }
    }
}
