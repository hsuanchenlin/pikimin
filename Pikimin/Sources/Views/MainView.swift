import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var stepInput: Int = 50_000
    @State private var dateText: String = ""
    @State private var coordsInput: String = ""
    @State private var showHelp: Bool = false
    @State private var showSaveDialog: Bool = false
    @State private var savePointName: String = ""
    @State private var showEditDialog: Bool = false
    @State private var editingPoint: SavedPoint?
    @State private var editPointName: String = ""
    @State private var editPointCoords: String = ""

    var body: some View {
        let emu = appState.emulatorManager
        let walk = appState.walkState

        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text("Pikimin")
                        .font(.title.bold())
                    Text("Pikmin Bloom Walk Simulator")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Emulator Card
                GroupBox {
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(emuStatusColor(emu.state))
                                .frame(width: 10, height: 10)
                                .shadow(color: emuStatusColor(emu.state).opacity(0.5), radius: 4)
                            Text("Emulator")
                                .font(.headline)
                            Text(emu.state.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if emu.state == .stopped {
                                    Task { await emu.start() }
                                } else {
                                    appState.walkSimulator.stop()
                                    emu.stop()
                                }
                            } label: {
                                Label(emuButtonTitle(emu.state),
                                      systemImage: emu.state == .stopped ? "play.fill" : "stop.fill")
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(emu.state == .stopped ? .green : .red)
                            .disabled(emu.state == .booting)
                        }

                        if let error = emu.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Text input helper
                        if emu.state == .running {
                            Divider()
                            HStack(spacing: 8) {
                                Image(systemName: "keyboard")
                                    .foregroundStyle(.secondary)
                                TextField("Type text (e.g. 01011990)", text: $dateText)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    sendTextToEmulator(dateText)
                                } label: {
                                    Label("Send", systemImage: "paperplane.fill")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                                .disabled(dateText.isEmpty)
                            }
                            Text("Tap the input field in the emulator first (numpad should appear), then click Send")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } label: {
                    Label("Emulator", systemImage: "iphone")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Walk Card
                GroupBox {
                    VStack(spacing: 14) {
                        // Walk settings row 1: mode + speed
                        HStack(spacing: 12) {
                            Picker("Mode", selection: Binding(
                                get: { walk.mode },
                                set: { walk.mode = $0 }
                            )) {
                                ForEach(WalkMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .frame(width: 180)
                            .disabled(walk.isWalking)

                            Picker("Speed", selection: Binding(
                                get: { walk.speed },
                                set: { walk.speed = $0 }
                            )) {
                                ForEach(WalkSpeed.allCases, id: \.self) { speed in
                                    Text(speed.rawValue).tag(speed)
                                }
                            }
                            .frame(width: 120)
                            .disabled(walk.isWalking)

                            Spacer()
                        }

                        // Walk settings row 2: mode-specific options
                        if walk.mode == .fixedDirection && !walk.isWalking {
                            HStack(spacing: 8) {
                                Text("Direction:")
                                    .font(.subheadline)
                                Picker("", selection: Binding(
                                    get: { walk.direction },
                                    set: { walk.direction = $0 }
                                )) {
                                    ForEach(WalkDirection.allCases, id: \.self) { dir in
                                        Text(dir.rawValue).tag(dir)
                                    }
                                }
                                .frame(width: 80)
                                Spacer()
                            }
                        }

                        if walk.mode == .toDestination && !walk.isWalking {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin")
                                        .foregroundStyle(.blue)
                                    TextField("lat, lon (e.g. 37.3239, -121.8950)", text: $coordsInput)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: coordsInput) { _, newValue in
                                        walk.destCoords = newValue
                                    }
                                    Button {
                                        if let dest = walk.parsedDestination {
                                            savePointName = String(format: "%.4f, %.4f", dest.latitude, dest.longitude)
                                            showSaveDialog = true
                                        }
                                    } label: {
                                        Image(systemName: "star.fill")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(walk.parsedDestination == nil)
                                    .help("Save to favorites")
                                }

                                if !walk.savedPoints.isEmpty {
                                    HStack(spacing: 8) {
                                        Image(systemName: "star")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(walk.savedPoints) { point in
                                                    Button {
                                                        coordsInput = point.coordsString
                                                        walk.destCoords = point.coordsString
                                                    } label: {
                                                        Text(point.name)
                                                            .font(.caption)
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .contextMenu {
                                                        Button {
                                                            editingPoint = point
                                                            editPointName = point.name
                                                            editPointCoords = point.coordsString
                                                            showEditDialog = true
                                                        } label: {
                                                            Label("Edit", systemImage: "pencil")
                                                        }
                                                        Divider()
                                                        Button(role: .destructive) {
                                                            deletePoint(point)
                                                        } label: {
                                                            Label("Delete", systemImage: "trash")
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Steps + start/stop
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.walk")
                                    .foregroundStyle(.blue)
                                Text("Steps:")
                                    .font(.subheadline)
                            }
                            TextField("Steps", value: $stepInput, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .disabled(walk.isWalking)

                            Spacer()

                            if walk.isWalking {
                                Text(walk.elapsedText)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }

                            Button {
                                if walk.isWalking {
                                    appState.walkSimulator.stop()
                                } else {
                                    walk.totalSteps = stepInput
                                    appState.walkSimulator.start()
                                }
                            } label: {
                                Label(walk.isWalking ? "Stop" : "Start Walk",
                                      systemImage: walk.isWalking ? "stop.fill" : "figure.walk")
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(walk.isWalking ? .orange : .blue)
                            .disabled(emu.state != .running)
                        }

                        if walk.isWalking {
                            VStack(spacing: 10) {
                                ProgressView(value: walk.progress)
                                    .progressViewStyle(.linear)
                                    .tint(.blue)

                                HStack {
                                    Label("\(walk.currentStep)", systemImage: "shoeprints.fill")
                                        .monospacedDigit()
                                    Text("/ \(walk.totalSteps)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    Spacer()
                                    Text(walk.phase.rawValue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(phaseColor(walk.phase).opacity(0.15))
                                        .clipShape(Capsule())
                                    Spacer()
                                    Text(walk.percentText)
                                        .fontWeight(.medium)
                                        .monospacedDigit()
                                }
                                .font(.caption)

                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(.blue)
                                        .font(.caption2)
                                    Text("\(walk.latitude, specifier: "%.6f"), \(walk.longitude, specifier: "%.6f")")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }

                        // Walk log
                        if walk.isWalking || !walk.logEntries.isEmpty {
                            Divider()
                            HStack {
                                Label("Walk Log", systemImage: "list.bullet.rectangle")
                                    .font(.caption.bold())
                                Spacer()
                                Text("\(walk.logEntries.count) entries")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 3) {
                                        ForEach(walk.logEntries) { entry in
                                            HStack(spacing: 8) {
                                                Text(formatTime(entry.timestamp))
                                                    .frame(width: 60, alignment: .leading)
                                                    .foregroundStyle(.secondary)
                                                Text("Step \(entry.step)")
                                                    .frame(width: 75, alignment: .leading)
                                                    .fontWeight(.medium)
                                                Text(entry.phase.rawValue)
                                                    .frame(width: 65, alignment: .leading)
                                                    .foregroundStyle(phaseColor(entry.phase))
                                                Text("\(entry.latitude, specifier: "%.5f"), \(entry.longitude, specifier: "%.5f")")
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .font(.system(.caption2, design: .monospaced))
                                            .id(entry.id)
                                        }
                                    }
                                    .padding(8)
                                }
                                .onChange(of: walk.logEntries.count) { _, _ in
                                    if let last = walk.logEntries.last {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                            .frame(maxHeight: 160)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                } label: {
                    Label("Walk Simulation", systemImage: "figure.walk")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Help Card
                GroupBox {
                    DisclosureGroup(isExpanded: $showHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            helpSection(
                                icon: "location.fill",
                                title: "Setting GPS Location",
                                steps: [
                                    "Click the \"...\" button on the emulator toolbar",
                                    "Click \"Location\" in the left sidebar",
                                    "Enter coordinates or click on the map",
                                    "Click \"Set Location\"",
                                    "Tip: Click \"SAVE POINT\" to save locations for later"
                                ]
                            )

                            Divider()

                            helpSection(
                                icon: "keyboard",
                                title: "Date of Birth Input",
                                steps: [
                                    "If the numpad doesn't appear: go to emulator Settings > System > Keyboard > On-screen keyboard > turn off ADB Keyboard",
                                    "Tap the date field in Pikmin Bloom — a numpad should appear",
                                    "Type the date as digits in the panel above (e.g. 01011990)",
                                    "Click Send"
                                ]
                            )

                            Divider()

                            helpSection(
                                icon: "exclamationmark.triangle",
                                title: "Important",
                                steps: [
                                    "Log out of Pikmin Bloom on your phone before logging in on the emulator",
                                    "Only use one device at a time to avoid account issues"
                                ]
                            )
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(showHelp ? "Hide Instructions" : "Show Instructions")
                            .font(.subheadline)
                    }
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.emulatorManager.detectRunning()
            appState.walkState.savedPoints = SavedPoint.load()
        }
        .alert("Save Location", isPresented: $showSaveDialog) {
            TextField("Name", text: $savePointName)
            Button("Save") {
                saveCurrentCoords(name: savePointName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this location")
        }
        .alert("Edit Location", isPresented: $showEditDialog) {
            TextField("Name", text: $editPointName)
            TextField("Coordinates (lat, lon)", text: $editPointCoords)
            Button("Save") {
                if let point = editingPoint {
                    updatePoint(point, name: editPointName, coords: editPointCoords)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Edit the name or coordinates")
        }
    }

    private func phaseColor(_ phase: WalkPhase) -> Color {
        switch phase {
        case .idle: return .gray
        case .wandering: return .green
        case .returning: return .orange
        case .toDestination: return .blue
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
        case .stopped: return "Start"
        case .booting: return "Starting..."
        case .running: return "Stop"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private func helpSection(icon: String, title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .trailing)
                    Text(step)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func saveCurrentCoords(name: String) {
        guard let dest = appState.walkState.parsedDestination else { return }
        let pointName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(format: "%.4f, %.4f", dest.latitude, dest.longitude)
            : name.trimmingCharacters(in: .whitespaces)
        let point = SavedPoint(name: pointName, latitude: dest.latitude, longitude: dest.longitude)
        appState.walkState.savedPoints.append(point)
        SavedPoint.save(appState.walkState.savedPoints)
    }

    private func deletePoint(_ point: SavedPoint) {
        appState.walkState.savedPoints.removeAll { $0.id == point.id }
        SavedPoint.save(appState.walkState.savedPoints)
    }

    private func updatePoint(_ point: SavedPoint, name: String, coords: String) {
        let parts = coords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let newName = trimmedName.isEmpty ? String(format: "%.4f, %.4f", lat, lon) : trimmedName
        if let index = appState.walkState.savedPoints.firstIndex(where: { $0.id == point.id }) {
            appState.walkState.savedPoints[index] = SavedPoint(id: point.id, name: newName, latitude: lat, longitude: lon)
            SavedPoint.save(appState.walkState.savedPoints)
        }
    }

    private func sendTextToEmulator(_ text: String) {
        let adb = ADBHelper(sdkDir: appState.sdkDir)
        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty else { return }
        Task.detached {
            // Clear existing content
            for _ in 0..<20 {
                _ = try? adb.run("shell", "input", "keyevent", "67")
            }
            try? await Task.sleep(for: .milliseconds(200))
            // Type the digits
            _ = try? adb.run("shell", "input", "text", digits)
        }
    }
}
