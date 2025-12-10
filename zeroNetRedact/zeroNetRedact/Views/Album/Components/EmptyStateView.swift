import SwiftUI

/// 相册空状态视图
/// 当没有脱敏文件时显示的引导视图
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // 图标
                iconView

                // 标题
                Text(NSLocalizedString("album.empty", comment: ""))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                // 步骤指示器
                StepIndicatorView()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            .padding(.horizontal, DesignSystem.Spacing.xxxl)

            Spacer()
            Spacer()
        }
    }

    // MARK: - 子视图

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Gradients.lightBackground)
                .frame(width: 100, height: 100)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(DesignSystem.Gradients.success)
        }
    }
}

// MARK: - 步骤指示器

struct StepIndicatorView: View {
    var body: some View {
        HStack(spacing: 0) {
            // 步骤 1
            stepItem(
                number: "1",
                icon: "square.and.arrow.down",
                title: NSLocalizedString("album.step.import", comment: "")
            )

            // 连接线
            connectorLine

            // 步骤 2
            stepItem(
                number: "2",
                icon: "hand.draw",
                title: NSLocalizedString("album.step.redact", comment: "")
            )

            // 连接线
            connectorLine

            // 步骤 3
            stepItem(
                number: "3",
                icon: "checkmark.circle",
                title: NSLocalizedString("album.step.done", comment: "")
            )
        }
        .padding(.vertical, DesignSystem.Spacing.lg)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(Color.gray.opacity(0.06))
        )
    }

    // MARK: - 子视图

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

    private var connectorLine: some View {
        Rectangle()
            .fill(DesignSystem.Colors.primaryBlue.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    EmptyStateView()
}
