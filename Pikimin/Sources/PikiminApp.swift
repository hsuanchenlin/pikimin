import SwiftUI

@main
struct PikiminApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("Pikimin", id: "main") {
            Group {
                switch appState.phase {
                case .setup:
                    SetupView()
                case .ready:
                    MainView()
                }
            }
            .environment(appState)
            .frame(minWidth: 500, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
    }
}
