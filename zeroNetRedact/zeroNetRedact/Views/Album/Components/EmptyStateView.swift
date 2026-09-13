import SwiftUI

struct EmptyStateView: View {
    @Binding var selectedTab: Int

    var body: some View {
        ContentUnavailableView {
            Label("album.empty", systemImage: "checkmark.shield")
        } description: {
            Text("album.empty.explanation")
        } actions: {
            Button("album.empty.start") { selectedTab = 0 }
                .buttonStyle(.borderedProminent)
        }
    }
}
