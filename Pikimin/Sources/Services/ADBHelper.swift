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
