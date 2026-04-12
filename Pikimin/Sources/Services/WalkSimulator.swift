import Foundation

@MainActor
final class WalkSimulator {
    private let adb: ADBHelper
    private let state: WalkState
    private var walkTask: Task<Void, Never>?

    init(sdkDir: URL, state: WalkState) {
        self.adb = ADBHelper(sdkDir: sdkDir)
        self.state = state
    }

    func start() {
        guard !state.isWalking else { return }
        state.reset()
        state.startTime = Date()

        walkTask = Task {
            await run()
        }
    }

    func stop() {
        walkTask?.cancel()
        walkTask = nil
        state.phase = .idle
    }

    private func run() async {
        guard let coords = getLocation() else {
            state.phase = .idle
            return
        }

        let baseLat = coords.latitude
        let baseLon = coords.longitude
        var lat = baseLat
        var lon = baseLon
        state.latitude = lat
        state.longitude = lon

        let totalSteps = state.totalSteps
        let mode = state.mode
        let speed = state.speed
        let gpsStep = speed.gpsStep
        let gaitDelay = speed.gaitDelay
        let restDelay = speed.restDelay

        switch mode {
        case .randomWalk:
            await runRandomWalk(baseLat: baseLat, baseLon: baseLon, lat: &lat, lon: &lon,
                                totalSteps: totalSteps, gpsStep: gpsStep,
                                gaitDelay: gaitDelay, restDelay: restDelay)
        case .fixedDirection:
            await runFixedDirection(lat: &lat, lon: &lon, totalSteps: totalSteps,
                                   gpsStep: gpsStep, gaitDelay: gaitDelay, restDelay: restDelay)
        case .toDestination:
            await runToDestination(baseLat: baseLat, baseLon: baseLon, lat: &lat, lon: &lon,
                                  totalSteps: totalSteps, gpsStep: gpsStep,
                                  gaitDelay: gaitDelay, restDelay: restDelay)
        }

        state.addLog()
        state.phase = .idle
    }

    // MARK: - Walk Modes

    private func runRandomWalk(baseLat: Double, baseLon: Double,
                               lat: inout Double, lon: inout Double,
                               totalSteps: Int, gpsStep: Double,
                               gaitDelay: Int, restDelay: Int) async {
        let halfSteps = totalSteps / 2
        var direction = Int.random(in: 0..<8)
        var stepsInDir = 0
        var dirLength = Int.random(in: 30...150)

        for step in 1...totalSteps {
            if Task.isCancelled { break }
            state.phase = step <= halfSteps ? .wandering : .returning

            stepsInDir += 1
            if stepsInDir >= dirLength {
                stepsInDir = 0
                dirLength = Int.random(in: 30...150)
                direction = Int.random(in: 0..<8)
            }

            moveInDirection(direction, lat: &lat, lon: &lon, gpsStep: gpsStep)

            if step > halfSteps {
                let remaining = Double(totalSteps - step + 1)
                lat += (baseLat - lat) / (remaining * 3)
                lon += (baseLon - lon) / (remaining * 3)
            }

            await doStep(step: step, lat: lat, lon: lon, gaitDelay: gaitDelay, restDelay: restDelay)
        }
    }

    private func runFixedDirection(lat: inout Double, lon: inout Double,
                                   totalSteps: Int, gpsStep: Double,
                                   gaitDelay: Int, restDelay: Int) async {
        let dirIndex = state.direction.index

        for step in 1...totalSteps {
            if Task.isCancelled { break }
            state.phase = .wandering

            moveInDirection(dirIndex, lat: &lat, lon: &lon, gpsStep: gpsStep)
            await doStep(step: step, lat: lat, lon: lon, gaitDelay: gaitDelay, restDelay: restDelay)
        }
    }

    private func runToDestination(baseLat: Double, baseLon: Double,
                                  lat: inout Double, lon: inout Double,
                                  totalSteps: Int, gpsStep: Double,
                                  gaitDelay: Int, restDelay: Int) async {
        guard let destLat = Double(state.destLatitude),
              let destLon = Double(state.destLongitude) else {
            state.phase = .idle
            return
        }

        for step in 1...totalSteps {
            if Task.isCancelled { break }
            state.phase = .toDestination

            // Calculate direction toward destination
            let dLat = destLat - lat
            let dLon = destLon - lon
            let dist = (dLat * dLat + dLon * dLon).squareRoot()

            // Reached destination (within ~5m)
            if dist < 0.00005 { break }

            // Normalize and move
            let nLat = dLat / dist * gpsStep
            let nLon = dLon / dist * gpsStep
            // Add slight wobble for realism
            let wobble = Double.random(in: -0.15...0.15)
            lat += nLat + nLon * wobble
            lon += nLon + nLat * wobble

            await doStep(step: step, lat: lat, lon: lon, gaitDelay: gaitDelay, restDelay: restDelay)
        }
    }

    // MARK: - Shared

    private func moveInDirection(_ dir: Int, lat: inout Double, lon: inout Double, gpsStep: Double) {
        let wobble = Double.random(in: -0.000005...0.000005)
        switch dir {
        case 0: lat += gpsStep;           lon += wobble
        case 1: lat += gpsStep * 0.7;     lon += gpsStep * 0.7
        case 2: lon += gpsStep;           lat += wobble
        case 3: lat -= gpsStep * 0.7;     lon += gpsStep * 0.7
        case 4: lat -= gpsStep;           lon += wobble
        case 5: lat += gpsStep * 0.7;     lon -= gpsStep * 0.7
        case 6: lon -= gpsStep;           lat += wobble
        case 7: lat -= gpsStep * 0.7;     lon -= gpsStep * 0.7
        default: break
        }
    }

    private func doStep(step: Int, lat: Double, lon: Double, gaitDelay: Int, restDelay: Int) async {
        try? adb.geoFix(longitude: lon, latitude: lat)

        try? adb.setAcceleration(0.3, 0.4, 5.0)
        try? adb.setGyroscope(0.2, 0.3, 0.0)
        try? await Task.sleep(for: .milliseconds(gaitDelay))

        try? adb.setAcceleration(-1.5, 2.0, 22.0)
        try? await Task.sleep(for: .milliseconds(gaitDelay))

        try? adb.setAcceleration(-2.0, 2.5, 25.0)
        try? await Task.sleep(for: .milliseconds(gaitDelay))

        try? adb.setAcceleration(-0.3, 0.5, 12.0)
        try? await Task.sleep(for: .milliseconds(gaitDelay))

        try? adb.setAcceleration(0.0, 0.0, 9.8)
        try? adb.setGyroscope(0.0, 0.0, 0.0)
        try? await Task.sleep(for: .milliseconds(restDelay))

        try? adb.setAcceleration(0.5, -0.6, 15.0)
        try? await Task.sleep(for: .milliseconds(gaitDelay))

        try? adb.setAcceleration(0.0, 0.0, 9.8)
        try? await Task.sleep(for: .milliseconds(restDelay))

        state.currentStep = step
        state.latitude = lat
        state.longitude = lon

        if step % 50 == 0 || step == 1 {
            state.addLog()
        }
    }

    private func getLocation() -> (latitude: Double, longitude: Double)? {
        guard let output = try? adb.shell("dumpsys location") else { return nil }
        guard let range = output.range(of: #"Location\[gps\s+"#, options: .regularExpression) else { return nil }
        let after = output[range.upperBound...]
        guard let endRange = after.range(of: " ") else { return nil }
        let coordStr = String(after[after.startIndex..<endRange.lowerBound])
        let parts = coordStr.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }
}
