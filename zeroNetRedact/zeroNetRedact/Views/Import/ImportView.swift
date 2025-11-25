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
                VStack(spacing: 0) {
                    // 分组选择器
                    GroupSelectorBar(viewModel: viewModel)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))

                    Divider()

                    // 主内容区
                    Group {
                        if viewModel.originalFiles.isEmpty {
                            // 空状态 - 显示导入引导
                            emptyStateView
                        } else {
                            // 文件网格
                            originalFilesGridView
                        }
                    }
                }

                // 底部固定导入按钮栏
                if !viewModel.originalFiles.isEmpty {
                    importButtonBar
                }
            }
            .navigationTitle("导入")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.showManageGroups = true
                    }) {
                        Image(systemName: "folder.badge.gearshape")
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
            .alert("导入失败", isPresented: $viewModel.showError) {
                Button("确定", role: .cancel) {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .overlay {
                if viewModel.isImporting {
                    ProgressView("正在导入...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) {
                _ in
                viewModel.loadOriginalFiles()
            }
        }
    }

    // MARK: - 空状态视图

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            // 导入说明
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("零网隐私保护")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("导入文件后将被加密存储,只有你能访问")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 40)

            Spacer()

            // 导入按钮组
            VStack(spacing: 16) {
                // 从相册导入图片
                Button(action: {
                    viewModel.showPhotosPicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text("从相册导入图片")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                // 导入PDF文件
                Button(action: {
                    viewModel.showDocumentPicker = true
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.title2)
                        Text("导入PDF文件")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 60)
        }
    }

    // MARK: - 文件网格视图

    private var originalFilesGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ],
                spacing: 12
            ) {
                ForEach(viewModel.originalFiles, id: \.id) { file in
                    OriginalFileGridItem(file: file, viewModel: viewModel)
                        .onTapGesture {
                            selectedOriginalFile = file
                        }
                }
            }
            .padding()
            .padding(.bottom, 80)  // 为底部按钮栏留出空间
        }
    }

    // MARK: - 底部导入按钮栏

    private var importButtonBar: some View {
        HStack(spacing: 12) {
            // 导入图片按钮
            Button(action: {
                viewModel.showPhotosPicker = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.body)
                    Text("导入图片")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // 导入PDF按钮
            Button(action: {
                viewModel.showDocumentPicker = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.body)
                    Text("导入PDF")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
}

// MARK: - 原始文件网格项

struct OriginalFileGridItem: View {
    let file: OriginalFile
    @ObservedObject var viewModel: ImportViewModel
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 6) {
            // 缩略图卡片
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Group {
                            if isLoading {
                                ProgressView()
                            } else if let thumbnail = thumbnailImage {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                VStack(spacing: 8) {
                                    Image(
                                        systemName: file.fileType == .image
                                            ? "photo.circle.fill" : "doc.text.fill"
                                    )
                                    .font(.system(size: 40))
                                    .foregroundStyle(
                                        file.fileType == .image
                                            ? LinearGradient(
                                                colors: [.blue, .cyan], startPoint: .topLeading,
                                                endPoint: .bottomTrailing)
                                            : LinearGradient(
                                                colors: [.orange, .red], startPoint: .topLeading,
                                                endPoint: .bottomTrailing)
                                    )
                                    Text("原文件")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        // 类型徽章
                        CategoryBadge(fileType: file.fileType)
                            .padding(8)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // 文件信息
            VStack(spacing: 2) {
                Text(file.createdAt, style: .date)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(file.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let cacheKey = "original_thumbnail_\(file.id.uuidString)"

        // 先检查缓存
        if let cachedImage = ImageCache.shared.getImage(forKey: cacheKey) {
            await MainActor.run {
                thumbnailImage = cachedImage
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 读取加密缩略图
            let encryptedData = try StorageManager.shared.loadEncryptedThumbnail(
                id: file.id,
                type: file.fileType
            )

            // 解密
            let decryptedData = try CryptoEngine.shared.decrypt(data: encryptedData)

            // 创建图片
            if let image = UIImage(data: decryptedData) {
                // 缓存缩略图
                ImageCache.shared.setImage(image, forKey: cacheKey)

                await MainActor.run {
                    thumbnailImage = image
                }
            }
        } catch {
            print("❌ 加载原文件缩略图失败: \(error)")
        }
    }
}

#Preview {
    ImportView()
}
