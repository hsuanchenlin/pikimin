import Foundation

enum EmulatorState: String {
    case stopped = "Stopped"
    case booting = "Booting"
    case running = "Running"
}

@MainActor
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

    /// Check if an emulator is already running and attach to it
    func detectRunning() {
        if adb.isDeviceOnline() && adb.isBootComplete() {
            setupKeyboard()
            state = .running
        }
    }

    /// Install ADBKeyboard and enable it for text input into Unity apps
    private func setupKeyboard() {
        // Check if already installed
        let packages = (try? adb.shell("pm list packages com.android.adbkeyboard")) ?? ""
        if !packages.contains("com.android.adbkeyboard") {
            // Find the APK bundled with the app
            let apkPath = findBundledAPK()
            if let apk = apkPath {
                _ = try? adb.run("install", apk)
            }
        }
        _ = try? adb.shell("ime enable com.android.adbkeyboard/.AdbIME")
    }

    private func findBundledAPK() -> String? {
        // Check in app bundle Resources
        if let bundlePath = Bundle.main.path(forResource: "ADBKeyboard", ofType: "apk") {
            return bundlePath
        }
        // Check in project Resources directory (dev mode)
        let devPath = sdkDir
            .deletingLastPathComponent() // sdk/
            .deletingLastPathComponent() // Pikimin app support/
            .appendingPathComponent("ADBKeyboard.apk")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }
        return nil
    }

    func start() async {
        guard state == .stopped else { return }
        state = .booting
        error = nil

        do {
            let emulatorPath = sdkDir.appendingPathComponent("emulator/emulator").path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: emulatorPath)

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

            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            emulatorProcess = process

            Task.detached { [weak self] in
                process.waitUntilExit()
                await MainActor.run {
                    self?.state = .stopped
                    self?.emulatorProcess = nil
                }
            }

            try await waitForBoot()
            _ = try? adb.shell("settings put secure show_ime_with_hard_keyboard 1")
            setupKeyboard()
            state = .running
        } catch is CancellationError {
            stop()
        } catch {
            self.error = error.localizedDescription
            state = .stopped
        }
    }

    func stop() {
        // Kill via adb regardless of whether we own the process
        _ = try? adb.run("emu", "kill")
        if let process = emulatorProcess, process.isRunning {
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if process.isRunning { process.terminate() }
            }
        }
        emulatorProcess = nil
        state = .stopped
    }

    private func waitForBoot() async throws {
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
