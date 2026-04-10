# Pikimin macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI macOS app that wraps the Android emulator for Pikmin Bloom walk simulation, distributed as a DMG.

**Architecture:** Single SwiftUI app with four modules — SDKManager (download/extract), EmulatorManager (start/stop/boot detection), WalkSimulator (sensor + GPS commands), and SwiftUI views. All state flows through `@Observable` view models. The app shells out to adb/emulator binaries via Swift `Process`.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-04-10-pikimin-app-design.md`

---

## File Structure

```
Pikimin/
├── Package.swift
├── Sources/
│   ├── PikiminApp.swift           — App entry point, window setup
│   ├── AppState.swift             — Top-level @Observable state coordinator
│   ├── Views/
│   │   ├── SetupView.swift        — First-run download UI
│   │   ├── MainView.swift         — Emulator controls + walk dashboard
│   │   └── LogView.swift          — Scrollable log output
│   ├── Services/
│   │   ├── ADBHelper.swift        — Process wrapper for adb commands
│   │   ├── SDKManager.swift       — Download + extract SDK components
│   │   ├── EmulatorManager.swift  — Start/stop emulator, AVD creation, boot detection
│   │   └── WalkSimulator.swift    — Gait simulation, GPS movement, progress
│   └── Models/
│       ├── SDKComponent.swift     — Download URL, path, size for each component
│       └── WalkState.swift        — Step count, coords, phase, progress
└── scripts/
    └── create-dmg.sh             — Build + package into DMG
```

---

### Task 1: Swift Package + App Shell

**Files:**
- Create: `Pikimin/Package.swift`
- Create: `Pikimin/Sources/PikiminApp.swift`
- Create: `Pikimin/Sources/AppState.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pikimin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pikimin",
            path: "Sources"
        )
    ]
)
```

- [ ] **Step 2: Create AppState.swift**

```swift
import Foundation
import SwiftUI

enum AppPhase {
    case setup
    case ready
}

@Observable
final class AppState {
    var phase: AppPhase = .setup

    let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Pikimin")
    }()

    var sdkDir: URL { appSupportDir.appendingPathComponent("sdk") }
    var avdDir: URL { appSupportDir.appendingPathComponent("avd") }

    func checkSetupComplete() {
        let emulatorExists = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("emulator/emulator").path
        )
        let adbExists = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("platform-tools/adb").path
        )
        let sysImgExists = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("system-images/android-35/google_apis_playstore/arm64-v8a/system.img").path
        )
        let avdExists = FileManager.default.fileExists(
            atPath: avdDir.appendingPathComponent("Pikimin.avd/config.ini").path
        )
        if emulatorExists && adbExists && sysImgExists && avdExists {
            phase = .ready
        } else {
            phase = .setup
        }
    }
}
```

- [ ] **Step 3: Create PikiminApp.swift**

```swift
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
```

- [ ] **Step 4: Create stub views so it compiles**

Create `Pikimin/Sources/Views/SetupView.swift`:
```swift
import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Text("Pikimin Setup")
                .font(.largeTitle)
            Text("Preparing to download Android emulator components...")
            ProgressView()
        }
        .padding(40)
    }
}
```

Create `Pikimin/Sources/Views/MainView.swift`:
```swift
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Text("Pikimin")
                .font(.largeTitle)
            Text("Ready")
        }
        .padding(40)
    }
}
```

- [ ] **Step 5: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds with no errors.

- [ ] **Step 6: Commit**

```bash
git add Pikimin/
git commit -m "feat: scaffold Pikimin SwiftUI app with Package.swift and app shell"
```

---

### Task 2: SDKComponent Model + ADBHelper

**Files:**
- Create: `Pikimin/Sources/Models/SDKComponent.swift`
- Create: `Pikimin/Sources/Services/ADBHelper.swift`

- [ ] **Step 1: Create SDKComponent.swift**

```swift
import Foundation

