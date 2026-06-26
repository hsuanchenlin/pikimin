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

    /// Ensure Gboard is active and soft keyboard shows with hardware keyboard
    private func setupKeyboard() {
        _ = try? adb.shell("ime set com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME")
    }

    /// Target data partition size for the AVD. New AVDs are created at this size;
    /// existing AVDs are raised to it on launch (non-destructively).
    static let targetDataPartitionSize = "16G"

    /// Raise an existing AVD's data partition ceiling to `targetDataPartitionSize`.
    /// Rewrites config.ini and grows the userdata qcow2. Both steps are non-destructive
    /// and idempotent. For Play Store images the larger size is only realized after a
    /// data reset, but setting it here is harmless and correct for fresh userdata.
    private func migrateDataPartitionSize() {
        let configURL = avdDir.appendingPathComponent("Pikimin.avd/config.ini")
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else { return }

        let target = EmulatorManager.targetDataPartitionSize
        var changed = false
        let lines = config.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard line.hasPrefix("disk.dataPartition.size=") else { return String(line) }
            let current = line.dropFirst("disk.dataPartition.size=".count)
            if current != target { changed = true }
            return "disk.dataPartition.size=\(target)"
        }
        guard changed else { return }   // already at target — nothing to do

        try? lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)

        // Grow the userdata image to match. Safe: qemu-img only grows here.
        let qemuImg = sdkDir.appendingPathComponent("emulator/qemu-img").path
        let userdata = avdDir.appendingPathComponent("Pikimin.avd/userdata-qemu.img").path
        guard FileManager.default.isExecutableFile(atPath: qemuImg),
              FileManager.default.fileExists(atPath: userdata) else { return }
        let resize = Process()
        resize.executableURL = URL(fileURLWithPath: qemuImg)
        resize.arguments = ["resize", userdata, target]
        resize.standardOutput = FileHandle.nullDevice
        resize.standardError = FileHandle.nullDevice
        try? resize.run()
        resize.waitUntilExit()
    }

    func start() async {
        guard state == .stopped else { return }
        state = .booting
        error = nil

        migrateDataPartitionSize()

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
