//
//  TextRecognition.swift
//  ZeroNet Redact
//
//  文字识别协议 - 支持多种识别方式的抽象
//

import Foundation

/// 文字识别协议
protocol TextRecognition {
    /// 识别文字
    /// - Parameters:
    ///   - data: 文件数据
    ///   - fileType: 文件类型
    /// - Returns: 识别到的文字列表
    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText]

    /// 检测敏感信息
    /// - Parameter texts: 识别到的文字列表
    /// - Returns: 敏感区域列表
    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion]
}

/// 识别的文字结构
struct RecognizedText: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let pageIndex: Int?  // PDF多页支持

    init(text: String, boundingBox: CGRect, confidence: Float, pageIndex: Int? = nil) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.pageIndex = pageIndex
    }
}

/// 敏感区域结构
struct SensitiveRegion: Identifiable {
    let id = UUID()
    let type: SensitiveType
    let boundingBox: CGRect
    let confidence: Float
    let pageIndex: Int?
    var isConfirmed: Bool
    let recognizedText: String?

    init(
        type: SensitiveType,
        boundingBox: CGRect,
        confidence: Float,
        pageIndex: Int? = nil,
        isConfirmed: Bool = false,
        recognizedText: String? = nil
    ) {
        self.type = type
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.pageIndex = pageIndex
        self.isConfirmed = isConfirmed
        self.recognizedText = recognizedText
    }
}
