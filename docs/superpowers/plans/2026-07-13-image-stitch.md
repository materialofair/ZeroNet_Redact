# 多图拼接长图功能 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户从相册多选 2–20 张截图,自动检测重叠竖向拼接为一张长图,长图进入现有加密导入管线后可用现有编辑器脱敏;免费用户单次限 4 张并计每日图片配额。

**Architecture:** 纯算法层(`OverlapDetector` 行指纹匹配)+ 渲染层(`StitchRenderer` 单上下文逐张绘制)+ 编排层(`StitchEngine` ImageIO 降采样)全部为可单测的无 UI 代码;UI 层(`StitchViewModel` + `StitchEditorView`)通过 `ImportSource.imageData` 接入现有 `ImportManager`,不改动编辑器/存储/加密。另对 `ImageOCRRecognizer` 增加大图分块路径、对 `ImageImportProcessor` 做 ImageIO 降采样修复,使长图可被 AI 检测且导入不再整图解码。

**Tech Stack:** Swift 5 / SwiftUI / CoreGraphics / ImageIO / Vision / XCTest。设计文档:仓库根 `IMAGE_STITCH_PLAN.md`(已批准)。

## Global Constraints

- 最低部署目标 iOS 26.1,纯 SwiftUI,MVVM + BusinessLogic 单例分层。
- Xcode 工程使用 fileSystemSynchronized groups:**新 .swift 文件放进对应目录即自动加入 target,无需改 pbxproj**。App 代码根:`zeroNetRedact/zeroNetRedact/`;测试根:`zeroNetRedact/zeroNetRedactTests/`。
- 测试命令(在仓库根执行;首跑会启动模拟器,较慢):
  `xcodebuild test -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:'zeroNetRedactTests/<测试类名>' 2>&1 | tail -20`
- 输出上限(来自设计文档,硬约束):总像素 ≤ 30_000_000;高度 ≤ 65_000px;超限整体等比缩放;导出 JPEG q0.9。
- 免费限制:单次拼接 ≤ 4 张;生成长图计 1 次每日图片配额(`UsageTracker.canExportImage()`/`recordImageExport()`);付费判定统一走 `AppState.shared.hasUnlimitedAccess`;触发付费弹 `PremiumView()`(无参)。付费上限 20 张。
- 所有用户可见文案必须同时加入 `zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings` 与 `en.lproj/Localizable.strings`(旧式 .strings,键名对齐)。
- 遵守现有代码风格:中文注释、`NSLocalizedString("key", comment: "")` 裸键、print 日志带 emoji 前缀。
- 每个 Task 结束必须 commit,消息格式与仓库一致(`feat:`/`fix:`/`test:` 前缀),结尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。

---

### Task 1: StitchModels + 行指纹提取

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/StitchModels.swift`
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/OverlapDetector.swift`
- Create: `zeroNetRedact/zeroNetRedactTests/StitchTestImages.swift`(测试图片工厂,后续 Task 复用)
- Test: `zeroNetRedact/zeroNetRedactTests/OverlapDetectorTests.swift`

**Interfaces:**
- Produces: `StitchItem`(`pixelSize/cropTop/cropBottom/seamConfidence/contentHeight`)、`StitchPlan`(`items/outputScale`)、`OverlapDetector.rowFingerprints(of: CGImage) -> [[Float]]`、`OverlapDetector.rowSimilarity(_:_:trimRatio:) -> Float`、测试工厂 `StitchTestImages.world/screenshot/pixelGray`。

- [ ] **Step 1: 写测试图片工厂**(无断言,是后续所有测试的地基)

```swift
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
```

- [ ] **Step 2: 写失败测试**

```swift
//
//  OverlapDetectorTests.swift
//  zeroNetRedactTests
//

import XCTest

@testable import zeroNetRedact

final class OverlapDetectorTests: XCTestCase {

    // MARK: 行指纹

    func testRowFingerprintsShapeAndValues() {
        let world = StitchTestImages.world(width: 390, height: 400)
        let fps = OverlapDetector.rowFingerprints(of: world.cgImage!)

        XCTAssertEqual(fps.count, 400, "每个像素行一条指纹")
        XCTAssertEqual(fps[0].count, OverlapDetector.samplesPerRow)
        // 纯色横纹:同一行内所有采样值相同
        let first = fps[10][0]
        XCTAssertTrue(fps[10].allSatisfy { abs($0 - first) < 0.02 })
        // 同一条纹内的两行指纹一致,跨条纹的两行不一致
        XCTAssertGreaterThan(OverlapDetector.rowSimilarity(fps[0], fps[7]), 0.98)
        var foundDifferent = false
        for row in stride(from: 8, to: 400, by: 8)
        where OverlapDetector.rowSimilarity(fps[0], fps[row]) < 0.9 {
            foundDifferent = true
            break
        }
        XCTAssertTrue(foundDifferent, "不同条纹应产生不同指纹")
    }

    func testRowSimilarityTrimmedIgnoresLocalChange() {
        var a = [Float](repeating: 0.5, count: 32)
        var b = a
        // 模拟状态栏时钟:32 个采样点中 4 个突变
        for i in 27..<31 { b[i] = 1.0 }
        XCTAssertLessThan(OverlapDetector.rowSimilarity(a, b), 0.95, "普通相似度应被拉低")
        XCTAssertGreaterThan(
            OverlapDetector.rowSimilarity(a, b, trimRatio: 0.25), 0.99,
            "截尾相似度应忽略局部突变")
        a = []; b = []
        XCTAssertEqual(OverlapDetector.rowSimilarity(a, b), 0, "空指纹相似度为 0")
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `xcodebuild test -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:'zeroNetRedactTests/OverlapDetectorTests' 2>&1 | tail -20`
Expected: **编译失败**,`cannot find 'OverlapDetector' in scope`

- [ ] **Step 4: 写模型与指纹实现**

`StitchModels.swift`:

```swift
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
```

`OverlapDetector.swift`(本 Task 只实现指纹与相似度,其余函数后续 Task 补):

```swift
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
```

- [ ] **Step 5: 运行测试确认通过**

Run: 同 Step 3 命令
Expected: `Test Suite 'OverlapDetectorTests' passed`,2 个用例全过

- [ ] **Step 6: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/ zeroNetRedact/zeroNetRedactTests/StitchTestImages.swift zeroNetRedact/zeroNetRedactTests/OverlapDetectorTests.swift
git commit -m "feat: Add stitch models and row-fingerprint extraction

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: 固定页眉/页脚检测

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/OverlapDetector.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/OverlapDetectorTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `rowFingerprints`/`rowSimilarity`
- Produces: `OverlapDetector.FixedRegions(headerRows:footerRows:)`、`OverlapDetector.detectFixedRegions(_ fingerprints: [[[Float]]]) -> FixedRegions`

- [ ] **Step 1: 追加失败测试**(加到 `OverlapDetectorTests.swift`)

```swift
    // MARK: 固定页眉/页脚检测

    /// 三张截图共享 60px 页眉、80px 页脚(页眉带"时钟变化"),内容各不相同
    func testDetectFixedRegionsWithClockTolerance() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let shots = [0.0, 500.0, 1100.0].enumerated().map { i, top in
            StitchTestImages.screenshot(
                from: world, contentTop: top, contentHeight: 700,
                headerBadgeGray: 0.3 + CGFloat(i) * 0.2)  // 每张"时钟"都不同
        }
        let fps = shots.map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)

        XCTAssertEqual(Double(fixed.headerRows), 60, accuracy: 10, "页眉约 60 行(容忍条纹边界)")
        XCTAssertEqual(Double(fixed.footerRows), 80, accuracy: 10, "页脚约 80 行")
    }

    /// 无固定区的两张图(纯内容,页眉页脚高度为 0)
    func testDetectFixedRegionsNoneWhenContentDiffers() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let a = StitchTestImages.screenshot(
            from: world, contentTop: 0, contentHeight: 700, headerHeight: 0, footerHeight: 0)
        let b = StitchTestImages.screenshot(
            from: world, contentTop: 900, contentHeight: 700, headerHeight: 0, footerHeight: 0)
        let fps = [a, b].map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)

        XCTAssertLessThan(fixed.headerRows, 16, "无共同页眉时应接近 0")
        XCTAssertLessThan(fixed.footerRows, 16)
    }

    /// 固定区上限:两张完全相同的图,固定区不得超过图高的 25%
    func testDetectFixedRegionsCapped() {
        let world = StitchTestImages.world(width: 390, height: 800)
        let fps = [world, world].map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)

        XCTAssertLessThanOrEqual(fixed.headerRows, 200)
        XCTAssertLessThanOrEqual(fixed.footerRows, 200)
    }
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: Task 1 Step 3 同命令
Expected: 编译失败,`type 'OverlapDetector' has no member 'detectFixedRegions'`

