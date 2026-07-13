//
//  StitchViewModel.swift
//  ZeroNet Redact
//
//  拼接会话 ViewModel:选图加载、方案计算、拼缝调整、配额门控与生成导入
//

import Combine
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
