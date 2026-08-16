//
//  ImageRedactionEditorRenderTests.swift
//  P0-10 回归测试：单遍合成渲染管线
//  覆盖批量应用、撤销/重做、移动、方向归一化与导出等待在途渲染
//

import CoreData
import UIKit
import XCTest

@testable import zeroNetRedact

@MainActor
final class ImageRedactionEditorRenderTests: XCTestCase {

    /// 草稿上下文：哑实体仅用于初始化编辑器，绝不落库，
    /// 避免未保存的非法插入污染共享 viewContext 导致其他测试 save 失败
    private lazy var scratchContext: NSManagedObjectContext = {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator =
            PersistenceController.shared.container.persistentStoreCoordinator
        return context
    }()

    /// 生成一张左白右灰的测试图（未落库的哑实体仅用于初始化编辑器）
    private func makeEditor(image: UIImage) -> ImageRedactionEditor {
        let file = OriginalImage(context: scratchContext)
        let editor = ImageRedactionEditor(file: file)
        editor.loadForTesting(image: image)
        return editor
    }

    private func makeTestImage() -> UIImage {
        // 显式 scale=1，像素坐标与点坐标 1:1，便于区域断言
        // 白/灰边界放在 x=103（不与 20px 马赛克块网格对齐，块内必含两色产生可见变化）
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(x: 103, y: 0, width: 97, height: 200))
        }
    }

    private func data(_ image: UIImage?) -> Data? {
        image?.pngData()
    }

    // MARK: - 批量应用

    func testApplySolidBlackChangesPixels() async throws {
        let editor = makeEditor(image: makeTestImage())
        let originalData = try XCTUnwrap(data(editor.currentImage))

        editor.applyRedaction(
            at: CGRect(x: 20, y: 20, width: 60, height: 60), effect: .solidBlack)
        await editor.waitForPendingRender()

        let redactedData = try XCTUnwrap(data(editor.currentImage))
        XCTAssertNotEqual(redactedData, originalData, "应用遮盖后像素应变化")
    }

    /// 批量应用与逐个应用产出一致（同一渲染管线）
    func testBatchApplyMatchesSequentialApply() async throws {
        let rects = [
            CGRect(x: 10, y: 10, width: 40, height: 40),
            CGRect(x: 120, y: 120, width: 50, height: 50),
            CGRect(x: 60, y: 30, width: 30, height: 70),
        ]

        let batchEditor = makeEditor(image: makeTestImage())
        batchEditor.applyRedactions(at: rects, effect: .solidBlack)
        await batchEditor.waitForPendingRender()

        let sequentialEditor = makeEditor(image: makeTestImage())
        for rect in rects {
            sequentialEditor.applyRedaction(at: rect, effect: .solidBlack)
            await sequentialEditor.waitForPendingRender()
        }

        XCTAssertEqual(
            data(batchEditor.currentImage), data(sequentialEditor.currentImage),
            "批量应用与逐个应用应产出相同像素")
    }

    /// 批量应用只记录一个撤销快照：undo 一次应回到全部应用之前
    func testBatchApplyIsSingleUndoStep() async throws {
        let editor = makeEditor(image: makeTestImage())
        let originalData = try XCTUnwrap(data(editor.currentImage))

        editor.applyRedactions(
            at: [
                CGRect(x: 10, y: 10, width: 40, height: 40),
                CGRect(x: 120, y: 120, width: 50, height: 50),
            ],
            effect: .solidBlack)
        await editor.waitForPendingRender()
        XCTAssertTrue(editor.canUndo)

        editor.undo()
        await editor.waitForPendingRender()
        XCTAssertEqual(
            data(editor.currentImage), originalData, "一次 undo 应恢复到批量应用前的像素")
    }

    // MARK: - 撤销 / 重做（快照式撤销路径，此前每次 undo 重放 O(n) 次全图合成）

    func testUndoRestoresOriginalPixels() async throws {
        let editor = makeEditor(image: makeTestImage())
        let originalData = try XCTUnwrap(data(editor.currentImage))

        editor.applyRedaction(
            at: CGRect(x: 20, y: 20, width: 60, height: 60), effect: .solidBlack)
        await editor.waitForPendingRender()
        XCTAssertNotEqual(data(editor.currentImage), originalData)

        editor.undo()
        await editor.waitForPendingRender()
        XCTAssertEqual(data(editor.currentImage), originalData, "undo 后应精确恢复原图像素")
    }

    func testRedoReappliesRedaction() async throws {
        let editor = makeEditor(image: makeTestImage())

        editor.applyRedaction(
            at: CGRect(x: 20, y: 20, width: 60, height: 60), effect: .solidBlack)
        await editor.waitForPendingRender()
        let appliedData = try XCTUnwrap(data(editor.currentImage))

        editor.undo()
        await editor.waitForPendingRender()
        editor.redo()
        await editor.waitForPendingRender()

        XCTAssertEqual(data(editor.currentImage), appliedData, "redo 后应恢复到应用后的像素")
    }

    /// 多步历史 undo 也应精确恢复（此前 undo 为 O(n) 全图重放，历史越长越卡）
    func testUndoThroughLongHistory() async throws {
        let editor = makeEditor(image: makeTestImage())
        let originalData = try XCTUnwrap(data(editor.currentImage))

        for i in 0..<10 {
            editor.applyRedaction(
                at: CGRect(x: 0, y: 0, width: CGFloat(i + 1) * 10, height: 40),
                effect: .solidBlack)
            await editor.waitForPendingRender()
        }

        for _ in 0..<10 {
            editor.undo()
        }
        await editor.waitForPendingRender()

        XCTAssertEqual(data(editor.currentImage), originalData, "连续 10 次 undo 应精确恢复原图")
    }

    // MARK: - 移动区域

    func testMoveRegionThenUndoRestores() async throws {
        let editor = makeEditor(image: makeTestImage())

        editor.applyRedaction(
            at: CGRect(x: 20, y: 20, width: 40, height: 40), effect: .solidBlack)
        await editor.waitForPendingRender()
        let beforeMove = try XCTUnwrap(data(editor.currentImage))

        editor.moveRedactionRegion(at: 0, offset: CGSize(width: 80, height: 60))
        await editor.waitForPendingRender()
        XCTAssertNotEqual(data(editor.currentImage), beforeMove, "移动后像素应变化")

        editor.undo()
        await editor.waitForPendingRender()
        XCTAssertEqual(data(editor.currentImage), beforeMove, "undo 移动应恢复移动前像素")
    }

    // MARK: - 效果渲染

    func testMosaicAndBlurRenderWithoutCrash() async throws {
        let editor = makeEditor(image: makeTestImage())
        let originalData = try XCTUnwrap(data(editor.currentImage))

        // 区域横跨 x=100 的白/灰边界，且不与 20px 块网格对齐（对齐时块内纯色、马赛克无可见变化）
        editor.applyRedactions(
            at: [
                CGRect(x: 95, y: 30, width: 40, height: 60),
                CGRect(x: 95, y: 120, width: 40, height: 60),
            ],
            effect: .mosaic(pixelSize: 20))
        await editor.waitForPendingRender()
        XCTAssertNotEqual(data(editor.currentImage), originalData, "马赛克应改变区域像素")

        editor.applyRedaction(
            at: CGRect(x: 90, y: 70, width: 40, height: 50), effect: .blur(radius: 8))
        await editor.waitForPendingRender()
        XCTAssertNotEqual(
            data(editor.currentImage), originalData, "模糊应改变区域像素")
    }

    // MARK: - 方向归一化

    /// EXIF 方向非 .up 的图片加载后应归一化（渲染管线按 .up 位图处理）
    func testLoadNormalizesOrientation() {
        // 显式 scale=1，避免屏幕倍率干扰尺寸断言
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 120), format: format)
        let base = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 120))
        }
        let rotated = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)

        let editor = makeEditor(image: rotated)
        XCTAssertEqual(editor.currentImage?.imageOrientation, .up)
        XCTAssertEqual(editor.currentImage?.size, CGSize(width: 120, height: 60))
    }

    // MARK: - 导出等待在途渲染

    /// 应用后立即导出：exportRedactedFile 必须等待在途渲染完成（导出旧画面回归）
    /// 逐像素采样比较（PNG 解码-重编码会因色彩空间/字节序产生不同字节）
    func testExportWaitsForPendingRender() async throws {
        let original = makeTestImage()
        let editor = makeEditor(image: original)

        // 不 await 渲染，立即导出
        editor.applyRedaction(
            at: CGRect(x: 20, y: 20, width: 60, height: 60), effect: .solidBlack)
        let exported = try await editor.exportRedactedFile()
        let exportedImage = try XCTUnwrap(UIImage(data: exported))

        await editor.waitForPendingRender()
        let finalImage = try XCTUnwrap(editor.currentImage)
        let center = CGPoint(x: 0.25, y: 0.25)

        // 导出画面必须包含刚涂抹的遮盖（与未脱敏原图不同）
        XCTAssertNotEqual(
            pixelColor(exportedImage, at: center), pixelColor(original, at: center),
            "导出数据应包含刚应用的最后一次遮盖")

        // 且与最终渲染画面逐点一致
        for point in [center, CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.5)] {
            XCTAssertEqual(
                pixelColor(exportedImage, at: point), pixelColor(finalImage, at: point),
                "导出画面应与渲染完成后的画面一致")
        }
    }

    /// 取归一化坐标处单像素颜色：把目标像素平移到 1×1 UIKit 渲染器原点。
    /// UIKit 渲染器上下文即左上原点、y 向下，直接平移 (x, y) 即可，无需翻转
    private func pixelColor(_ image: UIImage, at point: CGPoint) -> UIColor? {
        guard image.cgImage != nil else { return nil }
        let x = Int((point.x * image.size.width).rounded(.down))
        let y = Int((point.y * image.size.height).rounded(.down))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format)
        let sampled = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -CGFloat(x), y: -CGFloat(y))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let data = sampled.cgImage?.dataProvider?.data,
            let ptr = CFDataGetBytePtr(data)
        else { return nil }
        return UIColor(
            red: CGFloat(ptr[0]) / 255,
            green: CGFloat(ptr[1]) / 255,
            blue: CGFloat(ptr[2]) / 255,
            alpha: CGFloat(ptr[3]) / 255
        )
    }
}
