//
//  zeroNetRedactApp.swift
//  zeroNetRedact
//
//  Created by WangQiao on 2025/11/19.
//

import SwiftData
import SwiftUI

@main
struct zeroNetRedactApp: App {
    @State private var isShowingLaunchScreen = true

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 初始化默认分组和迁移现有文件
        GroupManager.shared.ensureDefaultGroup()
        GroupManager.shared.migrateExistingFiles()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if isShowingLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // 延迟2秒后隐藏启动页
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        isShowingLaunchScreen = false
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