struct SDKComponent: Identifiable {
    let id: String
    let displayName: String
    let url: URL
    let extractedDirName: String
    let sizeBytes: Int64

    /// Where this component lives after extraction, relative to sdkDir
    func extractedPath(sdkDir: URL) -> URL {
        sdkDir.appendingPathComponent(extractedDirName)
    }

    func isInstalled(sdkDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: extractedPath(sdkDir: sdkDir).path)
    }

    static let platformTools = SDKComponent(
        id: "platform-tools",
        displayName: "Platform Tools (adb)",
        url: URL(string: "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip")!,
        extractedDirName: "platform-tools",
        sizeBytes: 38_000_000
    )

    static let emulator = SDKComponent(
        id: "emulator",
        displayName: "Android Emulator",
        url: URL(string: "https://dl.google.com/android/repository/emulator-darwin_aarch64-15142779.zip")!,
        extractedDirName: "emulator",
        sizeBytes: 1_100_000_000
    )

    static let systemImage = SDKComponent(
        id: "system-image",
        displayName: "Android 35 System Image (Play Store)",
        url: URL(string: "https://dl.google.com/android/repository/sys-img/google_apis_playstore/arm64-v8a-35_r09.zip")!,
        extractedDirName: "system-images/android-35/google_apis_playstore/arm64-v8a",
        sizeBytes: 1_789_211_399
    )

    static let all: [SDKComponent] = [platformTools, emulator, systemImage]
}
```

- [ ] **Step 2: Create ADBHelper.swift**

```swift
import Foundation

struct ADBHelper {
    let adbPath: String

    init(sdkDir: URL) {
        self.adbPath = sdkDir.appendingPathComponent("platform-tools/adb").path
    }

