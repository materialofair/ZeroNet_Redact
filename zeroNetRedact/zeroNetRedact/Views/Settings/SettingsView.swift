import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var usageTracker = UsageTracker.shared

    @State private var showAboutView = false
    @State private var showPremiumView = false

    // 审核模式相关
    @State private var iconTapCount = 0
    @State private var showReviewCodeInput = false
    @State private var reviewCodeInput = ""
    @State private var showReviewModeSuccess = false
    @State private var showReviewModeError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - 品牌卡片
                    brandCard

                    // MARK: - 付费状态
                    premiumSection
                        .padding(.top, DesignSystem.Spacing.md)

                    // MARK: - 安全设置
                    securitySection
                        .padding(.top, DesignSystem.Spacing.md)

                    // MARK: - 关于
                    aboutSection
                        .padding(.top, DesignSystem.Spacing.md)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .sheet(isPresented: $showAboutView) {
                AboutView()
            }
            .alert(
                NSLocalizedString("settings.disablePassword.title", comment: ""),
                isPresented: $viewModel.showDisablePasswordAlert
            ) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    viewModel.passwordProtectionEnabled = true
                }
                Button(
                    NSLocalizedString("settings.disablePassword.confirm", comment: ""),
                    role: .destructive
                ) {
                    viewModel.disablePasswordProtection()
                }
            } message: {
                Text(NSLocalizedString("settings.disablePassword.message", comment: ""))
            }
            .sheet(isPresented: $viewModel.showPasswordSetup) {
                PasswordSetupSheet()
                    .onDisappear {
                        // 更新状态
                        viewModel.passwordProtectionEnabled = AppState.shared.passwordEnabled
                    }
            }
            .sheet(isPresented: $viewModel.showChangePassword) {
                ChangePasswordSheet()
            }
            .sheet(isPresented: $showPremiumView) {
                PremiumView()
            }
            // 开发者选项输入框
            .alert(
                NSLocalizedString("settings.devOptions.title", comment: ""),
                isPresented: $showReviewCodeInput
            ) {
                TextField(
                    NSLocalizedString("settings.devOptions.placeholder", comment: ""),
                    text: $reviewCodeInput)
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    reviewCodeInput = ""
                }
                Button(NSLocalizedString("common.confirm", comment: "")) {
                    if appState.activateReviewMode(with: reviewCodeInput) {
                        showReviewModeSuccess = true
                    } else {
                        showReviewModeError = true
                    }
                    reviewCodeInput = ""
                }
            } message: {
                Text(NSLocalizedString("settings.devOptions.message", comment: ""))
            }
            // 开发者选项激活成功
            .alert(
                NSLocalizedString("settings.devOptions.success.title", comment: ""),
                isPresented: $showReviewModeSuccess
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings.devOptions.success.message", comment: ""))
            }
            // 开发者选项激活失败
            .alert(
                NSLocalizedString("settings.devOptions.error.title", comment: ""),
                isPresented: $showReviewModeError
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings.devOptions.error.message", comment: ""))
            }
            .onAppear {
                viewModel.loadStorageInfo()
                usageTracker.refresh()
            }
        }
    }

    // MARK: - 品牌卡片

    private var brandCard: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // App 图标和名称
            HStack(spacing: DesignSystem.Spacing.md) {
                // App 图标 - 使用真实的 App Icon (点击7次触发审核模式)
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(
                        color: DesignSystem.Colors.primaryBlue.opacity(0.3), radius: 8, x: 0, y: 4
                    )
                    .onTapGesture {
                        iconTapCount += 1
                        if iconTapCount >= 7 {
                            iconTapCount = 0
                            showReviewCodeInput = true
                        }
                        // 2秒后重置计数
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if iconTapCount < 7 {
                                iconTapCount = 0
                            }
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("ZeroNet Redact")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        // 已购买或审核模式徽章
                        if appState.isPremium {
                            Text("Pro")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Gradients.primary)
                                .cornerRadius(4)
                        } else if appState.isReviewModeActive {
                            Text(NSLocalizedString("settings.badge.active", comment: ""))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.warningOrange)
                                .cornerRadius(4)
                        }
                    }

                    Text("v1.0.0")
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()
            }

            Divider()
                .padding(.vertical, DesignSystem.Spacing.xs)

            // 存储统计
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.primaryBlue)
                        Text(
                            String(
                                format: NSLocalizedString("settings.fileCount", comment: ""),
                                viewModel.fileCount)
                        )
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive.fill")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.primaryPurple)
                        Text(viewModel.usedStorageText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
            }
        }
        .cardStyle()
        .padding(.top, DesignSystem.Spacing.lg)
    }

    // MARK: - 付费状态

    private var premiumSection: some View {
        VStack(spacing: 0) {
            if appState.isPremium || appState.isReviewModeActive {
                // 已解锁状态
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(DesignSystem.Colors.successGreen)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("settings.premium.unlocked", comment: ""))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text(NSLocalizedString("settings.premium.unlocked.desc", comment: ""))
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "infinity")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.successGreen)
                }
                .padding(.vertical, DesignSystem.Spacing.md)
                .padding(.horizontal, DesignSystem.Spacing.lg)
            } else {
                // 免费用户状态
                VStack(spacing: DesignSystem.Spacing.md) {
                    // 今日剩余配额
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(DesignSystem.Colors.primaryBlue)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.premium.todayQuota", comment: ""))
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            HStack(spacing: 12) {
                                // 图片配额 (已使用/限制)
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.fill")
                                        .font(.caption)
                                        .foregroundColor(DesignSystem.Colors.primaryBlue)
                                    Text(
                                        "\(usageTracker.usedImageExports)/\(UsageTracker.dailyImageLimit)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(
                                        usageTracker.usedImageExports
                                            >= UsageTracker.dailyImageLimit
                                            ? DesignSystem.Colors.dangerRed
                                            : DesignSystem.Colors.textSecondary)
                                }

                                // 文档配额 (已使用/限制)
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundColor(DesignSystem.Colors.warningOrange)
                                    Text(
                                        "\(usageTracker.usedDocExports)/\(UsageTracker.dailyDocLimit)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(
                                        usageTracker.usedDocExports >= UsageTracker.dailyDocLimit
                                            ? DesignSystem.Colors.dangerRed
                                            : DesignSystem.Colors.textSecondary)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    Divider()
                        .padding(.horizontal, DesignSystem.Spacing.lg)

                    // 升级按钮
                    Button {
                        showPremiumView = true
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(DesignSystem.Gradients.primary)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("settings.premium.upgrade", comment: ""))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text(
                                    NSLocalizedString("settings.premium.upgrade.desc", comment: "")
                                )
                                .font(.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    // MARK: - 安全设置

    private var securitySection: some View {
        VStack(spacing: 0) {
            // 密码保护开关
            SettingsRow(
                icon: "lock.shield.fill",
                iconColor: DesignSystem.Colors.successGreen,
                title: NSLocalizedString("settings.passwordProtection", comment: "")
            ) {
                Toggle("", isOn: $viewModel.passwordProtectionEnabled)
                    .tint(DesignSystem.Colors.primaryBlue)
                    .onChange(of: viewModel.passwordProtectionEnabled) { _, newValue in
                        if newValue {
                            viewModel.showPasswordSetup = true
                        } else {
                            viewModel.showDisablePasswordAlert = true
                        }
                    }
            }

            // 修改密码（仅在密码开启时显示）
            if viewModel.passwordProtectionEnabled {
                Divider()
                    .padding(.leading, 52)

                Button {
                    viewModel.showChangePassword = true
                } label: {
                    SettingsRow(
                        icon: "key.fill",
                        iconColor: DesignSystem.Colors.primaryPurple,
                        title: NSLocalizedString("settings.changePassword", comment: "")
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // 生物识别开关（仅在密码开启且支持时显示）
            if viewModel.passwordProtectionEnabled && viewModel.isBiometricAvailable {
                Divider()
                    .padding(.leading, 52)

                SettingsRow(
                    icon: viewModel.biometricIcon,
                    iconColor: DesignSystem.Colors.primaryBlue,
                    title: viewModel.biometricTypeText
                ) {
                    Toggle("", isOn: $viewModel.biometricEnabled)
                        .tint(DesignSystem.Colors.primaryBlue)
                        .onChange(of: viewModel.biometricEnabled) { _, newValue in
                            viewModel.updateBiometricSetting(newValue)
                        }
                }
            }

            Divider()
                .padding(.leading, 52)

            // 自动锁定开关
            SettingsRow(
                icon: "lock.fill",
                iconColor: DesignSystem.Colors.primaryBlue,
                title: NSLocalizedString("settings.autoLock", comment: "")
            ) {
                Toggle("", isOn: $viewModel.autoLock)
                    .tint(DesignSystem.Colors.primaryBlue)
            }

            if viewModel.autoLock {
                Divider()
                    .padding(.leading, 52)

                // 锁定时间选择
                SettingsRow(
                    icon: "clock.fill",
                    iconColor: DesignSystem.Colors.primaryPurple,
                    title: NSLocalizedString("settings.lockTimeout", comment: "")
                ) {
                    Picker("", selection: $viewModel.lockTimeout) {
                        Text(NSLocalizedString("settings.lockTimeout.immediate", comment: "")).tag(
                            0)
                        Text(NSLocalizedString("settings.lockTimeout.1min", comment: "")).tag(60)
                        Text(NSLocalizedString("settings.lockTimeout.5min", comment: "")).tag(300)
                        Text(NSLocalizedString("settings.lockTimeout.15min", comment: "")).tag(900)
                    }
                    .pickerStyle(.menu)
                    .tint(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Button {
            showAboutView = true
        } label: {
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: DesignSystem.Colors.primaryBlue,
                title: NSLocalizedString("settings.aboutApp", comment: "")
            ) {
                HStack(spacing: 6) {
                    Text("v1.0.0")
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

}

#Preview {
    SettingsView()
}