- [ ] **Step 3: 实现**(追加到 `OverlapDetector.swift`)

```swift
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: 同上
Expected: `OverlapDetectorTests` 5 个用例全过

- [ ] **Step 5: Commit**

```bash
git add -u && git add zeroNetRedact/zeroNetRedactTests/
git commit -m "feat: Detect fixed header/footer regions across screenshots

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: 重叠搜索 + 整组拼接方案

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/OverlapDetector.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/OverlapDetectorTests.swift`

**Interfaces:**
- Consumes: Task 1/2 全部
- Produces: `OverlapDetector.SeamResult(overlapRows:confidence:)`、`findOverlap(upper:lower:fixed:) -> SeamResult`、`computePlan(fingerprints:pixelSizes:) -> StitchPlan`

- [ ] **Step 1: 追加失败测试**

```swift
    // MARK: 重叠搜索与整组方案

    /// 两张截图内容区重叠 204px,应检出并给出高置信度
    func testFindOverlapKnownOffset() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let a = StitchTestImages.screenshot(from: world, contentTop: 0, contentHeight: 704)
        let b = StitchTestImages.screenshot(from: world, contentTop: 500, contentHeight: 704)
        let fps = [a, b].map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)
        let seam = OverlapDetector.findOverlap(upper: fps[0], lower: fps[1], fixed: fixed)

        // 重叠 = 704 - 500 = 204 行(容忍固定区检测误差)
        XCTAssertEqual(Double(seam.overlapRows), 204, accuracy: 12)
        XCTAssertGreaterThanOrEqual(seam.confidence, OverlapDetector.seamConfidenceThreshold)
    }

    /// 两张无重叠的截图:置信度应低于阈值,降级为堆叠(overlapRows = 0)
    func testFindOverlapNoneWhenDisjoint() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let a = StitchTestImages.screenshot(from: world, contentTop: 0, contentHeight: 704)
        let b = StitchTestImages.screenshot(from: world, contentTop: 1800, contentHeight: 704)
        let fps = [a, b].map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let fixed = OverlapDetector.detectFixedRegions(fps)
        let seam = OverlapDetector.findOverlap(upper: fps[0], lower: fps[1], fixed: fixed)

        XCTAssertEqual(seam.overlapRows, 0)
        XCTAssertEqual(seam.confidence, 0)
    }

    /// 三张连续滚动截图的整组方案:
    /// 首张保留页眉、末张保留页脚、中间图裁双侧,重叠计入 cropTop
    func testComputePlanThreeScreenshots() {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let tops: [CGFloat] = [0, 500, 1000]
        let shots = tops.map {
            StitchTestImages.screenshot(from: world, contentTop: $0, contentHeight: 704)
        }
        let fps = shots.map { OverlapDetector.rowFingerprints(of: $0.cgImage!) }
        let sizes = shots.map { CGSize(width: $0.size.width, height: $0.size.height) }
        let plan = OverlapDetector.computePlan(fingerprints: fps, pixelSizes: sizes)

        XCTAssertEqual(plan.items.count, 3)
        // 首张:保留页眉(cropTop 0),裁页脚(约 80)
        XCTAssertEqual(plan.items[0].cropTop, 0)
        XCTAssertEqual(Double(plan.items[0].cropBottom), 80, accuracy: 12)
        // 中间图:cropTop ≈ 页眉 60 + 重叠 204 = 264,cropBottom ≈ 80
        XCTAssertEqual(Double(plan.items[1].cropTop), 264, accuracy: 20)
        XCTAssertEqual(Double(plan.items[1].cropBottom), 80, accuracy: 12)
        // 末张:cropTop ≈ 264,保留页脚(cropBottom 0)
        XCTAssertEqual(Double(plan.items[2].cropTop), 264, accuracy: 20)
        XCTAssertEqual(plan.items[2].cropBottom, 0)
        // 拼出的总内容应连续覆盖 world 的 [0, 1704+60+80 区间内容),即无缝
        XCTAssertGreaterThanOrEqual(plan.items[1].seamConfidence, 0.92)
        XCTAssertGreaterThanOrEqual(plan.items[2].seamConfidence, 0.92)
    }

    /// 单张图:方案退化为原样保留
    func testComputePlanSingleImage() {
        let world = StitchTestImages.world(width: 390, height: 800)
        let fps = [OverlapDetector.rowFingerprints(of: world.cgImage!)]
        let plan = OverlapDetector.computePlan(
            fingerprints: fps, pixelSizes: [CGSize(width: 390, height: 800)])

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items[0].cropTop, 0)
        XCTAssertEqual(plan.items[0].cropBottom, 0)
    }
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: Task 1 Step 3 同命令
Expected: 编译失败,`no member 'findOverlap'`

- [ ] **Step 3: 实现**(追加到 `OverlapDetector.swift`)

```swift
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: 同上
Expected: `OverlapDetectorTests` 9 个用例全过

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "feat: Add overlap search and whole-group stitch plan computation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: StitchRenderer(尺寸上限 + 内存安全渲染)

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/StitchRenderer.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/StitchRendererTests.swift`

**Interfaces:**
- Consumes: `StitchPlan`/`StitchItem`
- Produces: `StitchImageProvider`(协议,`loadCGImage(at:) throws -> CGImage`)、`StitchRenderer.outputSize(for:) -> (size: CGSize, scale: CGFloat)`、`StitchRenderer.render(plan:provider:) throws -> Data`、`StitchRenderError`

- [ ] **Step 1: 写失败测试**

