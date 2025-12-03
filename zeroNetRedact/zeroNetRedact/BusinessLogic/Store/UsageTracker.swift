import Combine
import Foundation
import SwiftUI

/// 使用量追踪器 - 记录免费用户的每日导出次数
@MainActor
class UsageTracker: ObservableObject {

    // MARK: - Singleton

    static let shared = UsageTracker()

    // MARK: - Constants

    /// 免费用户每日图片导出限制
    static let dailyImageLimit = 3

    /// 免费用户每日文档导出限制
    static let dailyDocLimit = 3

    // MARK: - AppStorage Properties

    /// 今日图片导出次数
    @AppStorage("dailyImageExports") private var dailyImageExports: Int = 0

    /// 今日文档导出次数
    @AppStorage("dailyDocExports") private var dailyDocExports: Int = 0

    /// 上次导出日期 (格式: "2025-01-15")
    @AppStorage("lastExportDate") private var lastExportDate: String = ""

    // MARK: - Published Properties

    /// 今日已使用图片导出次数
    @Published private(set) var usedImageExports: Int = 0

    /// 今日已使用文档导出次数
    @Published private(set) var usedDocExports: Int = 0

    /// 今日剩余图片导出次数
    @Published private(set) var remainingImageExports: Int = 0

    /// 今日剩余文档导出次数
    @Published private(set) var remainingDocExports: Int = 0

    // MARK: - Initialization

    private init() {
        // 延迟执行以确保 @AppStorage 已正确初始化
        DispatchQueue.main.async { [weak self] in
            self?.checkAndResetDaily()
            self?.updateRemainingCounts()
        }

        // 同步执行一次，设置初始值
        let today = Self.todayString()
        if lastExportDate != today {
            dailyImageExports = 0
            dailyDocExports = 0
            lastExportDate = today
        }
        usedImageExports = dailyImageExports
        usedDocExports = dailyDocExports
        remainingImageExports = max(0, Self.dailyImageLimit - dailyImageExports)
        remainingDocExports = max(0, Self.dailyDocLimit - dailyDocExports)
    }

    // MARK: - Public Methods

    /// 检查是否可以导出图片
    func canExportImage() -> Bool {
        checkAndResetDaily()
        return dailyImageExports < Self.dailyImageLimit
    }

    /// 检查是否可以导出文档
    func canExportDocument() -> Bool {
        checkAndResetDaily()
        return dailyDocExports < Self.dailyDocLimit
    }

    /// 记录一次图片导出
    func recordImageExport() {
        checkAndResetDaily()
        dailyImageExports += 1
        updateRemainingCounts()
        print("📊 UsageTracker: 图片导出 \(dailyImageExports)/\(Self.dailyImageLimit)")
    }

    /// 记录一次文档导出
    func recordDocExport() {
        checkAndResetDaily()
        dailyDocExports += 1
        updateRemainingCounts()
        print("📊 UsageTracker: 文档导出 \(dailyDocExports)/\(Self.dailyDocLimit)")
    }

    /// 获取今日图片导出次数
    func getTodayImageExports() -> Int {
        checkAndResetDaily()
        return dailyImageExports
    }

    /// 获取今日文档导出次数
    func getTodayDocExports() -> Int {
        checkAndResetDaily()
        return dailyDocExports
    }

    /// 刷新状态（用于界面更新）
    func refresh() {
        checkAndResetDaily()
        updateRemainingCounts()
    }

    // MARK: - Private Methods

    /// 检查日期变化并重置计数
    private func checkAndResetDaily() {
        let today = Self.todayString()

        if lastExportDate != today {
            // 新的一天，重置计数
            dailyImageExports = 0
            dailyDocExports = 0
            lastExportDate = today
            print("🔄 UsageTracker: 新的一天，计数已重置")
        }
    }

    /// 更新使用次数
    private func updateRemainingCounts() {
        usedImageExports = dailyImageExports
        usedDocExports = dailyDocExports
        remainingImageExports = max(0, Self.dailyImageLimit - dailyImageExports)
        remainingDocExports = max(0, Self.dailyDocLimit - dailyDocExports)
    }

    /// 获取今天的日期字符串
    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }
}

// MARK: - Usage Status

extension UsageTracker {

    /// 使用状态描述
    struct UsageStatus {
        let imageUsed: Int
        let imageLimit: Int
        let docUsed: Int
        let docLimit: Int

        var imageRemaining: Int { imageLimit - imageUsed }
        var docRemaining: Int { docLimit - docUsed }

        var isImageLimitReached: Bool { imageRemaining <= 0 }
        var isDocLimitReached: Bool { docRemaining <= 0 }
        var isAnyLimitReached: Bool { isImageLimitReached || isDocLimitReached }

        /// 本地化的状态文本
        var localizedStatusText: String {
            String(
                format: NSLocalizedString("usage.status.format", comment: ""),
                imageRemaining, imageLimit, docRemaining, docLimit)
        }
    }

    /// 获取当前使用状态
    func getUsageStatus() -> UsageStatus {
        checkAndResetDaily()
        return UsageStatus(
            imageUsed: dailyImageExports,
            imageLimit: Self.dailyImageLimit,
            docUsed: dailyDocExports,
            docLimit: Self.dailyDocLimit
        )
    }
}
