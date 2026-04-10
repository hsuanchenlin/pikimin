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

    func isValidSDK(at path: URL) -> Bool {
        let fm = FileManager.default
        let hasEmulator = fm.fileExists(atPath: path.appendingPathComponent("emulator/emulator").path)
        let hasAdb = fm.fileExists(atPath: path.appendingPathComponent("platform-tools/adb").path)
        let hasSysImg = fm.fileExists(atPath: path.appendingPathComponent("system-images/android-35/google_apis_playstore/arm64-v8a/system.img").path)
        return hasEmulator && hasAdb && hasSysImg
    }

    func checkSetupComplete() {
        // First try to find an existing SDK installation
        if let existingSDK = detectExistingSDK() {
            useSDK(at: existingSDK)
            // Ensure AVD exists
            if !FileManager.default.fileExists(atPath: avdDir.appendingPathComponent("Pikimin.avd/config.ini").path) {
                // Need to create AVD — go to setup (it will skip downloads)
                phase = .setup
                return
            }
            phase = .ready
            return
        }

        // Check our own app support directory
        let hasEmulator = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("emulator/emulator").path
        )
        let hasAdb = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("platform-tools/adb").path
        )
        let hasSysImg = FileManager.default.fileExists(
            atPath: sdkDir.appendingPathComponent("system-images/android-35/google_apis_playstore/arm64-v8a/system.img").path
        )
        let hasAvd = FileManager.default.fileExists(
            atPath: avdDir.appendingPathComponent("Pikimin.avd/config.ini").path
        )
        if hasEmulator && hasAdb && hasSysImg && hasAvd {
            phase = .ready
        } else {
            phase = .setup
        }
    }
}