```swift
//
//  StitchRendererTests.swift
//  zeroNetRedactTests
//

import UIKit
import XCTest

@testable import zeroNetRedact

/// 直接持有 UIImage 的测试 provider
private struct ArrayProvider: StitchImageProvider {
    let images: [UIImage]
    func loadCGImage(at index: Int) throws -> CGImage {
        guard let cg = images[index].cgImage else {
            throw StitchRenderError.imageLoadFailed(index: index)
        }
        return cg
    }
}

final class StitchRendererTests: XCTestCase {

    func testOutputSizeSimpleStack() {
        let plan = StitchPlan(items: [
            StitchItem(pixelSize: CGSize(width: 390, height: 844)),
            StitchItem(pixelSize: CGSize(width: 390, height: 844)),
        ])
        let (size, scale) = StitchRenderer.outputSize(for: plan)
        XCTAssertEqual(scale, 1.0)
        XCTAssertEqual(size, CGSize(width: 390, height: 1688))
    }

    func testOutputSizeAppliesCrops() {
        var a = StitchItem(pixelSize: CGSize(width: 390, height: 844))
        a.cropBottom = 80
        var b = StitchItem(pixelSize: CGSize(width: 390, height: 844))
        b.cropTop = 264
        let (size, _) = StitchRenderer.outputSize(for: StitchPlan(items: [a, b]))
        XCTAssertEqual(size.height, 844 - 80 + 844 - 264)
    }

    func testOutputSizeCappedAt30MPixels() {
        // 2 × (1170×20000) = 46.8M 像素,超 3000 万上限 → 等比缩放
        let plan = StitchPlan(items: [
            StitchItem(pixelSize: CGSize(width: 1170, height: 20000)),
            StitchItem(pixelSize: CGSize(width: 1170, height: 20000)),
        ])
        let (size, scale) = StitchRenderer.outputSize(for: plan)
        XCTAssertLessThan(scale, 1.0)
        XCTAssertLessThanOrEqual(size.width * size.height, StitchRenderer.maxOutputPixels)
        XCTAssertGreaterThan(
            size.width * size.height, StitchRenderer.maxOutputPixels * 0.98,
            "应贴近上限而不是过度缩小")
    }

    /// 端到端:两张已知内容的图拼接后,接缝两侧像素应与源图一致
    func testRenderSeamPixelsMatchSources() throws {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let a = StitchTestImages.screenshot(from: world, contentTop: 0, contentHeight: 704)
        let b = StitchTestImages.screenshot(from: world, contentTop: 500, contentHeight: 704)

        var itemA = StitchItem(pixelSize: a.size)
        itemA.cropBottom = 80  // 裁页脚
        var itemB = StitchItem(pixelSize: b.size)
        itemB.cropTop = 60 + 204  // 裁页眉 + 重叠

        let data = try StitchRenderer.render(
            plan: StitchPlan(items: [itemA, itemB]),
            provider: ArrayProvider(images: [a, b]))
        let output = UIImage(data: data)!.cgImage!

        // 总高 = (844-80) + (844-264) = 1344
        XCTAssertEqual(output.height, 1344)
        XCTAssertEqual(output.width, 390)

        // 接缝上方 20px:应等于 world 中 y = 704-20-8=676 附近条纹
        // (A 的内容区底部,world y = 704 - 84 = ...)直接与源图 a 同位置比较
        let seamY = 844 - 80  // 输出中 A 段结束的位置
        let aGray = StitchTestImages.pixelGray(in: a.cgImage!, x: 195, y: seamY - 20)
        let outAGray = StitchTestImages.pixelGray(in: output, x: 195, y: seamY - 20)
        XCTAssertEqual(Double(outAGray), Double(aGray), accuracy: 0.06, "接缝上方来自 A")

        // 接缝下方 20px:应等于源图 b 中 cropTop+20 的像素
        let bGray = StitchTestImages.pixelGray(in: b.cgImage!, x: 195, y: 264 + 20)
        let outBGray = StitchTestImages.pixelGray(in: output, x: 195, y: seamY + 20)
        XCTAssertEqual(Double(outBGray), Double(bGray), accuracy: 0.06, "接缝下方来自 B")
    }

    func testRenderEmptyPlanThrows() {
        XCTAssertThrowsError(
            try StitchRenderer.render(
                plan: StitchPlan(items: []), provider: ArrayProvider(images: [])))
    }
}
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `xcodebuild test ... -only-testing:'zeroNetRedactTests/StitchRendererTests' 2>&1 | tail -20`(完整命令同 Task 1)
Expected: 编译失败,`cannot find 'StitchRenderer'`

- [ ] **Step 3: 实现 `StitchRenderer.swift`**

```swift
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
        let (size, _) = outputSize(for: plan)
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0,
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

                let widthScale = size.width / item.pixelSize.width
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: `StitchRendererTests` 5 个用例全过(注意 `testRenderSeamPixelsMatchSources` 的灰度断言容差 0.06 覆盖 JPEG 压缩误差;若因 JPEG 压缩偶发超差,把该测试导出改走 `UIImage(cgImage: output)` 前的无损比较——直接对 `ctx.makeImage()` 断言,渲染函数增加内部可测点不是必须,优先调大容差到 0.08)

- [ ] **Step 5: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/StitchRenderer.swift zeroNetRedact/zeroNetRedactTests/StitchRendererTests.swift
git commit -m "feat: Add memory-safe stitch renderer with 30MP output cap

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: StitchEngine(降采样加载 + 端到端编排)

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/StitchEngine.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/StitchEngineTests.swift`

**Interfaces:**
- Consumes: Task 1–4 全部
- Produces: `StitchSource`(`id/data/pixelSize/preview/fingerprints`)、`StitchEngine.makeSource(from: Data) throws -> StitchSource`、`StitchEngine.computePlan(for: [StitchSource]) -> StitchPlan`、`StitchEngine.render(plan:sources:) throws -> Data`、`StitchEngineError`

- [ ] **Step 1: 写失败测试**

```swift
//
//  StitchEngineTests.swift
//  zeroNetRedactTests
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class StitchEngineTests: XCTestCase {

    private func makeShotData(contentTop: CGFloat, world: UIImage) -> Data {
        StitchTestImages.screenshot(from: world, contentTop: contentTop, contentHeight: 704)
            .pngData()!
    }

    func testMakeSourceExtractsSizePreviewAndFingerprints() throws {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let source = try StitchEngine.makeSource(from: makeShotData(contentTop: 0, world: world))

        XCTAssertEqual(source.pixelSize, CGSize(width: 390, height: 844))
        XCTAssertLessThanOrEqual(source.preview.size.width, 750)
        XCTAssertFalse(source.fingerprints.isEmpty)
        XCTAssertEqual(source.fingerprints.count, Int(source.preview.size.height))
    }

    func testMakeSourceRejectsGarbage() {
        XCTAssertThrowsError(try StitchEngine.makeSource(from: Data([0x00, 0x01, 0x02])))
    }

    /// 端到端:两张 PNG 数据 → 方案 → 渲染,输出高度符合"页脚+页眉+重叠都被裁掉"
    func testEndToEndStitchTwoScreenshots() throws {
        let world = StitchTestImages.world(width: 390, height: 3000)
        let sources = try [0.0, 500.0].map {
            try StitchEngine.makeSource(from: makeShotData(contentTop: $0, world: world))
        }
        let plan = StitchEngine.computePlan(for: sources)
        XCTAssertGreaterThanOrEqual(plan.items[1].seamConfidence, 0.92)

        let data = try StitchEngine.render(plan: plan, sources: sources)
        let output = UIImage(data: data)!
        // 期望高度 = (844-80) + (844-60-204) = 1344,容忍检测量化误差
        XCTAssertEqual(Double(output.size.height), 1344, accuracy: 25)
        XCTAssertEqual(output.size.width, 390)
    }
}
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `... -only-testing:'zeroNetRedactTests/StitchEngineTests'`
Expected: 编译失败,`cannot find 'StitchEngine'`

- [ ] **Step 3: 实现 `StitchEngine.swift`**

```swift
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
```

注意:`makeSource` 测试里 390×844 的 PNG,`maxPixel = max(750, 750×844/390)` 大于原图尺寸,ImageIO 不会放大 → preview 即原尺寸,`preview.size.width == 390 ≤ 750` 断言成立。

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: `StitchEngineTests` 3 个用例全过

- [ ] **Step 5: 全量跑一次拼接相关测试防回归**

Run: `... -only-testing:'zeroNetRedactTests/OverlapDetectorTests' -only-testing:'zeroNetRedactTests/StitchRendererTests' -only-testing:'zeroNetRedactTests/StitchEngineTests'`
Expected: 全过

