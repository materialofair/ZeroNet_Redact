import SwiftUI

// MARK: - Design System for ZeroNet Redact

/// 设计系统 - 统一的颜色、渐变、样式
enum DesignSystem {

    // MARK: - Colors (Dark/Light Theme Adaptive)

    enum Colors {
        /// 主蓝色
        static let primaryBlue = Color(hex: "007AFF")
        /// 主紫色
        static let primaryPurple = Color(hex: "5856D6")
        /// 成功绿
        static let successGreen = Color(hex: "34C759")
        /// 成功薄荷绿
        static let successMint = Color(hex: "30D158")
        /// 警告橙
        static let warningOrange = Color(hex: "FF9500")
        /// 危险红
        static let dangerRed = Color(hex: "FF3B30")

        /// 背景色 - 自动适配深色/浅色主题
        static let backgroundPrimary = Color(uiColor: .systemGroupedBackground)
        static let backgroundSecondary = Color(uiColor: .secondarySystemGroupedBackground)
        static let backgroundCard = Color(uiColor: .secondarySystemGroupedBackground)
        static let backgroundElevated = Color(uiColor: .tertiarySystemGroupedBackground)

        /// 分隔线颜色
        static let separator = Color(uiColor: .separator)
        static let separatorOpaque = Color(uiColor: .opaqueSeparator)

        /// 文字色 - 自动适配深色/浅色主题
        static let textPrimary = Color(uiColor: .label)
        static let textSecondary = Color(uiColor: .secondaryLabel)
        static let textTertiary = Color(uiColor: .tertiaryLabel)
        static let textQuaternary = Color(uiColor: .quaternaryLabel)

        /// 填充色 - 自动适配深色/浅色主题
        static let fillPrimary = Color(uiColor: .systemFill)
        static let fillSecondary = Color(uiColor: .secondarySystemFill)
        static let fillTertiary = Color(uiColor: .tertiarySystemFill)
        static let fillQuaternary = Color(uiColor: .quaternarySystemFill)
    }

    // MARK: - Gradients

    enum Gradients {
        /// 主色渐变（蓝紫）
        static let primary = LinearGradient(
            colors: [Colors.primaryBlue, Colors.primaryPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 成功渐变（绿色）
        static let success = LinearGradient(
            colors: [Colors.successGreen, Colors.successMint],
            startPoint: .top,
            endPoint: .bottom
        )

        /// 图片类型渐变（青蓝）
        static let imageType = LinearGradient(
            colors: [Color.cyan, Colors.primaryBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// PDF类型渐变（橙红）
        static let pdfType = LinearGradient(
            colors: [Colors.warningOrange, Color(hex: "FF6B35")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 危险渐变（红色）
        static let danger = LinearGradient(
            colors: [Colors.dangerRed, Color(hex: "FF6B6B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 浅色背景渐变
        static let lightBackground = LinearGradient(
            colors: [Colors.primaryBlue.opacity(0.08), Colors.primaryPurple.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 20
        static let circular: CGFloat = 100
    }

    // MARK: - Shadow (Theme Adaptive)

    enum Shadow {
        /// 卡片阴影颜色 - 浅色模式显示，深色模式隐藏
        static func cardShadow(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .clear : .black.opacity(0.06)
        }

        static func cardShadowSecondary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .clear : .black.opacity(0.04)
        }

        /// 边框颜色 - 深色模式显示，浅色模式隐藏
        static func cardBorder(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .white.opacity(0.1) : .clear
        }
    }
}

// MARK: - View Modifiers

/// 标准卡片样式 - 自动适配深色/浅色主题
struct CardStyle: ViewModifier {
    var padding: CGFloat = DesignSystem.Spacing.lg
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.backgroundCard)
            .cornerRadius(DesignSystem.CornerRadius.large)
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.06),
                radius: 12, x: 0, y: 4
            )
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.04),
                radius: 1, x: 0, y: 1
            )
            .overlay(
                // 深色模式下添加边框增强层次感
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear,
                        lineWidth: 1
                    )
            )
    }
}

/// 悬浮卡片样式（毛玻璃）
struct ElevatedCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.lg)
            .background(.ultraThinMaterial)
            .cornerRadius(DesignSystem.CornerRadius.extraLarge)
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }
}

/// 渐变按钮样式
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = DesignSystem.Gradients.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(gradient)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 描边按钮样式
struct OutlineButtonStyle: ButtonStyle {
    var color: Color = DesignSystem.Colors.primaryBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(color.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    /// 应用标准卡片样式
    func cardStyle(padding: CGFloat = DesignSystem.Spacing.lg) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// 应用悬浮卡片样式
    func elevatedCardStyle() -> some View {
        modifier(ElevatedCardStyle())
    }
}

// MARK: - Color Extension

extension Color {
    /// 从十六进制字符串创建颜色
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Icon Badge Components

/// 文件类型徽章
struct FileTypeBadge: View {
    let fileType: FileType
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: fileType == .image ? "photo.fill" : "doc.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(
                        fileType == .image
                            ? DesignSystem.Gradients.imageType : DesignSystem.Gradients.pdfType)
            )
            .shadow(
                color: (fileType == .image ? Color.cyan : DesignSystem.Colors.warningOrange)
                    .opacity(0.4), radius: 4, x: 0, y: 2)
    }
}

/// 脱敏完成徽章
struct RedactedBadge: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(DesignSystem.Gradients.success)
            )
            .shadow(color: DesignSystem.Colors.successGreen.opacity(0.4), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Section Header

/// 设置页面的 Section 标题
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.xl)
            .padding(.bottom, DesignSystem.Spacing.sm)
    }
}

// MARK: - Settings Row

/// 设置项行
struct SettingsRow<Accessory: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let accessory: () -> Accessory

    init(
        icon: String,
        iconColor: Color = DesignSystem.Colors.primaryBlue,
        title: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.accessory = accessory
    }

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

            // 标题
            Text(title)
                .font(.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            // 附件视图
            accessory()
        }
        .padding(.vertical, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

// MARK: - Preview

#Preview("Design System") {
    ScrollView {
        VStack(spacing: 20) {
            // 卡片示例
            Text("Card Style")
                .cardStyle()

            // 徽章示例
            HStack(spacing: 16) {
                FileTypeBadge(fileType: .image)
                FileTypeBadge(fileType: .pdf)
                RedactedBadge()
            }

            // 按钮示例
            Button("Primary Button") {}
                .buttonStyle(GradientButtonStyle())

            Button("Outline Button") {}
                .buttonStyle(OutlineButtonStyle())
        }
        .padding()
    }
    .background(DesignSystem.Colors.backgroundPrimary)
}
