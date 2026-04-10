import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var setupTask: Task<Void, Never>?

    var body: some View {
        let sdk = appState.sdkManager

        VStack(spacing: 24) {
            Text("Pikimin")
                .font(.largeTitle.bold())

            if let error = sdk.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { startSetup() }
                }
            } else if sdk.completed {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Setup complete!")
                }
                .onAppear {
                    appState.phase = .ready
                }
            } else if let component = sdk.currentComponent {
                VStack(spacing: 16) {
                    if sdk.extracting {
                        Text("Extracting \(component.displayName)...")
                            .font(.headline)
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Text("Downloading \(component.displayName)...")
                            .font(.headline)
                        ProgressView(value: sdk.downloadProgress)
                            .progressViewStyle(.linear)
                        Text("\(Int(sdk.downloadProgress * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Text("Welcome! Pikimin needs to download Android emulator components.")
                        .multilineTextAlignment(.center)
                    Text("This requires about 7 GB of disk space.")
                        .foregroundStyle(.secondary)
                    Button("Download & Install") { startSetup() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func startSetup() {
        setupTask?.cancel()
        appState.sdkManager.error = nil
        setupTask = Task { @MainActor in
            await appState.sdkManager.setupAll()
        }
    }
}
