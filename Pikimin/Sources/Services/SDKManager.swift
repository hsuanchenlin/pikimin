import Foundation

@MainActor
@Observable
final class SDKManager {
    var currentComponent: SDKComponent?
    var downloadProgress: Double = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
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

        // Use curl for reliable large downloads with resume support
        let curlProcess = Process()
        curlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curlProcess.arguments = [
            "-L",                    // follow redirects
            "-C", "-",               // resume partial downloads
            "--retry", "5",          // retry up to 5 times
            "--retry-delay", "3",    // wait 3s between retries
            "--connect-timeout", "30",
            "-o", destURL.path,
            component.url.absoluteString
        ]
        curlProcess.standardOutput = FileHandle.nullDevice
        curlProcess.standardError = FileHandle.nullDevice

        try curlProcess.run()

        // Poll file size for progress updates
        // Set totalBytes immediately so UI shows target size
        let expectedSize = component.sizeBytes
        totalBytes = expectedSize
        downloadedBytes = 0
        while curlProcess.isRunning {
            try await Task.sleep(for: .milliseconds(500))
            try Task.checkCancellation()
            let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
            let currentSize = (attrs?[.size] as? Int64) ?? 0
            downloadedBytes = currentSize
            totalBytes = expectedSize
            if expectedSize > 0 {
                downloadProgress = Double(currentSize) / Double(expectedSize)
            }
        }

        guard curlProcess.terminationStatus == 0 else {
            // Clean up partial file on failure
            try? FileManager.default.removeItem(at: destURL)
            throw SDKError.extractionFailed("Download failed (curl exit \(curlProcess.terminationStatus))")
        }

        downloadProgress = 1.0
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

    private func findSystemImage() -> String? {
        for imgPath in [
            "system-images/android-36.0-Baklava/google_apis_playstore/arm64-v8a",
            "system-images/android-36.0-Baklava/google_apis_playstore_ps16k/arm64-v8a",
            "system-images/android-35/google_apis_playstore/arm64-v8a",
        ] {
            if FileManager.default.fileExists(atPath: sdkDir.appendingPathComponent(imgPath + "/system.img").path) {
                return imgPath
            }
        }
        return nil
    }

    /// Public entry point for creating AVD only (when SDK already exists)
    func createAVDOnly() async throws {
        try FileManager.default.createDirectory(at: avdDir, withIntermediateDirectories: true)
        try await createAVD()
    }

    private func createAVD() async throws {
        let avdPath = avdDir.appendingPathComponent("Pikimin.avd")
        if FileManager.default.fileExists(atPath: avdPath.appendingPathComponent("config.ini").path) {
            return
        }

        // Find the system image
        let sysImageRelPath: String
        if let found = findSystemImage() {
            sysImageRelPath = found + "/"
        } else {
            sysImageRelPath = "system-images/android-35/google_apis_playstore/arm64-v8a/"
        }

        // Determine target from path (e.g. "android-36.0-Baklava" or "android-35")
        let pathParts = sysImageRelPath.split(separator: "/")
        let target = pathParts.count >= 2 ? String(pathParts[1]) : "android-35"

        try FileManager.default.createDirectory(at: avdPath, withIntermediateDirectories: true)

        // Write the AVD ini pointer
        let iniContent = """
avd.ini.encoding=UTF-8
path=\(avdPath.path)
path.rel=avd/Pikimin.avd
target=\(target)
"""
        try iniContent.write(to: avdDir.appendingPathComponent("Pikimin.ini"), atomically: true, encoding: .utf8)
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
target=\(target)
vm.heapSize=228M
"""
        try config.write(
            to: avdPath.appendingPathComponent("config.ini"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((Double, Int64, Int64) -> Void)?
    var onComplete: ((URL?, Error?) -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete?(location, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete?(nil, error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                     didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                     totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), totalBytesWritten, totalBytesExpectedToWrite)
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
