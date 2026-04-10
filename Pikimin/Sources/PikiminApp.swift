import SwiftUI

@main
struct PikiminApp: App {
    @State private var appState = AppState()
    @State private var platformError: String?

    var body: some Scene {
        Window("Pikimin", id: "main") {
            Group {
                if let error = platformError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.red)
                        Text("Unsupported Platform")
                            .font(.title2.bold())
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch appState.phase {
                    case .setup:
                        SetupView()
                    case .ready:
                        MainView()
                    }
                }
            }
            .environment(appState)
            .frame(minWidth: 500, minHeight: 400)
            .onAppear {
                if let error = checkPlatform() {
                    platformError = error
                } else {
                    appState.checkSetupComplete()
                }
            }
        }
        .windowResizability(.contentMinSize)
    }

    private func checkPlatform() -> String? {
        #if !os(macOS)
        return "Pikimin only runs on macOS."
        #else
        #if !arch(arm64)
        return "Pikimin requires Apple Silicon (M1 or later). Intel Macs are not supported."
        #else
        return nil
        #endif
        #endif
    }
}
