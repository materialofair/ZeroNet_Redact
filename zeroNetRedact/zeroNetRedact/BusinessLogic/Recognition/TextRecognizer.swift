//
//  TextRecognizer.swift
//  ZeroNet Redact
//
//  统一文字识别器 - 支持图片OCR和PDF文字提取
//

import Foundation
import PDFKit
import UIKit
import Vision

/// 文字识别器单例
class TextRecognizer {
    static let shared = TextRecognizer()

    private init() {}

    // MARK: - 统一识别接口

    /// 识别文件中的文字
    func recognizeText(in file: OriginalFile) async throws -> [RecognizedText] {
        // 加载并解密数据
        let encryptedData = try StorageManager.shared.loadEncryptedOriginal(
            id: file.id, type: file.fileType)
        let data = try CryptoEngine.shared.decrypt(data: encryptedData)

        // 根据文件类型选择识别器
        let recognizer: TextRecognition
        switch file.fileType {
        case .image:
            recognizer = ImageOCRRecognizer()
        case .pdf:
            recognizer = PDFTextRecognizer()
        }

        return try await recognizer.recognizeText(in: data, fileType: file.fileType)
    }

    // MARK: - 检测敏感信息

    /// 检测文字中的敏感信息
    func detectSensitiveRegions(in texts: [RecognizedText]) -> [SensitiveRegion] {
        var regions: [SensitiveRegion] = []

        let patterns: [(pattern: String, type: SensitiveType)] = [
            (SensitivePatterns.idCard, .idCard),  // 优先检测身份证
            (SensitivePatterns.phoneNumber, .phoneNumber),
            (SensitivePatterns.bankCard, .bankCard),
            (SensitivePatterns.email, .email),
        ]

        for text in texts {
            // 清理文本：移除空格和常见分隔符
            let cleanedText = text.text.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")

            for (pattern, type) in patterns {
                // 同时检测原始文本和清理后的文本
                let textsToCheck = [text.text, cleanedText]

                for checkText in textsToCheck {
                    let matches = SensitivePatterns.findMatches(in: checkText, pattern: pattern)

                    for match in matches {
                        if let range = Range(match.range, in: checkText) {
                            let matchedText = String(checkText[range])

                            // 额外验证：避免误报
                            if isValidSensitiveData(matchedText, type: type) {
                                regions.append(
                                    SensitiveRegion(
                                        type: type,
                                        boundingBox: text.boundingBox,
                                        confidence: text.confidence,
                                        pageIndex: text.pageIndex,
                                        isConfirmed: false,
                                        recognizedText: matchedText
                                    ))

                                // 找到一个匹配就停止该文本的检测
                                break
                            }
                        }
                    }

                    if !regions.isEmpty && regions.last?.boundingBox == text.boundingBox {
                        break
                    }
                }
            }
        }

        // 去重：合并重叠的区域
        return deduplicateRegions(regions)
    }

    /// 验证敏感数据的有效性
    private func isValidSensitiveData(_ text: String, type: SensitiveType) -> Bool {
        switch type {
        case .idCard:
            // 身份证号长度验证
            let cleanText = text.replacingOccurrences(of: " ", with: "")
            return cleanText.count == 18 || cleanText.count == 15

        case .phoneNumber:
            // 手机号验证：移除分隔符后必须是11位
            let digits = text.filter { $0.isNumber }
            return digits.count == 11

        case .bankCard:
            // 银行卡验证：13-19位数字
            let digits = text.filter { $0.isNumber }
            return digits.count >= 13 && digits.count <= 19

        default:
            return true
        }
    }

    /// 去重和合并重叠的检测区域
    private func deduplicateRegions(_ regions: [SensitiveRegion]) -> [SensitiveRegion] {
        var uniqueRegions: [SensitiveRegion] = []

        for region in regions {
            // 检查是否与已有区域重叠
            let hasOverlap = uniqueRegions.contains { existing in
                existing.boundingBox.intersects(region.boundingBox)
            }

            if !hasOverlap {
                uniqueRegions.append(region)
            }
        }

        return uniqueRegions
    }
}

// MARK: - 图片OCR识别器 (使用 Apple Vision Framework)

class ImageOCRRecognizer: TextRecognition {

    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText] {
        return try await recognizeWithVision(data: data)
    }

    /// Apple Vision 文字识别 (优化版)
    private func recognizeWithVision(data: Data) async throws -> [RecognizedText] {
        guard let image = UIImage(data: data),
            let cgImage = image.cgImage
        else {
            throw RecognitionError.invalidImageData
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let texts = observations.compactMap { observation -> RecognizedText? in
                    guard let topCandidate = observation.topCandidates(1).first else {
                        return nil
                    }

                    return RecognizedText(
                        text: topCandidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: topCandidate.confidence,
                        pageIndex: nil
                    )
                }

                continuation.resume(returning: texts)
            }

            // 🔧 优化配置 - 针对中文身份证识别
            request.recognitionLevel = .accurate  // 使用最高精度
            request.recognitionLanguages = ["zh-Hans", "en-US"]  // 简体中文 + 英文
            request.usesLanguageCorrection = true  // 启用语言纠正
            request.minimumTextHeight = 0.005  // 降低最小文字高度，识别更小的字

            // 添加身份证常见词汇，提高识别准确率
            request.customWords = [
                "身份证", "公民身份号码", "居民身份证",
                "姓名", "性别", "民族", "出生", "住址", "公民身份",
                "签发机关", "有效期限", "年", "月", "日",
                "男", "女", "汉族",
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion] {
        return TextRecognizer.shared.detectSensitiveRegions(in: texts)
    }
}

// MARK: - PDF文字识别器

class PDFTextRecognizer: TextRecognition {

    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText] {
        guard let document = PDFDocument(data: data) else {
            throw RecognitionError.invalidPDFData
        }

        var allTexts: [RecognizedText] = []

        // 遍历所有页面
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                let pageContent = page.string
            else {
                continue
            }

            // PDF可以直接获取文字（不需要OCR）
            let words = pageContent.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            for word in words {
                // 在PDF中查找这个词的位置
                if let selections = page.selection(for: NSRange(location: 0, length: word.count)),
                    let firstSelection = selections.selectionsByLine().first
                {
                    let bounds = firstSelection.bounds(for: page)

                    allTexts.append(
                        RecognizedText(
                            text: word,
                            boundingBox: bounds,
                            confidence: 1.0,  // PDF文字100%准确
                            pageIndex: pageIndex
                        ))
                }
            }
        }

        return allTexts
    }

    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion] {
        return TextRecognizer.shared.detectSensitiveRegions(in: texts)
    }
}

// MARK: - 错误定义

enum RecognitionError: LocalizedError {
    case invalidImageData
    case invalidPDFData
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "无效的图片数据"
        case .invalidPDFData:
            return "无效的PDF数据"
        case .recognitionFailed:
            return "文字识别失败"
        }
    }
}
