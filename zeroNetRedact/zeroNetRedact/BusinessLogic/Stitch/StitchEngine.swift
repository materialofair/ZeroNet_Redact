//
//  StitchEngine.swift
//  ZeroNet Redact
//
//  拼接编排:原始编码数据 → 降采样源图(ImageIO,不解码全图)→ 方案 → 渲染
//

import ImageIO
import UIKit

/// 一次拼接会话中的单张源图
struct StitchSource: Identifiable {
    let id = UUID()
    /// 原始编码数据(PNG/JPEG/HEIC),渲染时才解码全图
    let data: Data
    /// 原始像素尺寸
    let pixelSize: CGSize
    /// 降采样预览图(宽 ≤ previewMaxWidth),UI 显示与指纹计算共用
    let preview: UIImage
    /// 预览图的行指纹缓存(排序/调整时重算方案无需重新采样)
    let fingerprints: [[Float]]
    /// 并发契约:渲染路径(Task.detached)只可读取 data(值类型);preview 为 UIImage 非 Sendable,只能在主线程使用
}

enum StitchEngineError: LocalizedError {
    case invalidImageData

    var errorDescription: String? {
        NSLocalizedString("import.error.invalidImageData", comment: "")
    }
}

enum StitchEngine {

    /// 预览/检测用降采样宽度上限
    static let previewMaxWidth: CGFloat = 750

    /// 从原始编码数据构建源图(ImageIO 缩略图 API,不整图解码)。
    /// 注:截图方向恒为 .up;带 EXIF 旋转的普通照片由
    /// kCGImageSourceCreateThumbnailWithTransform 处理,pixelSize 取变换后尺寸。
    static func makeSource(from data: Data) throws -> StitchSource {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let rawW = props[kCGImagePropertyPixelWidth] as? CGFloat,
            let rawH = props[kCGImagePropertyPixelHeight] as? CGFloat,
            rawW > 0, rawH > 0
        else { throw StitchEngineError.invalidImageData }

        // EXIF 5~8 表示带 90° 旋转,显示尺寸宽高互换
        let exif = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let rotated = (5...8).contains(Int(exif))
        let w = rotated ? rawH : rawW
        let h = rotated ? rawW : rawH

        // maxPixelSize 约束的是长边:按 "宽 ≤ previewMaxWidth" 换算
        let maxPixel = h > w ? previewMaxWidth * h / w : previewMaxWidth
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { throw StitchEngineError.invalidImageData }

        return StitchSource(
            data: data,
            pixelSize: CGSize(width: w, height: h),
            preview: UIImage(cgImage: thumb),
            fingerprints: OverlapDetector.rowFingerprints(of: thumb))
    }

    /// 计算拼接方案(使用缓存指纹,可在排序/增删后随时重算)
    static func computePlan(for sources: [StitchSource]) -> StitchPlan {
        OverlapDetector.computePlan(
            fingerprints: sources.map(\.fingerprints),
            pixelSizes: sources.map(\.pixelSize))
    }

    /// 渲染最终长图为 JPEG 数据
    static func render(plan: StitchPlan, sources: [StitchSource]) throws -> Data {
        try StitchRenderer.render(plan: plan, provider: DataImageProvider(sources: sources))
    }
}

/// 渲染时从编码数据逐张解码的 provider
private struct DataImageProvider: StitchImageProvider {
    let sources: [StitchSource]

    func loadCGImage(at index: Int) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(sources[index].data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw StitchRenderError.imageLoadFailed(index: index) }
        return image
    }
}
