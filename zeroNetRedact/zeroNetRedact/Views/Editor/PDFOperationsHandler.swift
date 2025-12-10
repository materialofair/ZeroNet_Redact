import PDFKit
import SwiftUI

/// PDF 操作处理器
/// 负责处理 PDF 相关的所有操作（页面渲染和导航、注释管理等）
@MainActor
class PDFOperationsHandler {
    private weak var editor: AnyRedactionEditor?

    init(editor: AnyRedactionEditor?) {
        self.editor = editor
    }

    // MARK: - PDF 页面渲染

    /// 渲染当前 PDF 页面为图片
    func renderCurrentPDFPage() -> UIImage? {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let pdfDocument = pdfEditor.pdfDocument,
            let page = pdfDocument.page(at: pdfEditor.currentPageIndex)
        else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let screenScale = UIScreen.main.scale
        let targetWidth: CGFloat = 1200
        let scale = min(targetWidth / pageRect.width, screenScale)
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))

            context.cgContext.translateBy(x: 0, y: scaledSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    // MARK: - PDF 页面导航

    /// 跳转到指定 PDF 页面
    func goToPDFPage(_ index: Int) -> UIImage? {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor else {
            return nil
        }

        let totalPages = pdfEditor.getTotalPages()
        guard index >= 0 && index < totalPages else {
            print("⚠️ PDFOperationsHandler: 页面索引超出范围: \(index)")
            return nil
        }

        pdfEditor.goToPage(index)
        return renderCurrentPDFPage()
    }

    // MARK: - PDF 注释管理

    /// 获取当前页面的所有注释
    func getCurrentPageAnnotations() -> [(index: Int, bounds: CGRect)] {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return []
        }
        return page.annotations.enumerated().map { (index: $0.offset, bounds: $0.element.bounds) }
    }

    /// 查找指定点击位置的注释
    func findAnnotation(at point: CGPoint) -> Int? {
        let annotations = getCurrentPageAnnotations()

        for (index, annotation) in annotations.enumerated().reversed() {
            let expandedBounds = annotation.bounds.insetBy(dx: -20, dy: -20)
            if expandedBounds.contains(point) {
                return index
            }
        }
        return nil
    }

    /// 移动注释位置
    func moveAnnotation(at index: Int, offset: CGSize) -> Bool {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let currentPage = pdfEditor.currentPage
        else {
            return false
        }

        let annotations = currentPage.annotations
        guard index >= 0 && index < annotations.count else {
            return false
        }

        let annotation = annotations[index]
        var newBounds = annotation.bounds
        newBounds.origin.x += offset.width
        newBounds.origin.y += offset.height

        let pageBounds = currentPage.bounds(for: .mediaBox)
        newBounds.origin.x = max(0, min(newBounds.origin.x, pageBounds.width - newBounds.width))
        newBounds.origin.y = max(0, min(newBounds.origin.y, pageBounds.height - newBounds.height))

        annotation.bounds = newBounds
        return true
    }

    /// 移除注释
    func removeAnnotation(at index: Int) -> Bool {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let currentPage = pdfEditor.currentPage
        else {
            return false
        }

        let annotations = currentPage.annotations
        guard index >= 0 && index < annotations.count else {
            return false
        }

        currentPage.removeAnnotation(annotations[index])
        return true
    }

    /// 缩放注释大小
    func scaleAnnotation(at index: Int, scale: CGFloat) -> Bool {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor else {
            return false
        }

        pdfEditor.scaleAnnotation(at: index, scale: scale)
        return true
    }

    /// 获取 PDF 注释总数
    func getAnnotationCount() -> Int {
        guard let pdfEditor = editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return 0
        }
        return page.annotations.count
    }
}