    @discardableResult
    func run(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = Array(arguments)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func runEmu(_ command: String) throws -> String {
        try run("emu", command)
    }

    func shell(_ command: String) throws -> String {
        try run("shell", command)
    }

    func setAcceleration(_ x: Double, _ y: Double, _ z: Double) throws {
        try run("emu", "sensor", "set", "acceleration", "\(x):\(y):\(z)")
    }

    func setGyroscope(_ x: Double, _ y: Double, _ z: Double) throws {
        try run("emu", "sensor", "set", "gyroscope", "\(x):\(y):\(z)")
    }

    func geoFix(longitude: Double, latitude: Double) throws {
        try run("emu", "geo", "fix", String(longitude), String(latitude))
    }

    func isDeviceOnline() -> Bool {
        guard let output = try? run("devices") else { return false }
        return output.contains("emulator") && output.contains("device")
    }

    func isBootComplete() -> Bool {
        guard let output = try? shell("getprop sys.boot_completed") else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Pikimin/Sources/Models/ Pikimin/Sources/Services/ADBHelper.swift
git commit -m "feat: add SDKComponent model and ADBHelper process wrapper"
```

---

### Task 3: SDKManager — Download + Extract

**Files:**
- Create: `Pikimin/Sources/Services/SDKManager.swift`
- Modify: `Pikimin/Sources/AppState.swift`

- [ ] **Step 1: Create SDKManager.swift**

```swift
import Foundation

@Observable
final class SDKManager {
    var currentComponent: SDKComponent?
    var downloadProgress: Double = 0
    var extracting = false
    var error: String?
    var completed = false

    private let sdkDir: URL
    private let avdDir: URL

    init(sdkDir: URL, avdDir: URL) {
        self.sdkDir = sdkDir
        self.avdDir = avdDir
    }

    func setupAll() async {
        do {
            try FileManager.default.createDirectory(at: sdkDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: avdDir, withIntermediateDirectories: true)

            for component in SDKComponent.all {
                if component.isInstalled(sdkDir: sdkDir) { continue }
                currentComponent = component
                downloadProgress = 0
                extracting = false

                let zipURL = try await download(component)
                extracting = true
                try await extract(zipURL, component: component)
                try FileManager.default.removeItem(at: zipURL)
            }

            try await createAVD()
            completed = true
        } catch is CancellationError {
            // user cancelled
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func download(_ component: SDKComponent) async throws -> URL {
        let destURL = sdkDir.appendingPathComponent("\(component.id).zip")
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: component.url)
        let totalBytes = (response as? HTTPURLResponse)
            .flatMap { Int64($0.value(forHTTPHeaderField: "Content-Length") ?? "") }
            ?? component.sizeBytes

        var data = Data()
        data.reserveCapacity(Int(totalBytes))

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count % 1_000_000 == 0 {
                downloadProgress = Double(data.count) / Double(totalBytes)
            }
        }
        downloadProgress = 1.0

        try data.write(to: destURL)
        return destURL
    }

    private func extract(_ zipURL: URL, component: SDKComponent) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, sdkDir.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SDKError.extractionFailed(output)
        }

        // System image extracts as just "arm64-v8a/" — move to correct nested path
        if component.id == "system-image" {
            let extractedFlat = sdkDir.appendingPathComponent("arm64-v8a")
            if FileManager.default.fileExists(atPath: extractedFlat.path) {
                let targetDir = component.extractedPath(sdkDir: sdkDir)
                try FileManager.default.createDirectory(
                    at: targetDir.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: extractedFlat, to: targetDir)
            }
        }

        // Make emulator binary executable
        if component.id == "emulator" {
            let emulatorBin = sdkDir.appendingPathComponent("emulator/emulator")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: emulatorBin.path
            )
        }

        // Make adb executable
        if component.id == "platform-tools" {
            let adbBin = sdkDir.appendingPathComponent("platform-tools/adb")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: adbBin.path
            )
        }
    }

    private func createAVD() async throws {
        let avdPath = avdDir.appendingPathComponent("Pikimin.avd")
        if FileManager.default.fileExists(atPath: avdPath.appendingPathComponent("config.ini").path) {
            return
        }

        try FileManager.default.createDirectory(at: avdPath, withIntermediateDirectories: true)

        // Write the AVD ini pointer
        let iniContent = """
        avd.ini.encoding=UTF-8
        path=\(avdPath.path)
        path.rel=avd/Pikimin.avd
        target=android-35
        """
        try iniContent.write(to: avdDir.appendingPathComponent("Pikimin.ini"), atomically: true, encoding: .utf8)

        // Write the AVD config
        let sysImageRelPath = "system-images/android-35/google_apis_playstore/arm64-v8a/"
        let config = """
        PlayStore.enabled=yes
        abi.type=arm64-v8a
        avd.ini.encoding=UTF-8
        avd.name=Pikimin
        disk.cachePartition=yes
        disk.cachePartition.size=66MB
        disk.dataPartition.size=6G
        hw.accelerometer=yes
        hw.accelerometer_uncalibrated=yes
        hw.audioInput=yes
        hw.audioOutput=yes
        hw.battery=yes
        hw.camera.back=emulated
        hw.camera.front=none
        hw.cpu.arch=arm64
        hw.cpu.ncore=4
        hw.device.manufacturer=Google
        hw.device.name=pixel_7
        hw.gps=yes
        hw.gpu.enabled=yes
        hw.gpu.mode=host
        hw.gsmModem=yes
        hw.gyroscope=yes
        hw.keyboard=yes
        hw.keyboard.charmap=qwerty2
        hw.keyboard.lid=yes
        hw.lcd.density=420
        hw.lcd.height=2400
        hw.lcd.width=1080
        hw.mainKeys=no
        hw.ramSize=2G
        hw.screen=multi-touch
        hw.sdCard=yes
        hw.sensors.gyroscope_uncalibrated=yes
        hw.sensors.humidity=yes
        hw.sensors.light=yes
        hw.sensors.magnetic_field=yes
        hw.sensors.magnetic_field_uncalibrated=yes
        hw.sensors.orientation=yes
        hw.sensors.pressure=yes
        hw.sensors.proximity=yes
        hw.sensors.temperature=yes
        image.sysdir.1=\(sdkDir.path)/\(sysImageRelPath)
        runtime.network.latency=none
        runtime.network.speed=full
        sdcard.size=512 MB
        showDeviceFrame=yes
        tag.display=Google Play
        tag.id=google_apis_playstore
        target=android-35
        vm.heapSize=228M
        """
        try config.write(
            to: avdPath.appendingPathComponent("config.ini"),
            atomically: true,
            encoding: .utf8
        )
    }
}

