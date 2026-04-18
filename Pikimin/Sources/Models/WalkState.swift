import Foundation

enum WalkPhase: String {
    case idle = "Idle"
    case wandering = "Wandering"
    case returning = "Returning"
    case toDestination = "To Destination"
}

enum WalkMode: String, CaseIterable {
    case randomWalk = "Random Walk"
    case fixedDirection = "Fixed Direction"
    case toDestination = "Walk to Destination"
}

enum WalkDirection: String, CaseIterable {
    case north = "N"
    case northEast = "NE"
    case east = "E"
    case southEast = "SE"
    case south = "S"
    case southWest = "SW"
    case west = "W"
    case northWest = "NW"

    var index: Int {
        switch self {
        case .north: return 0
        case .northEast: return 1
        case .east: return 2
        case .southEast: return 3
        case .south: return 4
        case .southWest: return 5
        case .west: return 6
        case .northWest: return 7
        }
    }
}

enum WalkSpeed: String, CaseIterable {
    case slow = "Slow"
    case normal = "Normal"
    case fast = "Fast"
    case sprint = "Sprint"

    /// GPS step size in degrees (~meters per step)
    var gpsStep: Double {
        switch self {
        case .slow: return 0.000008     // ~0.9m  → ~3 km/h
        case .normal: return 0.000014   // ~1.5m  → ~5 km/h
        case .fast: return 0.000022     // ~2.4m  → ~9 km/h
        case .sprint: return 0.000018   // ~2.0m  → ~14 km/h (faster cadence)
        }
    }

    /// Delay between gait phases in ms
    var gaitDelay: Int {
        switch self {
        case .slow: return 80           // ~1.5 steps/sec
        case .normal: return 50         // ~2 steps/sec
        case .fast: return 40           // ~2.5 steps/sec
        case .sprint: return 25         // ~3.5 steps/sec
        }
    }

    /// Rest delay in ms
    var restDelay: Int {
        switch self {
        case .slow: return 150          // ~1.5 steps/sec
        case .normal: return 100        // ~2 steps/sec
        case .fast: return 50           // ~2.5 steps/sec
        case .sprint: return 30         // ~3.5 steps/sec
        }
    }
}

struct SavedPoint: Identifiable, Codable {
    var id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double

    var coordsString: String {
        "\(latitude), \(longitude)"
    }

    static func load() -> [SavedPoint] {
        let url = savedPointsURL
        guard let data = try? Data(contentsOf: url),
              let points = try? JSONDecoder().decode([SavedPoint].self, from: data) else {
            return []
        }
        return points
    }

    static func save(_ points: [SavedPoint]) {
        let url = savedPointsURL
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: url)
        }
    }

    private static var savedPointsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Pikimin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("saved_points.json")
    }
}

struct WalkLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let step: Int
    let phase: WalkPhase
    let latitude: Double
    let longitude: Double
}

@MainActor
@Observable
final class WalkState {
    var currentStep: Int = 0
    var totalSteps: Int = 50_000
    var phase: WalkPhase = .idle
    var latitude: Double = 0
    var longitude: Double = 0
    var logEntries: [WalkLogEntry] = []
    var startTime: Date?
    var isWalking: Bool { phase != .idle }

    // Walk settings
    var mode: WalkMode = .randomWalk
    var direction: WalkDirection = .north
    var speed: WalkSpeed = .normal
    var destCoords: String = ""  // "lat, lon" format
    var savedPoints: [SavedPoint] = []

    /// Parse destCoords into lat/lon
    var parsedDestination: (latitude: Double, longitude: Double)? {
        let parts = destCoords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }

    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }

    var percentText: String {
        "\(Int(progress * 100))%"
    }

    var elapsedText: String {
        guard let start = startTime else { return "" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    func addLog() {
        logEntries.append(WalkLogEntry(
            timestamp: Date(),
            step: currentStep,
            phase: phase,
            latitude: latitude,
            longitude: longitude
        ))
        if logEntries.count > 200 {
            logEntries.removeFirst(logEntries.count - 200)
        }
    }

    func reset() {
        currentStep = 0
        phase = .idle
        latitude = 0
        longitude = 0
        logEntries = []
        startTime = nil
    }
}
