import Combine
import CoreData
import Foundation
import SwiftUI

/// 销毁式重置（`AppState.resetAllData()`）过程中可能发生的错误
enum ResetAllDataError: LocalizedError {
    /// Core Data 清空/保存失败，此时磁盘文件与密码均未被清除
    case coreDataSaveFailed(Error)
    /// Core Data 已清空，但磁盘上部分文件夹未能成功删除
    case filesNotFullyDeleted(remaining: [String])

    var errorDescription: String? {
        switch self {
        case .coreDataSaveFailed:
            return NSLocalizedString("resetAllData.error.coreData", comment: "")
        case .filesNotFullyDeleted:
            return NSLocalizedString("resetAllData.error.filesRemaining", comment: "")
        }
    }
}

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

    /// 审核模式有效期: 2026年8月1日 00:00:00 UTC
    static let reviewModeExpiryDate = Date(timeIntervalSince1970: 1_785_542_400)

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

        withAnimation(.easeOut(duration: 0.25)) {
            isAuthenticated = false
            isLocked = true
        }
        lastActiveTime = Date()
    }

    /// 解锁应用
    func unlockApp() {
        withAnimation(.easeOut(duration: 0.25)) {
            isAuthenticated = true
            isLocked = false
        }
        lastActiveTime = Date()
    }

    /// 重置认证状态（用于退出登录等场景）
    func reset() {
        isAuthenticated = false
        isLocked = true
    }

    /// 销毁式重置：清除密码及全部本地数据，恢复到首次启动状态
    /// - Warning: 这是破坏性操作且不可恢复，调用前必须已完成 UI 层的二次确认
    /// - Throws: `ResetAllDataError`，当 Core Data 清空或磁盘文件删除失败时抛出；
    ///   失败时不会解锁应用、也不会重置密码/使用记录，调用方应保持锁定状态并提示用户
    func resetAllData() throws {
        print("🗑️ AppState.resetAllData: 开始销毁式重置")

        // 1) 清空 Core Data 中的所有文件记录与分组（级联删除脱敏文件记录）；失败则整体中止
        let context = PersistenceController.shared.container.viewContext
        if let files = try? context.fetch(OriginalFile.fetchRequest()) {
            files.forEach { context.delete($0) }
        }
        if let groups = try? context.fetch(FileGroup.fetchRequest()) {
            groups.forEach { context.delete($0) }
        }
        do {
            try context.save()
            print("✅ AppState.resetAllData: Core Data 已清空")
        } catch {
            print("❌ AppState.resetAllData: Core Data 清空失败 - \(error)")
            throw ResetAllDataError.coreDataSaveFailed(error)
        }

        // 2) 删除磁盘上的原文件、缩略图与脱敏文件，并复核确实已删除
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var remainingFolders: [String] = []
        for folder in ["Originals", "Thumbnails", "Redacted"] {
            let folderURL = documentsURL.appendingPathComponent(folder)
            try? FileManager.default.removeItem(at: folderURL)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                remainingFolders.append(folder)
            }
        }
        if !remainingFolders.isEmpty {
            // Core Data 此时已清空，仅磁盘文件残留；错误信息中说明这一情况
            print("❌ AppState.resetAllData: 磁盘文件未能完全删除 - \(remainingFolders)")
            throw ResetAllDataError.filesNotFullyDeleted(remaining: remainingFolders)
        }
        print("✅ AppState.resetAllData: 磁盘文件已清空")

        // 3) 前两步都成功后，才清除密码、使用记录并重建默认分组、解锁应用
        try? passwordManager.removePassword()

        // 清除当日免费导出配额记录
        UsageTracker.shared.resetAllUsage()

        // 重建默认分组，恢复到首次启动状态
        GroupManager.shared.ensureDefaultGroup()

        passwordEnabled = false
        biometricEnabled = true
        isFirstLaunch = true
        withAnimation(.easeOut(duration: 0.25)) {
            isAuthenticated = true
            isLocked = false
        }
        print("✅ AppState.resetAllData: 重置完成")
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
