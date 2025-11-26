//
//  OriginalFileGridItem.swift
//  ZeroNet Redact
//
//  原始文件网格项组件
//

import SwiftUI

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
                                    placeholderView
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
            fileInfoView
        }
        .task {
            await loadThumbnail()
        }
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
            Text("原文件")
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.textTertiary)
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
