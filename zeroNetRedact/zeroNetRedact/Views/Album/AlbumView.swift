import CoreData
import PDFKit
import SwiftUI

// MARK: - PDFDocument扩展，使其可用于fullScreenCover的item绑定

extension PDFDocument: @retroactive Identifiable {
    public var id: String {
        // 使用文档的内存地址作为唯一标识
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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 分组选择器
                RedactedGroupSelectorBar(viewModel: viewModel)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))

                Divider()

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
            .navigationTitle("脱敏文件")
            .navigationBarTitleDisplayMode(.large)

            .fullScreenCover(item: $previewImage) { image in
                ImagePreviewView(image: image)
            }
            .fullScreenCover(item: $previewPDFDocument) { document in
                let _ = print("📄 [AlbumView] fullScreenCover被触发，文档页数: \(document.pageCount)")
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

    // MARK: - 空状态视图

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // 图标组 - 多层叠加效果
                ZStack {
                    // 背景圆圈
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    // 主图标
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.bottom, 8)

                // 标题
                Text("还没有脱敏文件")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                // 描述
                VStack(spacing: 8) {
                    Text("从导入页面添加文件并完成脱敏")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("脱敏后的文件会出现在这里")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                }

                // 步骤提示
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("1")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.blue))

                        Text("导入图片或PDF文件")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("2")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.blue))

                        Text("使用涂抹工具进行脱敏")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("3")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.blue))

                        Text("点击\"应用\"完成导出")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - 脱敏文件网格视图

    private var redactedFilesGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ],
                spacing: 12
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
            .padding()
        }
    }

    // MARK: - 加载并显示预览

    private func loadAndShowPreview(file: RedactedFile) async {
        do {
            print("🔍 [直接预览] 开始加载: \(file.id)")
            print("🔍 文件类型: \(file.fileType)")
            print("🔍 文件路径: \(file.fullFilePath)")

            // 验证文件存在
            guard FileManager.default.fileExists(atPath: file.fullFilePath) else {
                print("❌ 文件不存在: \(file.fullFilePath)")
                return
            }

            // 读取脱敏文件
            let data = try StorageManager.shared.loadRedactedFile(
                id: file.id,
                type: file.fileType
            )
            print("🔍 文件数据大小: \(data.count) bytes")

            if file.fileType == .pdf {
                // PDF类型：加载文档对象
                print("🔍 开始创建PDFDocument...")
                if let document = PDFDocument(data: data) {
                    print("✅ PDFDocument创建成功，共\(document.pageCount)页")
                    // 使用item绑定，直接设置文档即可触发fullScreenCover
                    await MainActor.run {
                        self.previewPDFDocument = document
                    }
                    print("✅ PDF预览已触发显示")
                } else {
                    print("❌ 无法创建PDFDocument")
                }
            } else {
                // 图片类型
                print("🔍 开始创建UIImage...")
                if let image = UIImage(data: data) {
                    print("✅ UIImage创建成功，尺寸: \(image.size)")
                    await MainActor.run {
                        self.previewImage = image
                    }
                    print("✅ 图片预览已触发显示")
                } else {
                    print("❌ 无法创建UIImage")
                }
            }
        } catch {
            print("❌ 加载预览失败: \(error)")
            print("❌ 错误详情: \(error.localizedDescription)")
        }
    }
}

// MARK: - 脱敏文件网格项

