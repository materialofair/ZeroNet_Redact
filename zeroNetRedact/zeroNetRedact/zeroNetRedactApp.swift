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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingLaunchScreen = true
    @State private var isObscured = false

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
        // 上次运行若被系统终止，启动时清理仅供视频处理使用的明文工作副本。
        StorageManager.shared.cleanupVideoWorkspaces()

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
                    } else if !appState.hasSeenOnboarding {
                        // 首启密码流程结束后（设置或跳过），展示新手引导；
                        // 独立于 isFirstLaunch 的状态，避免与密码 sheet 同时弹出
                        ContentView()
                            .sheet(
                                isPresented: Binding(
                                    get: { !appState.hasSeenOnboarding },
                                    set: { presented in
                                        if !presented {
                                            appState.hasSeenOnboarding = true
                                        }
                                    }
                                )
                            ) {
                                OnboardingView(onFinish: {
                                    appState.hasSeenOnboarding = true
                                })
                            }
                    } else {
                        ContentView()
                    }
                }

                // 隐私遮罩：App 切换器/多任务预览时防止内容截图泄漏
                if isObscured {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(3)
                }
            }
            .onAppear {
                // 延迟隐藏启动页（Reduce Motion 时无淡出动画）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
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
            if appState.passwordEnabled {
                if appState.autoLockEnabled {
                    // 自动锁定：记录进入后台的时间，回到前台超时后再锁
                    appState.lastActiveTime = Date()
                } else {
                    // 未开启自动锁定：进入后台立即锁定
                    appState.lockApp()
                }
            }
            setObscured(true)

        case .inactive:
            // 暂时失活（如通知中心下拉、控制中心、App 切换器快照等）
            // 显示隐私遮罩，避免系统截图捕获到敏感内容
            setObscured(true)

        case .active:
            // 恢复到前台，移除隐私遮罩
            setObscured(false)
            // 自动锁定：后台时间超过设定阈值则锁定，否则保持解锁
            if appState.passwordEnabled && appState.autoLockEnabled {
                let elapsed = Date().timeIntervalSince(appState.lastActiveTime)
                if elapsed >= TimeInterval(appState.autoLockTimeout) {
                    appState.lockApp()
                }
            }

        @unknown default:
            break
        }
    }

    /// 显示/隐藏隐私遮罩
    /// - HIGH-9: 显示遮罩（进入后台/失活）必须立即生效、不带动画，否则 0.12s 的淡入窗口期内
    ///   系统截图仍可能捕获到未遮挡的敏感内容；隐藏遮罩（回到前台）保留淡出动画以避免闪烁感
    private func setObscured(_ value: Bool) {
        if value {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isObscured = true
            }
        } else {
            // Reduce Motion 时不播放淡出动画
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isObscured = false
            }
        }
    }
}
