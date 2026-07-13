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
    private var savedReviewMode = false

    override func setUp() async throws {
        savedPremium = AppState.shared.isPremium
        savedReviewMode = UserDefaults.standard.bool(forKey: "reviewModeActivated")
        AppState.shared.isPremium = false
        UserDefaults.standard.set(false, forKey: "reviewModeActivated")
        UsageTracker.shared.resetAllUsage()
    }

    override func tearDown() async throws {
        AppState.shared.isPremium = savedPremium
        UserDefaults.standard.set(savedReviewMode, forKey: "reviewModeActivated")
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
        // 导入页按分组过滤查询(group == selectedGroup),无分组的文件在列表中不可见
        XCTAssertNotNil(file.group, "拼接产物必须挂到默认分组,否则导入页查不到")

        // 清理:先删磁盘上的加密原图与缩略图,再删 Core Data 记录
        try? StorageManager.shared.deleteOriginal(id: file.id, type: file.fileType)
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

    /// 回归:渲染进行中重入 generateAndImport 应直接返回(防双击并发渲染/重复扣配额)
    func testGenerateAndImportReentrancyGuard() async throws {
        let vm = StitchViewModel()
        await vm.setSources(try makeTwoSources())
        vm.isRendering = true
        await vm.generateAndImport()
        XCTAssertNil(vm.finishedFile, "渲染中重入应被拒绝")
        XCTAssertEqual(UsageTracker.shared.getTodayImageExports(), 0, "重入不得扣配额")
    }
}
