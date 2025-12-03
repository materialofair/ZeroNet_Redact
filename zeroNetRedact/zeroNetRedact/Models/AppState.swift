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

    /// 是否已购买高级版
    @Published var isPremium = false

    /// 审核模式是否激活
    @Published var isReviewMode = false

    // MARK: - AppStorage Properties

    /// 是否启用密码保护
    @AppStorage("passwordEnabled") var passwordEnabled = false

    /// 是否启用生物识别
    @AppStorage("biometricEnabled") var biometricEnabled = true

    /// 是否首次启动
    @AppStorage("isFirstLaunch") var isFirstLaunch = true

    /// 最后活跃时间
    @AppStorage("lastActiveTimestamp") private var lastActiveTimestamp: Double = 0

    /// 审核模式是否已激活（持久化）
    @AppStorage("reviewModeActivated") private var reviewModeActivated: Bool = false

    // MARK: - Constants

    /// 审核模式有效期: 2026年1月1日 00:00:00 UTC
    static let reviewModeExpiryDate = Date(timeIntervalSince1970: 1_767_225_600)

    /// 审核密码
    static let reviewCode = "REVIEW2026"

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

        // 检查审核模式状态
        checkReviewModeStatus()
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

    // MARK: - Premium & Review Mode

    /// 检查是否有无限使用权限（付费用户或审核模式）
    var hasUnlimitedAccess: Bool {
        return isPremium || isReviewModeActive
    }

    /// 审核模式是否有效（已激活且未过期）
    var isReviewModeActive: Bool {
        return reviewModeActivated && Date() < Self.reviewModeExpiryDate
    }

    /// 激活审核模式
    /// - Parameter code: 审核密码
    /// - Returns: 是否激活成功
    @discardableResult
    func activateReviewMode(with code: String) -> Bool {
        if code == Self.reviewCode && Date() < Self.reviewModeExpiryDate {
            reviewModeActivated = true
            isReviewMode = true
            print("✅ AppState: 审核模式已激活，有效期至 \(Self.reviewModeExpiryDate)")
            return true
        }
        print("❌ AppState: 审核模式激活失败 - 密码错误或已过期")
        return false
    }

    /// 检查并更新审核模式状态
    private func checkReviewModeStatus() {
        if reviewModeActivated {
            if Date() < Self.reviewModeExpiryDate {
                isReviewMode = true
                print("✅ AppState: 审核模式有效")
            } else {
                // 已过期，清除状态
                reviewModeActivated = false
                isReviewMode = false
                print("⚠️ AppState: 审核模式已过期")
            }
        }
    }
}
