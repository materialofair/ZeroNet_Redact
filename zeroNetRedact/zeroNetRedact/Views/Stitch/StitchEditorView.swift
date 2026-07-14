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

    /// 目标分组(导入页当前选中分组),nil 时 VM 回退默认分组
    var targetGroup: FileGroup? = nil

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
                        Task { await viewModel.generateAndImport(targetGroup: targetGroup) }
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
                if viewModel.sources.count == 1 {
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("stitch.empty.hint", comment: ""))
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Button(NSLocalizedString("stitch.selectImages", comment: "")) {
                            showPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
                Task { await viewModel.generateAndImport(targetGroup: targetGroup) }
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
