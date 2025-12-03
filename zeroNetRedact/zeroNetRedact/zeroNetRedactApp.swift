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
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase
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

        // 预初始化 StoreManager，确保内购服务尽早启动
        _ = StoreManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 主内容
                if isShowingLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(2)
                } else {
                    // 认证门控
                    if appState.shouldAuthenticate() {
                        AuthenticationView()
                            .transition(.opacity)
                            .zIndex(1)
                    } else if appState.isFirstLaunch && !appState.passwordEnabled {
                        // 首次启动，显示主界面并弹出密码设置提示
                        ContentView()
                            .sheet(isPresented: $appState.isFirstLaunch) {
                                PasswordSetupSheet()
                            }
                    } else {
                        ContentView()
                    }
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    // MARK: - Scene Phase Handling

    /// 处理应用生命周期变化
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // 进入后台，立即锁定（如果启用了密码保护）
            if appState.passwordEnabled {
                appState.lockApp()
            }

        case .inactive:
            // 暂时失活（如通知中心下拉、控制中心等）
            // 不做处理，避免频繁锁定
            break

        case .active:
            // 恢复到前台
            // 如果需要认证，AuthenticationView 会自动显示
            break

        @unknown default:
            break
        }
    }
}
