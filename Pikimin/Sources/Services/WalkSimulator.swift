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
        let halfSteps = totalSteps / 2
        let gpsStep = 0.000014

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

            let wobble = Double.random(in: -0.000005...0.000005)
            switch direction {
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

            if step > halfSteps {
                let remaining = Double(totalSteps - step + 1)
                lat += (baseLat - lat) / (remaining * 3)
                lon += (baseLon - lon) / (remaining * 3)
            }

            try? adb.geoFix(longitude: lon, latitude: lat)

            // Gait cycle
            try? adb.setAcceleration(0.3, 0.4, 5.0)
            try? adb.setGyroscope(0.2, 0.3, 0.0)
            try? await Task.sleep(for: .milliseconds(50))

            try? adb.setAcceleration(-1.5, 2.0, 22.0)
            try? await Task.sleep(for: .milliseconds(50))

            try? adb.setAcceleration(-2.0, 2.5, 25.0)
            try? await Task.sleep(for: .milliseconds(50))

            try? adb.setAcceleration(-0.3, 0.5, 12.0)
            try? await Task.sleep(for: .milliseconds(50))

            try? adb.setAcceleration(0.0, 0.0, 9.8)
            try? adb.setGyroscope(0.0, 0.0, 0.0)
            try? await Task.sleep(for: .milliseconds(100))

            try? adb.setAcceleration(0.5, -0.6, 15.0)
            try? await Task.sleep(for: .milliseconds(50))

            try? adb.setAcceleration(0.0, 0.0, 9.8)
            try? await Task.sleep(for: .milliseconds(100))

            state.currentStep = step
            state.latitude = lat
            state.longitude = lon
        }

        state.phase = .idle
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