enum SDKError: LocalizedError {
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let output): return "Extraction failed: \(output)"
        }
    }
}
```

- [ ] **Step 2: Add SDKManager to AppState**

In `AppState.swift`, add a lazy property and update `checkSetupComplete`:

```swift
import Foundation
import SwiftUI

enum AppPhase {
    case setup
    case ready
}

@Observable
final class AppState {
    var phase: AppPhase = .setup
    lazy var sdkManager = SDKManager(sdkDir: sdkDir, avdDir: avdDir)

    let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Pikimin")
    }()

    var sdkDir: URL { appSupportDir.appendingPathComponent("sdk") }
    var avdDir: URL { appSupportDir.appendingPathComponent("avd") }

    func checkSetupComplete() {
        let emulatorExists = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("emulator/emulator").path
        )
        let adbExists = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("platform-tools/adb").path
        )
        let sysImgExists = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("system-images/android-35/google_apis_playstore/arm64-v8a/system.img").path
        )
        let avdExists = FileManager.default.fileExists(
            atPath: avdDir.appendingPathComponent("Pikimin.avd/config.ini").path
        )
        if emulatorExists && adbExists && sysImgExists && avdExists {
            phase = .ready
        } else {
            phase = .setup
        }
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Pikimin/Sources/Services/SDKManager.swift Pikimin/Sources/AppState.swift
git commit -m "feat: add SDKManager for downloading and extracting Android SDK components"
```

---

### Task 4: SetupView — Download Progress UI

**Files:**
- Modify: `Pikimin/Sources/Views/SetupView.swift`

- [ ] **Step 1: Implement SetupView with download progress**

Replace `SetupView.swift` with:

```swift
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

    private func startSetup() {
        setupTask?.cancel()
        appState.sdkManager.error = nil
        setupTask = Task {
            await appState.sdkManager.setupAll()
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Pikimin/Sources/Views/SetupView.swift
git commit -m "feat: implement SetupView with download progress and error handling"
```

---

### Task 5: EmulatorManager — Start/Stop/Boot Detection

**Files:**
- Create: `Pikimin/Sources/Services/EmulatorManager.swift`

- [ ] **Step 1: Create EmulatorManager.swift**

```swift
import Foundation

enum EmulatorState: String {
    case stopped = "Stopped"
    case booting = "Booting"
    case running = "Running"
}

@Observable
final class EmulatorManager {
    var state: EmulatorState = .stopped
    var error: String?

    private var emulatorProcess: Process?
    private let sdkDir: URL
    private let avdDir: URL
    private let adb: ADBHelper

    init(sdkDir: URL, avdDir: URL) {
        self.sdkDir = sdkDir
        self.avdDir = avdDir
        self.adb = ADBHelper(sdkDir: sdkDir)
    }

    func start() async {
        guard state == .stopped else { return }
        state = .booting
        error = nil

        do {
            let emulatorPath = sdkDir.appendingPathComponent("emulator/emulator").path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: emulatorPath)

            // Set ANDROID_HOME and ANDROID_AVD_HOME so emulator finds SDK and AVD
            var env = ProcessInfo.processInfo.environment
            env["ANDROID_HOME"] = sdkDir.path
            env["ANDROID_SDK_ROOT"] = sdkDir.path
            env["ANDROID_AVD_HOME"] = avdDir.path
            process.environment = env

            process.arguments = [
                "-avd", "Pikimin",
                "-no-snapshot-load",
                "-gpu", "host",
                "-dns-server", "8.8.8.8"
            ]

            // Silence emulator stdout/stderr
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            emulatorProcess = process

            // Monitor for unexpected termination
            Task.detached { [weak self] in
                process.waitUntilExit()
                await MainActor.run {
                    self?.state = .stopped
                    self?.emulatorProcess = nil
                }
            }

            // Wait for boot
            try await waitForBoot()
            state = .running
        } catch is CancellationError {
            stop()
        } catch {
            self.error = error.localizedDescription
            state = .stopped
        }
    }

    func stop() {
        if let process = emulatorProcess, process.isRunning {
            _ = try? adb.run("emu", "kill")
            // Give it a moment, then force kill if needed
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if process.isRunning { process.terminate() }
            }
        }
        emulatorProcess = nil
        state = .stopped
    }

    private func waitForBoot() async throws {
        // Wait up to 120 seconds for boot
        for _ in 0..<120 {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            if adb.isBootComplete() { return }
        }
        throw EmulatorError.bootTimeout
    }
}

