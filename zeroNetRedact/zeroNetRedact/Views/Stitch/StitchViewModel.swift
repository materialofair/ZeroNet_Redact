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
        showError = false
        errorMessage = nil
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

    /// 生成长图并导入(配额检查 → 后台渲染 → ImportManager 去重 + 加密入库)
    /// - Parameter targetGroup: 目标分组(导入页当前选中分组);nil 时回退默认分组
    func generateAndImport(targetGroup: FileGroup? = nil) async {
        guard !isRendering else { return }
        showPaywall = false
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
            // 与照片导入同路径:SHA256 去重,重复生成同一拼接方案不重复入库
            switch try await ImportManager.shared.importFileWithDuplicateCheck(
                from: .imageData(data))
            {
            case .success(let file):
                attachToGroup(file, preferred: targetGroup)
                if !appState.hasUnlimitedAccess {
                    usageTracker.recordImageExport()
                }
                finishedFile = file
                print("🧵 StitchViewModel: 长图已生成并导入 id=\(file.id)")

            case .duplicate(let existingFile):
                // 复用已有记录:不重复入库、不扣配额;历史无分组记录顺带修复可见性
                if existingFile.group == nil {
                    attachToGroup(existingFile, preferred: targetGroup)
                }
                finishedFile = existingFile
                print("🧵 StitchViewModel: 检测到相同长图,复用已有记录 id=\(existingFile.id)")
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 挂到目标分组;导入页按 group == selectedGroup 过滤,无分组的文件不可见
    private func attachToGroup(_ file: RedactableFile, preferred: FileGroup?) {
        guard let original = file as? OriginalFile else { return }
        GroupManager.shared.ensureDefaultGroup()
        guard let group = preferred ?? GroupManager.shared.getDefaultGroup() else {
            print("❌ StitchViewModel: 目标/默认分组均不存在,长图未挂分组 id=\(original.id)")
            return
        }
        if !GroupManager.shared.moveFile(original, to: group) {
            print("❌ StitchViewModel: 分组挂载保存失败 id=\(original.id),文件可能不出现在导入列表")
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
