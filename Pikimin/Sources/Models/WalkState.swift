import Foundation

enum WalkPhase: String {
    case idle = "Idle"
    case wandering = "Wandering"
    case returning = "Returning"
}

@MainActor
@Observable
final class WalkState {
    var currentStep: Int = 0
    var totalSteps: Int = 50_000
    var phase: WalkPhase = .idle
    var latitude: Double = 0
    var longitude: Double = 0
    var isWalking: Bool { phase != .idle }

    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }

    var percentText: String {
        "\(Int(progress * 100))%"
    }

    func reset() {
        currentStep = 0
        phase = .idle
        latitude = 0
        longitude = 0
    }
}
