import SwiftUI

/// 关于页面 - 介绍应用理念和相关信息
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // MARK: - App 品牌展示
                    brandSection

                    // MARK: - 核心理念
                    philosophySection

                    // MARK: - 链接入口
                    linksSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("about.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }

    // MARK: - 品牌展示

    private var brandSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // App 图标
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: DesignSystem.Colors.primaryBlue.opacity(0.3), radius: 12, x: 0, y: 6)

            // App 名称
            Text("ZeroNet Redact")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // 版本号
            Text(String(format: NSLocalizedString("about.version", comment: ""), "1.0.0"))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // 一句话描述
            Text(NSLocalizedString("about.tagline", comment: ""))
                .font(.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }

    // MARK: - 核心理念

    private var philosophySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            // 标题
            Text(NSLocalizedString("about.philosophy.title", comment: ""))
                .font(.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // 理念卡片
            VStack(spacing: DesignSystem.Spacing.md) {
                PhilosophyCard(
                    icon: "wifi.slash",
                    iconColor: DesignSystem.Colors.primaryBlue,
                    title: NSLocalizedString("about.philosophy.offline.title", comment: ""),
                    description: NSLocalizedString("about.philosophy.offline.desc", comment: "")
                )

                PhilosophyCard(
                    icon: "iphone",
                    iconColor: DesignSystem.Colors.successGreen,
                    title: NSLocalizedString("about.philosophy.local.title", comment: ""),
                    description: NSLocalizedString("about.philosophy.local.desc", comment: "")
                )

                PhilosophyCard(
                    icon: "eye.slash.fill",
                    iconColor: DesignSystem.Colors.primaryPurple,
                    title: NSLocalizedString("about.philosophy.privacy.title", comment: ""),
                    description: NSLocalizedString("about.philosophy.privacy.desc", comment: "")
                )

                PhilosophyCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    iconColor: DesignSystem.Colors.warningOrange,
                    title: NSLocalizedString("about.philosophy.openSource.title", comment: ""),
                    description: NSLocalizedString("about.philosophy.openSource.desc", comment: "")
                )
            }
        }
    }

    // MARK: - 链接入口

    private var linksSection: some View {
        VStack(spacing: 0) {
            // GitHub 项目
            Link(destination: URL(string: "https://github.com/materialofair/ZeroNet-Redact")!) {
                LinkRow(
                    icon: "link",
                    iconColor: Color(hex: "333333"),
                    title: NSLocalizedString("about.github", comment: ""),
                    subtitle: NSLocalizedString("about.github.desc", comment: "")
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 52)

            // 反馈建议
            Link(
                destination: URL(string: "https://github.com/materialofair/ZeroNet-Redact/issues")!
            ) {
                LinkRow(
                    icon: "bubble.left.fill",
                    iconColor: DesignSystem.Colors.primaryBlue,
                    title: NSLocalizedString("about.feedback", comment: ""),
                    subtitle: NSLocalizedString("about.feedback.desc", comment: "")
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 52)

            // 隐私政策
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                LinkRow(
                    icon: "hand.raised.fill",
                    iconColor: DesignSystem.Colors.successGreen,
                    title: NSLocalizedString("about.privacy", comment: ""),
                    subtitle: NSLocalizedString("about.privacy.desc", comment: ""),
                    showChevron: true
                )
            }
            .buttonStyle(.plain)
        }
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Philosophy Card Component

private struct PhilosophyCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.12))
                .cornerRadius(10)

            // 文字内容
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Link Row Component

private struct LinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor)
                )

            // 文字
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            Spacer()

            // 箭头
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // 核心承诺
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text(NSLocalizedString("privacy.promise.title", comment: ""))
                        .font(.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(NSLocalizedString("privacy.promise.content", comment: ""))
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineSpacing(4)
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.large)

                // 数据处理
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text(NSLocalizedString("privacy.data.title", comment: ""))
                        .font(.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    PrivacyItem(
                        icon: "checkmark.circle.fill",
                        color: DesignSystem.Colors.successGreen,
                        text: NSLocalizedString("privacy.data.item1", comment: "")
                    )

                    PrivacyItem(
                        icon: "checkmark.circle.fill",
                        color: DesignSystem.Colors.successGreen,
                        text: NSLocalizedString("privacy.data.item2", comment: "")
                    )

                    PrivacyItem(
                        icon: "checkmark.circle.fill",
                        color: DesignSystem.Colors.successGreen,
                        text: NSLocalizedString("privacy.data.item3", comment: "")
                    )

                    PrivacyItem(
                        icon: "xmark.circle.fill",
                        color: DesignSystem.Colors.dangerRed,
                        text: NSLocalizedString("privacy.data.item4", comment: "")
                    )

                    PrivacyItem(
                        icon: "xmark.circle.fill",
                        color: DesignSystem.Colors.dangerRed,
                        text: NSLocalizedString("privacy.data.item5", comment: "")
                    )
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.large)

                // 联系方式
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text(NSLocalizedString("privacy.contact.title", comment: ""))
                        .font(.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(NSLocalizedString("privacy.contact.content", comment: ""))
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineSpacing(4)
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.large)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("privacy.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Item Component

private struct PrivacyItem: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(text)
                .font(.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}

#Preview {
    AboutView()
}
