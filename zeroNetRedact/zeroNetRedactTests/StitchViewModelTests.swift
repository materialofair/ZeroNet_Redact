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

    private func makeTwoSources(seed: UInt64 = 7) throws -> [StitchSource] {
        let world = StitchTestImages.world(width: 390, height: 3000, seed: seed)
        return try [0.0, 500.0].map { top in
            try StitchEngine.makeSource(
                from: StitchTestImages.screenshot(
                    from: world, contentTop: top, contentHeight: 704
                ).pngData()!)
        }
    }

    /// 注册导入产物清理(磁盘 + Core Data);teardown 在断言失败时也会执行,避免残留污染后续跑次
    private func scheduleCleanup(_ file: OriginalImage) {
        addTeardownBlock { @MainActor in
            try? StorageManager.shared.deleteOriginal(id: file.id, type: file.fileType)
            let context = PersistenceController.shared.container.viewContext
            context.delete(file)
            try? context.save()
        }
    }

    /// 注册分组清理(在文件清理之后执行:teardown 为 LIFO,先注册的后跑)
    private func scheduleCleanup(group: FileGroup) {
        addTeardownBlock { @MainActor in
            _ = GroupManager.shared.deleteGroup(group)
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
        scheduleCleanup(file)
        XCTAssertEqual(Int(file.width), 390)
        XCTAssertGreaterThan(Int(file.height), 1000, "长图高度应大于单张")
        XCTAssertEqual(
            UsageTracker.shared.getTodayImageExports(), 1, "免费用户生成应计 1 次配额")
        // 导入页按分组过滤查询(group == selectedGroup),无分组的文件在列表中不可见
        XCTAssertNotNil(file.group, "拼接产物必须挂到默认分组,否则导入页查不到")
    }

    /// 拼接产物应挂到调用方指定的目标分组(跟随导入页当前选中分组)
    func testGenerateAndImportAttachesToTargetGroup() async throws {
        let customGroup = try XCTUnwrap(
            GroupManager.shared.createGroup(name: "拼接测试分组"), "创建自定义分组失败")
        scheduleCleanup(group: customGroup)
        let vm = StitchViewModel()
        await vm.setSources(try makeTwoSources(seed: 77))
        await vm.generateAndImport(targetGroup: customGroup)

        let file = try XCTUnwrap(vm.finishedFile as? OriginalImage)
        scheduleCleanup(file)
        XCTAssertEqual(file.group?.objectID, customGroup.objectID, "应挂到指定分组而非默认分组")
    }

    /// 同一拼接方案重复生成:应复用已有记录,不重复入库、不重复扣配额
    func testGenerateAndImportDeduplicatesRepeatedStitch() async throws {
        let vm1 = StitchViewModel()
        await vm1.setSources(try makeTwoSources(seed: 99))
        await vm1.generateAndImport()
        let first = try XCTUnwrap(vm1.finishedFile as? OriginalImage)
        scheduleCleanup(first)
        XCTAssertEqual(UsageTracker.shared.getTodayImageExports(), 1)

        // 第二次在另一个分组下重复生成:应复用记录并移动到该分组
        let customGroup = try XCTUnwrap(
            GroupManager.shared.createGroup(name: "去重目标分组"), "创建自定义分组失败")
        scheduleCleanup(group: customGroup)
        let vm2 = StitchViewModel()
        await vm2.setSources(try makeTwoSources(seed: 99))
        await vm2.generateAndImport(targetGroup: customGroup)
        let second = try XCTUnwrap(vm2.finishedFile as? OriginalImage)

        XCTAssertEqual(
            second.objectID, first.objectID, "重复拼接应返回已有记录而非新建")
        XCTAssertEqual(
            UsageTracker.shared.getTodayImageExports(), 1, "重复拼接不得再扣配额")
        XCTAssertEqual(
            second.group?.objectID, customGroup.objectID,
            "复用记录应移动到本次目标分组,用户在当前分组下应能看到它")
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
