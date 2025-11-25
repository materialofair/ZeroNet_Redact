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
    /// - Returns: 检测到的敏感区域列表
    func detectSensitiveRegions() async throws -> [SensitiveRegion]

    /// 应用脱敏效果
    /// - Parameters:
    ///   - region: 脱敏区域
    ///   - effect: 脱敏效果
    func applyRedaction(at region: CGRect, effect: RedactionEffect)

    /// 撤销上一次操作
    func undo()

    /// 重做上一次撤销的操作
    func redo()

    /// 导出脱敏后的文件
    /// - Returns: 文件数据
    func exportRedactedFile() async throws -> Data
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
