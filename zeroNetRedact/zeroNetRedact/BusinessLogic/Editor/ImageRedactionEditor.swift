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
    /// 重做栈：撤销前的编辑状态快照（UI 通过 canRedo 访问）
    @Published var redoStack: [[EditOperation]] = []
    @Published var detectedRegions: [SensitiveRegion] = []
    @Published var isProcessing: Bool = false

    // MARK: - Private Properties

    private(set) var currentFile: OriginalImage?
    private var originalImage: UIImage?
    /// 撤销栈：每次变更前的编辑状态快照（快照式撤销，覆盖新增/移动/缩放/删除）
    private var undoStack: [[EditOperation]] = []
    private let crypto = CryptoEngine.shared
    private let storage = StorageManager.shared
    private let recognizer = TextRecognizer.shared

    // MARK: - 后台渲染串行化

    /// 渲染代数：每次变更自增，渲染完成时代数不匹配的过期结果直接丢弃
    private var renderGeneration: UInt64 = 0
    /// 最近一次渲染任务（导出前等待其完成，避免导出旧画面）
    private var pendingRenderTask: Task<Void, Never>?
    /// 跨渲染复用的 CI 上下文。
    /// 使用软件渲染器：渲染在后台线程执行，GPU/Metal 上下文在后台线程
    /// 首次创建时会静默失效（输出无变化）；裁剪小图用 CPU 渲染足够快
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: true])

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

        // 归一化 EXIF 方向：渲染管线按 .up 位图处理（见 renderImage），
        // 否则旋转方向的照片在合成时坐标与像素错位
        let normalized = image.normalizedToUpOrientation()

        // 4. 在主线程更新UI
        await MainActor.run {
            self.originalImage = normalized
            self.currentImage = normalized
            self.editHistory = []
            self.redoStack = []
            print("✅ ImageRedactionEditor: 图片已在主线程更新")
        }
    }

    func detectSensitiveRegions(progress: ((Double) -> Void)?) async throws -> [SensitiveRegion] {
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
        let texts = try await ocrRecognizer.recognizeText(
            in: imageData, fileType: .image, progress: progress)

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
        applyRedactions(at: [region], effect: effect)
    }

    /// 批量应用脱敏：单快照 + 单次合成渲染
    /// 涂抹等多笔同效果的 stroke 一次合成，避免逐笔整图重绘（大图关键路径）
    func applyRedactions(at regions: [CGRect], effect: RedactionEffect) {
        guard !regions.isEmpty else { return }

        // 记录快照（撤销可回到变更前状态）
        recordSnapshot()

        for region in regions {
            editHistory.append(EditOperation(region: region, effect: effect))
        }

        scheduleRender()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }

        // 当前状态入重做栈，恢复上一快照
        redoStack.append(editHistory)
        editHistory = previous
        scheduleRender()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }

        undoStack.append(editHistory)
        editHistory = next
        scheduleRender()
    }

    /// 替换原始图片（用于旋转等操作）
    func replaceOriginalImage(with newImage: UIImage) {
        let normalized = newImage.normalizedToUpOrientation()
        originalImage = normalized
        currentImage = normalized
        // 清空编辑历史（因为坐标系已改变）
        editHistory.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        // 使在途渲染结果失效
        renderGeneration += 1
    }

    func exportRedactedFile(progress: ((Double) -> Void)?) async throws -> Data {
        // 导出前等在途渲染完成，避免导出旧画面（如最后一笔涂抹尚未合成）
        await waitForPendingRender()

        progress?(0.5)

        guard let finalImage = currentImage else {
            throw EditorError.noImageLoaded
        }

        guard let data = finalImage.pngData() else {
            throw EditorError.exportFailed
        }

        progress?(1.0)
        return data
    }

    /// 等待在途渲染完成
    func waitForPendingRender() async {
        await pendingRenderTask?.value
    }

    // MARK: - 渲染管线（单遍合成，后台执行）

    /// 从原图 + 操作列表单遍合成成品图（纯函数，可在任意线程执行）
    /// 滤镜只作用于目标区域的裁剪小图，不再整图滤镜后合成——大图性能关键路径
    static func renderImage(
        base: CGImage,
        scale: CGFloat,
        size: CGSize,
        operations: [EditOperation]
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { renderContext in
            // 背景：原图（.up 位图，与渲染器像素 1:1 映射）
            UIImage(cgImage: base, scale: scale, orientation: .up).draw(at: .zero)

            let context = renderContext.cgContext
            for operation in operations {
                draw(operation: operation, in: context, base: base, imageScale: scale)
            }
        }.cgImage
    }

    /// 在上下文中绘制单个操作的脱敏效果
    private static func draw(
        operation: EditOperation, in context: CGContext, base: CGImage, imageScale: CGFloat
    ) {
        let region = operation.region

        switch operation.effect {
        case .solidBlack:
            context.setFillColor(UIColor.black.cgColor)
            context.fill(region)

        case .rectangle(let color, let opacity):
            context.setFillColor(color.withAlphaComponent(CGFloat(opacity)).cgColor)
            context.fill(region)

        case .mosaic(let pixelSize):
            drawMosaic(
                in: context, base: base, region: region, imageScale: imageScale,
                pixelSize: pixelSize)

        case .blur(let radius):
            guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
            // 高斯模糊有边缘衰减，裁剪区向外扩 radius 点，避免区域边缘发暗
            let expanded = region.insetBy(dx: -CGFloat(radius), dy: -CGFloat(radius))
            drawFilteredCrop(
                in: context, base: base, region: expanded, imageScale: imageScale,
                clipTo: region, filter: filter
            ) { filter in
                filter.setValue(radius, forKey: kCIInputRadiusKey)
            }
        }
    }

    /// 手写马赛克：块平均 + 最近邻放大，块网格与整图对齐
    /// （CIPixellate 在裁剪小图上输出与输入几乎一致，块状效果失效，
    ///   且 iOS 26 模拟器上行为不稳定，改用确定性实现）
    private static func drawMosaic(
        in context: CGContext,
        base: CGImage,
        region: CGRect,
        imageScale: CGFloat,
        pixelSize: Int
    ) {
        let blockSize = max(2, pixelSize)

        // 像素空间裁剪（对齐像素边界）
        let pixelRect = CGRect(
            x: (region.origin.x * imageScale).rounded(.down),
            y: (region.origin.y * imageScale).rounded(.down),
            width: (region.width * imageScale).rounded(.up),
            height: (region.height * imageScale).rounded(.up)
        ).intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))

        guard pixelRect.width >= 1, pixelRect.height >= 1,
            let crop = base.cropping(to: pixelRect),
            let srcData = crop.dataProvider?.data,
            let src = CFDataGetBytePtr(srcData)
        else { return }

        let w = crop.width
        let h = crop.height
        let bpp = crop.bitsPerPixel / 8
        let minX = Int(pixelRect.minX)
        let minY = Int(pixelRect.minY)

        // 块网格与整图对齐：块索引按整图全局坐标计算
        let firstBlockX = minX / blockSize
        let firstBlockY = minY / blockSize
        let lastBlockX = (minX + w - 1) / blockSize
        let lastBlockY = (minY + h - 1) / blockSize
        let blockCols = lastBlockX - firstBlockX + 1
        let blockRows = lastBlockY - firstBlockY + 1

        // 1. 块内逐通道求和（保持源字节序，无需颜色空间转换）
        var blockSums = [UInt32](repeating: 0, count: blockCols * blockRows * 4)
        var blockCounts = [UInt32](repeating: 0, count: blockCols * blockRows)
        for y in 0..<h {
            let blockY = (minY + y) / blockSize - firstBlockY
            let srcRow = y * crop.bytesPerRow
            for x in 0..<w {
                let blockIndex = blockY * blockCols + ((minX + x) / blockSize - firstBlockX)
                let srcOffset = srcRow + x * bpp
                let sumBase = blockIndex * 4
                for c in 0..<4 {
                    blockSums[sumBase + c] += UInt32(src[srcOffset + c])
                }
                blockCounts[blockIndex] += 1
            }
        }

        // 2. 块平均
        for blockIndex in 0..<(blockCols * blockRows) {
            let count = max(1, blockCounts[blockIndex])
            let base = blockIndex * 4
            for c in 0..<4 {
                blockSums[base + c] /= count
            }
        }

        // 3. 最近邻放大回裁剪尺寸
        var output = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let blockY = (minY + y) / blockSize - firstBlockY
            let dstRow = y * w * 4
            for x in 0..<w {
                let blockIndex = blockY * blockCols + ((minX + x) / blockSize - firstBlockX)
                let srcBase = blockIndex * 4
                let dstOffset = dstRow + x * 4
                for c in 0..<4 {
                    output[dstOffset + c] = UInt8(blockSums[srcBase + c])
                }
            }
        }

        // 4. 生成 CGImage 并画回（字节序与源一致，用源的 bitmapInfo）
        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return }
        guard let mosaicImage = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: crop.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        let drawRect = CGRect(
            x: pixelRect.origin.x / imageScale,
            y: pixelRect.origin.y / imageScale,
            width: pixelRect.width / imageScale,
            height: pixelRect.height / imageScale
        )

        context.saveGState()
        context.clip(to: region)
        UIImage(cgImage: mosaicImage, scale: 1, orientation: .up).draw(in: drawRect)
        context.restoreGState()
    }

    /// 裁剪区域小图 → 应用滤镜 → 画回上下文（可裁剪到指定区域）
    private static func drawFilteredCrop(
        in context: CGContext,
        base: CGImage,
        region: CGRect,
        imageScale: CGFloat,
        clipTo clipRegion: CGRect,
        filter: CIFilter,
        configure: (CIFilter) -> Void
    ) {
        // 像素空间裁剪（对齐像素边界，避免半像素采样）
        let pixelRect = CGRect(
            x: (region.origin.x * imageScale).rounded(.down),
            y: (region.origin.y * imageScale).rounded(.down),
            width: (region.width * imageScale).rounded(.up),
            height: (region.height * imageScale).rounded(.up)
        ).intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))

        guard pixelRect.width >= 1, pixelRect.height >= 1,
            let crop = base.cropping(to: pixelRect)
        else { return }

        let ciImage = CIImage(cgImage: crop)
        configure(filter)
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        guard let output = filter.outputImage?.cropped(to: ciImage.extent),
            let rendered = sharedCIContext.createCGImage(output, from: output.extent)
        else { return }

        // 画回位置（像素矩形换算回点空间，与像素 1:1）
        let drawRect = CGRect(
            x: pixelRect.origin.x / imageScale,
            y: pixelRect.origin.y / imageScale,
            width: pixelRect.width / imageScale,
            height: pixelRect.height / imageScale
        )

        context.saveGState()
        context.clip(to: clipRegion)
        UIImage(cgImage: rendered, scale: 1, orientation: .up).draw(in: drawRect)
        context.restoreGState()
    }

    /// 触发后台渲染：捕获原图位图与操作快照后离线合成，主线程只回写结果
    /// 连续操作时以代数（generation）丢弃过期结果，最后发起的渲染胜出
    private func scheduleRender() {
        renderGeneration += 1
        let generation = renderGeneration
        let base = originalImage?.cgImage
        let scale = originalImage?.scale ?? 1
        let size = originalImage?.size ?? .zero
        let operations = editHistory

        pendingRenderTask = Task { @MainActor [weak self] in
            guard let base else { return }

            let rendered = await Task.detached(priority: .userInitiated) {
                ImageRedactionEditor.renderImage(
                    base: base, scale: scale, size: size, operations: operations)
            }.value

            guard let self, generation == self.renderGeneration else { return }
            self.currentImage = rendered.map {
                UIImage(cgImage: $0, scale: scale, orientation: .up)
            }
            self.pendingRenderTask = nil
        }
    }

    // MARK: - Private Methods - 撤销/重做

    /// 记录当前编辑状态快照（每次变更前调用），并清空重做栈
    private func recordSnapshot() {
        undoStack.append(editHistory)
        redoStack.removeAll()
    }

    // MARK: - Public Helper Methods

    /// 清除所有脱敏
    func clearAll() {
        currentImage = originalImage
        editHistory.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        // 使在途渲染结果失效
        renderGeneration += 1
    }

    /// 获取当前编辑状态
    var canUndo: Bool {
        !undoStack.isEmpty
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

        recordSnapshot()

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
        scheduleRender()
    }

    /// 删除指定索引的脱敏区域
    /// - Parameter index: 脱敏区域索引
    func removeRedactionRegion(at index: Int) {
        guard index >= 0 && index < editHistory.count else {
            print("⚠️ removeRedactionRegion: 索引越界 \(index)/\(editHistory.count)")
            return
        }

        recordSnapshot()

        // 移除操作
        let removed = editHistory.remove(at: index)
        print("🗑️ removeRedactionRegion: 删除区域\(index)，位置: \(removed.region)")

        // 重新渲染图片
        scheduleRender()
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

        recordSnapshot()

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
        scheduleRender()
    }

    // MARK: - Testing Support

    /// 直接以给定图片作为底图（测试用，绕过加密存储加载）
    func loadForTesting(image: UIImage) {
        let normalized = image.normalizedToUpOrientation()
        originalImage = normalized
        currentImage = normalized
        editHistory.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        renderGeneration += 1
    }
}
