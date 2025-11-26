import SwiftUI

// MARK: - Feature Item Model

/// 特性项数据模型
private struct FeatureItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Feature Card Component

/// 单个特性卡片组件
private struct FeatureCard: View {
    let item: FeatureItem

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // 图标
            Image(systemName: item.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(item.color.gradient)
                )

            // 标题
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // 描述
            Text(item.description)
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
    }
}

// MARK: - Features Grid Component

/// 特性卡片网格 (2x2)
private struct FeaturesGridView: View {
    private let features: [FeatureItem] = [
        FeatureItem(
            icon: "wifi.slash",
            title: NSLocalizedString("feature.zeroNetwork.title", comment: ""),
            description: NSLocalizedString("feature.zeroNetwork.desc", comment: ""),
            color: DesignSystem.Colors.primaryBlue
        ),
        FeatureItem(
            icon: "lock.shield.fill",
            title: NSLocalizedString("feature.localRedact.title", comment: ""),
            description: NSLocalizedString("feature.localRedact.desc", comment: ""),
            color: DesignSystem.Colors.successGreen
        ),
        FeatureItem(
            icon: "hand.raised.fill",
            title: NSLocalizedString("feature.privacy.title", comment: ""),
            description: NSLocalizedString("feature.privacy.desc", comment: ""),
            color: DesignSystem.Colors.primaryPurple
        ),
        FeatureItem(
            icon: "chevron.left.forwardslash.chevron.right",
            title: NSLocalizedString("feature.openSource.title", comment: ""),
            description: NSLocalizedString("feature.openSource.desc", comment: ""),
            color: DesignSystem.Colors.warningOrange
        ),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.md) {
            ForEach(features) { feature in
                FeatureCard(item: feature)
            }
        }
    }
}

// MARK: - Password Setup Sheet

/// 密码设置界面 - 用于首次设置密码
struct PasswordSetupSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = PasswordSetupViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // 品牌头部
                    brandHeaderSection

                    // 核心特性网格
                    FeaturesGridView()

                    // 分隔提示
                    setupPromptSection

                    // 密码输入卡片
                    passwordInputSection

                    // 生物识别选项
                    if viewModel.isBiometricAvailable {
                        biometricSection
                    }

                    // 错误提示
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }

                    // 操作按钮
                    actionButtons

                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Brand Header Section

    private var brandHeaderSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // App 图标
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: DesignSystem.Colors.primaryBlue.opacity(0.3), radius: 12, x: 0, y: 6)

            // App 名称
            Text("ZeroNet Redact")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // Slogan
            Text(NSLocalizedString("passwordSetup.brand.slogan", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.top, DesignSystem.Spacing.xl)
    }

    // MARK: - Setup Prompt Section

    private var setupPromptSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Rectangle()
                .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                .frame(height: 1)

            Text(NSLocalizedString("passwordSetup.brand.subtitle", comment: ""))
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    // MARK: - Password Input Section

    private var passwordInputSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // 输入密码
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    if viewModel.showPassword {
                        TextField(
                            NSLocalizedString("password.enter", comment: ""),
                            text: $viewModel.password
                        )
                        .textContentType(.newPassword)
                        .autocapitalization(.none)
                    } else {
                        SecureField(
                            NSLocalizedString("password.enter", comment: ""),
                            text: $viewModel.password
                        )
                        .textContentType(.newPassword)
                    }

                    Button {
                        viewModel.showPassword.toggle()
                    } label: {
                        Image(systemName: viewModel.showPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }

            // 密码强度指示器
            if !viewModel.password.isEmpty {
                PasswordStrengthView(password: viewModel.password)
            }

            // 确认密码
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    if viewModel.showPassword {
                        TextField(
                            NSLocalizedString("password.confirm", comment: ""),
                            text: $viewModel.confirmPassword
                        )
                        .textContentType(.newPassword)
                        .autocapitalization(.none)
                    } else {
                        SecureField(
                            NSLocalizedString("password.confirm", comment: ""),
                            text: $viewModel.confirmPassword
                        )
                        .textContentType(.newPassword)
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.medium)

                // 匹配提示
                if !viewModel.confirmPassword.isEmpty {
                    HStack(spacing: 6) {
                        Image(
                            systemName: viewModel.passwordsMatch
                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundColor(
                            viewModel.passwordsMatch
                                ? DesignSystem.Colors.successGreen
                                : DesignSystem.Colors.dangerRed
                        )
                        Text(
                            viewModel.passwordsMatch
                                ? NSLocalizedString("password.match", comment: "")
                                : NSLocalizedString("password.mismatch", comment: "")
                        )
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }

            // 密码要求
            PasswordRequirementsView(password: viewModel.password)
        }
        .cardStyle()
    }

    // MARK: - Biometric Section

    private var biometricSection: some View {
        HStack {
            Image(systemName: viewModel.biometricIcon)
                .font(.title3)
                .foregroundColor(DesignSystem.Colors.primaryBlue)

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    String(
                        format: NSLocalizedString("biometric.enable", comment: ""),
                        viewModel.biometricTypeText)
                )
                .font(.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(NSLocalizedString("biometric.description", comment: ""))
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $viewModel.enableBiometric)
                .tint(DesignSystem.Colors.primaryBlue)
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error)
                .font(.caption)
        }
        .foregroundColor(DesignSystem.Colors.dangerRed)
        .multilineTextAlignment(.center)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Button {
                Task {
                    if await viewModel.setupPassword() {
                        dismiss()
                    }
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(NSLocalizedString("password.setup", comment: ""))
                }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(!viewModel.canSubmit || viewModel.isLoading)

            Button {
                viewModel.skipSetup()
                dismiss()
            } label: {
                Text(NSLocalizedString("password.setupLater", comment: ""))
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }
}

