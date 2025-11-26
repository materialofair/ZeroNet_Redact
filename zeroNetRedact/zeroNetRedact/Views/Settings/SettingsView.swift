import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showAboutView = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - 品牌卡片
                    brandCard

                    // MARK: - 安全设置
                    SectionHeader(title: NSLocalizedString("settings.security", comment: ""))
                    securitySection

                    // MARK: - 关于
                    SectionHeader(title: NSLocalizedString("settings.about", comment: ""))
                    aboutSection

                    // MARK: - 危险区域
                    SectionHeader(title: NSLocalizedString("settings.data", comment: ""))
                    dangerSection

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
                NSLocalizedString("settings.clearAll.title", comment: ""),
                isPresented: $viewModel.showClearAllAlert
            ) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
                Button(
                    NSLocalizedString("settings.clearAll.confirm", comment: ""), role: .destructive
                ) {
                    viewModel.clearAllFiles()
                }
            } message: {
                Text(NSLocalizedString("settings.clearAll.message", comment: ""))
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
            .onAppear {
                viewModel.loadStorageInfo()
            }
        }
    }

    // MARK: - 品牌卡片

    private var brandCard: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // App 图标和名称
            HStack(spacing: DesignSystem.Spacing.md) {
                // App 图标 - 使用真实的 App Icon
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(
                        color: DesignSystem.Colors.primaryBlue.opacity(0.3), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ZeroNet Redact")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

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

                // 存储进度条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 背景
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 8)

                        // 进度
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Gradients.primary)
                            .frame(
                                width: min(
                                    CGFloat(viewModel.fileCount) / 100.0 * geometry.size.width,
                                    geometry.size.width), height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .cardStyle()
        .padding(.top, DesignSystem.Spacing.lg)
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
        }
        .buttonStyle(.plain)
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    // MARK: - 危险区域

    private var dangerSection: some View {
        Button {
            viewModel.showClearAllAlert = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.dangerRed)
                    )

                Text(NSLocalizedString("settings.clearAllFiles", comment: ""))
                    .font(.body)
                    .foregroundColor(DesignSystem.Colors.dangerRed)

                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .buttonStyle(.plain)
        .background(DesignSystem.Colors.backgroundCard)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.dangerRed.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    SettingsView()
}
