import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Text("Pikimin Setup")
                .font(.largeTitle)
            Text("Preparing to download Android emulator components...")
            ProgressView()
        }
        .padding(40)
    }
}
