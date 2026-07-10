import CoreData
import PDFKit
import SwiftUI

// MARK: - PDFDocument扩展，使其可用于fullScreenCover的item绑定

extension PDFDocument: @retroactive Identifiable {
    public var id: String {
        return String(describing: Unmanaged.passUnretained(self).toOpaque())
    }
}

// MARK: - UIImage Identifiable包装

extension UIImage: @retroactive Identifiable {
    public var id: String {
        return String(describing: Unmanaged.passUnretained(self).toOpaque())
    }
}

struct AlbumView: View {
    @StateObject private var viewModel = AlbumViewModel()
    @Binding var selectedTab: Int

    @State private var previewFile: RedactedFile?
    @State private var previewImage: UIImage?
    @State private var previewPDFDocument: PDFDocument?
    @State private var isLoadingPreview = false
    @State private var previewFailedFile: RedactedFile?
    @State private var showPreviewFailedAlert = false
    @State private var previewTask: Task<Void, Never>?

    @State private var isSelectionMode = false
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var showBatchDeleteAlert = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景色
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 统计卡片（只有在有文件时显示）
                    if !viewModel.redactedFiles.isEmpty {
                        statisticsCard
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.top, DesignSystem.Spacing.md)
                    }

                    // 分组选择器
                    RedactedGroupSelectorBar(viewModel: viewModel)
                        .padding(.vertical, 12)

                    // 主内容
                    Group {
                        if viewModel.redactedFiles.isEmpty {
                            // 空状态
                            emptyStateView
                        } else {
                            // 脱敏文件网格
                            redactedFilesGridView
                        }
                    }

                    // 多选删除操作栏
                    if isSelectionMode && !viewModel.redactedFiles.isEmpty {
                        selectionActionBar
                    }
                }

                // 预览加载态
                if isLoadingPreview {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle(NSLocalizedString("album.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !viewModel.redactedFiles.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            withAnimation {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedFileIDs.removeAll()
                                }
                            }
                        } label: {
                            Text(
                                isSelectionMode
                                    ? NSLocalizedString("common.done", comment: "")
                                    : NSLocalizedString("album.select", comment: ""))
                        }
                    }
                }
            }
            .fullScreenCover(item: $previewImage) { image in
                if let file = previewFile {
                    ImagePreviewView(image: image, file: file, viewModel: viewModel)
                        .onDisappear { previewFile = nil }
                }
            }
            .fullScreenCover(item: $previewPDFDocument) { document in
                if let file = previewFile {
                    PDFPreviewView(pdfDocument: document, file: file, viewModel: viewModel)
                        .onDisappear { previewFile = nil }
                }
            }
            .alert(
                NSLocalizedString("album.preview.failed.title", comment: ""),
                isPresented: $showPreviewFailedAlert,
                presenting: previewFailedFile
            ) { file in
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
                Button(
                    NSLocalizedString("album.preview.deleteRecord", comment: ""), role: .destructive
                ) {
                    viewModel.deleteFile(file)
                }
            } message: { _ in
                Text(NSLocalizedString("album.preview.failed.message", comment: ""))
            }
            .alert(
                NSLocalizedString("album.batchDelete.title", comment: ""),
                isPresented: $showBatchDeleteAlert
            ) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                    let filesToDelete = viewModel.redactedFiles.filter {
                        selectedFileIDs.contains($0.id)
                    }
                    viewModel.deleteFiles(filesToDelete)
                    selectedFileIDs.removeAll()
                    isSelectionMode = false
                }
            } message: {
                Text(
                    String(
                        format: NSLocalizedString("album.batchDelete.message", comment: ""),
                        selectedFileIDs.count))
            }
            .alert(
                NSLocalizedString("common.error", comment: ""),
                isPresented: $viewModel.showError
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                viewModel.loadFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) {
                _ in
                viewModel.loadFiles()
            }
            .onDisappear {
                previewTask?.cancel()
                isLoadingPreview = false
            }
            .onChange(of: selectedTab) { _, newValue in
                // 切到相册（tag 1）以外的 Tab 时取消进行中的预览加载，避免完成后在其他 Tab 上弹出全屏预览
                if newValue != 1 {
                    previewTask?.cancel()
                    isLoadingPreview = false
                }
            }
        }
    }

    // MARK: - 统计卡片

    private var statisticsCard: some View {
        StatisticsCardView(files: viewModel.redactedFiles)
    }

    // MARK: - 空状态视图

    private var emptyStateView: some View {
        EmptyStateView(selectedTab: $selectedTab)
    }

    // MARK: - 脱敏文件网格视图

    private var redactedFilesGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 16
            ) {
                // 用 objectID 做标识：对象删除后 \.id 键路径取非可选 UUID 会崩溃，objectID 永远有效
                ForEach(viewModel.redactedFiles, id: \.objectID) { file in
                    RedactedFileGridItem(
                        file: file,
                        viewModel: viewModel,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedFileIDs.contains(file.id)
                    )
                    .onTapGesture {
                        if isSelectionMode {
                            toggleSelection(for: file)
                        } else {
                            previewTask?.cancel()
                            isLoadingPreview = true
                            previewTask = Task {
                                await loadAndShowPreview(file: file)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 多选删除操作栏

    private var selectionActionBar: some View {
        HStack {
            Text(
                String(
                    format: NSLocalizedString("album.batchDelete.selectedCount", comment: ""),
                    selectedFileIDs.count)
            )
            .font(.subheadline)
            .foregroundColor(DesignSystem.Colors.textSecondary)

            Spacer()

            Button(role: .destructive) {
                showBatchDeleteAlert = true
            } label: {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
            }
            .disabled(selectedFileIDs.isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundCard)
    }

    private func toggleSelection(for file: RedactedFile) {
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
        } else {
            selectedFileIDs.insert(file.id)
        }
    }

    // MARK: - 加载并显示预览

    private func loadAndShowPreview(file: RedactedFile) async {
        guard FileManager.default.fileExists(atPath: file.fullFilePath) else {
            print("❌ 文件不存在: \(file.fullFilePath)")
            if Task.isCancelled { return }
            await MainActor.run {
                previewFailedFile = file
                showPreviewFailedAlert = true
                isLoadingPreview = false
            }
            return
        }

        do {
            let data = try StorageManager.shared.loadRedactedFile(
                id: file.id,
                type: file.fileType
            )

            if Task.isCancelled { return }

            if file.fileType == .pdf {
                await loadPDFPreview(file: file, data: data)
            } else {
                await loadImagePreview(file: file, data: data)
            }
        } catch {
            print("❌ 加载预览失败: \(error)")
            if Task.isCancelled { return }
            await MainActor.run {
                previewFailedFile = file
                showPreviewFailedAlert = true
                isLoadingPreview = false
            }
        }
    }

    // MARK: - 加载图片预览

    private func loadImagePreview(file: RedactedFile, data: Data) async {
        if let image = UIImage(data: data) {
            if Task.isCancelled { return }
            await MainActor.run {
                self.previewFile = file
                self.previewImage = image
                isLoadingPreview = false
            }
        } else {
            if Task.isCancelled { return }
            await MainActor.run {
                previewFailedFile = file
                showPreviewFailedAlert = true
                isLoadingPreview = false
            }
        }
    }

    // MARK: - 加载 PDF 预览

    private func loadPDFPreview(file: RedactedFile, data: Data) async {
        if let document = PDFDocument(data: data) {
            if Task.isCancelled { return }
            await MainActor.run {
                self.previewFile = file
                self.previewPDFDocument = document
                isLoadingPreview = false
            }
        } else {
            if Task.isCancelled { return }
            await MainActor.run {
                previewFailedFile = file
                showPreviewFailedAlert = true
                isLoadingPreview = false
            }
        }
    }
}

// MARK: - 脱敏文件网格项

struct RedactedFileGridItem: View {
    let file: RedactedFile
    @ObservedObject var viewModel: AlbumViewModel
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    @State private var showDeleteAlert = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // 对象删除保存后属性变为 nil，而 SwiftUI 可能在列表刷新过渡期间再次对残留视图求值，
        // 此时访问非可选属性会崩溃，直接跳过渲染
        if file.isDeleted || file.managedObjectContext == nil {
            Color.clear
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
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
                                        .tint(DesignSystem.Colors.successGreen)
                                } else if let thumbnail = thumbnailImage {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: innerSize, height: innerSize)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: DesignSystem.CornerRadius.medium - 2))
                                } else {
                                    VStack(spacing: 6) {
                                        Image(
                                            systemName: file.fileType == .image
                                                ? "photo.fill" : "doc.text.fill"
                                        )
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(DesignSystem.Gradients.success)
                                        Text(NSLocalizedString("album.redacted", comment: ""))
                                            .font(.caption2)
                                            .foregroundColor(DesignSystem.Colors.successGreen)
                                    }
                                }
                            }
                        }
                        // 脱敏徽章
                        .overlay(alignment: .topTrailing) {
                            RedactedBadge(size: 26)
                                .padding(4)
                        }
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? DesignSystem.Colors.primaryBlue : .white)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.white : Color.black.opacity(0.35))
                                .padding(-3)
                        )
                        .padding(8)
                }
            }

            // 文件信息
            VStack(spacing: 2) {
                Text(NSLocalizedString("album.redacted", comment: ""))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.successGreen)

                Text(file.exportedAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
            }
        }
        .alert(
            NSLocalizedString("album.delete.title", comment: ""),
            isPresented: $showDeleteAlert
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                viewModel.deleteFile(file)
            }
        } message: {
            Text(NSLocalizedString("album.delete.message", comment: ""))
        }
        .task {
            await loadThumbnail()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 无障碍

    private var accessibilityLabelText: String {
        String(
            format: NSLocalizedString("import.accessibility.fileLabel", comment: ""),
            file.fileType.displayName,
            file.exportedAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func loadThumbnail() async {
        let cacheKey = "redacted_thumbnail_\(file.id.uuidString)"

        if let cachedImage = ImageCache.shared.getImage(forKey: cacheKey) {
            await MainActor.run {
                thumbnailImage = cachedImage
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fullThumbnailPath = file.fullThumbnailPath
            if !fullThumbnailPath.isEmpty {
                if FileManager.default.fileExists(atPath: fullThumbnailPath) {
                    let thumbData = try Data(contentsOf: URL(fileURLWithPath: fullThumbnailPath))
                    if let image = UIImage(data: thumbData) {
                        ImageCache.shared.setImage(image, forKey: cacheKey)
                        await MainActor.run {
                            thumbnailImage = image
                        }
                        return
                    }
                }
            }

            let data = try StorageManager.shared.loadRedactedFile(
                id: file.id,
                type: file.fileType
            )

            let image: UIImage?
            if file.fileType == .pdf {
                if let pdfDocument = PDFDocument(data: data),
                    let firstPage = pdfDocument.page(at: 0)
                {
                    let pageRect = firstPage.bounds(for: .mediaBox)
                    let thumbnailSize = CGSize(width: 200, height: 200)
                    let scale = min(
                        thumbnailSize.width / pageRect.width,
                        thumbnailSize.height / pageRect.height)
                    let scaledSize = CGSize(
                        width: pageRect.width * scale,
                        height: pageRect.height * scale)

                    let renderer = UIGraphicsImageRenderer(size: scaledSize)
                    image = renderer.image { context in
                        UIColor.white.setFill()
                        context.fill(CGRect(origin: .zero, size: scaledSize))
                        context.cgContext.translateBy(x: 0, y: scaledSize.height)
                        context.cgContext.scaleBy(x: scale, y: -scale)
                        firstPage.draw(with: .mediaBox, to: context.cgContext)
                    }
                } else {
                    image = nil
                }
            } else {
                image = UIImage(data: data)
            }

            if let finalImage = image {
                ImageCache.shared.setImage(finalImage, forKey: cacheKey)
                await MainActor.run {
                    thumbnailImage = finalImage
                }
            }
        } catch {
            print("❌ 加载脱敏文件缩略图失败: \(error)")
        }
    }
}

// MARK: - 信息行组件

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

// MARK: - 系统分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 图片预览视图

struct ImagePreviewView: View {
    let image: UIImage
    let file: RedactedFile
    @ObservedObject var viewModel: AlbumViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                    .accessibilityLabel(NSLocalizedString("common.close", comment: ""))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
                        FilePreviewActionsMenu(file: file, viewModel: viewModel) {
                            dismiss()
                        }
                        .foregroundColor(.white)

                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                        .accessibilityLabel(NSLocalizedString("album.shareFile", comment: ""))
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [image])
            }
        }
    }
}

