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
            // Show soft keyboard even with hw.keyboard=yes
            _ = try? adb.shell("settings put secure show_ime_with_hard_keyboard 1")
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
