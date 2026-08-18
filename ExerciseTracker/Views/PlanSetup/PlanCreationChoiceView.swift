import SwiftUI
import UniformTypeIdentifiers

struct PlanCreationChoiceView: View {
    @Environment(AppState.self) private var appState
    @State private var showingFileImporter = false
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("WorkoutMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)

                VStack(spacing: 8) {
                    Text("Create a Workout Plan")
                        .font(.title2.bold())
                    Text("Build it set by set, or import a structured plan file.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    Button {
                        appState.setupDays.removeAll()
                        appState.setupDayNames.removeAll()
                        appState.navigationPath.append(WorkoutRoute.manualPlan)
                    } label: {
                        PlanCreationOption(
                            title: "Create Manually",
                            detail: "Choose training days and add exercises yourself.",
                            symbol: "square.and.pencil"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingFileImporter = true
                    } label: {
                        PlanCreationOption(
                            title: "Import Plan File",
                            detail: "Select a .txt or .json plan in the documented format.",
                            symbol: "doc.badge.plus"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("New Plan")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText, .json]
        ) { result in
            importFile(result)
        }
        .alert("Could Not Import Plan", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Please choose a valid plan file.")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let grantedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if grantedAccess { url.stopAccessingSecurityScopedResource() }
            }
            try appState.importPlan(from: Data(contentsOf: url))
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct PlanCreationOption: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}
