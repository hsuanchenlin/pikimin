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

    let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Pikimin")
    }()

    var sdkDir: URL { appSupportDir.appendingPathComponent("sdk") }
    var avdDir: URL { appSupportDir.appendingPathComponent("avd") }

    var sdkManager: SDKManager
    var emulatorManager: EmulatorManager

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupport = base.appendingPathComponent("Pikimin")
        let sdk = appSupport.appendingPathComponent("sdk")
        let avd = appSupport.appendingPathComponent("avd")
        sdkManager = SDKManager(sdkDir: sdk, avdDir: avd)
        emulatorManager = EmulatorManager(sdkDir: sdk, avdDir: avd)
    }

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
