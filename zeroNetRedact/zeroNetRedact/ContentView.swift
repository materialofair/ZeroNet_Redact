import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.import", comment: ""),
                        systemImage: "square.and.arrow.down")
                }
                .tag(0)

            AlbumView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.redacted", comment: ""),
                        systemImage: "checkmark.shield.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label(NSLocalizedString("tab.settings", comment: ""), systemImage: "gearshape")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
