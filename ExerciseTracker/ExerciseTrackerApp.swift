import SwiftUI

@main
struct ExerciseTrackerApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
                .environment(appState)
                .task {
                    appState.loadInitialData()
                }
        }
    }
}