// MARK: - 预览操作菜单（信息 / 移动分组 / 删除）

struct FilePreviewActionsMenu: View {
    let file: RedactedFile
    @ObservedObject var viewModel: AlbumViewModel
    let onDelete: () -> Void

    @State private var showInfoSheet = false
    @State private var showGroupPicker = false
    @State private var showDeleteAlert = false

    var body: some View {
        Menu {
            Button {
                showInfoSheet = true
            } label: {
                Label(NSLocalizedString("album.fileInfo", comment: ""), systemImage: "info.circle")
            }

            Button {
                viewModel.loadGroups()
                showGroupPicker = true
            } label: {
                Label(NSLocalizedString("group.moveTo", comment: ""), systemImage: "folder")
            }

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
        .accessibilityLabel(NSLocalizedString("album.moreActions", comment: ""))
        .sheet(isPresented: $showInfoSheet) {
            FileInfoSheet(file: file)
        }
        .sheet(isPresented: $showGroupPicker) {
            RedactedFileGroupPicker(
                redactedFile: file,
                allGroups: viewModel.allGroups,
                currentGroup: file.group,
                onGroupSelected: { newGroup in
                    viewModel.moveFileToGroup(file, group: newGroup)
                    showGroupPicker = false
                }
            )
        }
        .alert(
            NSLocalizedString("album.delete.title", comment: ""),
            isPresented: $showDeleteAlert
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                viewModel.deleteFile(file)
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("album.delete.message", comment: ""))
        }
    }
}

