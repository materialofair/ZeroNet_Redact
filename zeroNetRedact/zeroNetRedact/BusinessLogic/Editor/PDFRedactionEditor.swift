//
//  PDFRedactionEditor.swift
//  ZeroNet Redact
//
//  PDF脱敏编辑器
//

import Combine
import Foundation
import PDFKit

/// PDF脱敏编辑器
class PDFRedactionEditor: RedactionEditor, ObservableObject {
    typealias FileType = OriginalPDF

    // MARK: - Published Properties

    @Published var pdfDocument: PDFDocument?
    @Published var currentPageIndex: Int = 0
    @Published var redactionAnnotations: [Int: [PDFAnnotation]] = [:]  // 页码 -> 注释列表
    /// 重做栈：撤销前的注释状态快照
    @Published var redoStack: [[PDFAnnotationSnapshot]] = []
    @Published var detectedRegions: [SensitiveRegion] = []
    @Published var isProcessing: Bool = false

    // MARK: - Private Properties

    private(set) var currentFile: OriginalPDF?
    private var originalDocument: PDFDocument?
    private var originalPDFData: Data?
    /// 撤销栈：每次变更前的注释状态快照（快照式撤销，覆盖新增/移动/缩放/删除）
    private var undoStack: [[PDFAnnotationSnapshot]] = []
    private let crypto = CryptoEngine.shared
    private let storage = StorageManager.shared
    private let recognizer = TextRecognizer.shared

    /// 标记本 App 创建的遮盖注释，导出时据此识别真删除区域
    static let redactionAnnotationMarker = "com.zeronet.redact"

    /// 真删除失败时退回视觉遮盖导出（EditorViewModel 据此提示用户）
    private(set) var usedFallbackExport = false

    /// 注释状态快照：标记注释对象 + 当前 bounds
    struct PDFAnnotationSnapshot {
        let pageIndex: Int
        let annotation: PDFAnnotation
        let bounds: CGRect
    }

    init(file: OriginalPDF) {
        self.currentFile = file
    }

    // MARK: - RedactionEditor Protocol

    func loadFile(_ file: OriginalPDF) async throws {
        isProcessing = true
        defer { isProcessing = false }

        self.currentFile = file

        // 1. 读取加密数据
        let encryptedData = try storage.loadEncryptedOriginal(
            id: file.id,
            type: .pdf
        )

        // 2. 解密
        let decryptedData = try crypto.decrypt(data: encryptedData)

        // 3. 加载PDF（保留干净的原始数据，供导出时做真删除）
        guard let document = PDFDocument(data: decryptedData) else {
            throw EditorError.noPDFLoaded
        }
        self.originalPDFData = decryptedData

        await MainActor.run {
            self.originalDocument = document
            self.pdfDocument = document.copy() as? PDFDocument
            self.currentPageIndex = 0
            self.redactionAnnotations = [:]
        }
    }

    func detectSensitiveRegions(progress: ((Double) -> Void)?) async throws -> [SensitiveRegion] {
        guard let file = currentFile else {
            throw EditorError.noFileLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        // 使用TextRecognizer识别敏感信息
        let texts = try await recognizer.recognizeText(in: file, progress: progress)
        let regions = recognizer.detectSensitiveRegions(in: texts)

        await MainActor.run {
            self.detectedRegions = regions
        }

        return regions
    }

    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        applyRedactions(at: [region], effect: effect)
    }

    /// 批量应用脱敏：单快照 + 一次添加全部注释
    func applyRedactions(at regions: [CGRect], effect: RedactionEffect) {
        guard !regions.isEmpty else { return }
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex)
        else {
            print("⚠️ PDFRedactionEditor: 无法获取PDF页面")
            return
        }

        // 根据效果设置样式
        var fillColor: UIColor
        switch effect {
        case .solidBlack:
            fillColor = UIColor.black
        case .rectangle(let color, _):
            fillColor = color
        case .mosaic:
            // 马赛克效果用深灰色模拟
            fillColor = UIColor.darkGray
        case .blur:
            // 模糊效果用灰色模拟
            fillColor = UIColor.gray
        default:
            fillColor = UIColor.black
        }

        // 记录快照（撤销可回到变更前状态）
        recordSnapshot()

