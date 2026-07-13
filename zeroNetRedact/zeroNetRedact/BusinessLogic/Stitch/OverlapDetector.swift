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

    /// 固定页眉/页脚检测结果(单位:指纹行)
    struct FixedRegions: Equatable {
        var headerRows: Int
        var footerRows: Int
    }

    /// 检测全组截图共有的固定页眉/页脚行数。
    /// 以第一张为参照,某行在所有图中截尾相似度均 ≥ 阈值则计入固定区;
    /// 固定区上限为最矮图高的 25%。
    static func detectFixedRegions(_ fingerprints: [[[Float]]]) -> FixedRegions {
        guard fingerprints.count >= 2,
            let minRows = fingerprints.map({ $0.count }).min(), minRows > 0
        else { return FixedRegions(headerRows: 0, footerRows: 0) }

        let maxRegion = Int(Double(minRows) * maxFixedRegionRatio)
        let reference = fingerprints[0]

        var header = 0
        while header < maxRegion {
            let row = reference[header]
            let allMatch = fingerprints.dropFirst().allSatisfy {
                rowSimilarity(row, $0[header], trimRatio: fixedRowTrimRatio)
                    >= fixedRowThreshold
            }
            if !allMatch { break }
            header += 1
        }

        var footer = 0
        while footer < maxRegion {
            let row = reference[reference.count - 1 - footer]
            let allMatch = fingerprints.dropFirst().allSatisfy {
                rowSimilarity(row, $0[$0.count - 1 - footer], trimRatio: fixedRowTrimRatio)
                    >= fixedRowThreshold
            }
            if !allMatch { break }
            footer += 1
        }
        return FixedRegions(headerRows: header, footerRows: footer)
    }

    /// 单个拼缝的检测结果
    struct SeamResult: Equatable {
        /// 下图内容区顶部应额外裁剪的行数(指纹行,不含页眉)
        var overlapRows: Int
        /// 匹配置信度 0~1;低于阈值时 overlapRows 为 0
        var confidence: Float
    }

    /// 在上图内容区中滑动搜索"下图内容区开头探针条"的最佳匹配位置。
    /// 匹配成功则重叠 = 上图内容区自匹配点到底部的行数,应从下图顶部裁掉。
    static func findOverlap(
        upper: [[Float]], lower: [[Float]], fixed: FixedRegions
    ) -> SeamResult {
        let none = SeamResult(overlapRows: 0, confidence: 0)
        guard upper.count > fixed.headerRows + fixed.footerRows,
            lower.count > fixed.headerRows + fixed.footerRows
        else { return none }

        let upperContent = Array(upper[fixed.headerRows..<(upper.count - fixed.footerRows)])
        let lowerContent = Array(lower[fixed.headerRows..<(lower.count - fixed.footerRows)])
        let probeCount = min(maxProbeRows, lowerContent.count / 4)
        guard probeCount >= 8, upperContent.count > probeCount else { return none }

        let probe = Array(lowerContent.prefix(probeCount))
        var bestScore: Float = 0
        var bestStart = -1
        for start in stride(from: upperContent.count - probeCount, through: 0, by: -1) {
            var score: Float = 0
            for i in 0..<probeCount {
                score += rowSimilarity(probe[i], upperContent[start + i])
            }
            score /= Float(probeCount)
            if score > bestScore {
                bestScore = score
                bestStart = start
            }
        }
        guard bestScore >= seamConfidenceThreshold, bestStart >= 0 else { return none }
        return SeamResult(overlapRows: upperContent.count - bestStart, confidence: bestScore)
    }

    /// 计算整组图的拼接方案。
    /// fingerprints 基于降采样图;裁剪值按 (原图高 / 指纹行数) 映射回原图像素。
    static func computePlan(fingerprints: [[[Float]]], pixelSizes: [CGSize]) -> StitchPlan {
        precondition(fingerprints.count == pixelSizes.count)
        guard fingerprints.count >= 2 else {
            return StitchPlan(items: pixelSizes.map { StitchItem(pixelSize: $0) })
        }
        let fixed = detectFixedRegions(fingerprints)
        var items = [StitchItem]()
        items.reserveCapacity(fingerprints.count)

        for i in 0..<fingerprints.count {
            let rows = fingerprints[i].count
            guard rows > 0 else {
                items.append(StitchItem(pixelSize: pixelSizes[i]))
                continue
            }
            let scale = pixelSizes[i].height / CGFloat(rows)
            var item = StitchItem(pixelSize: pixelSizes[i])

            // 非首张:裁固定页眉 + 与上一张的重叠区
            if i > 0 {
                let seam = findOverlap(
                    upper: fingerprints[i - 1], lower: fingerprints[i], fixed: fixed)
                let cropRows = fixed.headerRows + seam.overlapRows
                item.seamConfidence = seam.confidence
                // 保底:至少保留 10% 内容,防御异常匹配
                item.cropTop = min(CGFloat(cropRows) * scale, pixelSizes[i].height * 0.9)
            }
            // 非末张:裁固定页脚
            if i < fingerprints.count - 1 {
                item.cropBottom = CGFloat(fixed.footerRows) * scale
            }
            items.append(item)
        }
        return StitchPlan(items: items)
    }
}
