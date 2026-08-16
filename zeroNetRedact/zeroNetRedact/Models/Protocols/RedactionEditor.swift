//
//  RedactionEditor.swift
//  ZeroNet Redact
//
//  脱敏编辑器协议 - 支持多种文件类型的编辑器抽象
//

import CoreGraphics
import Foundation

/// 脱敏编辑器协议
protocol RedactionEditor: AnyObject {
    associatedtype FileType: RedactableFile

    /// 加载文件
    /// - Parameter file: 要加载的文件
    func loadFile(_ file: FileType) async throws

    /// 智能识别敏感区域
    /// - Parameter progress: 进度回调（0...1，OCR 分片/逐页/方向轮次上报；nil 表示不需要）
    /// - Returns: 检测到的敏感区域列表
    func detectSensitiveRegions(progress: ((Double) -> Void)?) async throws -> [SensitiveRegion]

    /// 应用脱敏效果
    /// - Parameters:
    ///   - region: 脱敏区域
    ///   - effect: 脱敏效果
    func applyRedaction(at region: CGRect, effect: RedactionEffect)

    /// 批量应用脱敏效果（同效果的多个区域合并为一次快照/渲染）
    func applyRedactions(at regions: [CGRect], effect: RedactionEffect)

    /// 撤销上一次操作
    func undo()

    /// 重做上一次撤销的操作
    func redo()

    /// 导出脱敏后的文件
    /// - Parameter progress: 进度回调（0...1，PDF 逐页/阶段上报；nil 表示不需要）
    /// - Returns: 文件数据
    func exportRedactedFile(progress: ((Double) -> Void)?) async throws -> Data
}

extension RedactionEditor {
    /// 无进度回调的便捷版本
    func exportRedactedFile() async throws -> Data {
        try await exportRedactedFile(progress: nil)
    }
}

/// 编辑操作（用于撤销/重做）
struct EditOperation {
    let region: CGRect
    let effect: RedactionEffect
    let timestamp: Date
    let pageIndex: Int?  // PDF多页支持

    init(region: CGRect, effect: RedactionEffect, pageIndex: Int? = nil) {
        self.region = region
        self.effect = effect
        self.timestamp = Date()
        self.pageIndex = pageIndex
    }
}

extension RedactionEditor {
    /// 无进度回调的便捷版本
    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        try await detectSensitiveRegions(progress: nil)
    }
}
