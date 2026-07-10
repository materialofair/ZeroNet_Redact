//
//  CoordinateConverter.swift
//  ZeroNet Redact
//
//  坐标转换工具类 - 处理屏幕、PDF、图片坐标系之间的转换
//

import PDFKit
import SwiftUI

/// 坐标转换器
struct CoordinateConverter {
    let imageSize: CGSize
    let viewModel: EditorViewModel

    // MARK: - PDF Coordinate Conversion

    /// 屏幕坐标转PDF坐标(含Y轴翻转)
    func screenToPDF(_ screenPoint: CGPoint) -> CGPoint? {
        guard viewModel.isPDFFile,
            let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfPageWidth = pageRect.width
        let pdfPageHeight = pageRect.height

        let pdfScaleX = pdfPageWidth / imageSize.width
        let pdfScaleY = pdfPageHeight / imageSize.height

        let pdfX = screenPoint.x * pdfScaleX
        let pdfY = screenPoint.y * pdfScaleY

        // Y轴翻转
        let flippedY = pdfPageHeight - pdfY

        return CGPoint(x: pdfX, y: flippedY)
    }

    /// PDF坐标转屏幕坐标(含Y轴翻转)
    func pdfToScreen(_ pdfPoint: CGPoint) -> CGPoint? {
        guard viewModel.isPDFFile,
            let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfPageWidth = pageRect.width
        let pdfPageHeight = pageRect.height

        let screenScaleX = imageSize.width / pdfPageWidth
        let screenScaleY = imageSize.height / pdfPageHeight

        // Y轴翻转
        let flippedY = pdfPageHeight - pdfPoint.y

        let screenX = pdfPoint.x * screenScaleX
        let screenY = flippedY * screenScaleY

        return CGPoint(x: screenX, y: screenY)
    }

    /// PDF矩形转屏幕矩形
    func pdfRectToScreen(_ pdfRect: CGRect) -> CGRect? {
        guard let topLeft = pdfToScreen(CGPoint(x: pdfRect.minX, y: pdfRect.maxY)),
            let bottomRight = pdfToScreen(CGPoint(x: pdfRect.maxX, y: pdfRect.minY))
        else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    // MARK: - Image Coordinate Conversion

    /// 屏幕坐标转图片像素坐标
    func screenToImage(_ screenPoint: CGPoint) -> CGPoint? {
        guard viewModel.isImageFile,
            let originalImage = viewModel.currentImage
        else {
            return nil
        }

        // 计算缩放比例（原始图片像素 / 屏幕显示尺寸）
        let scaleX = originalImage.size.width / imageSize.width
        let scaleY = originalImage.size.height / imageSize.height

        let imageX = screenPoint.x * scaleX
        let imageY = screenPoint.y * scaleY

        return CGPoint(x: imageX, y: imageY)
    }

    /// 图片像素坐标转屏幕坐标
    func imageToScreen(_ imagePoint: CGPoint) -> CGPoint? {
        guard viewModel.isImageFile,
            let originalImage = viewModel.currentImage
        else {
            return nil
        }

        // 计算缩放比例（屏幕显示尺寸 / 原始图片像素）
        let scaleX = imageSize.width / originalImage.size.width
        let scaleY = imageSize.height / originalImage.size.height

        let screenX = imagePoint.x * scaleX
        let screenY = imagePoint.y * scaleY

        return CGPoint(x: screenX, y: screenY)
    }

    /// 图片像素矩形转屏幕矩形
    func imageRectToScreen(_ imageRect: CGRect) -> CGRect? {
        guard let topLeft = imageToScreen(CGPoint(x: imageRect.minX, y: imageRect.minY)),
            let bottomRight = imageToScreen(CGPoint(x: imageRect.maxX, y: imageRect.maxY))
        else {
            return nil
        }

        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    // MARK: - Sensitive Region Conversion

    /// 将检测到的敏感区域转换为编辑器可直接使用的坐标系矩形
    /// (图片文件: 图片像素坐标；PDF文件: PDF页面坐标，均与 applyRedaction(at:) 期望的坐标系一致)
    func regionRect(for region: SensitiveRegion) -> CGRect? {
        if viewModel.isPDFFile {
            // PDFTextRecognizer 返回的 boundingBox 已经是PDF页面坐标(左下角原点)
            return region.boundingBox
        } else if viewModel.isImageFile {
            guard let image = viewModel.currentImage else { return nil }
            let bb = region.boundingBox
            let width = image.size.width
            let height = image.size.height
            // Vision归一化坐标(左下角原点) -> 图片像素坐标(左上角原点)
            return CGRect(
                x: bb.minX * width,
                y: (1 - bb.maxY) * height,
                width: bb.width * width,
                height: bb.height * height
            )
        }
        return nil
    }

    /// 将检测到的敏感区域转换为屏幕坐标，用于画布上高亮显示
    func regionScreenRect(for region: SensitiveRegion) -> CGRect? {
        guard let rect = regionRect(for: region) else { return nil }
        if viewModel.isPDFFile {
            return pdfRectToScreen(rect)
        } else if viewModel.isImageFile {
            return imageRectToScreen(rect)
        }
        return nil
    }

    // MARK: - Display Size Calculation

    /// 计算图片显示尺寸
    static func calculateDisplaySize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    // MARK: - Drag Offset Conversion

    /// 将屏幕拖拽偏移转换为PDF坐标系偏移
    func screenDragToPDFDelta(_ screenOffset: CGSize) -> CGSize? {
        guard viewModel.isPDFFile,
            let pdfEditor = viewModel.editor?.baseEditor as? PDFRedactionEditor,
            let page = pdfEditor.currentPage
        else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let pdfPageWidth = pageRect.width
        let pdfPageHeight = pageRect.height

        // 计算缩放比例
        let pdfScaleX = pdfPageWidth / imageSize.width
        let pdfScaleY = pdfPageHeight / imageSize.height

        // 偏移量转换：只需缩放，Y方向需要翻转（屏幕向下=PDF向上）
        return CGSize(
            width: screenOffset.width * pdfScaleX,
            height: -screenOffset.height * pdfScaleY  // Y方向相反
        )
    }

    /// 将屏幕拖拽偏移转换为图片坐标系偏移
    func screenDragToImageDelta(_ screenOffset: CGSize) -> CGSize? {
        guard viewModel.isImageFile,
            let originalImage = viewModel.currentImage
        else {
            return nil
        }

        // 计算缩放比例（原始图片像素 / 屏幕显示尺寸）
        let imageScaleX = originalImage.size.width / imageSize.width
        let imageScaleY = originalImage.size.height / imageSize.height

        // 偏移量转换：屏幕偏移 -> 图片像素偏移
        return CGSize(
            width: screenOffset.width * imageScaleX,
            height: screenOffset.height * imageScaleY  // 图片坐标系与屏幕同向
        )
    }
}
