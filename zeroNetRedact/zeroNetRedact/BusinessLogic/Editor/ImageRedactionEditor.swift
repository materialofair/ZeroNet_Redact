//
//  ImageRedactionEditor.swift
//  ZeroNet Redact
//
//  图片脱敏编辑器
//

import Combine
import CoreImage
import Foundation
import UIKit

/// 图片脱敏编辑器
class ImageRedactionEditor: RedactionEditor, ObservableObject {
    typealias FileType = OriginalImage

    // MARK: - Published Properties

    @Published var currentImage: UIImage?
    @Published var editHistory: [EditOperation] = []
    @Published var redoStack: [EditOperation] = []
    @Published var detectedRegions: [SensitiveRegion] = []
    @Published var isProcessing: Bool = false

    // MARK: - Private Properties

    private(set) var currentFile: OriginalImage?
    private var originalImage: UIImage?
    private let crypto = CryptoEngine.shared
    private let storage = StorageManager.shared
    private let recognizer = TextRecognizer.shared

    init(file: OriginalImage) {
        self.currentFile = file
    }

    // MARK: - RedactionEditor Protocol

    func loadFile(_ file: OriginalImage) async throws {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        self.currentFile = file

        print("🔍 ImageRedactionEditor: 开始加载文件 ID=\(file.id)")

        // 1. 读取加密数据
        let encryptedData = try storage.loadEncryptedOriginal(
            id: file.id,
            type: .image
        )
        print("✅ 成功读取加密数据，大小: \(encryptedData.count) bytes")

        // 2. 解密
        let decryptedData = try crypto.decrypt(data: encryptedData)
        print("✅ 成功解密数据，大小: \(decryptedData.count) bytes")

        // 3. 加载图片
        guard let image = UIImage(data: decryptedData) else {
            print("❌ 无法从解密数据创建UIImage")
            throw EditorError.noImageLoaded
        }
        print("✅ 成功创建UIImage，尺寸: \(image.size)")

        // 4. 在主线程更新UI
        await MainActor.run {
            self.originalImage = image
            self.currentImage = image
            self.editHistory = []
            self.redoStack = []
            print("✅ ImageRedactionEditor: 图片已在主线程更新")
        }
    }

    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        guard let image = currentImage else {
            print("❌ detectSensitiveRegions: 没有当前图片")
            throw EditorError.noImageLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        print("🔍 开始AI检测敏感信息")
        print("📐 原始图片尺寸: \(image.size) (width: \(image.size.width), height: \(image.size.height))")
        print("📐 图片scale: \(image.scale)")

        // 将图片转换为数据用于OCR识别
        // 先归一化EXIF方向:pngData()不会应用方向信息,直接编码会得到未旋转的原始位图,
        // 导致OCR坐标与显示空间错位
        guard let imageData = image.normalizedToUpOrientation().pngData() else {
            print("❌ detectSensitiveRegions: 无法转换图片为PNG数据")
            throw EditorError.noImageLoaded
        }

        print("✅ 图片数据大小: \(imageData.count) bytes")

        // 使用ImageOCRRecognizer识别文字
        let ocrRecognizer = ImageOCRRecognizer()
        let texts = try await ocrRecognizer.recognizeText(in: imageData, fileType: .image)

        // 隐私:系统日志可能进入Console/诊断包,只输出长度与几何,不输出识别原文
        print("✅ OCR识别到 \(texts.count) 个文本块")
        for (index, text) in texts.enumerated() {
            print("  📝 文本[\(index)]: 长度\(text.text.count)")
            print(
                "     归一化坐标: origin(\(text.boundingBox.origin.x), \(text.boundingBox.origin.y)) size(\(text.boundingBox.size.width) x \(text.boundingBox.size.height))"
            )
            print("     置信度: \(text.confidence)")
        }

        // 检测敏感信息
        let regions = recognizer.detectSensitiveRegions(in: texts)

        print("✅ 检测到 \(regions.count) 个敏感区域")
        for (index, region) in regions.enumerated() {
            print("  🔴 敏感区域[\(index)]: \(region.type.displayName)")
            print("     匹配文本长度: \(region.recognizedText?.count ?? 0)")
            print("     归一化坐标: \(region.boundingBox)")
            print("     置信度: \(region.confidence)")
        }

        await MainActor.run {
            self.detectedRegions = regions
        }

        return regions
    }

    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        guard let image = currentImage else { return }

