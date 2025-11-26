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
    @State private var selectedRedactedFile: RedactedFile?
    @State private var previewImage: UIImage?
    @State private var previewPDFDocument: PDFDocument?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
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
                }
            }
            .navigationTitle("脱敏文件")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(item: $previewImage) { image in
                ImagePreviewView(image: image)
            }
            .fullScreenCover(item: $previewPDFDocument) { document in
                PDFPreviewView(pdfDocument: document)
            }
            .onAppear {
                viewModel.loadFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) {
                _ in
                viewModel.loadFiles()
            }
        }
    }

    // MARK: - 统计卡片

    private var statisticsCard: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // 盾牌图标
            ZStack {
                Circle()
                    .fill(DesignSystem.Gradients.success)
                    .frame(width: 44, height: 44)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: DesignSystem.Colors.successGreen.opacity(0.3), radius: 6, x: 0, y: 3)

            // 统计信息
            VStack(alignment: .leading, spacing: 4) {
                Text("已安全保护")
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                HStack(spacing: 4) {
                    Text("\(viewModel.redactedFiles.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text("个文件")
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            // 类型分布
            VStack(alignment: .trailing, spacing: 4) {
                let imageCount = viewModel.redactedFiles.filter { $0.fileType == .image }.count
                let pdfCount = viewModel.redactedFiles.filter { $0.fileType == .pdf }.count

                if imageCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.primaryBlue)
                        Text("\(imageCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }

                if pdfCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.warningOrange)
                        Text("\(pdfCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(DesignSystem.Colors.backgroundCard)
                .shadow(
                    color: DesignSystem.Shadow.cardShadow(for: colorScheme), radius: 12, x: 0, y: 4
                )
                .shadow(
                    color: DesignSystem.Shadow.cardShadowSecondary(for: colorScheme), radius: 1,
                    x: 0, y: 1
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Shadow.cardBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    // MARK: - 空状态视图

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // 图标
                ZStack {
                    Circle()
                        .fill(DesignSystem.Gradients.lightBackground)
                        .frame(width: 100, height: 100)

                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(DesignSystem.Gradients.success)
                }

                // 标题
                Text("还没有脱敏文件")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                // 步骤指示器
                StepIndicator()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            .padding(.horizontal, DesignSystem.Spacing.xxxl)

            Spacer()
            Spacer()
        }
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
                ForEach(viewModel.redactedFiles, id: \.id) { file in
                    RedactedFileGridItem(file: file)
                        .onTapGesture {
                            Task {
                                await loadAndShowPreview(file: file)
                            }
                        }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 加载并显示预览

    private func loadAndShowPreview(file: RedactedFile) async {
        do {
            guard FileManager.default.fileExists(atPath: file.fullFilePath) else {
                print("❌ 文件不存在: \(file.fullFilePath)")
                return
            }

            let data = try StorageManager.shared.loadRedactedFile(
                id: file.id,
                type: file.fileType
            )

            if file.fileType == .pdf {
                if let document = PDFDocument(data: data) {
                    await MainActor.run {
                        self.previewPDFDocument = document
                    }
                }
            } else {
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.previewImage = image
                    }
                }
            }
        } catch {
            print("❌ 加载预览失败: \(error)")
        }
    }
}

// MARK: - 步骤指示器

struct StepIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            // 步骤 1
            stepItem(number: "1", icon: "square.and.arrow.down", title: "导入")

            // 连接线
            Rectangle()
                .fill(DesignSystem.Colors.primaryBlue.opacity(0.3))
                .frame(height: 2)
                .frame(maxWidth: .infinity)

            // 步骤 2
            stepItem(number: "2", icon: "hand.draw", title: "涂抹")

            // 连接线
            Rectangle()
                .fill(DesignSystem.Colors.primaryBlue.opacity(0.3))
                .frame(height: 2)
                .frame(maxWidth: .infinity)

            // 步骤 3
            stepItem(number: "3", icon: "checkmark.circle", title: "完成")
        }
        .padding(.vertical, DesignSystem.Spacing.lg)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(Color.gray.opacity(0.06))
        )
    }

    private func stepItem(number: String, icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Gradients.primary)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}

// MARK: - 脱敏文件网格项

struct RedactedFileGridItem: View {
    let file: RedactedFile
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
                                        Text("已脱敏")
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

            // 文件信息
            VStack(spacing: 2) {
                Text("已脱敏")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.successGreen)

