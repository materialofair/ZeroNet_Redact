import SwiftUI

/// 相册统计卡片视图
/// 显示脱敏文件的总数和类型分布统计（单行紧凑版）
struct StatisticsCardView: View {
    let files: [RedactedFile]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // 盾牌图标
            shieldIcon

            // 统计信息
            statisticsInfo

            Spacer()

            // 类型分布（横向紧凑胶囊，不再竖向占三行）
            typeDistribution
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    // MARK: - 子视图

    private var shieldIcon: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Gradients.success)
                .frame(width: 32, height: 32)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var statisticsInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString("album.secured", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            HStack(spacing: 4) {
                Text("\(files.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(NSLocalizedString("album.files", comment: ""))
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }

    private var typeDistribution: some View {
        HStack(spacing: 6) {
            let imageCount = files.filter { $0.fileType == .image }.count
            let pdfCount = files.filter { $0.fileType == .pdf }.count
            let videoCount = files.filter { $0.fileType == .video }.count

            if imageCount > 0 {
                typeChip(icon: "photo.fill", count: imageCount, color: DesignSystem.Colors.primaryBlue)
            }

            if pdfCount > 0 {
                typeChip(icon: "doc.fill", count: pdfCount, color: DesignSystem.Colors.warningOrange)
            }

            if videoCount > 0 {
                typeChip(icon: "video.fill", count: videoCount, color: DesignSystem.Colors.successGreen)
            }
        }
    }

    private func typeChip(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.backgroundSecondary, in: Capsule())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
            .fill(DesignSystem.Colors.backgroundCard)
            .shadow(
                color: DesignSystem.Shadow.cardShadow(for: colorScheme),
                radius: 6, x: 0, y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Shadow.cardBorder(for: colorScheme), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview {
    StatisticsCardView(files: [])
        .padding()
}
