//
//  StitchModels.swift
//  ZeroNet Redact
//
//  多图拼接数据模型
//

import CoreGraphics
import Foundation

/// 单张源图在拼接中的裁剪配置(所有值为该图原始像素)
struct StitchItem: Equatable {
    /// 原图像素尺寸
    let pixelSize: CGSize
    /// 顶部裁剪像素(含固定页眉与上一张的重叠区)
    var cropTop: CGFloat = 0
    /// 底部裁剪像素(固定页脚)
    var cropBottom: CGFloat = 0
    /// 与上一张图拼缝的置信度;第一张恒为 1,0 表示检测失败已降级为直接堆叠
    var seamConfidence: Float = 1.0

    /// 裁剪后参与拼接的内容高度
    var contentHeight: CGFloat { max(0, pixelSize.height - cropTop - cropBottom) }
}

/// 一次拼接的完整方案(算法产出,用户可修改)
struct StitchPlan: Equatable {
    var items: [StitchItem]
    /// 超出像素上限时的整体缩放系数(≤1),由渲染器计算
    var outputScale: CGFloat = 1.0
}
