import Foundation

enum AppVersion {
    static let current = "1.1.0"

    /// Compare two semver strings. Returns true if remote > current.
    static func isNewer(_ remote: String) -> Bool {
        let strip = { (s: String) -> String in
            s.hasPrefix("v") ? String(s.dropFirst()) : s
        }
        let r = strip(remote).split(separator: ".").compactMap { Int($0) }
        let c = strip(current).split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
