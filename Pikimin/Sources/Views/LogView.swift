import SwiftUI

struct LogView: View {
    let entries: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        Text(entry)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .onChange(of: entries.count) { _, newCount in
                if newCount > 0 {
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
        .background(.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
