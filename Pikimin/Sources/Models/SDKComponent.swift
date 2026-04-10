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
