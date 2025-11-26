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
            .alert("导入失败", isPresented: $viewModel.showError) {
                Button("确定", role: .cancel) {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .overlay {
                if viewModel.isImporting {
                    // 导入中遮罩
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)
                            Text("正在导入...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
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
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // 图标组合 - 盾牌 + 光晕
                ZStack {
                    // 外层光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DesignSystem.Colors.primaryBlue.opacity(0.15),
                                    DesignSystem.Colors.primaryPurple.opacity(0.05),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    // 内层圆形背景
                    Circle()
                        .fill(DesignSystem.Gradients.lightBackground)
                        .frame(width: 100, height: 100)

                    // 盾牌图标
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(DesignSystem.Gradients.primary)
                }
                .padding(.bottom, 8)

                // 标题和描述
                VStack(spacing: 10) {
                    Text("零网隐私保护")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("导入的文件将被加密存储在本地\n只有你能访问，安全无忧")
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()

            // 导入按钮组
            VStack(spacing: 12) {
                // 从相册导入图片 - 主按钮
                Button(action: {
                    viewModel.showPhotosPicker = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .medium))
                        Text("从相册选择图片")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(GradientButtonStyle())

                // 导入PDF文件 - 次按钮
                Button(action: {
                    viewModel.showDocumentPicker = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18, weight: .medium))
                        Text("选择 PDF 文件")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(OutlineButtonStyle(color: DesignSystem.Colors.warningOrange))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - 文件网格视图

    private var originalFilesGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 16
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
            .padding(.bottom, 100)  // 为底部按钮栏留出空间
        }
    }

    // MARK: - 底部导入按钮栏

    private var importButtonBar: some View {
        HStack(spacing: 12) {
            // 导入图片按钮
            Button(action: {
                viewModel.showPhotosPicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .medium))
                    Text("导入图片")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Gradients.primary)
                .foregroundColor(.white)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }

            // 导入PDF按钮
            Button(action: {
                viewModel.showDocumentPicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 15, weight: .medium))
                    Text("导入PDF")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Gradients.pdfType)
                .foregroundColor(.white)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }
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
}

// MARK: - 原始文件网格项

struct OriginalFileGridItem: View {
    let file: OriginalFile
    @ObservedObject var viewModel: ImportViewModel
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            // 缩略图卡片
            ZStack {
                // 卡片背景
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundCard)
                    .shadow(
                        color: DesignSystem.Shadow.cardShadow(for: colorScheme), radius: 8, x: 0,
                        y: 3
                    )
                    .shadow(
                        color: DesignSystem.Shadow.cardShadowSecondary(for: colorScheme), radius: 1,
                        x: 0, y: 1
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(DesignSystem.Shadow.cardBorder(for: colorScheme), lineWidth: 1)
                    )

                // 内容区域
                GeometryReader { geometry in
                    let innerSize = geometry.size.width - 12  // 6pt padding on each side

                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium - 2)
                        .fill(Color.gray.opacity(0.08))
                        .frame(width: innerSize, height: innerSize)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .overlay {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(DesignSystem.Colors.primaryBlue)
                                } else if let thumbnail = thumbnailImage {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: innerSize, height: innerSize)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: DesignSystem.CornerRadius.medium - 2))
                                } else {
                                    // 占位图标
                                    VStack(spacing: 6) {
                                        Image(
                                            systemName: file.fileType == .image
                                                ? "photo.fill" : "doc.text.fill"
                                        )
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(
                                            file.fileType == .image
                                                ? DesignSystem.Gradients.imageType
                                                : DesignSystem.Gradients.pdfType
                                        )
                                        Text("原文件")
                                            .font(.caption2)
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                    }
                                }
                            }
                        }
                        // 类型徽章
                        .overlay(alignment: .topLeading) {
                            FileTypeBadge(fileType: file.fileType)
                                .padding(4)
                        }
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(6)
            }

            // 文件信息
            VStack(spacing: 2) {
                Text(file.createdAt, style: .date)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(file.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
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
