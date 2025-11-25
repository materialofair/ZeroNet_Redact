//
//  EditorFactory.swift
//  ZeroNet Redact
//
//  编辑器工厂 - 根据文件类型创建对应的编辑器
//

import Foundation
import PDFKit
import UIKit

/// 编辑器工厂
class EditorFactory {

    /// 创建编辑器
    /// - Parameter file: 可脱敏文件
    /// - Returns: 对应的编辑器实例
    static func createEditor(for file: RedactableFile) -> AnyRedactionEditor {
        switch file.fileType {
        case .image:
            guard let imageFile = file as? OriginalImage else {
                fatalError("文件类型不匹配：期望OriginalImage，实际\(type(of: file))")
            }
            return AnyRedactionEditor(ImageRedactionEditor(file: imageFile))

        case .pdf:
            guard let pdfFile = file as? OriginalPDF else {
                fatalError("文件类型不匹配：期望OriginalPDF，实际\(type(of: file))")
            }
            return AnyRedactionEditor(PDFRedactionEditor(file: pdfFile))
        }
    }
}

// MARK: - 类型擦除包装器

/// 类型擦除的编辑器包装器（解决Protocol with associatedtype无法直接使用的问题）
class AnyRedactionEditor {
    private let _loadFile: () async throws -> Void
    private let _detectSensitiveRegions: () async throws -> [SensitiveRegion]
    private let _applyRedaction: (CGRect, RedactionEffect) -> Void
    private let _undo: () -> Void
    private let _redo: () -> Void
    private let _canUndo: () -> Bool
    private let _canRedo: () -> Bool
    private let _exportRedactedFile: () async throws -> Data

    let fileType: FileType
    let baseEditor: Any  // 保存原始editor实例，用于访问特定编辑器的属性

    private let _getCurrentImage: () -> UIImage?

    init<Editor: RedactionEditor>(_ editor: Editor) {
        self.baseEditor = editor  // 保存原始实例
        // 从editor的currentFile属性获取fileType
        if let imageEditor = editor as? ImageRedactionEditor {
            self.fileType = imageEditor.currentFile?.fileType ?? .image
        } else if let pdfEditor = editor as? PDFRedactionEditor {
            self.fileType = pdfEditor.currentFile?.fileType ?? .pdf
        } else {
            self.fileType = .image  // 默认值
        }

        self._loadFile = { [editor] in
            // 编辑器已经在init时接收了文件，直接调用loadFile加载
            if let imageEditor = editor as? ImageRedactionEditor,
                let file = imageEditor.currentFile
            {
                try await imageEditor.loadFile(file)
            } else if let pdfEditor = editor as? PDFRedactionEditor,
                let file = pdfEditor.currentFile
            {
                try await pdfEditor.loadFile(file)
            } else {
                throw EditorError.noFileLoaded
            }
        }

        self._getCurrentImage = { [weak editor] in
            if let imageEditor = editor as? ImageRedactionEditor {
                return imageEditor.currentImage
            } else if let pdfEditor = editor as? PDFRedactionEditor,
                let page = pdfEditor.currentPage
            {
                // PDF: 手动渲染当前页为图片（包含annotations）
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2.0  // 2x分辨率
                let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

                // 使用UIGraphicsImageRenderer渲染，包含annotations
                let renderer = UIGraphicsImageRenderer(size: size)
                return renderer.image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))

                    context.cgContext.saveGState()
                    context.cgContext.scaleBy(x: scale, y: scale)
                    context.cgContext.translateBy(x: 0, y: pageRect.height)
                    context.cgContext.scaleBy(x: 1.0, y: -1.0)

                    page.draw(with: .mediaBox, to: context.cgContext)

                    context.cgContext.restoreGState()
                }
            }
            return nil
        }

        self._detectSensitiveRegions = { [weak editor] in
            guard let editor = editor else { return [] }
            return try await editor.detectSensitiveRegions()
        }

        self._applyRedaction = { [weak editor] region, effect in
            editor?.applyRedaction(at: region, effect: effect)
        }

        self._undo = { [weak editor] in
            editor?.undo()
        }

        self._redo = { [weak editor] in
            editor?.redo()
        }

        self._canUndo = { [weak editor] in
            if let imageEditor = editor as? ImageRedactionEditor {
                return !imageEditor.editHistory.isEmpty
            } else if let pdfEditor = editor as? PDFRedactionEditor {
                return pdfEditor.canUndo
            }
            return false
        }

        self._canRedo = { [weak editor] in
            if let imageEditor = editor as? ImageRedactionEditor {
                return !imageEditor.redoStack.isEmpty
            } else if let pdfEditor = editor as? PDFRedactionEditor {
                return pdfEditor.canRedo
            }
            return false
        }

        self._exportRedactedFile = { [weak editor] in
            guard let editor = editor else {
                throw EditorError.exportFailed
            }
            return try await editor.exportRedactedFile()
        }
    }

    func loadFile() async throws {
        try await _loadFile()
    }

    func detectSensitiveRegions() async throws -> [SensitiveRegion] {
        try await _detectSensitiveRegions()
    }

    func applyRedaction(at region: CGRect, effect: RedactionEffect) {
        _applyRedaction(region, effect)
    }

    func undo() {
        _undo()
    }

    func redo() {
        _redo()
    }

    var canUndo: Bool {
        _canUndo()
    }

    var canRedo: Bool {
        _canRedo()
    }

    func exportRedactedFile() async throws -> Data {
        try await _exportRedactedFile()
    }

    func getCurrentImage() -> UIImage? {
        _getCurrentImage()
    }
}

// MARK: - 编辑器错误

enum EditorError: LocalizedError {
    case noFileLoaded
    case noImageLoaded
    case noPDFLoaded
    case exportFailed
    case applyRedactionFailed

    var errorDescription: String? {
        switch self {
        case .noFileLoaded:
            return "未加载文件"
        case .noImageLoaded:
            return "未加载图片"
        case .noPDFLoaded:
            return "未加载PDF"
        case .exportFailed:
            return "导出失败"
        case .applyRedactionFailed:
            return "应用脱敏失败"
        }
    }
}
