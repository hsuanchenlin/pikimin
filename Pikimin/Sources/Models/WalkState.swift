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
        case .slow: return 0.000008     // ~0.9m
        case .normal: return 0.000014   // ~1.5m
        case .fast: return 0.000025     // ~2.8m
        case .sprint: return 0.000045   // ~5.0m
        }
    }

    /// Delay between gait phases in ms
    var gaitDelay: Int {
        switch self {
        case .slow: return 80
        case .normal: return 50
        case .fast: return 30
        case .sprint: return 15
        }
    }

    /// Rest delay in ms
    var restDelay: Int {
        switch self {
        case .slow: return 150
        case .normal: return 100
        case .fast: return 60
        case .sprint: return 30
        }
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
    var destLatitude: String = ""
    var destLongitude: String = ""

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