- [ ] **Step 6: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Stitch/StitchEngine.swift zeroNetRedact/zeroNetRedactTests/StitchEngineTests.swift
git commit -m "feat: Add stitch engine with ImageIO downsampled loading

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 长图分块 OCR

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition/TextRecognizer.swift`(`ImageOCRRecognizer` 类,约 L143–207)
- Test: `zeroNetRedact/zeroNetRedactTests/LongImageOCRTests.swift`

**Interfaces:**
- Consumes: 现有 `ImageOCRRecognizer.recognizeText(in:fileType:)`、`RecognizedText`、`TextRecognizer.detectSensitiveRegions`
- Produces: 行为增强(高 > 8192px 分块识别),对外接口不变。新增内部常量 `tileHeightThreshold/tileHeight/tileOverlap` 与私有方法 `performVisionOCR(on:)`/`recognizeTiled(cgImage:)`/`dedupeAcrossTiles(_:)`

- [ ] **Step 1: 写失败测试**(参考现有 `SensitiveDetectionTests` 的渲染方式;此测试跑 accurate OCR × 多分块,预计 1–3 分钟,属正常)

```swift
//
//  LongImageOCRTests.swift
//  zeroNetRedactTests
//
//  验证超长图(> 8192px)分块 OCR:头/中/尾的敏感信息全部检出且坐标正确
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class LongImageOCRTests: XCTestCase {

    /// 渲染 1170×20000 长图,敏感信息分布在头/中/尾
    private func makeLongImage() -> Data {
        let size = CGSize(width: 1170, height: 20000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 40, weight: .medium),
            .foregroundColor: UIColor.black,
        ]
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ("联系电话: 13812345678" as NSString).draw(
                at: CGPoint(x: 60, y: 500), withAttributes: attrs)
            ("Email: test@example.com" as NSString).draw(
                at: CGPoint(x: 60, y: 10000), withAttributes: attrs)
            ("身份证号: 110101199003074518" as NSString).draw(
                at: CGPoint(x: 60, y: 19500), withAttributes: attrs)
        }
        return image.pngData()!
    }

    func testTiledOCRDetectsAllRegionsInLongImage() async throws {
        let data = makeLongImage()
        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: data, fileType: .image)
        XCTAssertFalse(texts.isEmpty, "长图 OCR 未识别到任何文本")

        let regions = recognizer.detectSensitiveInfo(in: texts)
        let types = Set(regions.map(\.type))
        XCTAssertTrue(types.contains(.phoneNumber), "未检出头部手机号")
        XCTAssertTrue(types.contains(.email), "未检出中部邮箱")
        XCTAssertTrue(types.contains(.idCard), "未检出尾部身份证号")

        // 坐标应已映射回整图归一化空间(Vision 原点在左下):
        // 头部(y≈500/20000)的归一化 y 应接近 1,尾部接近 0
        let phone = regions.first { $0.type == .phoneNumber }!
        let idCard = regions.first { $0.type == .idCard }!
        XCTAssertGreaterThan(phone.boundingBox.midY, 0.9)
        XCTAssertLessThan(idCard.boundingBox.midY, 0.1)
        // 归一化高度应极小(40px 文字 / 20000px 高)
        XCTAssertLessThan(phone.boundingBox.height, 0.01)
    }

    /// 短图不受影响:走原单请求路径,行为与既有 SensitiveDetectionTests 一致
    func testShortImageStillWorks() async throws {
        let size = CGSize(width: 800, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ("Email: test@example.com" as NSString).draw(
                at: CGPoint(x: 40, y: 150),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black,
                ])
        }
        let recognizer = ImageOCRRecognizer()
        let texts = try await recognizer.recognizeText(in: image.pngData()!, fileType: .image)
        let regions = recognizer.detectSensitiveInfo(in: texts)
        XCTAssertTrue(regions.contains { $0.type == .email })
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `... -only-testing:'zeroNetRedactTests/LongImageOCRTests'`
Expected: `testTiledOCRDetectsAllRegionsInLongImage` **失败**(现有实现把 20000px 整图丢给单个 Vision 请求,或三处不全检出,或超时;`testShortImageStillWorks` 应通过)。若整图路径侥幸全检出,该测试对坐标的断言仍可作为分块后的回归保障——继续 Step 3。

- [ ] **Step 3: 实现分块**(修改 `ImageOCRRecognizer`)

把现有 `recognizeWithVision(data:)` 中 `withCheckedThrowingContinuation` 整段抽为 `performVisionOCR(on cgImage: CGImage)`(内容原样保留,含全部 request 配置与 customWords),然后:

```swift
class ImageOCRRecognizer: TextRecognition {

    /// 超过该高度启用分块识别
    static let tileHeightThreshold = 8192
    /// 分块高度
    static let tileHeight = 4096
    /// 相邻分块重叠(避免文字被切断漏识)
    static let tileOverlap = 400

    func recognizeText(in data: Data, fileType: FileType) async throws -> [RecognizedText] {
        return try await recognizeWithVision(data: data)
    }

    private func recognizeWithVision(data: Data) async throws -> [RecognizedText] {
        guard let image = UIImage(data: data),
            let cgImage = image.cgImage
        else {
            throw RecognitionError.invalidImageData
        }
        if cgImage.height <= Self.tileHeightThreshold {
            return try await performVisionOCR(on: cgImage)
        }
        return try await recognizeTiled(cgImage: cgImage)
    }

    /// 长图分块识别:按 tileHeight 高、tileOverlap 重叠切片,
    /// 每片独立 OCR 后把归一化坐标映射回整图空间,再跨片去重
    private func recognizeTiled(cgImage: CGImage) async throws -> [RecognizedText] {
        let fullHeight = CGFloat(cgImage.height)
        var all: [RecognizedText] = []
        var yTop = 0
        while yTop < cgImage.height {
            let tileH = min(Self.tileHeight, cgImage.height - yTop)
            let rect = CGRect(x: 0, y: yTop, width: cgImage.width, height: tileH)
            guard let tile = cgImage.cropping(to: rect) else { break }
            let texts = try await performVisionOCR(on: tile)

            // Vision 坐标原点在左下:tile 底边距整图底边的偏移
            let tileBottomOffset = fullHeight - CGFloat(yTop + tileH)
            for t in texts {
                let box = t.boundingBox
                let mapped = CGRect(
                    x: box.origin.x,
                    y: (tileBottomOffset + box.origin.y * CGFloat(tileH)) / fullHeight,
                    width: box.width,
                    height: box.height * CGFloat(tileH) / fullHeight)
                all.append(
                    RecognizedText(
                        text: t.text, boundingBox: mapped,
                        confidence: t.confidence, pageIndex: t.pageIndex))
            }
            if yTop + tileH >= cgImage.height { break }
            yTop += Self.tileHeight - Self.tileOverlap
        }
        print("🔍 ImageOCRRecognizer: 分块 OCR 完成,合并前 \(all.count) 段文本")
        return dedupeAcrossTiles(all)
    }

    /// 跨片去重:同文本且区域相交视为重复,保留置信度高者
    private func dedupeAcrossTiles(_ texts: [RecognizedText]) -> [RecognizedText] {
        var result: [RecognizedText] = []
        for t in texts {
            if let i = result.firstIndex(where: {
                $0.text == t.text && $0.boundingBox.intersects(t.boundingBox)
            }) {
                if t.confidence > result[i].confidence { result[i] = t }
            } else {
                result.append(t)
            }
        }
        return result
    }

    /// 单张(或单片)Vision OCR —— 原 recognizeWithVision 的 continuation 逻辑原样搬入
    private func performVisionOCR(on cgImage: CGImage) async throws -> [RecognizedText] {
        // ……原有 withCheckedThrowingContinuation + VNRecognizeTextRequest 配置全部保留……
    }

    func detectSensitiveInfo(in texts: [RecognizedText]) -> [SensitiveRegion] {
        return TextRecognizer.shared.detectSensitiveRegions(in: texts)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `... -only-testing:'zeroNetRedactTests/LongImageOCRTests' -only-testing:'zeroNetRedactTests/SensitiveDetectionTests'`
Expected: 新旧 OCR 测试全过(旧 `SensitiveDetectionTests` 验证抽取 `performVisionOCR` 未破坏短图路径)

- [ ] **Step 5: Commit**

```bash
git add -u && git add zeroNetRedact/zeroNetRedactTests/LongImageOCRTests.swift
git commit -m "feat: Tile-based OCR for images taller than 8192px

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 导入处理器 ImageIO 降采样(大图导入不再整图解码)

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Import/FileImportProcessor.swift`(`ImageImportProcessor.generateThumbnail`/`extractMetadata`,L67–92)
- Test: `zeroNetRedact/zeroNetRedactTests/ImageImportProcessorTests.swift`

**Interfaces:**
- Consumes: 现有 `FileImportProcessor` 协议
- Produces: 行为等价的实现(缩略图 ≤200px、metadata 的 width/height/orientation 与 `UIImage(data:)` 语义一致),新增 `UIImage.Orientation(exifOrientation:)` 内部映射

- [ ] **Step 1: 写失败测试**

```swift
//
//  ImageImportProcessorTests.swift
//  zeroNetRedactTests
//