// MARK: - 文件信息卡片

struct FileInfoSheet: View {
    let file: RedactedFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // 对象删除后属性变为 nil，访问非可选属性会崩溃，直接跳过渲染
        if file.isDeleted || file.managedObjectContext == nil {
            Color.clear
        } else {
            infoContent
        }
    }

    private var infoContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(
                    label: NSLocalizedString("album.exportTime", comment: ""),
                    value: file.formattedExportedAt)
                InfoRow(
                    label: NSLocalizedString("album.fileSize", comment: ""),
                    value: file.formattedFileSize)
                InfoRow(
                    label: NSLocalizedString("album.fileType", comment: ""),
                    value: file.fileType == .image
                        ? NSLocalizedString("album.fileType.image", comment: "")
                        : NSLocalizedString("album.fileType.pdf", comment: ""))
            }
            .cardStyle()
            .padding()
            .navigationTitle(NSLocalizedString("album.fileInfo", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 脱敏文件分组选择器

struct RedactedFileGroupPicker: View {
    let redactedFile: RedactedFile
    let allGroups: [FileGroup]
    let currentGroup: FileGroup?
    let onGroupSelected: (FileGroup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(allGroups, id: \.id) { group in
                    Button(action: {
                        onGroupSelected(group)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: group.iconName ?? "folder.fill")
                                .font(.title3)
                                .foregroundColor(Color(hex: group.colorTag ?? "#8E8E93"))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(hex: group.colorTag ?? "#8E8E93").opacity(0.15))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name ?? NSLocalizedString("group.unnamed", comment: ""))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                let fileCount = GroupManager.shared.getRedactedFiles(in: group)
                                    .count
                                if fileCount > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "album.redactedCount", comment: ""), fileCount)
                                    )
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                } else {
                                    Text(NSLocalizedString("group.empty", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                            }

                            Spacer()

                            if group.id == currentGroup?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.primaryBlue)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("group.moveTo", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AlbumView(selectedTab: .constant(1))
}
