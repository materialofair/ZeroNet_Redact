//
//  OverlapDetector.swift
//  ZeroNet Redact
//
//  拼接重叠检测:行指纹 + 固定页眉/页脚识别 + 相邻图重叠搜索
//  全部为纯函数,在降采样图上运算,可独立单测
//

import CoreGraphics
import Foundation

enum OverlapDetector {

    /// 每行采样点数
    static let samplesPerRow = 32
    /// 固定页眉/页脚行判定阈值(用截尾相似度,容忍状态栏时钟变化)
    static let fixedRowThreshold: Float = 0.95
    /// 截尾比例:丢弃差异最大的 25% 采样点
    static let fixedRowTrimRatio: Double = 0.25
    /// 拼缝置信度阈值,低于则降级为直接堆叠
    static let seamConfidenceThreshold: Float = 0.92
    /// 页眉/页脚最大占图高比例
    static let maxFixedRegionRatio = 0.25
    /// 重叠搜索探针条最大行数
    static let maxProbeRows = 48

    /// 从 CGImage 提取行指纹:渲染为 8-bit 灰度位图后,每行等距采样 samplesPerRow 个点
    static func rowFingerprints(of image: CGImage) -> [[Float]] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard
            let ctx = CGContext(
                data: &pixels, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let step = max(1, width / samplesPerRow)
        var result = [[Float]]()
        result.reserveCapacity(height)
        for row in 0..<height {
            var fp = [Float]()
            fp.reserveCapacity(samplesPerRow)
            var x = step / 2
            while x < width && fp.count < samplesPerRow {
                fp.append(Float(pixels[row * width + x]) / 255.0)
                x += step
            }
            result.append(fp)
        }
        return result
    }

    /// 两行指纹相似度 = 1 - 平均绝对差
    /// - Parameter trimRatio: 截尾比例,丢弃差异最大的一部分采样点后再取均值,
    ///   用于容忍状态栏时钟等局部变化;0 为普通均值
    static func rowSimilarity(_ a: [Float], _ b: [Float], trimRatio: Double = 0) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var diffs = [Float]()
        diffs.reserveCapacity(a.count)
        for i in 0..<a.count { diffs.append(abs(a[i] - b[i])) }
        if trimRatio > 0 {
            diffs.sort()
            let keep = max(1, Int(Double(diffs.count) * (1 - trimRatio)))
            diffs = Array(diffs.prefix(keep))
        }
        let mean = diffs.reduce(0, +) / Float(diffs.count)
        return 1 - mean
    }
}