// MARK: - Change Password Sheet

/// 修改密码界面
struct ChangePasswordSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = PasswordSetupViewModel()
    @State private var oldPassword = ""
    @State private var showOldPassword = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // 顶部说明
                    headerSection

                    // 原密码输入
                    oldPasswordSection

                    // 新密码输入卡片
                    newPasswordSection

                    // 错误提示
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundColor(DesignSystem.Colors.dangerRed)
                        .multilineTextAlignment(.center)
                    }

                    // 操作按钮
                    actionButtons

                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.close", comment: "")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // 图标背景圆形
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primaryBlue.opacity(0.15),
                                DesignSystem.Colors.primaryPurple.opacity(0.15),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "key.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primaryBlue,
                                DesignSystem.Colors.primaryPurple,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(NSLocalizedString("password.change.title", comment: ""))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text(NSLocalizedString("password.change.subtitle", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.top, DesignSystem.Spacing.xl)
    }

    // MARK: - Old Password Section

    private var oldPasswordSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(NSLocalizedString("password.current", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack {
                if showOldPassword {
                    TextField(
                        NSLocalizedString("password.current.enter", comment: ""), text: $oldPassword
                    )
                    .textContentType(.password)
                    .autocapitalization(.none)
                } else {
                    SecureField(
                        NSLocalizedString("password.current.enter", comment: ""), text: $oldPassword
                    )
                    .textContentType(.password)
                }

                Button {
                    showOldPassword.toggle()
                } label: {
                    Image(systemName: showOldPassword ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.backgroundCard)
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
        .cardStyle()
    }

    // MARK: - New Password Section

    private var newPasswordSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text(NSLocalizedString("password.new", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // 输入新密码
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    if viewModel.showPassword {
                        TextField(
                            NSLocalizedString("password.new.enter", comment: ""),
                            text: $viewModel.password
                        )
                        .textContentType(.newPassword)
                        .autocapitalization(.none)
                    } else {
                        SecureField(
                            NSLocalizedString("password.new.enter", comment: ""),
                            text: $viewModel.password
                        )
                        .textContentType(.newPassword)
                    }

                    Button {
                        viewModel.showPassword.toggle()
                    } label: {
                        Image(
                            systemName: viewModel.showPassword
                                ? "eye.fill" : "eye.slash.fill"
                        )
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }

            // 密码强度指示器
            if !viewModel.password.isEmpty {
                PasswordStrengthView(password: viewModel.password)
            }

            // 确认新密码
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    if viewModel.showPassword {
                        TextField(
                            NSLocalizedString("password.new.confirm", comment: ""),
                            text: $viewModel.confirmPassword
                        )
                        .textContentType(.newPassword)
                        .autocapitalization(.none)
                    } else {
                        SecureField(
                            NSLocalizedString("password.new.confirm", comment: ""),
                            text: $viewModel.confirmPassword
                        )
                        .textContentType(.newPassword)
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundCard)
                .cornerRadius(DesignSystem.CornerRadius.medium)

                // 匹配提示
                if !viewModel.confirmPassword.isEmpty {
                    HStack(spacing: 6) {
                        Image(
                            systemName: viewModel.passwordsMatch
                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundColor(
                            viewModel.passwordsMatch
                                ? DesignSystem.Colors.successGreen
                                : DesignSystem.Colors.dangerRed
                        )
                        Text(
                            viewModel.passwordsMatch
                                ? NSLocalizedString("password.match", comment: "")
                                : NSLocalizedString("password.mismatch", comment: "")
                        )
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }

            // 密码要求
            PasswordRequirementsView(password: viewModel.password)
        }
        .cardStyle()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Button {
                Task {
                    if await viewModel.changePassword(oldPassword: oldPassword) {
                        dismiss()
                    }
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(NSLocalizedString("password.change.confirm", comment: ""))
                }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(
                !viewModel.canSubmit || oldPassword.isEmpty || viewModel.isLoading)

            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("common.cancel", comment: ""))
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }
}

#Preview {
    PasswordSetupSheet()
}

#Preview("Change Password") {
    ChangePasswordSheet()
}
