import SwiftUI

/// 密码验证界面 - 用于解锁应用
struct AuthenticationView: View {
    @StateObject private var viewModel = AuthenticationViewModel()
    @State private var showShakeAnimation = false

    var body: some View {
        ZStack {
            // 背景渐变
            backgroundGradient

            VStack(spacing: DesignSystem.Spacing.xxl) {
                Spacer()

                // Logo 和标题
                headerSection

                // 密码输入卡片
                passwordInputCard

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            // 自动触发生物识别
            if viewModel.isBiometricAvailable {
                Task {
                    await viewModel.authenticateWithBiometric()
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                DesignSystem.Colors.primaryBlue.opacity(0.1),
                DesignSystem.Colors.primaryPurple.opacity(0.1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(
                    color: DesignSystem.Colors.primaryBlue.opacity(0.3),
                    radius: 20, x: 0, y: 10
                )

            Text("ZeroNet Redact")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text(NSLocalizedString("auth.welcome", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Password Input Card

    private var passwordInputCard: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // 密码输入框
            passwordInputField

            // Face ID/Touch ID 按钮
            if viewModel.isBiometricAvailable {
                biometricButton
            }

            // 错误提示
            if let error = viewModel.errorMessage {
                errorMessage(error)
            }

            // 剩余尝试次数
            if viewModel.remainingAttempts < 5 {
                remainingAttemptsText
            }

            // 解锁按钮
            unlockButton
        }
        .cardStyle()
        .padding(.horizontal, DesignSystem.Spacing.xl)
    }

    // MARK: - Password Input Field

    private var passwordInputField: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "lock.fill")
                .foregroundColor(DesignSystem.Colors.textSecondary)

            if viewModel.showPassword {
                TextField(
                    NSLocalizedString("password.enter", comment: ""), text: $viewModel.passwordInput
                )
                .textContentType(.password)
                .autocapitalization(.none)
                .submitLabel(.done)
                .onSubmit {
                    Task { await attemptLogin() }
                }
            } else {
                SecureField(
                    NSLocalizedString("password.enter", comment: ""), text: $viewModel.passwordInput
                )
                .textContentType(.password)
                .submitLabel(.done)
                .onSubmit {
                    Task { await attemptLogin() }
                }
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
        .offset(x: showShakeAnimation ? -8 : 0)
    }

    // MARK: - Biometric Button

    private var biometricButton: some View {
        Button {
            Task {
                await viewModel.authenticateWithBiometric()
            }
        } label: {
            HStack {
                Image(systemName: viewModel.biometricIcon)
                Text(
                    String(
                        format: NSLocalizedString("auth.useBiometric", comment: ""),
                        viewModel.biometricTypeText))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(OutlineButtonStyle(color: DesignSystem.Colors.primaryBlue))
    }

    // MARK: - Error Message

    private func errorMessage(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error)
                .font(.caption)
        }
        .foregroundColor(DesignSystem.Colors.dangerRed)
        .multilineTextAlignment(.center)
    }

    // MARK: - Remaining Attempts

    private var remainingAttemptsText: some View {
        Text(
            String(
                format: NSLocalizedString("auth.remainingAttempts", comment: ""),
                viewModel.remainingAttempts)
        )
        .font(.caption)
        .foregroundColor(
            viewModel.remainingAttempts <= 2
                ? DesignSystem.Colors.dangerRed
                : DesignSystem.Colors.warningOrange
        )
    }

    // MARK: - Unlock Button

    private var unlockButton: some View {
        Button {
            Task { await attemptLogin() }
        } label: {
            if viewModel.isVerifying {
                ProgressView()
                    .tint(.white)
            } else {
                Text(NSLocalizedString("auth.unlock", comment: ""))
            }
        }
        .buttonStyle(GradientButtonStyle())
        .disabled(viewModel.passwordInput.isEmpty || viewModel.isVerifying)
    }

    // MARK: - Helper Methods

    private func attemptLogin() async {
        let success = await viewModel.verifyPassword()
        if !success {
            // 震动反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            // 晃动动画
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                showShakeAnimation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showShakeAnimation = false
            }
        }
    }
}

#Preview {
    AuthenticationView()
}
