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

/// Persistent telnet connection to the emulator console.
/// Sends sensor/GPS commands without spawning new processes.
final class EmulatorConsole: @unchecked Sendable {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let host: String
    private let port: UInt32
    private let lock = NSLock()
    private(set) var isConnected = false

    init(host: String = "localhost", port: UInt32 = 5554) {
        self.host = host
        self.port = port
    }

    func connect() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, port, &readStream, &writeStream)

        guard let input = readStream?.takeRetainedValue() as InputStream?,
              let output = writeStream?.takeRetainedValue() as OutputStream? else {
            return false
        }

        inputStream = input
        outputStream = output
        input.open()
        output.open()

        // Wait for connection
        Thread.sleep(forTimeInterval: 0.3)

        // Read the welcome banner
        _ = readAvailable()

        // Authenticate
        let authToken = (try? String(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".emulator_console_auth_token").path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        send("auth \(authToken)")
        Thread.sleep(forTimeInterval: 0.3)
        _ = readAvailable()

        isConnected = true
        return true
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        send("quit")
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        isConnected = false
    }

    func send(_ command: String) {
        guard let output = outputStream else { return }
        let data = (command + "\r\n").data(using: .utf8)!
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            output.write(baseAddress, maxLength: data.count)
        }
    }

    func setAcceleration(_ x: Double, _ y: Double, _ z: Double) {
        send("sensor set acceleration \(x):\(y):\(z)")
    }

    func setGyroscope(_ x: Double, _ y: Double, _ z: Double) {
        send("sensor set gyroscope \(x):\(y):\(z)")
    }

    func geoFix(longitude: Double, latitude: Double) {
        send("geo fix \(longitude) \(latitude)")
    }

    /// Discard any pending console replies. We never use them, but if left unread
    /// they fill the socket receive buffer over a long walk and eventually stall the
    /// emulator's console thread (which burns CPU blocking on its write). Cheap to call.
    func drain() {
        _ = readAvailable()
    }

    private func readAvailable() -> String {
        guard let input = inputStream else { return "" }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var result = ""
        while input.hasBytesAvailable {
            let bytesRead = input.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                result += String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            } else {
                break
            }
        }
        return result
    }

    deinit {
        disconnect()
    }
}