enum EmulatorError: LocalizedError {
    case bootTimeout

    var errorDescription: String? {
        switch self {
        case .bootTimeout: return "Emulator failed to boot within 120 seconds"
        }
    }
}
```

- [ ] **Step 2: Add EmulatorManager to AppState**

Update `AppState.swift` — add:

```swift
lazy var emulatorManager = EmulatorManager(sdkDir: sdkDir, avdDir: avdDir)
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Pikimin/Sources/Services/EmulatorManager.swift Pikimin/Sources/AppState.swift
git commit -m "feat: add EmulatorManager with start/stop and boot detection"
```

---

### Task 6: WalkSimulator — Gait + GPS Simulation

**Files:**
- Create: `Pikimin/Sources/Models/WalkState.swift`
- Create: `Pikimin/Sources/Services/WalkSimulator.swift`

- [ ] **Step 1: Create WalkState.swift**

```swift
import Foundation

enum WalkPhase: String {
    case idle = "Idle"
    case wandering = "Wandering"
    case returning = "Returning"
}

@Observable
final class WalkState {
    var currentStep: Int = 0
    var totalSteps: Int = 50_000
    var phase: WalkPhase = .idle
    var latitude: Double = 0
    var longitude: Double = 0
    var isWalking: Bool { phase != .idle }

    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }

    var percentText: String {
        "\(Int(progress * 100))%"
    }

    func reset() {
        currentStep = 0
        phase = .idle
        latitude = 0
        longitude = 0
    }
}
```

- [ ] **Step 2: Create WalkSimulator.swift**

```swift
import Foundation

final class WalkSimulator {
    private let adb: ADBHelper
    private let state: WalkState
    private var walkTask: Task<Void, Never>?

    init(sdkDir: URL, state: WalkState) {
        self.adb = ADBHelper(sdkDir: sdkDir)
        self.state = state
    }

    func start() {
        guard !state.isWalking else { return }
        state.reset()

        walkTask = Task {
            await run()
        }
    }

    func stop() {
        walkTask?.cancel()
        walkTask = nil
        state.phase = .idle
    }

