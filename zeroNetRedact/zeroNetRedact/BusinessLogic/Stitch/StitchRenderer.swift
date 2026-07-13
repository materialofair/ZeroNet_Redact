//
//  StitchRenderer.swift
//  ZeroNet Redact
//
//  拼接渲染器:单个位图上下文,逐张"解码-绘制-释放",内存峰值 ≈ 输出位图 + 单张源图
//

import UIKit

/// 渲染时逐张惰性加载原图,避免全部源图同时解码到内存
protocol StitchImageProvider {
    func loadCGImage(at index: Int) throws -> CGImage
}

enum StitchRenderError: LocalizedError {
    case noItems
    case contextCreationFailed
    case imageLoadFailed(index: Int)
    case encodingFailed

    var errorDescription: String? {
        NSLocalizedString("stitch.error.renderFailed", comment: "")
    }
}

enum StitchRenderer {

    /// 输出总像素上限(约 1170 宽 × 25600 高;编辑器可承受的规模,见设计文档 §4.3)
    static let maxOutputPixels: CGFloat = 30_000_000
    /// 输出最大高度(JPEG 65535 上限兜底)
    static let maxOutputHeight: CGFloat = 65_000
    /// 导出 JPEG 质量
    static let jpegQuality: CGFloat = 0.9

    /// 计算输出尺寸与整体缩放系数。
    /// 宽取全组最小宽;各图先等比对齐到该宽再累计内容高;超限时整体等比缩小。
    static func outputSize(for plan: StitchPlan) -> (size: CGSize, scale: CGFloat) {
        guard let width = plan.items.map({ $0.pixelSize.width }).min(), width > 0 else {
            return (.zero, 1)
        }
        var height: CGFloat = 0
        for item in plan.items where item.pixelSize.width > 0 {
            height += item.contentHeight * (width / item.pixelSize.width)
        }
        guard height > 0 else { return (.zero, 1) }

        var scale: CGFloat = 1.0
        if width * height > maxOutputPixels {
            scale = (maxOutputPixels / (width * height)).squareRoot()
        }
        if height * scale > maxOutputHeight {
            scale = min(scale, maxOutputHeight / height)
        }
        return (
            CGSize(
                width: (width * scale).rounded(.down),
                height: (height * scale).rounded(.down)),
            scale
        )
    }

    /// 全分辨率渲染为 JPEG 数据
    static func render(plan: StitchPlan, provider: StitchImageProvider) throws -> Data {
        guard !plan.items.isEmpty else { throw StitchRenderError.noItems }
        let (size, scale) = outputSize(for: plan)
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0,
            let minWidth = plan.items.map({ $0.pixelSize.width }).min(),
            let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw StitchRenderError.contextCreationFailed }

        // JPEG 无 alpha,先铺白底,避免亚像素缝隙透黑
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        ctx.interpolationQuality = .high

        var y: CGFloat = 0  // 自顶向下累计
        for (index, item) in plan.items.enumerated() {
            try autoreleasepool {
                let cgImage = try provider.loadCGImage(at: index)
                // 裁剪区域(源图像素坐标,CGImage.cropping 原点在左上)
                let cropRect = CGRect(
                    x: 0, y: item.cropTop,
                    width: item.pixelSize.width, height: item.contentHeight)
                guard item.contentHeight > 0, let cropped = cgImage.cropping(to: cropRect)
                else { throw StitchRenderError.imageLoadFailed(index: index) }

                let widthScale = (minWidth * scale) / item.pixelSize.width
                let drawHeight = item.contentHeight * widthScale
                // CGContext 原点在左下:目标 y = 总高 - 已累计 - 本段高
                ctx.draw(
                    cropped,
                    in: CGRect(
                        x: 0, y: size.height - y - drawHeight,
                        width: size.width, height: drawHeight))
                y += drawHeight
            }
        }

        guard let output = ctx.makeImage(),
            let data = UIImage(cgImage: output).jpegData(compressionQuality: jpegQuality)
        else { throw StitchRenderError.encodingFailed }
        print("🧵 StitchRenderer: 输出 \(width)x\(height),\(data.count / 1024)KB")
        return data
    }
}
