import Combine
import PDFKit
import SwiftUI

/// 编辑器状态管理器
/// 负责管理编辑器的各种状态（加载、检测、导出等）
@MainActor
class EditorStateManager: ObservableObject {
    // MARK: - 加载状态

    @Published var isLoading = false
    @Published var isDetecting = false
    @Published var isExporting = false
    @Published var errorMessage: String?

    // MARK: - 编辑状态

    @Published var selectedEffect: RedactionEffect = .solidBlack
    @Published var detectedRegions: [SensitiveRegion] = []

    @Published var currentImage: UIImage?

    @Published var canUndo = false
    @Published var canRedo = false

    // MARK: - PDF 状态

    @Published var currentPDFDocument: PDFDocument?
    @Published var currentPDFPageIndex: Int = 0
    @Published var totalPDFPages: Int = 0

    // MARK: - 分组状态

    @Published var allGroups: [FileGroup] = []
    @Published var currentGroup: FileGroup?
    @Published var showGroupPicker = false

    // MARK: - 配额状态

    @Published var showUsageLimitAlert = false
    @Published var showPremiumView = false

    // MARK: - 方法

    /// 重置错误消息
    func clearError() {
        errorMessage = nil
    }

    /// 设置错误消息
    func setError(_ message: String) {
        errorMessage = message
    }

    /// 更新撤销/重做状态
    func updateUndoRedoState(canUndo: Bool, canRedo: Bool) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }

    /// 更新 PDF 页面状态
    func updatePDFPageState(document: PDFDocument?, pageIndex: Int, totalPages: Int) {
        self.currentPDFDocument = document
        self.currentPDFPageIndex = pageIndex
        self.totalPDFPages = totalPages
    }
}
