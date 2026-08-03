import Combine
import Foundation
import SwiftUI

/// 使用量追踪器 - 记录免费用户的每日导出次数
@MainActor
class UsageTracker: ObservableObject {

    // MARK: - Singleton

    static let shared = UsageTracker()

    // MARK: - Constants

    /// 免费用户每日媒体（图片+视频合并）导出限制
    static let dailyMediaLimit = 3

    /// 免费用户每日文档导出限制
    static let dailyDocLimit = 3

    /// 免费用户可脱敏的视频大小上限（超过需开通高级版）
    static let freeVideoSizeLimit: Int64 = 300 * 1024 * 1024

    // MARK: - AppStorage Properties

    /// 今日媒体（图片+视频）导出次数；存储键沿用历史 key，避免重置存量计数
    @AppStorage("dailyImageExports") private var dailyMediaExports: Int = 0

    /// 今日文档导出次数
    @AppStorage("dailyDocExports") private var dailyDocExports: Int = 0

    /// 上次导出日期 (格式: "2025-01-15")
    @AppStorage("lastExportDate") private var lastExportDate: String = ""

    // MARK: - Published Properties

    /// 今日已使用媒体（图片+视频）导出次数
    @Published private(set) var usedMediaExports: Int = 0

    /// 今日已使用文档导出次数
    @Published private(set) var usedDocExports: Int = 0

    /// 今日剩余媒体（图片+视频）导出次数
    @Published private(set) var remainingMediaExports: Int = 0

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
            dailyMediaExports = 0
            dailyDocExports = 0
            lastExportDate = today
        }
        usedMediaExports = dailyMediaExports
        usedDocExports = dailyDocExports
        remainingMediaExports = max(0, Self.dailyMediaLimit - dailyMediaExports)
        remainingDocExports = max(0, Self.dailyDocLimit - dailyDocExports)
    }

    // MARK: - Public Methods

    /// 检查是否可以导出媒体（图片/视频共用同一每日配额）
    func canExportMedia() -> Bool {
        checkAndResetDaily()
        return dailyMediaExports < Self.dailyMediaLimit
    }

    /// 检查是否可以导出文档
    func canExportDocument() -> Bool {
        checkAndResetDaily()
        return dailyDocExports < Self.dailyDocLimit
    }

    /// 记录一次媒体导出（图片/视频共用同一每日配额）
    func recordMediaExport() {
        checkAndResetDaily()
        dailyMediaExports += 1
        updateRemainingCounts()
        print("📊 UsageTracker: 媒体导出 \(dailyMediaExports)/\(Self.dailyMediaLimit)")
    }

    /// 记录一次文档导出
    func recordDocExport() {
        checkAndResetDaily()
        dailyDocExports += 1
        updateRemainingCounts()
        print("📊 UsageTracker: 文档导出 \(dailyDocExports)/\(Self.dailyDocLimit)")
    }

    /// 获取今日媒体导出次数
    func getTodayMediaExports() -> Int {
        checkAndResetDaily()
        return dailyMediaExports
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

    /// 清除全部使用记录（用于销毁式重置）
    func resetAllUsage() {
        dailyMediaExports = 0
        dailyDocExports = 0
        lastExportDate = ""
        updateRemainingCounts()
    }

    // MARK: - Private Methods

    /// 检查日期变化并重置计数
    private func checkAndResetDaily() {
        let today = Self.todayString()

        if lastExportDate != today {
            // 新的一天，重置计数
            dailyMediaExports = 0
            dailyDocExports = 0
            lastExportDate = today
            print("🔄 UsageTracker: 新的一天，计数已重置")
        }
    }

    /// 更新使用次数
    private func updateRemainingCounts() {
        usedMediaExports = dailyMediaExports
        usedDocExports = dailyDocExports
        remainingMediaExports = max(0, Self.dailyMediaLimit - dailyMediaExports)
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
        let mediaUsed: Int
        let mediaLimit: Int
        let docUsed: Int
        let docLimit: Int

        var mediaRemaining: Int { mediaLimit - mediaUsed }
        var docRemaining: Int { docLimit - docUsed }

        var isMediaLimitReached: Bool { mediaRemaining <= 0 }
        var isDocLimitReached: Bool { docRemaining <= 0 }
        var isAnyLimitReached: Bool { isMediaLimitReached || isDocLimitReached }

        /// 本地化的状态文本
        var localizedStatusText: String {
            String(
                format: NSLocalizedString("usage.status.format", comment: ""),
                mediaRemaining, mediaLimit, docRemaining, docLimit)
        }
    }

    /// 获取当前使用状态
    func getUsageStatus() -> UsageStatus {
        checkAndResetDaily()
        return UsageStatus(
            mediaUsed: dailyMediaExports,
            mediaLimit: Self.dailyMediaLimit,
            docUsed: dailyDocExports,
            docLimit: Self.dailyDocLimit
        )
    }
}
