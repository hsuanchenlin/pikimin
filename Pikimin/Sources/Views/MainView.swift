import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Text("Pikimin")
                .font(.largeTitle)
            Text("Ready")
        }
        .padding(40)
    }
}
