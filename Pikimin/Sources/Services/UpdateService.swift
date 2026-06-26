import Foundation
import AppKit

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }
}

@MainActor
@Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case available(version: String, url: String)
        case downloading(progress: Double)
        case installing
        case failed(String)
        case upToDate
    }

    var state: State = .idle

    private let repo = "hsuanchenlin/pikimin"

    func checkForUpdate() async {
        state = .checking
        do {
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("Could not reach GitHub")
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if AppVersion.isNewer(release.tagName) {
                let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
                let downloadUrl = dmgAsset?.browserDownloadUrl ?? release.htmlUrl
                state = .available(version: release.tagName, url: downloadUrl)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func downloadAndInstall(from urlString: String) async {
        guard urlString.hasSuffix(".dmg") else {
            // No DMG asset — open the release page in browser
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        state = .downloading(progress: 0)
        do {
            let url = URL(string: urlString)!
            let (tempURL, _) = try await URLSession.shared.download(from: url, delegate: nil)

            let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("Pikimin-update.dmg")
            try? FileManager.default.removeItem(at: dmgPath)
            try FileManager.default.moveItem(at: tempURL, to: dmgPath)

            state = .installing
            try installFromDMG(dmgPath)
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
        }
    }

    private func installFromDMG(_ dmgPath: URL) throws {
        // Mount the DMG
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["attach", dmgPath.path, "-nobrowse", "-quiet"]
        let mountPipe = Pipe()
        mountProcess.standardOutput = mountPipe
        try mountProcess.run()
        mountProcess.waitUntilExit()

        // Find the mounted volume
        let volumePath = "/Volumes/Pikimin"
        let sourceApp = URL(fileURLWithPath: "\(volumePath)/Pikimin.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            // Detach and fail
            detachVolume(volumePath)
            throw NSError(domain: "UpdateService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Pikimin.app not found in DMG"])
        }

        // Find where we're currently running from
        let currentApp = Bundle.main.bundleURL

        // Copy new app over current
        let backupPath = currentApp.deletingLastPathComponent().appendingPathComponent("Pikimin-old.app")
        try? FileManager.default.removeItem(at: backupPath)
        try FileManager.default.moveItem(at: currentApp, to: backupPath)

        do {
            try FileManager.default.copyItem(at: sourceApp, to: currentApp)
        } catch {
            // Restore backup on failure
            try? FileManager.default.moveItem(at: backupPath, to: currentApp)
            detachVolume(volumePath)
            throw error
        }

        // Clean up
        try? FileManager.default.removeItem(at: backupPath)
        detachVolume(volumePath)
        try? FileManager.default.removeItem(at: dmgPath)

        // Relaunch
        relaunch()
    }

    private func detachVolume(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private func relaunch() {
        let appPath = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appPath]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}
