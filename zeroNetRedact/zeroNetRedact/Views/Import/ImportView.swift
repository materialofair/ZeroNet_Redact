import CoreData
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedOriginalFile: OriginalFile?
    @State private var pendingRedactFile: OriginalFile?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideo: OriginalVideo?
    @State private var showVideoSourceDialog = false
    @State private var showVideoFileImporter = false
    @State private var showOnboarding = false
    @State private var showBatch = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 背景色
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if let id = viewModel.quickEditID,
                       let file = viewModel.originalFiles.first(where: { $0.id == id }) {
                        Button {
                            selectedOriginalFile = file
                            viewModel.quickEditID = nil
                        } label: {
                            Label("quickStart.openImported", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).padding(.horizontal)
                    }
                    // 主内容区
                    Group {
                        if viewModel.originalFiles.isEmpty {
                            if viewModel.filterType != nil {
                                ContentUnavailableView {
                                    Label("files.emptyFiltered", systemImage: "line.3.horizontal.decrease.circle")
                                } description: {
                                    Text("files.emptyFilteredHint")
                                } actions: {
                                    Button("files.clearFilter") { viewModel.filterType = nil }
                                        .buttonStyle(.borderedProminent)
                                }
                            } else {
                                ImportEmptyStateView(onAction: triggerImport)
                            }
                        } else {
                            // 文件网格
                            originalFilesGridView
                        }
                    }
                }

                // 底部操作栏（仅多选模式）
                if !viewModel.originalFiles.isEmpty && viewModel.isSelectionMode {
                    selectionActionBar
                }

                // 悬浮导入按钮：非多选模式且有文件时显示
                if !viewModel.isSelectionMode {
                    HStack {
                        Spacer()
                        importFabMenu
                    }
                    .padding(.trailing, DesignSystem.Spacing.xl)
                    .padding(.bottom, 24)
                }

                // 成功 Toast
                if viewModel.showSuccessToast {
                    VStack {
                        ToastView(message: viewModel.successToastMessage, isSuccess: true)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.showSuccessToast)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isSelectionMode {
                        Button("common.done") { viewModel.toggleSelectionMode() }
                    } else {
                        groupMenu
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    filterMenu.disabled(viewModel.isSelectionMode)
                    moreMenu
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showBatch) {
                BatchRedactionView(files: viewModel.originalFiles.filter { $0.fileType == .image })
            }
            .photosPicker(
                isPresented: $viewModel.showPhotosPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: Layout.maxPhotoSelection,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { newItems in
                if !newItems.isEmpty {
                    Task {
                        await viewModel.importPhotos(newItems)
                        selectedPhotoItems = []
                    }
                }
            }
            .photosPicker(
                isPresented: $viewModel.showVideoPicker,
                selection: $selectedVideoItem,
                matching: .videos
            )
            .onChange(of: selectedVideoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    defer { selectedVideoItem = nil }
                    do {
                        if let imported = try await newItem.loadTransferable(type: ImportedVideo.self) {
                            viewModel.importVideo(from: imported.url)
                        }
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                        viewModel.showError = true
                    }
                }
            }
            .confirmationDialog(
                NSLocalizedString("video.import.source", comment: ""),
                isPresented: $showVideoSourceDialog
            ) {
                Button(NSLocalizedString("video.import.photos", comment: "")) {
                    viewModel.showVideoPicker = true
                }
                Button(NSLocalizedString("video.import.files", comment: "")) {
                    showVideoFileImporter = true
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showVideoFileImporter,
                allowedContentTypes: [.movie],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else {
                    if case .failure(let error) = result {
                        viewModel.errorMessage = error.localizedDescription
                        viewModel.showError = true
                    }
                    return
                }
                Task { viewModel.importVideo(from: url) }
            }
            .sheet(isPresented: $viewModel.showDocumentPicker) {
                DocumentPickerView(viewModel: viewModel)
            }
            .sheet(item: $selectedOriginalFile) { originalFile in
                SimpleBrushEditor(file: originalFile)
            }
            .fullScreenCover(item: $selectedVideo) { video in
                VideoEditorView(video: video)
            }
            .fullScreenCover(
                isPresented: $viewModel.showStitchSheet,
                onDismiss: {
                    // cover 完全关闭后再呈现编辑器 sheet,避免同帧 present 被丢弃
                    if let file = pendingRedactFile {
                        pendingRedactFile = nil
                        selectedOriginalFile = file
                    }
                }
            ) {
                StitchEditorView(
                    targetGroup: viewModel.selectedGroup,
                    onRedact: { file in
                        pendingRedactFile = file as? OriginalFile
                    })
            }
            .sheet(isPresented: $viewModel.showCreateGroup) {
                CreateGroupSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showManageGroups) {
                GroupManagementSheet(viewModel: viewModel)
            }
            .alert(
                NSLocalizedString("import.failed", comment: ""), isPresented: $viewModel.showError
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .alert(
                NSLocalizedString("import.result.title", comment: ""),
                isPresented: $viewModel.showImportResultAlert
            ) {
                let duplicateCount =
                    viewModel.pendingDuplicateSources.count + viewModel.pendingDuplicateVideos.count
                if duplicateCount == 0 {
                    Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
                } else {
                    Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                        viewModel.dismissPendingDuplicates()
                    }
                    Button(
                        String(
                            format: NSLocalizedString(
                                "import.duplicate.import_anyway_count", comment: ""),
                            duplicateCount)
                    ) {
                        viewModel.forceImportPendingDuplicates()
                    }
                }
            } message: {
                Text(viewModel.importResultMessage)
            }
            .overlay {
                if viewModel.isImporting {
                    importingOverlay
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) {
                _ in
                viewModel.loadOriginalFiles()
            }
            .onChange(of: viewModel.filterType) { _, _ in
                viewModel.loadOriginalFiles()
            }
            .onChange(of: viewModel.sortOption) { _, _ in
                viewModel.loadOriginalFiles()
            }
        }
    }

    private var groupMenu: some View {
        Menu {
            ForEach(viewModel.allGroups, id: \.objectID) { group in
                Button { viewModel.selectGroup(group) } label: {
                    Label(group.name ?? NSLocalizedString("group.unnamed", comment: ""),
                          systemImage: viewModel.selectedGroup?.objectID == group.objectID ? "checkmark" : "folder")
                }
            }
            Divider()
            Button { viewModel.showCreateGroup = true } label: {
                Label("import.accessibility.newGroup", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 5) {
                Text(viewModel.selectedGroup?.name ?? NSLocalizedString("group.default", comment: ""))
                    .font(.headline).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .frame(maxWidth: 180, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("files.groupMenu")
        .accessibilityHint(Text("files.switchGroup"))
    }

    private var filterMenu: some View {
        Menu {
            ForEach([nil, FileType.image, .pdf, .video], id: \.self) { type in
                Button { viewModel.filterType = type } label: {
                    if viewModel.filterType == type {
                        Label(type?.displayName ?? NSLocalizedString("list.filter.all", comment: ""), systemImage: "checkmark")
                    } else {
                        Text(type?.displayName ?? NSLocalizedString("list.filter.all", comment: ""))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.filterType == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                Text(viewModel.filterType?.displayName ?? NSLocalizedString("files.filter", comment: ""))
                    .font(.subheadline).lineLimit(1)
            }.frame(minHeight: 44)
        }
        .accessibilityIdentifier("files.filterMenu")
        .accessibilityValue(viewModel.filterType?.displayName ?? NSLocalizedString("list.filter.all", comment: ""))
    }

    private var moreMenu: some View {
        Menu {
            Button { viewModel.toggleSelectionMode() } label: {
                Label(viewModel.isSelectionMode ? NSLocalizedString("common.done", comment: "") : NSLocalizedString("import.select", comment: ""),
                      systemImage: "checkmark.circle")
            }.disabled(viewModel.originalFiles.isEmpty && !viewModel.isSelectionMode)
            Menu {
                ForEach(FileSortOption.allCases) { option in
                    Button { viewModel.sortOption = option } label: {
                        Label(option.displayName, systemImage: viewModel.sortOption == option ? "checkmark" : option.icon)
                    }
                }
            } label: {
                Label("files.sort", systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button { showBatch = true } label: {
                Label("batch.title", systemImage: "rectangle.stack.badge.play")
            }
            Button { viewModel.showManageGroups = true } label: {
                Label("import.accessibility.manageGroups", systemImage: "folder.badge.gearshape")
            }
            Button { showOnboarding = true } label: {
                Label("onboarding.revisit", systemImage: "questionmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("common.more"))
    }

    // MARK: - 文件网格视图

    private var originalFilesGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Layout.gridSpacing),
                    GridItem(.flexible(), spacing: Layout.gridSpacing),
                    GridItem(.flexible(), spacing: Layout.gridSpacing),
                ],
                spacing: Layout.gridSpacing
            ) {
                // 用 objectID 做标识：对象删除后 \.id 键路径取非可选 UUID 会崩溃，objectID 永远有效
                ForEach(viewModel.originalFiles, id: \.objectID) { file in
                    OriginalFileGridItem(
                        file: file,
                        viewModel: viewModel,
                        isSelectionMode: viewModel.isSelectionMode,
                        isSelected: viewModel.selectedFileIDs.contains(file.id)
                    )
                    .onTapGesture {
                        if viewModel.isSelectionMode {
                            viewModel.toggleSelection(file)
                        } else {
                            if let video = file as? OriginalVideo {
                                selectedVideo = video
                            } else {
                                selectedOriginalFile = file
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, Layout.bottomPadding)  // 为悬浮导入按钮留出空间
        }
    }

    // MARK: - 悬浮导入按钮

    /// 触发导入动作（空状态卡片与悬浮「+」菜单共用，动作定义见 ImportAction）
    private func triggerImport(_ action: ImportAction) {
        switch action {
        case .photos: viewModel.showPhotosPicker = true
        case .video: showVideoSourceDialog = true
        case .pdf: viewModel.showDocumentPicker = true
        case .stitch: viewModel.showStitchSheet = true
        }
    }

    /// 单一「+」悬浮按钮，点开为原生菜单；取代此前常驻底部的 2x2 导入卡片
    private var importFabMenu: some View {
        Menu {
            ForEach(ImportAction.availableActions) { action in
                Button {
                    triggerImport(action)
                } label: {
                    Label(action.displayName, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(DesignSystem.Gradients.primary)
                .clipShape(Circle())
                .shadow(
                    color: DesignSystem.Colors.primaryBlue.opacity(0.35), radius: 12, x: 0, y: 6
                )
        }
        .accessibilityLabel(NSLocalizedString("import.addFile", comment: ""))
    }

    // MARK: - 多选删除操作栏

    private var selectionActionBar: some View {
        HStack {
            Button(role: .destructive) {
                viewModel.showBatchDeleteConfirm = true
            } label: {
                Text(
                    String(
                        format: NSLocalizedString("import.deleteSelectedCount", comment: ""),
                        viewModel.selectedFileIDs.count)
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Colors.dangerRed)
                .foregroundColor(.white)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }
            .disabled(viewModel.selectedFileIDs.isEmpty)
            .opacity(viewModel.selectedFileIDs.isEmpty ? 0.5 : 1)
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
        .alert(
            NSLocalizedString("import.delete.selected.title", comment: ""),
            isPresented: $viewModel.showBatchDeleteConfirm
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                viewModel.deleteSelectedFiles()
            }
        } message: {
            let selectedFiles = viewModel.originalFiles.filter {
                viewModel.selectedFileIDs.contains($0.id)
            }
            let redactedTotal = selectedFiles.reduce(0) { $0 + $1.redactedVersionsArray.count }
            if redactedTotal > 0 {
                Text(
                    String(
                        format: NSLocalizedString(
                            "import.delete.selected.messageWithRedacted", comment: ""),
                        viewModel.selectedFileIDs.count, redactedTotal))
            } else {
                Text(
                    String(
                        format: NSLocalizedString("import.delete.selected.message", comment: ""),
                        viewModel.selectedFileIDs.count)
                )
            }
        }
    }

    // MARK: - 导入中遮罩

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if viewModel.isImportingVideo {
                    ProgressView(value: viewModel.importProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 160)

                    Text(
                        String(
                            format: NSLocalizedString("import.videoProgress", comment: ""),
                            Int(viewModel.importProgress * 100))
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                } else if viewModel.importTotalCount > 0 {
                    ProgressView(
                        value: Double(viewModel.importCompletedCount),
                        total: Double(viewModel.importTotalCount)
                    )
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 160)

                    Text(
                        String(
                            format: NSLocalizedString("import.progress", comment: ""),
                            viewModel.importCompletedCount, viewModel.importTotalCount)
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text(NSLocalizedString("import.loading", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Button(NSLocalizedString("common.cancel", comment: "")) {
                    viewModel.cancelImport()
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
}

// MARK: - 布局常量

private enum Layout {
    static let gridColumns = 3
    static let gridSpacing: CGFloat = 12
    /// 网格底部留白：为悬浮导入按钮腾出空间（56pt 按钮 + 24pt 边距 + 16pt 呼吸空间）
    static let bottomPadding: CGFloat = 96
    static let maxPhotoSelection = 10
}

// MARK: - 预览

#Preview {
    ImportView()
}
