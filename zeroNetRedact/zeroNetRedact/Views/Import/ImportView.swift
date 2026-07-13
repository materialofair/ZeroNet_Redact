import CoreData
import PhotosUI
import SwiftUI

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()
    @State private var selectedOriginalFile: OriginalFile?
    @State private var pendingRedactFile: OriginalFile?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 背景色
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 分组选择器
                    GroupSelectorBar(viewModel: viewModel)
                        .padding(.vertical, 12)

                    // 主内容区
                    Group {
                        if viewModel.originalFiles.isEmpty {
                            // 空状态 - 显示导入引导
                            ImportEmptyStateView(
                                onPhotosImport: { viewModel.showPhotosPicker = true },
                                onDocumentImport: { viewModel.showDocumentPicker = true },
                                onStitch: { viewModel.showStitchSheet = true }
                            )
                        } else {
                            // 文件网格
                            originalFilesGridView
                        }
                    }
                }

                // 底部固定操作栏
                if !viewModel.originalFiles.isEmpty {
                    if viewModel.isSelectionMode {
                        selectionActionBar
                    } else {
                        ImportButtonBar(
                            onPhotosImport: { viewModel.showPhotosPicker = true },
                            onDocumentImport: { viewModel.showDocumentPicker = true },
                            onStitch: { viewModel.showStitchSheet = true }
                        )
                    }
                }

                // 成功 Toast
                if viewModel.showSuccessToast {
                    VStack {
                        ToastView(message: viewModel.successToastMessage, isSuccess: true)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.showSuccessToast)
                }
            }
            .navigationTitle(NSLocalizedString("import.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation {
                            viewModel.toggleSelectionMode()
                        }
                    }) {
                        Text(
                            viewModel.isSelectionMode
                                ? NSLocalizedString("common.done", comment: "")
                                : NSLocalizedString("import.select", comment: "")
                        )
                    }
                    .disabled(viewModel.originalFiles.isEmpty && !viewModel.isSelectionMode)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.showManageGroups = true
                    }) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(DesignSystem.Colors.primaryBlue)
                    }
                    .accessibilityLabel(
                        NSLocalizedString("import.accessibility.manageGroups", comment: ""))
                }
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
            .sheet(isPresented: $viewModel.showDocumentPicker) {
                DocumentPickerView(viewModel: viewModel)
            }
            .sheet(item: $selectedOriginalFile) { originalFile in
                SimpleBrushEditor(file: originalFile)
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
                StitchEditorView(onRedact: { file in
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
                if viewModel.pendingDuplicateSources.isEmpty {
                    Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
                } else {
                    Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                        viewModel.dismissPendingDuplicates()
                    }
                    Button(
                        String(
                            format: NSLocalizedString(
                                "import.duplicate.import_anyway_count", comment: ""),
                            viewModel.pendingDuplicateSources.count)
                    ) {
                        Task {
                            await viewModel.forceImportPendingDuplicates()
                        }
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
        }
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
                            selectedOriginalFile = file
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, Layout.bottomPadding)  // 为底部按钮栏留出空间
        }
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
            Text(
                String(
                    format: NSLocalizedString("import.delete.selected.message", comment: ""),
                    viewModel.selectedFileIDs.count)
            )
        }
    }

    // MARK: - 导入中遮罩

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if viewModel.importTotalCount > 0 {
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
    static let bottomPadding: CGFloat = 100
    static let maxPhotoSelection = 10
}

// MARK: - 预览

#Preview {
    ImportView()
}