    private func run() async {
        // Read starting GPS from emulator
        guard let coords = getLocation() else {
            state.phase = .idle
            return
        }

        let baseLat = coords.latitude
        let baseLon = coords.longitude
        var lat = baseLat
        var lon = baseLon
        state.latitude = lat
        state.longitude = lon

        let totalSteps = state.totalSteps
        let halfSteps = totalSteps / 2
        let gpsStep = 0.000014 // ~1.5m

        var direction = Int.random(in: 0..<8)
        var stepsInDir = 0
        var dirLength = Int.random(in: 30...150)

        for step in 1...totalSteps {
            if Task.isCancelled { break }

            // Update phase
            state.phase = step <= halfSteps ? .wandering : .returning

            // Direction change
            stepsInDir += 1
            if stepsInDir >= dirLength {
                stepsInDir = 0
                dirLength = Int.random(in: 30...150)
                direction = Int.random(in: 0..<8)
            }

            // Move in direction
            let wobble = Double.random(in: -0.000005...0.000005)
            switch direction {
            case 0: lat += gpsStep;           lon += wobble           // N
            case 1: lat += gpsStep * 0.7;     lon += gpsStep * 0.7   // NE
            case 2: lon += gpsStep;           lat += wobble           // E
            case 3: lat -= gpsStep * 0.7;     lon += gpsStep * 0.7   // SE
            case 4: lat -= gpsStep;           lon += wobble           // S
            case 5: lat += gpsStep * 0.7;     lon -= gpsStep * 0.7   // SW
            case 6: lon -= gpsStep;           lat += wobble           // W
            case 7: lat -= gpsStep * 0.7;     lon -= gpsStep * 0.7   // NW
            default: break
            }

            // Return bias in second half
            if step > halfSteps {
                let remaining = Double(totalSteps - step + 1)
                lat += (baseLat - lat) / (remaining * 3)
                lon += (baseLon - lon) / (remaining * 3)
            }

            // GPS update
            try? adb.geoFix(longitude: lon, latitude: lat)

            // Gait cycle — each adb call has ~50ms natural latency
            // 1. Swing
            try? adb.setAcceleration(0.3, 0.4, 5.0)
            try? adb.setGyroscope(0.2, 0.3, 0.0)
            try? await Task.sleep(for: .milliseconds(50))

            // 2. Heel strike
            try? adb.setAcceleration(-1.5, 2.0, 22.0)
            try? await Task.sleep(for: .milliseconds(50))

            // 3. Peak impact
            try? adb.setAcceleration(-2.0, 2.5, 25.0)
            try? await Task.sleep(for: .milliseconds(50))

            // 4. Settling
            try? adb.setAcceleration(-0.3, 0.5, 12.0)
            try? await Task.sleep(for: .milliseconds(50))

            // 5. Midstance
            try? adb.setAcceleration(0.0, 0.0, 9.8)
            try? adb.setGyroscope(0.0, 0.0, 0.0)
            try? await Task.sleep(for: .milliseconds(100))

            // 6. Toe off
            try? adb.setAcceleration(0.5, -0.6, 15.0)
            try? await Task.sleep(for: .milliseconds(50))

            // 7. Rest
            try? adb.setAcceleration(0.0, 0.0, 9.8)
            try? await Task.sleep(for: .milliseconds(100))

            // Update state
            state.currentStep = step
            state.latitude = lat
            state.longitude = lon
        }

        state.phase = .idle
    }

    private func getLocation() -> (latitude: Double, longitude: Double)? {
        guard let output = try? adb.shell("dumpsys location") else { return nil }
        // Parse "Location[gps lat,lon ...]"
        guard let range = output.range(of: #"Location\[gps\s+"#, options: .regularExpression) else { return nil }
        let after = output[range.upperBound...]
        guard let endRange = after.range(of: " ") else { return nil }
        let coordStr = String(after[after.startIndex..<endRange.lowerBound])
        let parts = coordStr.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }
}
```

- [ ] **Step 3: Add WalkState and WalkSimulator to AppState**

Update `AppState.swift` — add:

```swift
let walkState = WalkState()
lazy var walkSimulator: WalkSimulator = WalkSimulator(sdkDir: sdkDir, state: walkState)
```

- [ ] **Step 4: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Pikimin/Sources/Models/WalkState.swift Pikimin/Sources/Services/WalkSimulator.swift Pikimin/Sources/AppState.swift
git commit -m "feat: add WalkSimulator with gait cycle and GPS movement"
```

---

### Task 7: MainView — Emulator Controls + Walk Dashboard

**Files:**
- Modify: `Pikimin/Sources/Views/MainView.swift`
- Create: `Pikimin/Sources/Views/LogView.swift`

- [ ] **Step 1: Create LogView.swift**

```swift
import SwiftUI

struct LogView: View {
    let entries: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        Text(entry)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .onChange(of: entries.count) { _, newCount in
                if newCount > 0 {
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
        .background(.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Implement MainView**

Replace `MainView.swift` with:

```swift
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var stepInput: Int = 50_000

