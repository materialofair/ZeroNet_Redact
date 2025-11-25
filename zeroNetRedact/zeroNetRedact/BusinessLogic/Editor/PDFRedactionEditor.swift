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
    @Published var detectedRegions: [SensitiveRegion] = []
    @Published var isProcessing: Bool = false

    // MARK: - Private Properties

    private(set) var currentFile: OriginalPDF?
    private var originalDocument: PDFDocument?
    private let crypto = CryptoEngine.shared
    private let storage = StorageManager.shared
    private let recognizer = TextRecognizer.shared

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

        // 3. 加载PDF
        guard let document = PDFDocument(data: decryptedData) else {
            throw EditorError.noPDFLoaded
        }

        await MainActor.run {
            self.originalDocument = document
            self.pdfDocument = document.copy() as? PDFDocument
            self.currentPageIndex = 0
            self.redactionAnnotations = [:]
        }
    }

    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        guard let file = currentFile else {
            throw EditorError.noFileLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        // 使用TextRecognizer识别敏感信息
        let texts = try await recognizer.recognizeText(in: file)
        let regions = recognizer.detectSensitiveRegions(in: texts)

        await MainActor.run {
            self.detectedRegions = regions
        }

        return regions
    }

    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex)
        else {
            print("⚠️ PDFRedactionEditor: 无法获取PDF页面")
            return
        }

        // 创建注释（使用.square类型代替.redact）
        let annotation = PDFAnnotation(bounds: region, forType: .square, withProperties: nil)

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

        // 关键设置：填充颜色和边框
        annotation.interiorColor = fillColor  // 填充颜色
        annotation.color = fillColor  // 边框颜色

        // 重要：设置边框样式为实线，并设置边框宽度
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 0  // 无边框，只显示填充

        // 设置annotation的显示属性
        annotation.shouldDisplay = true
        annotation.shouldPrint = true

        print("📝 PDFRedactionEditor: 添加annotation at \(region), color=\(fillColor)")

        // 添加到页面
        page.addAnnotation(annotation)

        // 记录注释（用于撤销）
        if redactionAnnotations[currentPageIndex] == nil {
            redactionAnnotations[currentPageIndex] = []
        }
        redactionAnnotations[currentPageIndex]?.append(annotation)

        print("✅ PDFRedactionEditor: 当前页面共有\(page.annotations.count)个annotations")
    }

    func undo() {
        guard let document = pdfDocument,
            let page = document.page(at: currentPageIndex),
            var annotations = redactionAnnotations[currentPageIndex],
            let lastAnnotation = annotations.popLast()
        else {
            return
        }

        page.removeAnnotation(lastAnnotation)
        redactionAnnotations[currentPageIndex] = annotations
    }

    func redo() {
        // PDF编辑器的重做逻辑（可选实现）
        // 由于PDFKit不支持简单的重做，这里暂时留空
    }

    func exportRedactedFile() async throws -> Data {
        guard let document = pdfDocument else {
            throw EditorError.noPDFLoaded
        }

        // 注意：PDFKit在iOS中不支持直接应用redaction
        // 这里导出时注释会保留在PDF中，作为视觉遮挡
        // 对于真正的内容删除，需要使用专业PDF处理库

        // 清理元数据
        sanitizeMetadata(document: document)

        // 导出为Data
        guard let data = document.dataRepresentation() else {
            throw EditorError.exportFailed
        }

        return data
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
        currentPageIndex = 0
    }

    /// 清除当前页的所有脱敏
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
        currentPageRedactionCount > 0
    }

    /// 检查是否可以重做
    var canRedo: Bool {
        false  // PDF编辑器暂不支持重做
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
}
