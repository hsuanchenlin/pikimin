import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var setupTask: Task<Void, Never>?
    @State private var showAutoDownload = false

    var body: some View {
        let sdk = appState.sdkManager

        ScrollView {
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
                        appState.checkSetupComplete()
                    }
                } else if let component = sdk.currentComponent {
                    // Active download in progress
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
                            HStack {
                                Text("\(formatBytes(sdk.downloadedBytes)) / \(formatBytes(sdk.totalBytes))")
                                    .monospacedDigit()
                                Spacer()
                                Text("\(Int(sdk.downloadProgress * 100))%")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else if showAutoDownload {
                    // Auto-download option
                    VStack(spacing: 16) {
                        Text("Auto-download (~3 GB, may be slow)")
                            .font(.headline)
                        Button("Download & Install") { startSetup() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Button("Back") { showAutoDownload = false }
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Main setup instructions
                    VStack(spacing: 20) {
                        Text("Pikimin needs the Android Emulator to run.")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Option 1: Install Android Studio (recommended)")
                                .font(.subheadline.bold())
                            Text("Download and install Android Studio, then open it once to complete setup.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Android Studio Download Page") {
                                NSWorkspace.shared.open(URL(string: "https://developer.android.com/studio")!)
                            }

                            Divider()

                            Text("Option 2: Command Line (if you have Homebrew)")
                                .font(.subheadline.bold())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Run these commands in Terminal:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("""
                                brew install --cask android-commandlinetools
                                sdkmanager "platform-tools" "emulator" \
                                  "system-images;android-35;google_apis_playstore;arm64-v8a"
                                """)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(.black.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .frame(maxWidth: 400, alignment: .leading)

                        Divider()

                        HStack(spacing: 16) {
                            Button("Re-check") {
                                appState.checkSetupComplete()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Auto-download instead") {
                                showAutoDownload = true
                            }
                            .foregroundStyle(.secondary)
                        }

                        // Show detected paths
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Searched locations:")
                                .font(.caption2.bold())
                                .foregroundStyle(.tertiary)
                            ForEach(AppState.searchPaths, id: \.path) { path in
                                HStack(spacing: 4) {
                                    Image(systemName: appState.isValidSDK(at: path) ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundColor(appState.isValidSDK(at: path) ? .green : .gray)
                                        .font(.caption2)
                                    Text(path.path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .frame(maxWidth: 400, alignment: .leading)
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        }
        return String(format: "%.0f MB", mb)
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