        // 应用脱敏效果
        let redactedImage: UIImage
        switch effect {
        case .mosaic(let pixelSize):
            redactedImage = applyMosaic(to: image, at: region, pixelSize: pixelSize)
        case .blur(let radius):
            redactedImage = applyBlur(to: image, at: region, radius: radius)
        case .rectangle(let color, let opacity):
            redactedImage = applyRectangle(to: image, at: region, color: color, opacity: opacity)
        case .solidBlack:
            redactedImage = applyRectangle(to: image, at: region, color: .black, opacity: 1.0)
        }

        // 更新当前图片
        currentImage = redactedImage

        // 记录操作（用于撤销/重做）
        let operation = EditOperation(region: region, effect: effect)
        editHistory.append(operation)
        redoStack.removeAll()
    }

    func undo() {
        guard let lastOperation = editHistory.popLast() else { return }

        redoStack.append(lastOperation)

        // 重新应用所有操作（除了最后一个）
        reapplyHistory()
    }

    func redo() {
        guard let operation = redoStack.popLast() else { return }

        applyRedaction(at: operation.region, effect: operation.effect)
    }

    /// 替换原始图片（用于旋转等操作）
    func replaceOriginalImage(with newImage: UIImage) {
        originalImage = newImage
        currentImage = newImage
        // 清空编辑历史（因为坐标系已改变）
        editHistory.removeAll()
        redoStack.removeAll()
    }

    func exportRedactedFile() async throws -> Data {
        guard let finalImage = currentImage else {
            throw EditorError.noImageLoaded
        }

        guard let data = finalImage.pngData() else {
            throw EditorError.exportFailed
        }

        return data
    }

    // MARK: - Private Methods - 脱敏效果实现

    /// 应用马赛克效果
    private func applyMosaic(to image: UIImage, at region: CGRect, pixelSize: Int) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)

        // 创建马赛克滤镜
        guard let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(pixelSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(cgPoint: region.origin), forKey: kCIInputCenterKey)

        guard let outputImage = filter.outputImage,
            let renderedCGImage = context.createCGImage(outputImage, from: ciImage.extent)
        else {
            return image
        }

        // 合成图片
        return compositeImage(
            background: image,
            foreground: UIImage(cgImage: renderedCGImage),
            region: region
        )
    }

    /// 应用模糊效果
    private func applyBlur(to image: UIImage, at region: CGRect, radius: Float) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)

        // 创建高斯模糊滤镜
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter.outputImage,
            let renderedCGImage = context.createCGImage(outputImage, from: ciImage.extent)
        else {
            return image
        }

        return compositeImage(
            background: image,
            foreground: UIImage(cgImage: renderedCGImage),
            region: region
        )
    }

    /// 应用矩形遮盖效果
    private func applyRectangle(
        to image: UIImage, at region: CGRect, color: UIColor, opacity: Float
    ) -> UIImage {
        // 保持原图scale:默认format按屏幕倍率(3x)渲染,会把位图放大9倍像素量,
        // 相机照片导出PNG时内存暴涨导致OOM闪退
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { context in
            // 绘制原图
            image.draw(at: .zero)

            // 绘制矩形遮盖
            context.cgContext.setFillColor(color.withAlphaComponent(CGFloat(opacity)).cgColor)
            context.cgContext.fill(region)
        }
    }

    /// 合成图片（将前景图片的指定区域绘制到背景图片上）
    private func compositeImage(background: UIImage, foreground: UIImage, region: CGRect) -> UIImage
    {
        // 保持原图scale,避免按屏幕倍率放大位图(见applyRectangle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = background.scale
        let renderer = UIGraphicsImageRenderer(size: background.size, format: format)

        return renderer.image { context in
            // 绘制背景
            background.draw(at: .zero)

            // 裁剪并绘制前景
            context.cgContext.saveGState()
            context.cgContext.addRect(region)
            context.cgContext.clip()
            foreground.draw(at: .zero)
            context.cgContext.restoreGState()
        }
    }

    /// 重新应用历史操作
    private func reapplyHistory() {
        guard let original = originalImage else { return }

        currentImage = original

        let operations = editHistory
        editHistory.removeAll()

        for operation in operations {
            applyRedaction(at: operation.region, effect: operation.effect)
        }
    }

    // MARK: - Public Helper Methods

    /// 清除所有脱敏
    func clearAll() {
        currentImage = originalImage
        editHistory.removeAll()
        redoStack.removeAll()
    }

    /// 获取当前编辑状态
    var canUndo: Bool {
        !editHistory.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    // MARK: - Drag Mode Support (拖拽模式支持)

    /// 获取所有已应用的脱敏区域及其索引
    /// - Returns: 包含索引和区域矩形的元组数组
    func getRedactionRegions() -> [(index: Int, bounds: CGRect)] {
        return editHistory.enumerated().map { (index, operation) in
            (index: index, bounds: operation.region)
        }
    }

    /// 查找指定点击位置的脱敏区域索引（图片坐标系）
    /// - Parameter point: 点击位置（图片像素坐标）
    /// - Returns: 脱敏区域索引，如果没有找到则返回nil
    func findRedactionRegion(at point: CGPoint) -> Int? {
        // 从后往前查找，优先选择最上层的脱敏区域
        for (index, operation) in editHistory.enumerated().reversed() {
            if operation.region.contains(point) {
                return index
            }
        }
        return nil
    }

    /// 移动指定索引的脱敏区域
    /// - Parameters:
    ///   - index: 脱敏区域索引
    ///   - offset: 移动偏移量（图片像素坐标）
    func moveRedactionRegion(at index: Int, offset: CGSize) {
        guard index >= 0 && index < editHistory.count else {
            print("⚠️ moveRedactionRegion: 索引越界 \(index)/\(editHistory.count)")
            return
        }

        // 获取原有操作
        let oldOperation = editHistory[index]

        // 计算新位置
        var newBounds = oldOperation.region
        newBounds.origin.x += offset.width
        newBounds.origin.y += offset.height

        // 确保不超出图片边界
        if let image = originalImage {
            newBounds.origin.x = max(0, min(newBounds.origin.x, image.size.width - newBounds.width))
            newBounds.origin.y = max(
                0, min(newBounds.origin.y, image.size.height - newBounds.height))
        }

        // 创建新操作（保持原有效果）
        let newOperation = EditOperation(region: newBounds, effect: oldOperation.effect)

        // 替换操作
        editHistory[index] = newOperation

        print(
            "📍 moveRedactionRegion: 移动区域\(index)，偏移(\(offset.width), \(offset.height))，新位置: \(newBounds)"
        )

        // 重新渲染图片
        reapplyHistory()
    }

    /// 删除指定索引的脱敏区域
    /// - Parameter index: 脱敏区域索引
    func removeRedactionRegion(at index: Int) {
        guard index >= 0 && index < editHistory.count else {
            print("⚠️ removeRedactionRegion: 索引越界 \(index)/\(editHistory.count)")
            return
        }

        // 移除操作
        let removed = editHistory.remove(at: index)
        print("🗑️ removeRedactionRegion: 删除区域\(index)，位置: \(removed.region)")

        // 重新渲染图片
        reapplyHistory()
    }

    /// 缩放指定索引的脱敏区域
    /// - Parameters:
    ///   - index: 脱敏区域索引
    ///   - scale: 缩放比例 (1.0 = 不变, >1.0 = 放大, <1.0 = 缩小)
    func scaleRedactionRegion(at index: Int, scale: CGFloat) {
        guard index >= 0 && index < editHistory.count else {
            print("⚠️ scaleRedactionRegion: 索引越界 \(index)/\(editHistory.count)")
            return
        }

        // 获取原有操作
        let oldOperation = editHistory[index]
        let oldBounds = oldOperation.region

        // 计算中心点
        let centerX = oldBounds.midX
        let centerY = oldBounds.midY

        // 计算新的宽高
        let newWidth = oldBounds.width * scale
        let newHeight = oldBounds.height * scale

        // 计算新的原点（保持中心点不变）
        var newBounds = CGRect(
            x: centerX - newWidth / 2,
            y: centerY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )

        // 确保不超出图片边界，并保持最小尺寸
        let minSize: CGFloat = 10
        if let image = originalImage {
            newBounds.size.width = max(minSize, min(newBounds.width, image.size.width))
            newBounds.size.height = max(minSize, min(newBounds.height, image.size.height))
            newBounds.origin.x = max(0, min(newBounds.origin.x, image.size.width - newBounds.width))
            newBounds.origin.y = max(
                0, min(newBounds.origin.y, image.size.height - newBounds.height))
        }

        // 创建新操作（保持原有效果）
        let newOperation = EditOperation(region: newBounds, effect: oldOperation.effect)

        // 替换操作
        editHistory[index] = newOperation

        print("🔍 scaleRedactionRegion: 缩放区域\(index)，比例\(scale)，新尺寸: \(newBounds.size)")

        // 重新渲染图片
        reapplyHistory()
    }
}
