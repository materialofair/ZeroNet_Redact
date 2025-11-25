import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView()
                .tabItem {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .tag(0)

            AlbumView()
                .tabItem {
                    Label("脱敏文件", systemImage: "checkmark.shield.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
