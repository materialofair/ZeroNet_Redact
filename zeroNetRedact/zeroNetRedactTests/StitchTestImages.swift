//
//  StitchTestImages.swift
//  zeroNetRedactTests
//
//  拼接测试图片工厂:生成可控的"滚动截图"用于验证重叠检测与渲染
//

import UIKit

enum StitchTestImages {

    /// 确定性伪随机灰度序列(LCG),保证条纹图案跨测试可重现
    static func grayValue(seed: UInt64, index: Int) -> CGFloat {
        var state = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        state = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        state = (state ^ (state >> 27)) &* 0x94D0_49BB_1331_11EB
        return CGFloat((state >> 33) % 256) / 255.0
    }

    /// 生成一张"世界"长图:每 8px 一条灰度横纹,模拟可滚动的页面内容
    static func world(width: CGFloat, height: CGFloat, seed: UInt64 = 7) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // 关键:像素 == 点,保证坐标断言确定性
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            var y: CGFloat = 0
            var stripe = 0
            while y < height {
                let gray = grayValue(seed: seed, index: stripe)
                ctx.cgContext.setFillColor(CGColor(gray: gray, alpha: 1))
                ctx.cgContext.fill(CGRect(x: 0, y: y, width: width, height: 8))
                y += 8
                stripe += 1
            }
        }
    }

    /// 从"世界"图截取一张"截图":内容区取自 world 的 [contentTop, contentTop+contentHeight),
    /// 顶部叠加纯色页眉、底部叠加纯色页脚(模拟状态栏/导航栏/Tab栏)
    static func screenshot(
        from world: UIImage,
        contentTop: CGFloat,
        contentHeight: CGFloat,
        headerHeight: CGFloat = 60,
        footerHeight: CGFloat = 80,
        headerGray: CGFloat = 0.1,
        footerGray: CGFloat = 0.9,
        headerBadgeGray: CGFloat? = nil  // 模拟状态栏时钟变化:页眉右侧画一小块不同灰度
    ) -> UIImage {
        let width = world.size.width
        let height = headerHeight + contentHeight + footerHeight
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            // 内容区
            world.draw(at: CGPoint(x: 0, y: headerHeight - contentTop))
            // 页眉
            ctx.cgContext.setFillColor(CGColor(gray: headerGray, alpha: 1))
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: headerHeight))
            // 模拟时钟区域变化(页眉内约 12% 宽的小块)
            if let badge = headerBadgeGray {
                ctx.cgContext.setFillColor(CGColor(gray: badge, alpha: 1))
                ctx.cgContext.fill(
                    CGRect(x: width - width * 0.12 - 8, y: 12, width: width * 0.12, height: 24))
            }
            // 页脚
            ctx.cgContext.setFillColor(CGColor(gray: footerGray, alpha: 1))
            ctx.cgContext.fill(
                CGRect(x: 0, y: height - footerHeight, width: width, height: footerHeight))
        }
    }

    /// 读取图片某像素的灰度值(0~1),用于渲染结果断言
    static func pixelGray(in image: CGImage, x: Int, y: Int) -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 1)
        let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return CGFloat(pixel[0]) / 255.0
    }
}
