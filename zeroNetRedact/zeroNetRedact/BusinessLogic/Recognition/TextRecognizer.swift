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
            // 清理文本：移除空格和常见分隔符,并记录清理后索引→原始索引的映射
            let (cleanedText, cleanedIndexMap) = Self.cleanedTextWithIndexMap(text.text)

            // 同时检测原始文本和清理后的文本(附带匹配范围→原始范围的映射)
            let variants: [(checkText: String, mapToOriginal: (NSRange) -> NSRange?)] = [
                (text.text, { $0 }),
                (cleanedText, { Self.mapRangeToOriginal($0, indexMap: cleanedIndexMap) }),
            ]

            patternLoop: for (pattern, type) in patterns {
                for (checkText, mapToOriginal) in variants {
                    let matches = SensitivePatterns.findMatches(in: checkText, pattern: pattern)

                    for match in matches {
                        guard let range = Range(match.range, in: checkText) else { continue }
                        let matchedText = String(checkText[range])

                        // 额外验证：避免误报
                        guard isValidSensitiveData(matchedText, type: type) else { continue }

                        // 优先取匹配子串的精确框(如Vision字符级几何),回退到整行框
                        let box: CGRect
                        if let originalRange = mapToOriginal(match.range),
                            let substringBox = text.substringBox?(originalRange)
                        {
                            box = substringBox
                        } else {
                            box = text.boundingBox
                        }

                        regions.append(
                            SensitiveRegion(
                                type: type,
                                boundingBox: box,
                                confidence: text.confidence,
                                pageIndex: text.pageIndex,
                                isConfirmed: false,
                                recognizedText: matchedText
                            ))

                        // 找到一个匹配就停止该文本的检测
                        break patternLoop
                    }
                }
            }
        }

        // 去重：合并重叠的区域
        return deduplicateRegions(regions)
    }

    /// 清理文本(移除空格、-、_),返回清理结果与"清理后UTF-16索引→原始UTF-16索引"映射
    private static func cleanedTextWithIndexMap(_ text: String) -> (String, [Int]) {
        let removed: Set<unichar> = [0x20, 0x2D, 0x5F]  // 空格、-、_
        let nsText = text as NSString
        var units: [unichar] = []
        var indexMap: [Int] = []
        for i in 0..<nsText.length {
            let unit = nsText.character(at: i)
            if removed.contains(unit) { continue }
            units.append(unit)
            indexMap.append(i)
        }
        return (String(utf16CodeUnits: units, count: units.count), indexMap)
    }

    /// 将清理后文本中的匹配范围映射回原始文本范围(含被移除的分隔符)
    private static func mapRangeToOriginal(_ range: NSRange, indexMap: [Int]) -> NSRange? {
        guard range.length > 0,
            range.location >= 0,
            range.location + range.length <= indexMap.count
        else { return nil }
        let start = indexMap[range.location]
        let end = indexMap[range.location + range.length - 1] + 1
        return NSRange(location: start, length: end - start)
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

    /// 超过该高度启用分块识别
    static let tileHeightThreshold = 8192
    /// 分块高度
    static let tileHeight = 4096
    /// 相邻分块重叠(避免文字被切断漏识)
    static let tileOverlap = 400

    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText] {
        return try await recognizeWithVision(data: data)
    }

    /// Apple Vision 文字识别 (优化版)
    private func recognizeWithVision(data: Data) async throws -> [RecognizedText] {
        // 先归一化EXIF方向:cgImage是未旋转的原始位图,若不归一化,
        // Vision返回的坐标基于原始空间,与显示空间(旋转后)错位
        guard let image = UIImage(data: data)?.normalizedToUpOrientation(),
            let cgImage = image.cgImage
        else {
            throw RecognitionError.invalidImageData
        }
        if cgImage.height <= Self.tileHeightThreshold {
            return try await recognizeBestOrientation(on: cgImage)
        }
        return try await recognizeTiled(cgImage: cgImage)
    }

    /// 多方向识别:正向识别效果不佳时(如证件横放拍摄),
    /// 再按90°/180°/270°各识别一次,取整体置信度最高的一组,坐标映射回原图空间
    private func recognizeBestOrientation(on cgImage: CGImage) async throws -> [RecognizedText] {
        var best = try await performVisionOCR(on: cgImage)
        var bestScore = Self.recognitionScore(best)

        // 正向识别文本多且平均置信度高(常规截图/正拍照片)时直接采用,避免4倍耗时
        if best.count >= 5, bestScore / Float(best.count) >= 0.6 {
            return best
        }

        for orientation in [CGImagePropertyOrientation.right, .left, .down] {
            let texts = try await performVisionOCR(on: cgImage, orientation: orientation)
            let mapped = texts.map { Self.remapToUpSpace($0, from: orientation) }
            let score = Self.recognitionScore(mapped)
            if score > bestScore {
                best = mapped
                bestScore = score
            }
        }
        return best
    }

    /// 识别质量评分:置信度求和(正确方向下可识别的文本显著更多、置信度更高)
    private static func recognitionScore(_ texts: [RecognizedText]) -> Float {
        texts.reduce(0) { $0 + $1.confidence }
    }

    /// 将某方向识别结果的归一化坐标映射回原始位图(.up)空间
    private static func remapToUpSpace(
        _ text: RecognizedText, from orientation: CGImagePropertyOrientation
    ) -> RecognizedText {
        guard orientation != .up else { return text }
        let innerBox = text.substringBox
        return RecognizedText(
            text: text.text,
            boundingBox: remapRect(text.boundingBox, from: orientation),
            confidence: text.confidence,
            pageIndex: text.pageIndex,
            substringBox: innerBox.map { inner in
                { range in inner(range).map { Self.remapRect($0, from: orientation) } }
            }
        )
    }

    /// 归一化矩形(左下原点)从orientation校正空间映射回原始位图空间
    private static func remapRect(
        _ rect: CGRect, from orientation: CGImagePropertyOrientation
    ) -> CGRect {
        func mapPoint(_ p: CGPoint) -> CGPoint {
            switch orientation {
            case .right:  // 原图需顺时针90°才正 → 校正空间点绕回:(x,y)→(1-y,x)
                return CGPoint(x: 1 - p.y, y: p.x)
            case .left:  // 原图需逆时针90°才正:(x,y)→(y,1-x)
                return CGPoint(x: p.y, y: 1 - p.x)
            case .down:  // 180°:(x,y)→(1-x,1-y)
                return CGPoint(x: 1 - p.x, y: 1 - p.y)
            default:
                return p
            }
        }
        let a = mapPoint(CGPoint(x: rect.minX, y: rect.minY))
        let b = mapPoint(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    /// 长图分块识别:按 tileHeight 高、tileOverlap 重叠切片,
    /// 每片独立 OCR 后把归一化坐标映射回整图空间,再跨片去重
    private func recognizeTiled(cgImage: CGImage) async throws -> [RecognizedText] {
        let fullHeight = CGFloat(cgImage.height)
        var all: [RecognizedText] = []
        var yTop = 0
        while yTop < cgImage.height {
            let tileH = min(Self.tileHeight, cgImage.height - yTop)
            let rect = CGRect(x: 0, y: yTop, width: cgImage.width, height: tileH)
            guard let tile = cgImage.cropping(to: rect) else {
                print("❌ ImageOCRRecognizer: 分块裁剪失败 yTop=\(yTop), tileH=\(tileH),中止识别")
                throw RecognitionError.recognitionFailed
            }
            let texts = try await performVisionOCR(on: tile)

            // Vision 坐标原点在左下:tile 底边距整图底边的偏移
            let tileBottomOffset = fullHeight - CGFloat(yTop + tileH)
            let remapToFullImage: (CGRect) -> CGRect = { box in
                CGRect(
                    x: box.origin.x,
                    y: (tileBottomOffset + box.origin.y * CGFloat(tileH)) / fullHeight,
                    width: box.width,
                    height: box.height * CGFloat(tileH) / fullHeight)
            }
            for t in texts {
                let innerBox = t.substringBox
                all.append(
                    RecognizedText(
                        text: t.text, boundingBox: remapToFullImage(t.boundingBox),
                        confidence: t.confidence, pageIndex: t.pageIndex,
                        substringBox: innerBox.map { inner in
                            { range in inner(range).map(remapToFullImage) }
                        }))
            }
            if yTop + tileH >= cgImage.height { break }
            yTop += Self.tileHeight - Self.tileOverlap
        }
        print("🔍 ImageOCRRecognizer: 分块 OCR 完成,合并前 \(all.count) 段文本")
        return dedupeAcrossTiles(all)
    }

    /// 跨片去重:同文本且区域相交视为重复,保留置信度高者
    private func dedupeAcrossTiles(_ texts: [RecognizedText]) -> [RecognizedText] {
        var result: [RecognizedText] = []
        for t in texts {
            if let i = result.firstIndex(where: {
                $0.text == t.text && $0.boundingBox.intersects(t.boundingBox)
            }) {
                if t.confidence > result[i].confidence { result[i] = t }
            } else {
                result.append(t)
            }
        }
        return result
    }

    /// 单张(或单片)Vision OCR
    private func performVisionOCR(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [RecognizedText] {
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

                    let recognizedString = topCandidate.string
                    return RecognizedText(
                        text: recognizedString,
                        boundingBox: observation.boundingBox,
                        confidence: topCandidate.confidence,
                        pageIndex: nil,
                        // 子串精确框:敏感号码只占一行的一部分时,取号码本身的几何
                        substringBox: { nsRange in
                            guard let range = Range(nsRange, in: recognizedString),
                                let rect = try? topCandidate.boundingBox(for: range)
                            else { return nil }
                            return rect.boundingBox
                        }
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

            let handler = VNImageRequestHandler(
                cgImage: cgImage, orientation: orientation, options: [:])
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

            // 词按出现顺序切分,顺序推进搜索起点,保证重复词也能定位到各自的实际位置
            let nsContent = pageContent as NSString
            var searchLocation = 0

            for word in words {
                let searchRange = NSRange(
                    location: searchLocation, length: nsContent.length - searchLocation)
                let wordRange = nsContent.range(of: word, range: searchRange)
                guard wordRange.location != NSNotFound else { continue }
                searchLocation = wordRange.location + wordRange.length

                // 在PDF中查找这个词的位置
                if let selections = page.selection(for: wordRange),
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

// MARK: - UIImage 方向归一化

extension UIImage {
    /// 将带EXIF方向的图片重绘为orientation == .up的位图
    /// OCR与坐标换算都必须基于显示空间(旋转后),原始位图空间会导致检测框错位
    func normalizedToUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
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
            return NSLocalizedString("recognition.error.invalidImageData", comment: "")
        case .invalidPDFData:
            return NSLocalizedString("recognition.error.invalidPDFData", comment: "")
        case .recognitionFailed:
            return NSLocalizedString("recognition.error.recognitionFailed", comment: "")
        }
    }
}