                Text(file.exportedAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .task {
            await loadThumbnail()
        }
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

// MARK: - 脱敏文件详情视图

struct RedactedFileDetailView: View {
    let redactedFile: RedactedFile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var previewImage: UIImage?
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = false
    @State private var showShareSheet = false
    @State private var showPDFViewer = false
    @State private var showGroupPicker = false
    @State private var allGroups: [FileGroup] = []
    @State private var currentGroup: FileGroup?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: 300)
                } else if redactedFile.fileType == .pdf && pdfDocument != nil {
                    VStack(spacing: 12) {
                        if let image = previewImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                        }

                        Button {
                            showPDFViewer = true
                        } label: {
                            Label("查看完整PDF", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(GradientButtonStyle())
                    }
                } else if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .overlay {
                            VStack {
                                Image(
                                    systemName: redactedFile.fileType == .image
                                        ? "photo" : "doc.text"
                                )
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                                Text("预览不可用")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "导出时间", value: redactedFile.formattedExportedAt)
                    InfoRow(label: "文件大小", value: redactedFile.formattedFileSize)
                    InfoRow(label: "文件类型", value: redactedFile.fileType == .image ? "图片" : "PDF")
                }
                .cardStyle()

                Spacer()

                Button(action: {
                    showShareSheet = true
                }) {
                    Label("分享文件", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(GradientButtonStyle())
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("脱敏文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showGroupPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: currentGroup?.iconName ?? "folder.fill")
                                .font(.callout)
                            Text(currentGroup?.name ?? "默认分组")
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        )
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if redactedFile.fileType == .pdf {
                    if let pdfData = pdfDocument?.dataRepresentation() {
                        ShareSheet(items: [pdfData])
                    }
                } else if let image = previewImage {
                    ShareSheet(items: [image])
                }
            }
            .fullScreenCover(isPresented: $showPDFViewer) {
                if let document = pdfDocument {
                    PDFPreviewView(pdfDocument: document)
                }
            }
            .sheet(isPresented: $showGroupPicker) {
                RedactedFileGroupPicker(
                    redactedFile: redactedFile,
                    allGroups: allGroups,
                    currentGroup: currentGroup,
                    onGroupSelected: { newGroup in
                        moveToGroup(newGroup)
                    }
                )
            }
            .task {
                await loadPreview()
                loadGroups()
            }
        }
    }

    private func loadPreview() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if !FileManager.default.fileExists(atPath: redactedFile.fullFilePath) {
                return
            }

            let data = try StorageManager.shared.loadRedactedFile(
                id: redactedFile.id,
                type: redactedFile.fileType
            )

            let image: UIImage?
            if redactedFile.fileType == .pdf {
                if let document = PDFDocument(data: data) {
                    await MainActor.run {
                        pdfDocument = document
                    }

                    if let firstPage = document.page(at: 0) {
                        let pageRect = firstPage.bounds(for: .mediaBox)
                        let maxWidth: CGFloat = 600
                        let scale = min(maxWidth / pageRect.width, 1.0)
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
                    image = nil
                }
            } else {
                image = UIImage(data: data)
            }

            if let finalImage = image {
                await MainActor.run {
                    previewImage = finalImage
                }
            }
        } catch {
            print("❌ 加载脱敏文件预览失败: \(error)")
        }
    }

    private func loadGroups() {
        let fetchRequest: NSFetchRequest<FileGroup> = FileGroup.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \FileGroup.createdAt, ascending: true)
        ]

        do {
            allGroups = try viewContext.fetch(fetchRequest)
            currentGroup = redactedFile.group
        } catch {
            print("❌ 加载分组失败: \(error)")
        }
    }

    private func moveToGroup(_ newGroup: FileGroup) {
        redactedFile.group = newGroup

        do {
            try viewContext.save()
            currentGroup = newGroup
            showGroupPicker = false
        } catch {
            print("❌ 移动分组失败: \(error)")
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
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationView {
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
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [image])
            }
        }
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
        NavigationView {
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
                                Text(group.name ?? "未命名分组")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                let fileCount = GroupManager.shared.getRedactedFiles(in: group)
                                    .count
                                if fileCount > 0 {
                                    Text("\(fileCount)个脱敏文件")
                                        .font(.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                } else {
                                    Text("空分组")
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
            .navigationTitle("移动到分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AlbumView()
}
