import Combine
import CoreData
import PDFKit
import SwiftUI

@MainActor
class EditorViewModel: ObservableObject {
    let file: RedactableFile

    // MARK: - 状态管理（委托给 StateManager）

    @Published var isLoading = false
    @Published var isDetecting = false
    @Published var isExporting = false
    @Published var errorMessage: String?
    /// 检测进度（0...1；nil 表示未在检测）
    @Published var detectProgress: Double?
    /// 检测失败原因（UI 据此展示错误提示，与导出错误分开存放避免串扰）
    @Published var detectErrorMessage: String?

    @Published var selectedEffect: RedactionEffect = .solidBlack
    @Published var detectedRegions: [SensitiveRegion] = []

    @Published var currentImage: UIImage?

    @Published var canUndo = false
    @Published var canRedo = false

    // PDF专用属性
    @Published var currentPDFDocument: PDFDocument?
    @Published var currentPDFPageIndex: Int = 0
    @Published var totalPDFPages: Int = 0

    // 分组相关属性
    @Published var allGroups: [FileGroup] = []
    @Published var currentGroup: FileGroup?
    @Published var showGroupPicker = false

    // 配额限制相关
    @Published var showUsageLimitAlert = false
    @Published var showPremiumView = false

    /// 导出成功但使用了视觉遮盖兜底时的警告文案
    @Published private(set) var exportWarning: String?
    /// 导出进度（0...1；nil 表示未在导出）
    @Published var exportProgress: Double?
    /// 最近一次成功导出的文件 URL（供分享 sheet 使用）
    @Published private(set) var exportedFileURL: URL?

    private(set) var editor: AnyRedactionEditor?

    // MARK: - 渲染同步

    /// 图片编辑器 currentImage 订阅：后台渲染完成时把成品图同步到本 VM
    private var imageSubscription: AnyCancellable?
    /// PDF 页渲染代数：连续渲染时以代数丢弃过期结果
    private var pdfRenderGeneration: UInt64 = 0

    // MARK: - 辅助处理器

    private lazy var pdfOperations: PDFOperationsHandler = {
        PDFOperationsHandler(editor: editor)
    }()

    private lazy var imageOperations: ImageOperationsHandler = {
        ImageOperationsHandler(editor: editor)
    }()

    init(file: RedactableFile) {
        self.file = file
        loadGroups()
    }

    func loadFile() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            print("🔄 EditorViewModel: 开始加载文件...")
            editor = EditorFactory.createEditor(for: file)

            print("🔄 EditorViewModel: 正在调用 editor.loadFile()...")
            try await editor?.loadFile()

            // 图片编辑器：订阅后台渲染结果（currentImage 异步更新）
            if let imageEditor = editor?.baseEditor as? ImageRedactionEditor {
                imageSubscription = imageEditor.$currentImage
                    .receive(on: RunLoop.main)
                    .sink { [weak self] image in
                        self?.currentImage = image
                    }
            }

            print("🔄 EditorViewModel: loadFile() 完成，正在获取图片...")

            // PDF特殊处理
            if file.fileType == .pdf {
                if let pdfEditor = editor?.baseEditor as? PDFRedactionEditor {
                    await MainActor.run {
                        currentPDFDocument = pdfEditor.pdfDocument
                        currentPDFPageIndex = pdfEditor.currentPageIndex
                        totalPDFPages = pdfEditor.getTotalPages()

                        // 渲染PDF页面为图片
                        currentImage = renderCurrentPDFPage()
                        print(
                            "✅ EditorViewModel: PDF已加载，共\(totalPDFPages)页，当前第\(currentPDFPageIndex + 1)页"
                        )
                    }
                } else {
                    print("⚠️ EditorViewModel: 无法获取PDFRedactionEditor")
                    await MainActor.run {
                        errorMessage = NSLocalizedString("pdf.loadFailed", comment: "")
                    }
                }
            } else {
                // 图片文件：现有逻辑
                if let image = editor?.getCurrentImage() {
                    await MainActor.run {
                        currentImage = image
                        print("✅ EditorViewModel: 图片已加载，尺寸: \(image.size)")
                    }
                } else {
                    print("⚠️ EditorViewModel: editor?.getCurrentImage() 返回 nil")
                    await MainActor.run {
                        errorMessage = NSLocalizedString("editor.loadFailed", comment: "")
                    }
                }
            }

