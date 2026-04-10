import Foundation

enum WalkPhase: String {
    case idle = "Idle"
    case wandering = "Wandering"
    case returning = "Returning"
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
        // Keep last 200 entries
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