    var body: some View {
        let emu = appState.emulatorManager
        let walk = appState.walkState

        VStack(spacing: 0) {
            // Header
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
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Pikimin/Sources/Views/
git commit -m "feat: implement MainView with emulator controls and walk dashboard"
```

---

### Task 8: Wire Up App Lifecycle + First Launch Check

**Files:**
- Modify: `Pikimin/Sources/PikiminApp.swift`

- [ ] **Step 1: Add onAppear check and cleanup**

Replace `PikiminApp.swift` with:

```swift
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
            .onAppear {
                appState.checkSetupComplete()
            }
        }
        .windowResizability(.contentMinSize)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Run the app to smoke test**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && swift run Pikimin &
```

Expected: Window opens showing SetupView (since SDK not installed in `~/Library/Application Support/Pikimin/`). Kill it after verifying.

- [ ] **Step 4: Commit**

```bash
git add Pikimin/Sources/PikiminApp.swift
git commit -m "feat: wire up app lifecycle with first-launch setup check"
```

---

### Task 9: DMG Packaging Script

**Files:**
- Create: `Pikimin/scripts/create-dmg.sh`

- [ ] **Step 1: Create create-dmg.sh**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DMG_DIR="$PROJECT_DIR/.build/dmg"
APP_NAME="Pikimin"
DMG_NAME="Pikimin.dmg"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DMG_DIR/$APP_NAME.app/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$DMG_DIR/$APP_NAME.app/Contents/MacOS/"

# Create Info.plist
cat > "$DMG_DIR/$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Pikimin</string>
    <key>CFBundleIdentifier</key>
    <string>com.pikimin.app</string>
    <key>CFBundleName</key>
    <string>Pikimin</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc sign
codesign --force --sign - "$DMG_DIR/$APP_NAME.app"

echo "Creating DMG..."
rm -f "$PROJECT_DIR/$DMG_NAME"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$PROJECT_DIR/$DMG_NAME"

echo ""
echo "Done! Created: $PROJECT_DIR/$DMG_NAME"
echo "Size: $(du -h "$PROJECT_DIR/$DMG_NAME" | cut -f1)"
echo ""
echo "To install: open DMG, drag Pikimin.app to Applications."
echo "First launch: right-click -> Open to bypass Gatekeeper."
```

- [ ] **Step 2: Make executable and test build**

```bash
chmod +x /Users/hsuan/Projects/pikimin/Pikimin/scripts/create-dmg.sh
```

- [ ] **Step 3: Commit**

```bash
git add Pikimin/scripts/create-dmg.sh
git commit -m "feat: add DMG packaging script with ad-hoc signing"
```

---

### Task 10: End-to-End Test

- [ ] **Step 1: Build DMG**

```bash
cd /Users/hsuan/Projects/pikimin/Pikimin && ./scripts/create-dmg.sh
```

Expected: `Pikimin.dmg` created in project root.

- [ ] **Step 2: Install and launch**

Open DMG, drag to Applications (or run from DMG directly). Right-click -> Open to bypass Gatekeeper. Verify:
- App opens with SetupView
- "Download & Install" button is visible

- [ ] **Step 3: Test full flow** (manual)

- Click Download & Install — verify progress bar updates
- After setup completes, verify MainView appears
- Click Start Emulator — verify emulator window opens
- Set a GPS location in the emulator
- Click Start Walk — verify live stats update
- Click Stop Walk — verify it stops cleanly
- Click Stop Emulator — verify emulator closes

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: complete Pikimin v1 — macOS Android emulator wrapper for Pikmin Bloom"
```