            await MainActor.run {
                updateUndoRedoState()
            }
        } catch {
            await MainActor.run {
                errorMessage = String(
                    format: NSLocalizedString("editor.loadFileFailed", comment: ""),
                    error.localizedDescription)
                print("❌ EditorViewModel: 加载失败 - \(error)")
            }
        }
    }

    func detectSensitiveRegions() async {
        print("🎯 EditorViewModel: 开始检测敏感区域")
        isDetecting = true
        detectProgress = nil
        detectErrorMessage = nil
        defer {
            isDetecting = false
            detectProgress = nil
            print("🎯 EditorViewModel: 检测结束，isDetecting=false")
        }

        do {
            print("🎯 EditorViewModel: 调用editor.detectSensitiveRegions()")
            if let regions = try await editor?.detectSensitiveRegions(progress: { [weak self] value in
                Task { @MainActor in
                    self?.detectProgress = value
                }
            }) {
                print("🎯 EditorViewModel: 收到 \(regions.count) 个检测区域")
                detectedRegions = regions
                print("🎯 EditorViewModel: detectedRegions已更新，当前数量: \(detectedRegions.count)")
            } else {
                print("⚠️ EditorViewModel: editor?.detectSensitiveRegions() 返回 nil")
            }
        } catch {
            print("❌ EditorViewModel: 检测失败 - \(error)")
            let message = String(
                format: NSLocalizedString("editor.detectFailed", comment: ""),
                error.localizedDescription)
            errorMessage = message
            detectErrorMessage = message
        }
    }

    func applyRedaction(at region: CGRect) {
        applyRedaction(at: region, effect: selectedEffect)
    }

    /// 应用脱敏（显式指定效果）
    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        editor?.applyRedaction(at: region, effect: effect)

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    /// 批量应用脱敏（单快照 + 单次渲染，涂抹等场景避免逐笔整图重绘）
    func applyRedactions(at regions: [CGRect], effect: RedactionEffect) {
        editor?.applyRedactions(at: regions, effect: effect)

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    func undo() {
        editor?.undo()

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    func redo() {
        editor?.redo()

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    /// 旋转当前图片
    func rotateCurrentImage(to rotatedImage: UIImage) {
        // 更新编辑器中的原始图片
        if let imageEditor = editor?.baseEditor as? ImageRedactionEditor {
            imageEditor.replaceOriginalImage(with: rotatedImage)
        }

        // 更新显示的图片
        currentImage = rotatedImage

        // 清除撤销历史（旋转后坐标系变化）
        updateUndoRedoState()
    }

    /// 检查是否可以导出（配额检查）
    func canExport() -> Bool {
        let appState = AppState.shared

        // 付费用户或审核模式：无限制
        if appState.hasUnlimitedAccess {
            return true
        }

        // 免费用户：检查配额
        let tracker = UsageTracker.shared
        if file.fileType == .image {
            return tracker.canExportMedia()
        } else {
            return tracker.canExportDocument()
        }
    }

    /// 记录导出使用量
    private func recordExportUsage() {
        // 只有免费用户需要记录
        guard !AppState.shared.hasUnlimitedAccess else { return }

        let tracker = UsageTracker.shared
        if file.fileType == .image {
            tracker.recordMediaExport()
        } else {
            tracker.recordDocExport()
        }
    }

    /// 导出脱敏后的文件
    /// - Returns: 是否导出成功（配额超限或异常均返回 false，具体原因见 showUsageLimitAlert / errorMessage）
    @discardableResult
    func exportFile() async -> Bool {
        // 1. 检查配额
        if !canExport() {
            showUsageLimitAlert = true
            print("⚠️ EditorViewModel: 达到每日导出限制")
            return false
        }

        isExporting = true
        defer { isExporting = false }
        exportWarning = nil
        exportedFileURL = nil
        exportProgress = nil

        if Task.isCancelled {
            print("⚠️ EditorViewModel: 导出已取消，跳过处理")
            return false
        }

        do {
            print("📦 开始导出文件，类型: \(file.fileType)")

            if let data = try await editor?.exportRedactedFile(progress: { [weak self] value in
                Task { @MainActor in
                    self?.exportProgress = value
                }
            }) {
                print("📦 获取到打码数据，大小: \(data.count) bytes")

                // 取消检查：确保取消后不写入磁盘
                if Task.isCancelled {
                    print("⚠️ EditorViewModel: 导出已取消，跳过写入文件")
                    return false
                }

                // 生成新的文件ID
                let newFileId = UUID()

                // 保存打码后的文件（明文存储，不加密）
                let url = try StorageManager.shared.saveRedactedFile(
                    data: data,
                    id: newFileId,
                    type: file.fileType
                )
                print("✅ 打码文件已保存: \(url.path)")

                // 取消检查：确保取消后不创建相册记录、不扣配额；
                // 此时磁盘文件已写入，需一并清理，避免留下无记录引用的孤儿文件
                if Task.isCancelled {
                    print("⚠️ EditorViewModel: 导出已取消，清理已写入的文件并跳过创建记录")
                    try? StorageManager.shared.deleteRedacted(id: newFileId, type: file.fileType)
                    return false
                }

                // 创建新的OriginalFile记录（作为独立的打码文件显示在相册）
                var didSaveRecord = false
                await MainActor.run {
                    let context = PersistenceController.shared.container.viewContext

                    do {
                        // 生成缩略图（明文保存）
                        let thumbnailData: Data?
                        if file.fileType == .pdf,
                            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
                            let page = pdfEditor.pdfDocument?.page(at: 0)
                        {
                            let thumbnailSize = CGSize(width: 200, height: 200)
                            let pageRect = page.bounds(for: .mediaBox)
                            let scale = min(
                                thumbnailSize.width / pageRect.width,
                                thumbnailSize.height / pageRect.height)
                            let scaledSize = CGSize(
                                width: pageRect.width * scale,
                                height: pageRect.height * scale)

                            let renderer = UIGraphicsImageRenderer(size: scaledSize)
                            let thumbnail = renderer.image { context in
                                UIColor.white.setFill()
                                context.fill(CGRect(origin: .zero, size: scaledSize))
                                context.cgContext.translateBy(x: 0, y: scaledSize.height)
                                context.cgContext.scaleBy(x: scale, y: -scale)
                                page.draw(with: .mediaBox, to: context.cgContext)
                            }
                            thumbnailData = thumbnail.pngData()
                        } else if let currentImage {
                            let thumbnailSize = CGSize(width: 200, height: 200)
                            let thumbnail = currentImage.preparingThumbnail(of: thumbnailSize)
                            thumbnailData = thumbnail?.pngData()
                        } else {
                            thumbnailData = nil
                        }

                        // 保存缩略图（明文）
                        var thumbnailPath = ""
                        if let thumbData = thumbnailData {
                            let thumbURL = try StorageManager.shared.saveRedactedThumbnail(
                                data: thumbData,
                                id: newFileId,
                                type: file.fileType
                            )
                            thumbnailPath = thumbURL.path
                            print("✅ 缩略图已保存: \(thumbURL.path)")
                        }

                        // 创建RedactedFile（打码后的文件保存到相册Tab）
                        let redactedFile = RedactedFile(context: context)
                        redactedFile.id = newFileId
                        redactedFile.fileTypeRaw = file.fileType.rawValue
                        // 只保存相对路径（去掉Documents前面的部分）
                        if let documentsPath = FileManager.default.urls(
                            for: .documentDirectory, in: .userDomainMask
                        ).first?.path,
                            url.path.hasPrefix(documentsPath)
                        {
                            redactedFile.filePath = String(url.path.dropFirst(documentsPath.count))
                        } else {
                            redactedFile.filePath = url.path
                        }

                        // 缩略图路径也只保存相对路径
                        if !thumbnailPath.isEmpty,
                            let documentsPath = FileManager.default.urls(
                                for: .documentDirectory, in: .userDomainMask
                            ).first?.path,
                            thumbnailPath.hasPrefix(documentsPath)
                        {
                            redactedFile.thumbnailPath = String(
                                thumbnailPath.dropFirst(documentsPath.count))
                        } else {
                            redactedFile.thumbnailPath = thumbnailPath
                        }

                        redactedFile.exportedAt = Date()
                        redactedFile.fileSize = Int64(data.count)

                        // 关联原始文件（如果file是OriginalFile）
                        if let originalFile = file as? OriginalFile {
                            redactedFile.originalFile = originalFile
                            // 继承原文件的分组
                            redactedFile.group = originalFile.group
                            print("✅ 脱敏文件继承分组: \(originalFile.group?.name ?? "无分组")")
                        }

                        // 保存到CoreData
                        try context.save()
                        print("✅ 打码文件已保存到脱敏文件Tab，ID: \(redactedFile.id)")

                        // 记录导出使用量（免费用户计数）
                        self.recordExportUsage()

                        // 真删除失败退回视觉遮盖时，提示用户
                        if let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
                            pdfEditor.usedFallbackExport
                        {
                            self.exportWarning = NSLocalizedString(
                                "export.fallbackWarning", comment: "")
                        }

                        didSaveRecord = true
                    } catch {
                        print("❌ 保存打码文件到相册失败: \(error)")
                        self.errorMessage = String(
                            format: NSLocalizedString("editor.exportFailed", comment: ""),
                            error.localizedDescription)
                    }
                }
                if didSaveRecord {
                    // 记录导出文件位置，供导出后分享 sheet 使用
                    exportedFileURL = url
                }
                return didSaveRecord
            } else {
                print("❌ 导出失败: editor?.exportRedactedFile() 返回 nil")
                errorMessage = NSLocalizedString("export.failed", comment: "")
                return false
            }
        } catch {
            print("❌ 导出异常: \(error.localizedDescription)")
            errorMessage = String(
                format: NSLocalizedString("editor.exportFailed", comment: ""),
                error.localizedDescription)
            return false
        }
    }

    private func updateUndoRedoState() {
        canUndo = editor?.canUndo ?? false
        canRedo = editor?.canRedo ?? false
    }

    // MARK: - PDF Support Methods

    /// 检查是否是PDF文件
    var isPDFFile: Bool {
        file.fileType == .pdf
    }

    /// 当前页面可消费的检测区域（图片文件返回全部；PDF文件按当前页过滤）
    var regionsForCurrentPage: [SensitiveRegion] {
        guard isPDFFile else { return detectedRegions }
        return detectedRegions.filter { $0.pageIndex == currentPDFPageIndex }
    }

    /// 其他页面尚未处理的检测区域数量（仅PDF有意义）
    var otherPagesRegionCount: Int {
        guard isPDFFile else { return 0 }
        return detectedRegions.filter { $0.pageIndex != currentPDFPageIndex }.count
    }

    /// 渲染PDF当前页为UIImage（包含annotations，同步版本，加载/导出路径使用）
    func renderCurrentPDFPage() -> UIImage? {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let document = pdfEditor.pdfDocument,
            let page = document.page(at: currentPDFPageIndex)
        else {
            print("⚠️ renderCurrentPDFPage: 无法获取PDF页面")
            return nil
        }

        return Self.renderPDFPage(page)
    }

    /// PDF 页渲染（纯函数：只读 page，可后台线程执行）
    nonisolated private static func renderPDFPage(_ page: PDFPage) -> UIImage? {
        // 使用高分辨率渲染
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0  // 2x分辨率，平衡质量和性能
        let size = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale)

        // 关键：format.scale 固定为 1，保证真实 2x；
        // 否则会叠加屏幕倍率（3x 设备达 6x，大 PDF 内存压力大）
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            // 白色背景
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // 保存上下文
            context.cgContext.saveGState()

            // 缩放以适应目标尺寸
            context.cgContext.scaleBy(x: scale, y: scale)

            // PDF坐标系转换：翻转Y轴（PDF原点在左下角）
            context.cgContext.translateBy(x: 0, y: pageRect.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)

            // 绘制PDF页面（包含所有annotations）
            page.draw(with: .mediaBox, to: context.cgContext)

            // 恢复上下文
            context.cgContext.restoreGState()
        }

        return image
    }

    /// 后台渲染 PDF 当前页（带代数校验，过期结果丢弃）
    /// 编辑操作触发的重渲染走此路径，避免大页在主线程合成
    func refreshPDFPageImage() {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let document = pdfEditor.pdfDocument,
            let page = document.page(at: currentPDFPageIndex)
        else {
            return
        }

        pdfRenderGeneration += 1
        let generation = pdfRenderGeneration
        let pageIndex = currentPDFPageIndex

        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                EditorViewModel.renderPDFPage(page)
            }.value

            await MainActor.run {
                guard let self,
                    generation == self.pdfRenderGeneration,
                    pageIndex == self.currentPDFPageIndex
                else { return }
                self.currentImage = image
            }
        }
    }

    /// 跳转到指定PDF页面
    func goToPDFPage(_ index: Int) {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor else {
            print("⚠️ goToPDFPage: 不是PDF编辑器")
            return
        }

        guard index >= 0 && index < totalPDFPages else {
            print("⚠️ goToPDFPage: 页码超出范围 (\(index)/\(totalPDFPages))")
            return
        }

        print("📄 goToPDFPage: 跳转到第\(index + 1)页")
        pdfEditor.goToPage(index)
        currentPDFPageIndex = index

        // 后台渲染新页
        refreshPDFPageImage()
    }

    // MARK: - Annotation Drag Support (PDF)

    /// 获取当前PDF页面的所有注释及其边界框
    func getCurrentPageAnnotations() -> [(index: Int, bounds: CGRect)] {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return []
        }

        return page.annotations.enumerated().map { (index, annotation) in
            (index: index, bounds: annotation.bounds)
        }
    }

    /// 查找指定点击位置的注释索引 (PDF坐标系)
    func findAnnotation(at point: CGPoint) -> Int? {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return nil
        }

        // 从后往前查找,优先选择最上层的注释
        for (index, annotation) in page.annotations.enumerated().reversed() {
            if annotation.bounds.contains(point) {
                return index
            }
        }

        return nil
    }

    /// 移动指定索引的注释 (PDF坐标系偏移量)
    func moveAnnotation(at index: Int, offset: CGSize) {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor
        else {
            return
        }

        pdfEditor.moveAnnotation(at: index, offset: offset)

        // 后台刷新当前页面渲染
        refreshPDFPageImage()
    }

    // MARK: - Redaction Region Drag Support (Image)

    /// 检查是否是图片文件
    var isImageFile: Bool {
        file.fileType == .image
    }

    /// 获取图片的所有已应用脱敏区域及其边界框（图片像素坐标）
    func getImageRedactionRegions() -> [(index: Int, bounds: CGRect)] {
        guard isImageFile,
            let imageEditor = editor?.baseEditor as? ImageRedactionEditor
        else {
            return []
        }

        return imageEditor.getRedactionRegions()
    }

    /// 查找指定点击位置的图片脱敏区域索引（图片像素坐标）
    func findImageRedactionRegion(at point: CGPoint) -> Int? {
        guard isImageFile,
            let imageEditor = editor?.baseEditor as? ImageRedactionEditor
        else {
            return nil
        }

        return imageEditor.findRedactionRegion(at: point)
    }

    /// 移动指定索引的图片脱敏区域（图片像素偏移量）
    func moveImageRedactionRegion(at index: Int, offset: CGSize) {
        guard isImageFile,
            let imageEditor = editor?.baseEditor as? ImageRedactionEditor
        else {
            return
        }

        imageEditor.moveRedactionRegion(at: index, offset: offset)

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    /// 删除指定索引的图片脱敏区域
    func removeImageRedactionRegion(at index: Int) {
        guard isImageFile,
            let imageEditor = editor?.baseEditor as? ImageRedactionEditor
        else {
            return
        }

        imageEditor.removeRedactionRegion(at: index)

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    /// 缩放指定索引的图片脱敏区域
    /// - Parameters:
    ///   - index: 脱敏区域索引
    ///   - scale: 缩放比例 (1.0 = 不变, >1.0 = 放大, <1.0 = 缩小)
    func scaleImageRedactionRegion(at index: Int, scale: CGFloat) {
        guard isImageFile,
            let imageEditor = editor?.baseEditor as? ImageRedactionEditor
        else {
            return
        }

        imageEditor.scaleRedactionRegion(at: index, scale: scale)

        // 更新显示的图片
        if let image = editor?.getCurrentImage() {
            currentImage = image
        }

        updateUndoRedoState()
    }

    /// 获取当前PDF页面的注释（脱敏区域）数量
    /// - Returns: 注释数量，非PDF文件返回0
    func getPDFAnnotationCount() -> Int {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let document = pdfEditor.pdfDocument,
            let page = document.page(at: pdfEditor.currentPageIndex)
        else {
            return 0
        }
        return page.annotations.count
    }

    /// 删除指定索引的PDF注释（脱敏区域）
    /// - Parameter index: 注释索引
    func removePDFAnnotation(at index: Int) {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor
        else {
            return
        }

        // 委托编辑器处理（记录快照、同步撤销跟踪）
        pdfEditor.removeAnnotation(at: index)

        // 后台刷新当前页面渲染
        refreshPDFPageImage()

        updateUndoRedoState()
    }

    /// 缩放指定索引的PDF注释（脱敏区域）
    /// - Parameters:
    ///   - index: 注释索引
    ///   - scale: 缩放比例 (1.0 = 不变, >1.0 = 放大, <1.0 = 缩小)
    func scalePDFAnnotation(at index: Int, scale: CGFloat) {
        guard isPDFFile,
            let pdfEditor = editor?.baseEditor as? PDFRedactionEditor
        else {
            return
        }

        pdfEditor.scaleAnnotation(at: index, scale: scale)

        // 后台刷新当前页面渲染
        refreshPDFPageImage()
    }

    /// 统一的缩放脱敏区域方法（自动判断文件类型）
    /// - Parameters:
    ///   - index: 脱敏区域索引
    ///   - scale: 缩放比例
    func scaleRedactionRegion(at index: Int, scale: CGFloat) {
        if isPDFFile {
            scalePDFAnnotation(at: index, scale: scale)
        } else if isImageFile {
            scaleImageRedactionRegion(at: index, scale: scale)
        }
    }

    // MARK: - Group Management

    /// 加载所有分组
    func loadGroups() {
        allGroups = GroupManager.shared.getAllGroups()

        // 如果文件是OriginalFile，获取其当前分组
        if let originalFile = file as? OriginalFile {
            currentGroup = originalFile.group
        }
    }

    /// 移动文件到指定分组，返回是否成功
    @discardableResult
    func moveToGroup(_ group: FileGroup) -> Bool {
        guard let originalFile = file as? OriginalFile else {
            print("⚠️ 当前文件不是OriginalFile，无法移动分组")
            return false
        }

        if GroupManager.shared.moveFile(originalFile, to: group) {
            currentGroup = group
            showGroupPicker = false
            print("✅ 文件已移动到分组: \(group.name ?? "未命名")")
            return true
        } else {
            print("❌ 移动文件到分组失败")
            return false
        }
    }
}
