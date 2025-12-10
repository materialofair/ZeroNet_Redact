import SwiftUI

/// 相册统计卡片视图
/// 显示脱敏文件的总数和类型分布统计
struct StatisticsCardView: View {
    let files: [RedactedFile]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // 盾牌图标
            shieldIcon

            // 统计信息
            statisticsInfo

            Spacer()

            // 类型分布
            typeDistribution
        }
        .padding(DesignSystem.Spacing.lg)
        .background(cardBackground)
    }

    // MARK: - 子视图

    private var shieldIcon: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Gradients.success)
                .frame(width: 44, height: 44)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .shadow(color: DesignSystem.Colors.successGreen.opacity(0.3), radius: 6, x: 0, y: 3)
    }

    private var statisticsInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("album.secured", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack(spacing: 4) {
                Text("\(files.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(NSLocalizedString("album.files", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }

    private var typeDistribution: some View {
        VStack(alignment: .trailing, spacing: 4) {
            let imageCount = files.filter { $0.fileType == .image }.count
            let pdfCount = files.filter { $0.fileType == .pdf }.count

            if imageCount > 0 {
                typeCountRow(
                    icon: "photo.fill", count: imageCount, color: DesignSystem.Colors.primaryBlue)
            }

            if pdfCount > 0 {
                typeCountRow(
                    icon: "doc.fill", count: pdfCount, color: DesignSystem.Colors.warningOrange)
            }
        }
    }

    private func typeCountRow(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
            .fill(DesignSystem.Colors.backgroundCard)
            .shadow(
                color: DesignSystem.Shadow.cardShadow(for: colorScheme),
                radius: 12, x: 0, y: 4
            )
            .shadow(
                color: DesignSystem.Shadow.cardShadowSecondary(for: colorScheme),
                radius: 1, x: 0, y: 1
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
