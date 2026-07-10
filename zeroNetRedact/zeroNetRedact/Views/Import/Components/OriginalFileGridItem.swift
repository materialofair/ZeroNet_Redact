//
//  OriginalFileGridItem.swift
//  ZeroNet Redact
//
//  原始文件网格项组件
//

import CoreData
import SwiftUI

struct OriginalFileGridItem: View {
    let file: OriginalFile
    @ObservedObject var viewModel: ImportViewModel
    let isSelectionMode: Bool
    let isSelected: Bool
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    @State private var thumbnailLoadFailed = false
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
                                        .tint(DesignSystem.Colors.primaryBlue)
                                } else if let thumbnail = thumbnailImage {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: innerSize, height: innerSize)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: DesignSystem.CornerRadius.medium - 2))
                                } else if thumbnailLoadFailed {
                                    // 缩略图加载失败态
                                    failedPlaceholderView
                                } else {
                                    // 占位图标
                                    placeholderView
                                }
                            }
                        }
                        // 类型徽章
                        .overlay(alignment: .topLeading) {
                            FileTypeBadge(fileType: file.fileType)
                                .padding(4)
                        }
                        // 多选模式勾选标记
                        .overlay(alignment: .topTrailing) {
                            if isSelectionMode {
                                selectionIndicator
                                    .padding(4)
                            }
                        }
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(6)
            }

            // 文件信息
            fileInfoView
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
            }
        }
        .alert(
            NSLocalizedString("import.delete.title", comment: ""),
            isPresented: $showDeleteAlert
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                viewModel.deleteFile(file)
            }
        } message: {
            Text(NSLocalizedString("import.delete.message", comment: ""))
        }
        .task {
            await loadThumbnail()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(
            NSLocalizedString(
                isSelectionMode ? "import.accessibility.selectHint" : "import.accessibility.editHint",
                comment: "")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text(NSLocalizedString("common.delete", comment: ""))) {
            showDeleteAlert = true
        }
    }

    // MARK: - 无障碍

    private var accessibilityLabelText: String {
        String(
            format: NSLocalizedString("import.accessibility.fileLabel", comment: ""),
            file.fileType.displayName,
            file.createdAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    // MARK: - 子视图

    /// 占位图标视图
    private var placeholderView: some View {
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
            Text(NSLocalizedString("file.original", comment: ""))
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
    }

    /// 缩略图加载失败态视图
    private var failedPlaceholderView: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(DesignSystem.Colors.dangerRed)
            Text(NSLocalizedString("import.thumbnail.loadFailed", comment: ""))
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
    }

    /// 多选模式勾选标记
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? DesignSystem.Colors.primaryBlue : Color.black.opacity(0.35))
                .frame(width: 20, height: 20)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
            }
        }
    }

    /// 文件信息视图
    private var fileInfoView: some View {
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

    // MARK: - 缩略图加载

    private func loadThumbnail() async {
        let cacheKey = "original_thumbnail_\(file.id.uuidString)"

        // 先检查缓存
        if let cachedImage = ImageCache.shared.getImage(forKey: cacheKey) {
            await MainActor.run {
                thumbnailImage = cachedImage
                thumbnailLoadFailed = false
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
                    thumbnailLoadFailed = false
                }
            } else {
                print("❌ 原文件缩略图数据无法解码为图片: \(file.id)")
                await MainActor.run {
                    thumbnailLoadFailed = true
                }
            }
        } catch {
            print("❌ 加载原文件缩略图失败: \(error)")
            await MainActor.run {
                thumbnailLoadFailed = true
            }
        }
    }
}
