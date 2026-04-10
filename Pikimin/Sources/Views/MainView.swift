import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var stepInput: Int = 50_000

    var body: some View {
        let emu = appState.emulatorManager
        let walk = appState.walkState

        VStack(spacing: 0) {
            Text("Pikimin")
                .font(.title2.bold())
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            // Emulator section
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(emuStatusColor(emu.state))
                        .frame(width: 10, height: 10)
                    Text("Emulator: \(emu.state.rawValue)")
                        .font(.headline)
                    Spacer()
                    Button(emuButtonTitle(emu.state)) {
                        if emu.state == .stopped {
                            Task { await emu.start() }
                        } else {
                            appState.walkSimulator.stop()
                            emu.stop()
                        }
                    }
                    .disabled(emu.state == .booting)
                }

                if let error = emu.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)

            Divider()

            // Walk section
            VStack(spacing: 12) {
                HStack {
                    Text("Walk Simulation")
                        .font(.headline)
                    Spacer()
                }

                HStack {
                    Text("Steps:")
                    TextField("Steps", value: $stepInput, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(walk.isWalking)

                    Spacer()

                    Button(walk.isWalking ? "Stop Walk" : "Start Walk") {
                        if walk.isWalking {
                            appState.walkSimulator.stop()
                        } else {
                            walk.totalSteps = stepInput
                            appState.walkSimulator.start()
                        }
                    }
                    .disabled(emu.state != .running)
                }

                if walk.isWalking {
                    VStack(spacing: 8) {
                        ProgressView(value: walk.progress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text("\(walk.currentStep) / \(walk.totalSteps)")
                                .monospacedDigit()
                            Spacer()
                            Text(walk.phase.rawValue)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(walk.percentText)
                                .monospacedDigit()
                        }
                        .font(.caption)

                        HStack {
                            Text("GPS: \(walk.latitude, specifier: "%.6f"), \(walk.longitude, specifier: "%.6f")")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .padding(16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emuStatusColor(_ state: EmulatorState) -> Color {
        switch state {
        case .stopped: return .red
        case .booting: return .orange
        case .running: return .green
        }
    }

    private func emuButtonTitle(_ state: EmulatorState) -> String {
        switch state {
        case .stopped: return "Start Emulator"
        case .booting: return "Starting..."
        case .running: return "Stop Emulator"
        }
    }
}