import UIKit
import XCTest

@testable import zeroNetRedact

final class ImageImportProcessorTests: XCTestCase {

    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.pngData()!
    }

    func testThumbnailMaxDimension200() async throws {
        let processor = ImageImportProcessor()
        let thumbData = try await processor.generateThumbnail(
            from: makeImageData(width: 1170, height: 2532))
        let thumb = UIImage(data: thumbData)!
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), 200)
        XCTAssertEqual(
            thumb.size.width / thumb.size.height, 1170.0 / 2532.0, accuracy: 0.05,
            "保持宽高比")
    }

    func testMetadataMatchesPixelDimensions() {
        let processor = ImageImportProcessor()
        let metadata = processor.extractMetadata(from: makeImageData(width: 640, height: 480))
        XCTAssertEqual(metadata["width"] as? Int, 640)
        XCTAssertEqual(metadata["height"] as? Int, 480)
        XCTAssertEqual(metadata["orientation"] as? Int, UIImage.Orientation.up.rawValue)
    }

    func testMetadataGarbageDataReturnsEmpty() {
        let processor = ImageImportProcessor()
        XCTAssertTrue(processor.extractMetadata(from: Data([0xFF, 0x00])).isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认现状**

Run: `... -only-testing:'zeroNetRedactTests/ImageImportProcessorTests'`
Expected: **通过**(旧实现语义相同——这是等价重构的基线;测试先固定行为,再换实现)

- [ ] **Step 3: 替换实现**(修改 `ImageImportProcessor`,并在文件顶部 `import ImageIO`)

```swift
    func generateThumbnail(from data: Data) async throws -> Data {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImportError.invalidImageData
        }
        // ImageIO 直接生成降采样缩略图,不解码全图(对 3000 万像素长图至关重要)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 200,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard
            let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary),
            let thumbnailData = UIImage(cgImage: thumb).pngData()
        else {
            throw ImportError.thumbnailGenerationFailed
        }
        return thumbnailData
    }

    func extractMetadata(from data: Data) -> [String: Any] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let pixelWidth = props[kCGImagePropertyPixelWidth] as? Int,
            let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
        else { return [:] }

        // 与旧实现(UIImage(data:))语义对齐:
        // width/height 为"显示尺寸"(EXIF 旋转后),orientation 为 UIImage.Orientation
        let exif = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let rotated = (5...8).contains(Int(exif))
        return [
            "width": rotated ? pixelHeight : pixelWidth,
            "height": rotated ? pixelWidth : pixelHeight,
            "orientation": UIImage.Orientation(exifOrientation: exif).rawValue,
        ]
    }
```

文件末尾追加映射扩展:

```swift
// MARK: - EXIF 方向映射

extension UIImage.Orientation {
    /// EXIF/TIFF 方向值(1~8)→ UIImage.Orientation
    init(exifOrientation: UInt32) {
        switch exifOrientation {
        case 2: self = .upMirrored
        case 3: self = .down
        case 4: self = .downMirrored
        case 5: self = .leftMirrored
        case 6: self = .right
        case 7: self = .rightMirrored
        case 8: self = .left
        default: self = .up
        }
    }
}
```

- [ ] **Step 4: 运行测试确认仍通过(等价重构完成)**

Run: 同 Step 2,另加 `-only-testing:'zeroNetRedactTests/DeleteReproTests'`(该套件走完整导入流程,防回归)
Expected: 全过

- [ ] **Step 5: Commit**

```bash
git add -u && git add zeroNetRedact/zeroNetRedactTests/ImageImportProcessorTests.swift
git commit -m "fix: Generate import thumbnails via ImageIO without full decode

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: StitchViewModel(配额门控 + 生成导入)+ 本地化键

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/Views/Stitch/StitchViewModel.swift`
- Modify: `zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings`(文件末尾追加)
- Modify: `zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings`(文件末尾追加)
- Test: `zeroNetRedact/zeroNetRedactTests/StitchViewModelTests.swift`

**Interfaces:**
- Consumes: `StitchEngine`/`StitchSource`/`StitchPlan`、`AppState.shared.hasUnlimitedAccess`、`UsageTracker.shared.canExportImage()/recordImageExport()`、`ImportManager.shared.importFile(from: .imageData(_))`
- Produces: `StitchViewModel`(`@MainActor ObservableObject`):`sources/plan/isDetecting/isRendering/showError/errorMessage/showPaywall/finishedFile`、`maxSelectionCount/canGenerate`、`loadImages(_:) async`、`setSources(_:) async`、`moveSource(fromOffsets:toOffset:) async`、`removeSource(atOffsets:) async`、`updateSeam(at:cropTop:upperCropBottom:)`、`generateAndImport() async`。常量 `freeMaxImages = 4`/`premiumMaxImages = 20`/`minImages = 2`

- [ ] **Step 1: 写失败测试**

```swift
//
//  StitchViewModelTests.swift
//  zeroNetRedactTests
//

import CoreData
import UIKit
import XCTest

@testable import zeroNetRedact

@MainActor
final class StitchViewModelTests: XCTestCase {

    private var savedPremium = false

    override func setUp() async throws {
        savedPremium = AppState.shared.isPremium
        AppState.shared.isPremium = false
        UserDefaults.standard.set(false, forKey: "reviewModeActivated")
        UsageTracker.shared.resetAllUsage()
    }

    override func tearDown() async throws {
        AppState.shared.isPremium = savedPremium
        UsageTracker.shared.resetAllUsage()
    }

    private func makeTwoSources() throws -> [StitchSource] {
        let world = StitchTestImages.world(width: 390, height: 3000)
        return try [0.0, 500.0].map { top in
            try StitchEngine.makeSource(
                from: StitchTestImages.screenshot(
                    from: world, contentTop: top, contentHeight: 704
                ).pngData()!)
        }
    }

    func testMaxSelectionCountByEntitlement() {
        AppState.shared.isPremium = false
        XCTAssertEqual(StitchViewModel().maxSelectionCount, 4)
        AppState.shared.isPremium = true
        XCTAssertEqual(StitchViewModel().maxSelectionCount, 20)
    }

    func testSetSourcesComputesPlan() async throws {
        let vm = StitchViewModel()
        await vm.setSources(try makeTwoSources())
        XCTAssertNotNil(vm.plan)
        XCTAssertEqual(vm.plan?.items.count, 2)
        XCTAssertTrue(vm.canGenerate)
    }

    func testGenerateBlockedWhenQuotaExhausted() async throws {
        // 耗尽今日 3 次图片配额
        for _ in 0..<UsageTracker.dailyImageLimit {
            UsageTracker.shared.recordImageExport()
        }
        let vm = StitchViewModel()
        await vm.setSources(try makeTwoSources())
        await vm.generateAndImport()

        XCTAssertTrue(vm.showPaywall, "配额耗尽应弹付费页")
        XCTAssertNil(vm.finishedFile)
    }

    func testGenerateAndImportCreatesOriginalImage() async throws {
        let vm = StitchViewModel()
        await vm.setSources(try makeTwoSources())
        await vm.generateAndImport()

        XCTAssertFalse(vm.showPaywall)
        let file = try XCTUnwrap(vm.finishedFile as? OriginalImage, "应产出 OriginalImage")
        XCTAssertEqual(Int(file.width), 390)
        XCTAssertGreaterThan(Int(file.height), 1000, "长图高度应大于单张")
        XCTAssertEqual(
            UsageTracker.shared.getTodayImageExports(), 1, "免费用户生成应计 1 次配额")

        // 清理:删除本次导入的 Core Data 记录
        let context = PersistenceController.shared.container.viewContext
        context.delete(file)
        try context.save()
    }

    func testUpdateSeamMarksManualConfidence() async throws {
        let vm = StitchViewModel()
        await vm.setSources(try makeTwoSources())
        vm.updateSeam(at: 1, cropTop: 100)
        XCTAssertEqual(vm.plan?.items[1].cropTop, 100)
        XCTAssertEqual(vm.plan?.items[1].seamConfidence, 1.0, "手动调整后视为已确认")
    }
}
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `... -only-testing:'zeroNetRedactTests/StitchViewModelTests'`
Expected: 编译失败,`cannot find 'StitchViewModel'`

- [ ] **Step 3: 实现 `StitchViewModel.swift`**

```swift
//
//  StitchViewModel.swift
//  ZeroNet Redact
//
//  拼接会话 ViewModel:选图加载、方案计算、拼缝调整、配额门控与生成导入
//

import PhotosUI
import SwiftUI

@MainActor
final class StitchViewModel: ObservableObject {

    /// 免费用户单次拼接张数上限
    static let freeMaxImages = 4
    /// 付费用户单次拼接张数上限
    static let premiumMaxImages = 20
    /// 最少张数
    static let minImages = 2

    @Published private(set) var sources: [StitchSource] = []
    @Published private(set) var plan: StitchPlan?
    @Published var isDetecting = false
    @Published var isRendering = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var showPaywall = false
    @Published private(set) var finishedFile: RedactableFile?

    private let appState: AppState
    private let usageTracker: UsageTracker

    init(appState: AppState = .shared, usageTracker: UsageTracker = .shared) {
        self.appState = appState
        self.usageTracker = usageTracker
    }

    /// 相册多选上限(免费 4 / 付费 20)
    var maxSelectionCount: Int {
        appState.hasUnlimitedAccess ? Self.premiumMaxImages : Self.freeMaxImages
    }

    var canGenerate: Bool {
        sources.count >= Self.minImages && plan != nil && !isRendering
    }

    /// 从 PhotosPicker 结果加载源图(支持在已有基础上追加)
    func loadImages(_ items: [PhotosPickerItem]) async {
        isDetecting = true
        var loaded: [StitchSource] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                let source = try? StitchEngine.makeSource(from: data)
            else { continue }
            loaded.append(source)
        }
        if loaded.count < items.count {
            errorMessage = String(
                format: NSLocalizedString("import.photo.loadFailedCount", comment: ""),
                items.count - loaded.count)
            showError = true
        }
        sources.append(contentsOf: loaded)
        sources = Array(sources.prefix(maxSelectionCount))
        await recomputePlan()
        isDetecting = false
    }

    /// 测试/预览注入
    func setSources(_ new: [StitchSource]) async {
        sources = new
        await recomputePlan()
    }

    func moveSource(fromOffsets: IndexSet, toOffset: Int) async {
        sources.move(fromOffsets: fromOffsets, toOffset: toOffset)
        await recomputePlan()
    }

    func removeSource(atOffsets offsets: IndexSet) async {
        sources.remove(atOffsets: offsets)
        await recomputePlan()
    }

    /// 手动调整拼缝:cropTop 作用于第 index 张,upperCropBottom 作用于其上一张
    func updateSeam(at index: Int, cropTop: CGFloat? = nil, upperCropBottom: CGFloat? = nil) {
        guard var updated = plan, updated.items.indices.contains(index) else { return }
        if let cropTop {
            updated.items[index].cropTop = min(
                max(0, cropTop), updated.items[index].pixelSize.height - 50)
            updated.items[index].seamConfidence = 1.0  // 手动确认
        }
        if let upperCropBottom, index > 0 {
            updated.items[index - 1].cropBottom = min(
                max(0, upperCropBottom), updated.items[index - 1].pixelSize.height - 50)
        }
        plan = updated
    }

    /// 生成长图并导入(配额检查 → 后台渲染 → ImportManager 加密入库)
    func generateAndImport() async {
        guard let plan, sources.count >= Self.minImages else { return }
        guard appState.hasUnlimitedAccess || usageTracker.canExportImage() else {
            showPaywall = true
            return
        }
        isRendering = true
        defer { isRendering = false }
        do {
            let sources = self.sources
            let data = try await Task.detached(priority: .userInitiated) {
                try StitchEngine.render(plan: plan, sources: sources)
            }.value
            let file = try await ImportManager.shared.importFile(from: .imageData(data))
            if !appState.hasUnlimitedAccess {
                usageTracker.recordImageExport()
            }
            finishedFile = file
            print("🧵 StitchViewModel: 长图已生成并导入 id=\(file.id)")
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 在指纹缓存上后台重算方案(50 张以内耗时可忽略,但不阻塞主线程)
    private func recomputePlan() async {
        guard sources.count >= Self.minImages else {
            plan = nil
            return
        }
        let fps = sources.map(\.fingerprints)
        let sizes = sources.map(\.pixelSize)
        plan = await Task.detached(priority: .userInitiated) {
            OverlapDetector.computePlan(fingerprints: fps, pixelSizes: sizes)
        }.value
    }
}
```

- [ ] **Step 4: 追加本地化键**(两个文件末尾;en 为右列译文)

`zh-Hans.lproj/Localizable.strings` 追加:

```
/* Stitch - 多图拼接长图 */
"stitch.button" = "拼长图";
"stitch.title" = "拼接长图";
"stitch.detecting" = "智能拼接中…";
"stitch.generate" = "生成长图";
"stitch.generating" = "正在生成…";
"stitch.selectImages" = "选择图片";
"stitch.reorder" = "排序";
"stitch.seam.adjust" = "调整拼缝";
"stitch.seam.upperCrop" = "上图底部裁剪";
"stitch.seam.lowerCrop" = "下图顶部裁剪";
"stitch.seam.lowConfidence" = "自动拼接失败，请点击拼缝手动调整";
"stitch.done.title" = "长图已生成";
"stitch.done.message" = "已加密保存到导入列表，现在去脱敏？";
"stitch.done.redact" = "去脱敏";
"stitch.done.later" = "稍后";
"stitch.error.renderFailed" = "长图生成失败，请减少图片数量后重试";
"stitch.limit.hint" = "免费版单次最多 %d 张，升级后可拼 %d 张";
"stitch.empty.hint" = "选择 2 张以上截图，自动拼接为一张长图";
```

`en.lproj/Localizable.strings` 追加:

```
/* Stitch - Long screenshot stitching */
"stitch.button" = "Stitch";
"stitch.title" = "Stitch Long Image";
"stitch.detecting" = "Auto-stitching…";
"stitch.generate" = "Generate";
"stitch.generating" = "Generating…";
"stitch.selectImages" = "Select Images";
"stitch.reorder" = "Reorder";
"stitch.seam.adjust" = "Adjust Seam";
"stitch.seam.upperCrop" = "Crop bottom of upper image";
"stitch.seam.lowerCrop" = "Crop top of lower image";
"stitch.seam.lowConfidence" = "Auto-stitch failed. Tap the seam to adjust manually.";
"stitch.done.title" = "Long Image Created";
"stitch.done.message" = "Encrypted and saved to your import list. Redact it now?";
"stitch.done.redact" = "Redact Now";
"stitch.done.later" = "Later";
"stitch.error.renderFailed" = "Failed to generate. Try fewer images.";
"stitch.limit.hint" = "Free version stitches up to %d images. Upgrade for %d.";
"stitch.empty.hint" = "Pick 2+ screenshots to auto-stitch into one long image";
```

- [ ] **Step 5: 运行测试确认通过**

Run: 同 Step 2
Expected: `StitchViewModelTests` 5 个用例全过(注:`testGenerateAndImportCreatesOriginalImage` 会真实走加密+落盘,与现有 `DeleteReproTests` 同模式)

- [ ] **Step 6: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/Views/Stitch/ zeroNetRedact/zeroNetRedactTests/StitchViewModelTests.swift zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings
git commit -m "feat: Add stitch view model with quota gating and localized strings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: 拼接编辑 UI(StitchEditorView + SeamAdjustView + 排序)

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/Views/Stitch/StitchEditorView.swift`
- Create: `zeroNetRedact/zeroNetRedact/Views/Stitch/SeamAdjustView.swift`

**Interfaces:**
- Consumes: `StitchViewModel` 全部 API、`PremiumView()`、`DesignSystem.Colors/Gradients/Spacing/CornerRadius`
- Produces: `StitchEditorView(onRedact: (RedactableFile) -> Void)`(Task 10 从 ImportView 以 fullScreenCover 呈现)

UI 无单测,验收方式为 Step 3 的编译 + Task 10 的真机/模拟器手测清单。

- [ ] **Step 1: 实现 `StitchEditorView.swift`**

```swift
//
//  StitchEditorView.swift
//  ZeroNet Redact
//
//  拼接长图主界面:选图、预览、拼缝调整入口、排序、生成
//

import PhotosUI
import SwiftUI

/// sheet(item:) 需要 Identifiable 的拼缝选择
private struct SeamSelection: Identifiable {
    let id: Int
}

struct StitchEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = StitchViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var adjustingSeam: SeamSelection?
    @State private var showReorder = false
    @State private var showDoneAlert = false

    /// 用户点"去脱敏"时回调(ImportView 负责打开编辑器)
    let onRedact: (RedactableFile) -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                DesignSystem.Colors.backgroundPrimary.ignoresSafeArea()

                if viewModel.sources.isEmpty {
                    emptyState
                } else {
                    previewList
                    generateBar
                }

                if viewModel.isDetecting {
                    detectingOverlay
                }
            }
            .navigationTitle(NSLocalizedString("stitch.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("stitch.reorder", comment: "")) {
                        showReorder = true
                    }
                    .disabled(viewModel.sources.count < 2)
                }
            }
            .photosPicker(
                isPresented: $showPicker,
                selection: $pickerItems,
                maxSelectionCount: viewModel.maxSelectionCount,
                matching: .images
            )
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    await viewModel.loadImages(items)
                    pickerItems = []
                }
            }
            .onAppear {
                if viewModel.sources.isEmpty { showPicker = true }
            }
            .sheet(item: $adjustingSeam) { seam in
                SeamAdjustView(viewModel: viewModel, index: seam.id)
            }
            .sheet(isPresented: $showReorder) {
                StitchReorderSheet(viewModel: viewModel)
            }
            .sheet(
                isPresented: $viewModel.showPaywall,
                onDismiss: {
                    // 购买/恢复成功后自动继续生成(与 SimpleBrushEditor 配额模式一致)
                    if AppState.shared.hasUnlimitedAccess {
                        Task { await viewModel.generateAndImport() }
                    }
                }
            ) {
                PremiumView()
            }
            .alert(
                NSLocalizedString("stitch.done.title", comment: ""),
                isPresented: $showDoneAlert
            ) {
                Button(NSLocalizedString("stitch.done.redact", comment: "")) {
                    if let file = viewModel.finishedFile {
                        dismiss()
                        onRedact(file)
                    }
                }
                Button(NSLocalizedString("stitch.done.later", comment: ""), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("stitch.done.message", comment: ""))
            }
            .alert(
                NSLocalizedString("import.failed", comment: ""),
                isPresented: $viewModel.showError
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                if let message = viewModel.errorMessage { Text(message) }
            }
            .onChange(of: viewModel.finishedFile == nil) { isNil in
                if !isNil { showDoneAlert = true }
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(DesignSystem.Gradients.primary)
            Text(NSLocalizedString("stitch.empty.hint", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if !AppState.shared.hasUnlimitedAccess {
                Text(
                    String(
                        format: NSLocalizedString("stitch.limit.hint", comment: ""),
                        StitchViewModel.freeMaxImages, StitchViewModel.premiumMaxImages)
                )
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            Button(NSLocalizedString("stitch.selectImages", comment: "")) {
                showPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    // MARK: - 拼接预览

    private var previewList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.sources.enumerated()), id: \.element.id) {
                    index, source in
                    if let plan = viewModel.plan, index < plan.items.count {
                        StitchSegmentView(source: source, item: plan.items[index])
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    seamHandle(index: index, item: plan.items[index])
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, 120)  // 给底部生成栏留空间
        }
    }

    /// 拼缝手柄:绿色 = 自动检测成功;橙色 = 已降级堆叠,建议手动调
    private func seamHandle(index: Int, item: StitchItem) -> some View {
        let confident = item.seamConfidence >= OverlapDetector.seamConfidenceThreshold
        return Button {
            adjustingSeam = SeamSelection(id: index)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: confident ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(NSLocalizedString("stitch.seam.adjust", comment: ""))
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(confident ? Color.green : Color.orange, in: Capsule())
            .foregroundColor(.white)
        }
        .offset(y: -12)
    }

    // MARK: - 底部生成栏

    private var generateBar: some View {
        VStack(spacing: 6) {
            if let plan = viewModel.plan,
                plan.items.contains(where: {
                    $0.seamConfidence < OverlapDetector.seamConfidenceThreshold
                })
            {
                Text(NSLocalizedString("stitch.seam.lowConfidence", comment: ""))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Button {
                Task { await viewModel.generateAndImport() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRendering {
                        ProgressView().tint(.white)
                        Text(NSLocalizedString("stitch.generating", comment: ""))
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                        Text(NSLocalizedString("stitch.generate", comment: ""))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Gradients.primary)
                .foregroundColor(.white)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }
            .disabled(!viewModel.canGenerate)
            .opacity(viewModel.canGenerate ? 1 : 0.5)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var detectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.2)
                Text(NSLocalizedString("stitch.detecting", comment: ""))
                    .font(.subheadline)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}

// MARK: - 单段预览(不合成整图,按裁剪窗口显示降采样预览)

struct StitchSegmentView: View {
    let source: StitchSource
    let item: StitchItem

    var body: some View {
        let size = item.pixelSize
        let contentH = max(item.contentHeight, 1)
        Color.clear
            .aspectRatio(size.width / contentH, contentMode: .fit)
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    let scale = geo.size.width / size.width
                    Image(uiImage: source.preview)
                        .resizable()
                        .frame(width: size.width * scale, height: size.height * scale)
                        .offset(y: -item.cropTop * scale)
                }
            }
            .clipped()
    }
}

// MARK: - 排序/删除

struct StitchReorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StitchViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.sources) { source in
                    HStack(spacing: 12) {
                        Image(uiImage: source.preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipped()
                            .cornerRadius(6)
                        Text("\(Int(source.pixelSize.width))×\(Int(source.pixelSize.height))")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .onMove { from, to in
                    Task { await viewModel.moveSource(fromOffsets: from, toOffset: to) }
                }
                .onDelete { offsets in
                    Task { await viewModel.removeSource(atOffsets: offsets) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(NSLocalizedString("stitch.reorder", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 预览

#Preview {
    StitchEditorView(onRedact: { _ in })
}
```

- [ ] **Step 2: 实现 `SeamAdjustView.swift`**

```swift
//
//  SeamAdjustView.swift
//  ZeroNet Redact
//
//  拼缝精调:上下两图在拼缝处的局部对照 + 两条裁剪滑杆
//

import SwiftUI

struct SeamAdjustView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StitchViewModel
    /// 下图索引(调整 items[index-1].cropBottom 与 items[index].cropTop)
    let index: Int

    var body: some View {
        NavigationStack {
            Group {
                if let plan = viewModel.plan,
                    plan.items.indices.contains(index), index > 0
                {
                    content(plan: plan)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(NSLocalizedString("stitch.seam.adjust", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func content(plan: StitchPlan) -> some View {
        let upperItem = plan.items[index - 1]
        let lowerItem = plan.items[index]
        let upperSource = viewModel.sources[index - 1]
        let lowerSource = viewModel.sources[index]

        return VStack(spacing: 20) {
            // 拼缝局部对照
            VStack(spacing: 0) {
                SeamEdgeWindow(source: upperSource, item: upperItem, edge: .bottom)
                Rectangle()
                    .fill(DesignSystem.Colors.primaryBlue)
                    .frame(height: 2)
                SeamEdgeWindow(source: lowerSource, item: lowerItem, edge: .top)
            }
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .padding(.horizontal, DesignSystem.Spacing.lg)

            // 上图底部裁剪
            sliderRow(
                title: NSLocalizedString("stitch.seam.upperCrop", comment: ""),
                value: Binding(
                    get: { upperItem.cropBottom },
                    set: { viewModel.updateSeam(at: index, upperCropBottom: $0) }),
                range: 0...(upperItem.pixelSize.height - upperItem.cropTop - 50))

            // 下图顶部裁剪
            sliderRow(
                title: NSLocalizedString("stitch.seam.lowerCrop", comment: ""),
                value: Binding(
                    get: { lowerItem.cropTop },
                    set: { viewModel.updateSeam(at: index, cropTop: $0) }),
                range: 0...(lowerItem.pixelSize.height - lowerItem.cropBottom - 50))

            Spacer()
        }
        .padding(.top, 16)
    }

    private func sliderRow(
        title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue))px")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            Slider(value: value, in: range)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

/// 某一段在拼缝一侧的局部窗口(180pt 高)
struct SeamEdgeWindow: View {
    enum Edge { case top, bottom }

    let source: StitchSource
    let item: StitchItem
    let edge: Edge
    private let windowHeight: CGFloat = 180

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / item.pixelSize.width
            Image(uiImage: source.preview)
                .resizable()
                .frame(
                    width: item.pixelSize.width * scale,
                    height: item.pixelSize.height * scale
                )
                .offset(
                    y: edge == .top
                        ? -item.cropTop * scale
                        : windowHeight - (item.pixelSize.height - item.cropBottom) * scale)
        }
        .frame(height: windowHeight)
        .clipped()
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/Views/Stitch/
git commit -m "feat: Add stitch editor UI with seam adjustment and reorder

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: 入口接线(ImportView / ButtonBar / EmptyState)+ 手动验收

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/Views/Import/Components/ImportButtonBar.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Import/Components/ImportEmptyStateView.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Import/ImportViewModel.swift`(L8–9 附近)
- Modify: `zeroNetRedact/zeroNetRedact/Views/Import/ImportView.swift`

**Interfaces:**
- Consumes: `StitchEditorView(onRedact:)`
- Produces: 用户可从导入页两个入口进入拼接流程;"去脱敏"直接打开 `SimpleBrushEditor`

- [ ] **Step 1: ImportButtonBar 加第三按钮**

`ImportButtonBar` 结构体增加回调并加按钮(修改 L10–31):

```swift
struct ImportButtonBar: View {
    let onPhotosImport: () -> Void
    let onDocumentImport: () -> Void
    let onStitch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 导入图片按钮
            ActionButton(
                icon: "photo.on.rectangle.angled",
                title: NSLocalizedString("import.selectPhotos", comment: ""),
                gradient: DesignSystem.Gradients.primary,
                action: onPhotosImport
            )

            // 导入PDF按钮
            ActionButton(
                icon: "doc.text.fill",
                title: NSLocalizedString("import.selectPDF", comment: ""),
                gradient: DesignSystem.Gradients.pdfType,
                action: onDocumentImport
            )

            // 拼长图按钮
            ActionButton(
                icon: "rectangle.stack.badge.plus",
                title: NSLocalizedString("stitch.button", comment: ""),
                gradient: DesignSystem.Gradients.primary,
                action: onStitch
            )
        }
        // ……padding/background 原样保留……
    }
}
```

同步更新文件底部 `#Preview` 为三参数调用(加 `onStitch: { print("Stitch") }`)。

- [ ] **Step 2: ImportEmptyStateView 加引导入口**

结构体增加 `let onStitch: () -> Void`(L12 后),`importButtonsView`(L82–107)的 `HStack` 内追加第三个按钮:

```swift
            // 拼接长图
            ImportButton(
                icon: "rectangle.stack.badge.plus",
                title: NSLocalizedString("stitch.button", comment: ""),
                iconColor: DesignSystem.Colors.primaryPurple,
                action: onStitch
            )
```

`HStack` 的 `.padding(.horizontal, 40)` 改为 `.padding(.horizontal, 24)`(三按钮更挤)。底部 `#Preview` 补 `onStitch: {}`。若 `DesignSystem.Colors.primaryPurple` 不存在,改用 `DesignSystem.Colors.primaryBlue`。

- [ ] **Step 3: ImportViewModel 加状态**(在 `@Published var showDocumentPicker = false` 之后)

```swift
    @Published var showStitchSheet = false
```

- [ ] **Step 4: ImportView 接线**

三处修改:

1. 空状态(L26–29)传入新回调:

```swift
                            ImportEmptyStateView(
                                onPhotosImport: { viewModel.showPhotosPicker = true },
                                onDocumentImport: { viewModel.showDocumentPicker = true },
                                onStitch: { viewModel.showStitchSheet = true }
                            )
```

2. 底部栏(L42–45)同样加 `onStitch: { viewModel.showStitchSheet = true }`。

3. 在 `.sheet(item: $selectedOriginalFile) { ... }`(L106–108)之后追加:

```swift
            .fullScreenCover(isPresented: $viewModel.showStitchSheet) {
                StitchEditorView(onRedact: { file in
                    // 长图入库后直接打开脱敏编辑器
                    selectedOriginalFile = file as? OriginalFile
                })
            }
```

- [ ] **Step 5: 编译 + 全量单测回归**

Run: `xcodebuild test -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:'zeroNetRedactTests' 2>&1 | tail -20`
Expected: 全部测试通过

- [ ] **Step 6: 模拟器手动验收**(用 ios-debugger-agent / XcodeBuildMCP 或手动;逐项确认)

1. 导入页空状态与底部栏都出现"拼长图"入口。
2. 点击进入 → 相册多选(免费态上限 4)→ 自动拼接出预览,拼缝手柄可点。
3. 拼缝调整页两条滑杆实时改变对照窗口。
4. 排序 sheet 拖动换序后拼缝重新计算。
5. "生成长图" → 成功弹窗 → "去脱敏"直接进入 `SimpleBrushEditor` 且图像为拼接长图。
6. 免费账户配额耗尽(当日已导出 3 次)时点生成 → 弹 `PremiumView`。
7. 相册 Tab 能看到脱敏导出的长图产物。

- [ ] **Step 7: Commit**

```bash
git add -u
git commit -m "feat: Wire stitch entry into import view and empty state

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: 收尾回归

**Files:**
- Modify: `IMAGE_STITCH_PLAN.md`(状态改为"已实现 V1")

- [ ] **Step 1: 跑全量测试套件**

Run: `xcodebuild test -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30`
Expected: 全部通过(含 Crypto/Storage/Delete/Sensitive 等既有套件)

- [ ] **Step 2: 真机内存检查(如条件允许)**

Instruments Allocations 模板:20 张 1170×2532 截图拼接生成,内存峰值应 < 400MB 且无内存警告崩溃。不具备真机条件时,在模拟器用 Xcode Memory Gauge 观察并记录数值。

- [ ] **Step 3: 更新设计文档状态并提交**

`IMAGE_STITCH_PLAN.md` 头部 `> 状态:设计稿,待评审` 改为 `> 状态:V1 已实现(见 docs/superpowers/plans/2026-07-13-image-stitch.md)`。

```bash
git add IMAGE_STITCH_PLAN.md
git commit -m "docs: Mark stitch feature design as implemented (V1)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## 遗留到 V2(明确不在本计划内)

- 横向拼接(引擎已按竖向建模,方向参数化留待 V2)
- 编辑器整体 tile 化改造(V1 靠 30MP 上限规避)
- 上架材料更新(`APP_STORE_COPY.md` 加"长截图拼接"卖点、Paywall 权益文案)——发布前单独处理