struct RedactedFileGridItem: View {
    let file: RedactedFile
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 4) {
            // 缩略图
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
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
                            VStack {
                                Image(systemName: file.fileType == .image ? "photo" : "doc.text")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                                Text("已脱敏")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    // 脱敏标记
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.green)
                        .clipShape(Circle())
                        .offset(x: -4, y: 4)
                }

            // 文件信息
            Text(file.exportedAt, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let cacheKey = "redacted_thumbnail_\(file.id.uuidString)"

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
            print("📷 [RedactedFile缩略图] 开始加载: \(file.id)")
            print("📷 文件路径: \(file.filePath)")
            print("📷 文件类型: \(file.fileType)")

            // 检查缩略图路径是否存在
            let fullThumbnailPath = file.fullThumbnailPath
            if !fullThumbnailPath.isEmpty {
                print("📷 尝试加载已保存的缩略图: \(fullThumbnailPath)")
                if FileManager.default.fileExists(atPath: fullThumbnailPath) {
                    let thumbData = try Data(contentsOf: URL(fileURLWithPath: fullThumbnailPath))
                    if let image = UIImage(data: thumbData) {
                        print("✅ 缩略图加载成功")
                        ImageCache.shared.setImage(image, forKey: cacheKey)
                        await MainActor.run {
                            thumbnailImage = image
                        }
                        return
                    }
                } else {
                    print("⚠️ 缩略图文件不存在: \(fullThumbnailPath)")
                }
            }

            // 如果没有缩略图，直接读取脱敏文件（明文存储）
            print("📷 加载完整文件作为缩略图")
            let data = try StorageManager.shared.loadRedactedFile(
                id: file.id,
                type: file.fileType
            )
            print("📷 文件数据大小: \(data.count) bytes")

            // 根据文件类型创建缩略图
            let image: UIImage?
            if file.fileType == .pdf {
                // PDF类型：使用PDFKit生成缩略图
                print("📷 PDF文件，使用PDFKit生成缩略图")
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
                    print("✅ PDF缩略图生成成功")
                } else {
                    print("❌ 无法创建PDFDocument")
                    image = nil
                }
            } else {
                // 图片类型：直接创建UIImage
                image = UIImage(data: data)
                if image != nil {
                    print("✅ 图片创建成功，尺寸: \(image!.size)")
                } else {
                    print("❌ 无法从数据创建UIImage")
                }
            }

            // 缓存并显示
            if let finalImage = image {
                ImageCache.shared.setImage(finalImage, forKey: cacheKey)
                await MainActor.run {
                    thumbnailImage = finalImage
                }
            }
        } catch {
            print("❌ 加载脱敏文件缩略图失败: \(error)")
            print("❌ 错误详情: \(error.localizedDescription)")
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
                // 文件预览
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: 300)
                } else if redactedFile.fileType == .pdf && pdfDocument != nil {
                    // PDF预览 - 显示封面和打开全屏按钮
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
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
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

                // 文件信息
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "导出时间", value: redactedFile.formattedExportedAt)
                    InfoRow(label: "文件大小", value: redactedFile.formattedFileSize)
                    InfoRow(label: "文件类型", value: redactedFile.fileType == .image ? "图片" : "PDF")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()

                // 分享按钮
                Button(action: {
                    showShareSheet = true
                }) {
                    Label("分享文件", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
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
            print("🔍 [RedactedFile预览] 开始加载: \(redactedFile.id)")
            print("🔍 相对路径: \(redactedFile.filePath)")
            print("🔍 完整路径: \(redactedFile.fullFilePath)")
            print("🔍 文件类型: \(redactedFile.fileType)")

            // 验证文件是否存在（使用完整路径）
            if !FileManager.default.fileExists(atPath: redactedFile.fullFilePath) {
                print("❌ 文件不存在: \(redactedFile.fullFilePath)")
                return
            }

            // 读取脱敏文件
            let data = try StorageManager.shared.loadRedactedFile(
                id: redactedFile.id,
                type: redactedFile.fileType
            )
            print("🔍 文件数据大小: \(data.count) bytes")

            // 根据文件类型创建预览
            let image: UIImage?
            if redactedFile.fileType == .pdf {
                // PDF类型：加载文档对象并生成第一页预览
                print("🔍 PDF文件，加载PDF文档")
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
                        print("✅ PDF预览生成成功，共\(document.pageCount)页")
                    } else {
                        print("❌ 无法获取PDF第一页")
                        image = nil
                    }
                } else {
                    print("❌ 无法创建PDFDocument")
                    image = nil
                }
            } else {
                // 图片类型
                image = UIImage(data: data)
                if image != nil {
                    print("✅ 预览图片创建成功，尺寸: \(image!.size)")
                } else {
                    print("❌ 无法从数据创建UIImage")
                }
            }

            // 显示预览
            if let finalImage = image {
                await MainActor.run {
                    previewImage = finalImage
                }
            }
        } catch {
            print("❌ 加载脱敏文件预览失败: \(error)")
            print("❌ 错误详情: \(error.localizedDescription)")
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
            print("📁 [分组加载] 共\(allGroups.count)个分组，当前分组: \(currentGroup?.name ?? "无")")
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
            print("✅ 脱敏文件已移动到分组: \(newGroup.name ?? "未命名")")
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
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
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
                            // 分组图标
                            Image(systemName: group.iconName ?? "folder.fill")
                                .font(.title3)
                                .foregroundColor(Color(hex: group.colorTag ?? "#8E8E93"))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(hex: group.colorTag ?? "#8E8E93").opacity(0.15))
                                )

                            // 分组信息
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name ?? "未命名分组")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                let fileCount = GroupManager.shared.getRedactedFiles(in: group)
                                    .count
                                if fileCount > 0 {
                                    Text("\(fileCount)个脱敏文件")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("空分组")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            // 当前分组标记
                            if group.id == currentGroup?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
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
