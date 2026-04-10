import Foundation
import SwiftUI

enum AppPhase {
    case setup
    case ready
}

@MainActor
@Observable
final class AppState {
    var phase: AppPhase = .setup
    var detectedSDKPath: URL?

    let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Pikimin")
    }()

    var avdDir: URL { appSupportDir.appendingPathComponent("avd") }

    /// The active SDK directory — either detected or from app support
    var sdkDir: URL {
        detectedSDKPath ?? appSupportDir.appendingPathComponent("sdk")
    }

    var sdkManager: SDKManager
    var emulatorManager: EmulatorManager
    let walkState = WalkState()
    var walkSimulator: WalkSimulator

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupport = base.appendingPathComponent("Pikimin")
        let sdk = appSupport.appendingPathComponent("sdk")
        let avd = appSupport.appendingPathComponent("avd")
        sdkManager = SDKManager(sdkDir: sdk, avdDir: avd)
        emulatorManager = EmulatorManager(sdkDir: sdk, avdDir: avd)
        walkSimulator = WalkSimulator(sdkDir: sdk, state: walkState)
    }

    /// Reinitialize managers to point at the detected SDK
    func useSDK(at path: URL) {
        detectedSDKPath = path
        let avd = avdDir
        sdkManager = SDKManager(sdkDir: path, avdDir: avd)
        emulatorManager = EmulatorManager(sdkDir: path, avdDir: avd)
        walkSimulator = WalkSimulator(sdkDir: path, state: walkState)
    }

    static let searchPaths: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            home.appendingPathComponent("Library/Android/sdk"),                    // Android Studio default
            URL(fileURLWithPath: "/opt/homebrew/share/android-commandlinetools"),   // Homebrew
        ]
        // $ANDROID_HOME
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            paths.insert(URL(fileURLWithPath: androidHome), at: 0)
        }
        return paths
    }()

    func detectExistingSDK() -> URL? {
        for path in Self.searchPaths {
            if isValidSDK(at: path) {
                return path
            }
        }
        return nil
    }

    /// Known system image paths in order of preference
    static let systemImagePaths = [
        "system-images/android-36.0-Baklava/google_apis_playstore/arm64-v8a",
        "system-images/android-36.0-Baklava/google_apis_playstore_ps16k/arm64-v8a",
        "system-images/android-35/google_apis_playstore/arm64-v8a",
    ]

    func isValidSDK(at path: URL) -> Bool {
        let missing = missingComponents(at: path)
        return missing.isEmpty
    }

    /// Find the first available system image in an SDK directory
    func findSystemImage(at sdkPath: URL) -> String? {
        for imgPath in Self.systemImagePaths {
            if FileManager.default.fileExists(atPath: sdkPath.appendingPathComponent(imgPath + "/system.img").path) {
                return imgPath
            }
        }
        return nil
    }

    func missingComponents(at path: URL) -> [String] {
        let fm = FileManager.default
        var missing: [String] = []
        if !fm.fileExists(atPath: path.appendingPathComponent("emulator/emulator").path) {
            missing.append("Emulator")
        }
        if !fm.fileExists(atPath: path.appendingPathComponent("platform-tools/adb").path) {
            missing.append("Platform Tools")
        }
        if findSystemImage(at: path) == nil {
            missing.append("System Image (Android 35+ Play Store arm64)")
        }
        return missing
    }

    func checkSetupComplete() {
        // Try to find an existing SDK installation
        if let existingSDK = detectExistingSDK() {
            useSDK(at: existingSDK)

            // Ensure AVD exists, create synchronously if needed
            let avdConfig = avdDir.appendingPathComponent("Pikimin.avd/config.ini").path
            if !FileManager.default.fileExists(atPath: avdConfig) {
                // Create AVD directory and config synchronously
                let avdPath = avdDir.appendingPathComponent("Pikimin.avd")
                try? FileManager.default.createDirectory(at: avdDir, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: avdPath, withIntermediateDirectories: true)

                let sysImageRelPath = (findSystemImage(at: existingSDK) ?? "system-images/android-35/google_apis_playstore/arm64-v8a") + "/"
                let pathParts = sysImageRelPath.split(separator: "/")
                let target = pathParts.count >= 2 ? String(pathParts[1]) : "android-35"

                let iniContent = "avd.ini.encoding=UTF-8\npath=\(avdPath.path)\npath.rel=avd/Pikimin.avd\ntarget=\(target)\n"
                try? iniContent.write(to: avdDir.appendingPathComponent("Pikimin.ini"), atomically: true, encoding: .utf8)

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
                image.sysdir.1=\(existingSDK.path)/\(sysImageRelPath)
                runtime.network.latency=none
                runtime.network.speed=full
                sdcard.size=512 MB
                showDeviceFrame=yes
                tag.display=Google Play
                tag.id=google_apis_playstore
                target=\(target)
                vm.heapSize=228M
                """
                // Remove leading whitespace from each line (Swift multiline string indentation)
                let trimmedConfig = config.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                try? trimmedConfig.write(to: avdPath.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
            }

            phase = .ready
            return
        }

        // No valid SDK found anywhere
        if isValidSDK(at: sdkDir) {
            // Our own app support SDK is valid
            let avdConfig = avdDir.appendingPathComponent("Pikimin.avd/config.ini").path
            if FileManager.default.fileExists(atPath: avdConfig) {
                phase = .ready
                return
            }
        }

        phase = .setup
    }
}