        var added: [PDFAnnotation] = []
        for region in regions {
            // 创建注释（使用.square类型代替.redact）
            let annotation = PDFAnnotation(bounds: region, forType: .square, withProperties: nil)

            // 关键设置：填充颜色和边框
            annotation.interiorColor = fillColor  // 填充颜色
            annotation.color = fillColor  // 边框颜色

            // 重要：设置边框样式为实线，并设置边框宽度
            annotation.border = PDFBorder()
            annotation.border?.lineWidth = 0  // 无边框，只显示填充

            // 设置annotation的显示属性
            annotation.shouldDisplay = true
            annotation.shouldPrint = true

            // 标记为本 App 创建的遮盖注释
            annotation.userName = Self.redactionAnnotationMarker

            page.addAnnotation(annotation)
            added.append(annotation)
        }

        print("📝 PDFRedactionEditor: 批量添加\(added.count)个annotation, color=\(fillColor)")

        // 记录注释（用于撤销）
        if redactionAnnotations[currentPageIndex] == nil {
            redactionAnnotations[currentPageIndex] = []
        }
        redactionAnnotations[currentPageIndex]?.append(contentsOf: added)

        print("✅ PDFRedactionEditor: 当前页面共有\(page.annotations.count)个annotations")
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }

        // 当前状态入重做栈，恢复上一快照
        redoStack.append(captureSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }

        undoStack.append(captureSnapshot())
        restore(snapshot)
    }

    /// 记录当前注释状态快照（每次变更前调用），并清空重做栈
    private func recordSnapshot() {
        undoStack.append(captureSnapshot())
        redoStack.removeAll()
    }

    /// 捕获全部页面上标记注释的当前状态
    private func captureSnapshot() -> [PDFAnnotationSnapshot] {
        guard let document = pdfDocument else { return [] }
        var snapshot: [PDFAnnotationSnapshot] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations
            where annotation.userName == Self.redactionAnnotationMarker {
                snapshot.append(
                    PDFAnnotationSnapshot(
                        pageIndex: pageIndex, annotation: annotation, bounds: annotation.bounds))
            }
        }
        return snapshot
    }

    /// 恢复快照：移除当前标记注释，按快照重建 bounds 与页面归属
    private func restore(_ snapshot: [PDFAnnotationSnapshot]) {
        guard let document = pdfDocument else { return }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations
            where annotation.userName == Self.redactionAnnotationMarker {
                page.removeAnnotation(annotation)
            }
        }

        for entry in snapshot {
            guard let page = document.page(at: entry.pageIndex) else { continue }
            entry.annotation.bounds = entry.bounds
            page.addAnnotation(entry.annotation)
        }

        syncTrackingFromPages()
    }

    /// 从页面注释重建跟踪数组（保证与页面实际状态一致）
    private func syncTrackingFromPages() {
        guard let document = pdfDocument else { return }
        var tracking: [Int: [PDFAnnotation]] = [:]
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let marked = page.annotations.filter {
                $0.userName == Self.redactionAnnotationMarker
            }
            if !marked.isEmpty {
                tracking[pageIndex] = marked
            }
        }
        redactionAnnotations = tracking
    }

    /// 删除当前页指定索引的标记注释（记录快照，可撤销）
    func removeAnnotation(at index: Int) {
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex)
        else {
            return
        }
        guard index >= 0 && index < page.annotations.count else { return }
        let annotation = page.annotations[index]
        guard annotation.userName == Self.redactionAnnotationMarker else { return }

        recordSnapshot()
        page.removeAnnotation(annotation)
        syncTrackingFromPages()
    }

    func exportRedactedFile(progress: ((Double) -> Void)?) async throws -> Data {
        guard let document = pdfDocument else {
            throw EditorError.noPDFLoaded
        }

        let pageCount = max(1, document.pageCount)

        // 1. 收集当前生效的遮盖区域（直接读取页面上的注释，尊重用户的删除操作）
        var regions: [PDFRedactionRegion] = []
        var overlays: [(pageIndex: Int, bounds: CGRect, color: UIColor)] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.userName == Self.redactionAnnotationMarker {
                let bounds = annotation.bounds
                let color = annotation.interiorColor ?? UIColor.black
                regions.append(PDFRedactionRegion(pageIndex: pageIndex, rect: bounds))
                overlays.append((pageIndex: pageIndex, bounds: bounds, color: color))
            }
            progress?(0.35 * Double(pageIndex + 1) / Double(pageCount))
        }

        // 2. 干净底稿：原始数据 + 元数据清理
        //   （MuPDF C API 无元数据写入接口，元数据清理保留在 PDFKit 侧）
        guard let originalData = originalPDFData,
            let cleanDocument = PDFDocument(data: originalData)
        else {
            throw EditorError.noPDFLoaded
        }
        sanitizeMetadata(document: cleanDocument)
        guard let cleanData = cleanDocument.dataRepresentation() else {
            throw EditorError.exportFailed
        }
        progress?(0.4)

        // 3. 真删除：MuPDF 把遮盖区域内的文字从内容流中物理移除
        //   （坐标约定：PDFKit annotation.bounds 与 MuPDF set_annot_rect
        //     同为页面显示空间，直接传递；旋转页由 MuPDF page_ctm 处理）
        let redactedData: Data
        do {
            redactedData = try await Task.detached(priority: .userInitiated) {
                try MuPDFRedactor.redact(pdfData: cleanData, regions: regions)
            }.value
            usedFallbackExport = false
        } catch {
            // 兜底：真删除失败时退回旧的视觉遮盖路径
            print("⚠️ PDFRedactionEditor: MuPDF 真删除失败，退回视觉遮盖导出: \(error)")
            sanitizeMetadata(document: document)
            guard let fallbackData = document.dataRepresentation() else {
                throw EditorError.exportFailed
            }
            usedFallbackExport = true
            progress?(1.0)
            return fallbackData
        }
        progress?(0.6)

        // 4. 重新叠加效果覆盖层：与编辑器所见保持一致（纯视觉填充，不含文字）
        guard let redactedDocument = PDFDocument(data: redactedData) else {
            throw EditorError.exportFailed
        }
        for (overlayIndex, overlay) in overlays.enumerated() {
            guard let page = redactedDocument.page(at: overlay.pageIndex) else { continue }
            let annotation = PDFAnnotation(bounds: overlay.bounds, forType: .square, withProperties: nil)
            annotation.interiorColor = overlay.color
            annotation.color = overlay.color
            annotation.border = PDFBorder()
            annotation.border?.lineWidth = 0
            annotation.shouldDisplay = true
            annotation.shouldPrint = true
            page.addAnnotation(annotation)
            progress?(0.6 + 0.35 * Double(overlayIndex + 1) / Double(max(1, overlays.count)))
        }
        guard let finalData = redactedDocument.dataRepresentation() else {
            throw EditorError.exportFailed
        }
        progress?(1.0)
        return finalData
    }

    // MARK: - PDF特有功能

    /// 跳转到指定页面
    func goToPage(_ pageIndex: Int) {
        guard let document = pdfDocument,
            pageIndex >= 0 && pageIndex < document.pageCount
        else {
            return
        }

        currentPageIndex = pageIndex
    }

    /// 获取总页数
    func getTotalPages() -> Int {
        return pdfDocument?.pageCount ?? 0
    }

    /// 获取当前页面
    var currentPage: PDFPage? {
        return pdfDocument?.page(at: currentPageIndex)
    }

    /// 获取页面缩略图
    func getThumbnail(for pageIndex: Int, size: CGSize) -> UIImage? {
        guard let page = pdfDocument?.page(at: pageIndex) else {
            return nil
        }

        return page.thumbnail(of: size, for: .mediaBox)
    }

    // MARK: - Private Methods

    /// 清理PDF元数据
    private func sanitizeMetadata(document: PDFDocument) {
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Redacted Document",
            PDFDocumentAttribute.authorAttribute: "",
            PDFDocumentAttribute.creatorAttribute: "ZeroNet Redact",
            PDFDocumentAttribute.producerAttribute: "",
        ]
    }

    /// 检测并移除嵌入文件（安全性）
    func removeEmbeddedFiles() {
        // PDF可能包含嵌入的文件和JavaScript，需要移除
        // 这是一个安全性增强功能
        guard let document = pdfDocument else { return }

        // PDFKit暂不支持直接移除嵌入文件
        // 需要使用更底层的PDF操作库（如PDFBox）
        // 这里仅作为接口预留
    }

    // MARK: - Public Helper Methods

    /// 清除所有脱敏
    func clearAll() {
        guard let original = originalDocument else { return }

        pdfDocument = original.copy() as? PDFDocument
        redactionAnnotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        currentPageIndex = 0
    }

    /// 清除当前页的所有脱敏（批量破坏性操作，重置撤销历史）
    func clearCurrentPage() {
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex),
            let annotations = redactionAnnotations[currentPageIndex]
        else {
            return
        }

        for annotation in annotations {
            page.removeAnnotation(annotation)
        }

        redactionAnnotations[currentPageIndex] = nil
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// 获取当前页的脱敏数量
    var currentPageRedactionCount: Int {
        redactionAnnotations[currentPageIndex]?.count ?? 0
    }

    /// 获取所有页面的脱敏数量
    var totalRedactionCount: Int {
        redactionAnnotations.values.reduce(0) { $0 + $1.count }
    }

    /// 检查是否可以撤销
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// 检查是否可以重做
    var canRedo: Bool {
        !redoStack.isEmpty
    }

    // MARK: - Annotation Scaling

    /// 缩放指定索引的注释（脱敏区域）
    /// - Parameters:
    ///   - index: 注释索引
    ///   - scale: 缩放比例 (1.0 = 不变, >1.0 = 放大, <1.0 = 缩小)
    func scaleAnnotation(at index: Int, scale: CGFloat) {
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex)
        else {
            print("⚠️ scaleAnnotation: 无法获取PDF页面")
            return
        }

        guard index >= 0 && index < page.annotations.count else {
            print("⚠️ scaleAnnotation: 索引越界 \(index)/\(page.annotations.count)")
            return
        }

        recordSnapshot()

        let annotation = page.annotations[index]
        let oldBounds = annotation.bounds

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

        // 确保不超出页面边界，并保持最小尺寸
        let minSize: CGFloat = 5
        let pageRect = page.bounds(for: .mediaBox)
        newBounds.size.width = max(minSize, min(newBounds.width, pageRect.width))
        newBounds.size.height = max(minSize, min(newBounds.height, pageRect.height))
        newBounds.origin.x = max(0, min(newBounds.origin.x, pageRect.width - newBounds.width))
        newBounds.origin.y = max(0, min(newBounds.origin.y, pageRect.height - newBounds.height))

        // 保存原有属性
        let oldColor = annotation.color
        let oldInteriorColor = annotation.interiorColor
        let oldBorder = annotation.border
        let oldShouldDisplay = annotation.shouldDisplay
        let oldShouldPrint = annotation.shouldPrint

        // 移除旧注释
        page.removeAnnotation(annotation)

        // 创建新注释
        let newAnnotation = PDFAnnotation(bounds: newBounds, forType: .square, withProperties: nil)
        newAnnotation.color = oldColor
        newAnnotation.interiorColor = oldInteriorColor
        newAnnotation.border = oldBorder
        newAnnotation.shouldDisplay = oldShouldDisplay
        newAnnotation.shouldPrint = oldShouldPrint

        // 添加新注释
        page.addAnnotation(newAnnotation)

        // 更新跟踪列表
        if var pageAnnotations = redactionAnnotations[currentPageIndex] {
            if index < pageAnnotations.count {
                pageAnnotations[index] = newAnnotation
                redactionAnnotations[currentPageIndex] = pageAnnotations
            }
        }

        print("🔍 scaleAnnotation: 缩放注释\(index)，比例\(scale)，新尺寸: \(newBounds.size)")
    }

    // MARK: - Annotation Moving

    /// 移动指定索引的注释（脱敏区域）
    /// - Parameters:
    ///   - index: 注释索引
    ///   - offset: PDF坐标系偏移量
    func moveAnnotation(at index: Int, offset: CGSize) {
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex)
        else {
            print("⚠️ moveAnnotation: 无法获取PDF页面")
            return
        }

        guard index >= 0 && index < page.annotations.count else {
            print("⚠️ moveAnnotation: 索引越界 \(index)/\(page.annotations.count)")
            return
        }

        recordSnapshot()

        let annotation = page.annotations[index]

        // 计算新位置
        var newBounds = annotation.bounds
        newBounds.origin.x += offset.width
        newBounds.origin.y += offset.height

        // 保存原有属性
        let oldColor = annotation.color
        let oldInteriorColor = annotation.interiorColor
        let oldBorder = annotation.border
        let oldShouldDisplay = annotation.shouldDisplay
        let oldShouldPrint = annotation.shouldPrint

        // 移除旧注释
        page.removeAnnotation(annotation)

        // 创建新注释
        let newAnnotation = PDFAnnotation(bounds: newBounds, forType: .square, withProperties: nil)
        newAnnotation.color = oldColor
        newAnnotation.interiorColor = oldInteriorColor
        newAnnotation.border = oldBorder
        newAnnotation.shouldDisplay = oldShouldDisplay
        newAnnotation.shouldPrint = oldShouldPrint

        // 添加新注释
        page.addAnnotation(newAnnotation)

        // 更新跟踪列表（同步撤销状态）
        if var pageAnnotations = redactionAnnotations[currentPageIndex] {
            if index < pageAnnotations.count {
                pageAnnotations[index] = newAnnotation
                redactionAnnotations[currentPageIndex] = pageAnnotations
            }
        }

        print(
            "📍 moveAnnotation: 移动注释\(index)，偏移(\(offset.width), \(offset.height))，新位置: \(newBounds)"
        )
    }
}
