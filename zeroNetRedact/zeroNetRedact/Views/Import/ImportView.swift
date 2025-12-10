import CoreData
import PhotosUI
import SwiftUI

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()
    @State private var selectedOriginalFile: OriginalFile?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationView {
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
                                onDocumentImport: { viewModel.showDocumentPicker = true }
                            )
                        } else {
                            // 文件网格
                            originalFilesGridView
                        }
                    }
                }

                // 底部固定导入按钮栏
                if !viewModel.originalFiles.isEmpty {
                    ImportButtonBar(
                        onPhotosImport: { viewModel.showPhotosPicker = true },
                        onDocumentImport: { viewModel.showDocumentPicker = true }
                    )
                }
            }
            .navigationTitle(NSLocalizedString("import.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.showManageGroups = true
                    }) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(DesignSystem.Colors.primaryBlue)
                    }
                }
            }
            .photosPicker(
                isPresented: $viewModel.showPhotosPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
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
                NSLocalizedString("import.duplicate.title", comment: ""),
                isPresented: $viewModel.showDuplicateAlert
            ) {
                Button(NSLocalizedString("import.duplicate.skip", comment: ""), role: .cancel) {
                    viewModel.pendingImportSource = nil
                    viewModel.duplicateFile = nil
                }
                Button(NSLocalizedString("import.duplicate.import_anyway", comment: "")) {
                    Task {
                        await viewModel.forceImportDuplicate()
                    }
                }
            } message: {
                Text(NSLocalizedString("import.duplicate.message", comment: ""))
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
                ForEach(viewModel.originalFiles, id: \.id) { file in
                    OriginalFileGridItem(file: file, viewModel: viewModel)
                        .onTapGesture {
                            selectedOriginalFile = file
                        }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, Layout.bottomPadding)  // 为底部按钮栏留出空间
        }
    }

    // MARK: - 导入中遮罩

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                Text(NSLocalizedString("import.loading", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
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
