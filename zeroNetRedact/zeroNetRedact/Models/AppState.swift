import Combine
import Foundation
import SwiftUI

/// 全局应用状态管理
@MainActor
class AppState: ObservableObject {
    // MARK: - Singleton

    static let shared = AppState()

    // MARK: - Published Properties

    /// 认证状态
    @Published var isAuthenticated = false

    /// 锁定状态
    @Published var isLocked = true

    // MARK: - AppStorage Properties

    /// 是否启用密码保护
    @AppStorage("passwordEnabled") var passwordEnabled = false

    /// 是否启用生物识别
    @AppStorage("biometricEnabled") var biometricEnabled = true

    /// 是否首次启动
    @AppStorage("isFirstLaunch") var isFirstLaunch = true

    /// 最后活跃时间
    @AppStorage("lastActiveTimestamp") private var lastActiveTimestamp: Double = 0

    // MARK: - Computed Properties

    var lastActiveTime: Date {
        get { Date(timeIntervalSince1970: lastActiveTimestamp) }
        set { lastActiveTimestamp = newValue.timeIntervalSince1970 }
    }

    // MARK: - Private Properties

    private let passwordManager = PasswordManager.shared

    // MARK: - Initialization

    private init() {
        // 检查是否真的启用了密码
        if passwordEnabled && !passwordManager.hasPassword() {
            // 数据不一致，重置状态
            passwordEnabled = false
        }

        // 如果启用了密码，启动时需要锁定
        if passwordEnabled {
            isLocked = true
            isAuthenticated = false
        } else {
            isLocked = false
            isAuthenticated = true
        }
    }

    // MARK: - Public Methods

    /// 检查是否需要认证
    func shouldAuthenticate() -> Bool {
        return passwordEnabled && !isAuthenticated
    }

    /// 锁定应用
    func lockApp() {
        guard passwordEnabled else { return }

        isAuthenticated = false
        isLocked = true
        lastActiveTime = Date()
    }

    /// 解锁应用
    func unlockApp() {
        isAuthenticated = true
        isLocked = false
        lastActiveTime = Date()
    }

    /// 重置认证状态（用于退出登录等场景）
    func reset() {
        isAuthenticated = false
        isLocked = true
    }
}
