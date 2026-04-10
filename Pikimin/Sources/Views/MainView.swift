import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var stepInput: Int = 50_000
    @State private var dateText: String = ""

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

                // Date input helper
                if emu.state == .running {
                    HStack {
                        Text("Type into emulator:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("MM/DD/YYYY", text: $dateText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Button("Send") {
                            sendTextToEmulator(dateText)
                        }
                        .disabled(dateText.isEmpty)
                    }
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
                    if walk.isWalking {
                        Text(walk.elapsedText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
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

                if walk.isWalking || !walk.logEntries.isEmpty {
                    VStack(spacing: 8) {
                        if walk.isWalking {
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

                        // Walk log
                        Divider()
                        HStack {
                            Text("Walk Log")
                                .font(.caption.bold())
                            Spacer()
                            Text("\(walk.logEntries.count) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(walk.logEntries) { entry in
                                        HStack(spacing: 8) {
                                            Text(formatTime(entry.timestamp))
                                                .frame(width: 65, alignment: .leading)
                                            Text("Step \(entry.step)")
                                                .frame(width: 80, alignment: .leading)
                                            Text(entry.phase.rawValue)
                                                .frame(width: 70, alignment: .leading)
                                                .foregroundStyle(.secondary)
                                            Text("\(entry.latitude, specifier: "%.5f"), \(entry.longitude, specifier: "%.5f")")
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.system(.caption2, design: .monospaced))
                                        .id(entry.id)
                                    }
                                }
                                .padding(6)
                            }
                            .onChange(of: walk.logEntries.count) { _, _ in
                                if let last = walk.logEntries.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        .background(.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.emulatorManager.detectRunning()
        }
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

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private func sendTextToEmulator(_ text: String) {
        let adb = ADBHelper(sdkDir: appState.sdkDir)
        // Strip non-digits for the hidden EditText
        let digits = text.filter { $0.isNumber }
        // Clear existing field content
        Task.detached {
            for _ in 0..<20 {
                _ = try? adb.run("shell", "input", "keyevent", "67")
            }
            _ = try? adb.run("shell", "input", "text", digits)
        }
    }
}
