import Combine
import SwiftUI

/// 密码验证界面 - 用于解锁应用
struct AuthenticationView: View {
    @StateObject private var viewModel = AuthenticationViewModel()
    @State private var showShakeAnimation = false
    @FocusState private var isPasswordFieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded = false
    @State private var lockoutTick = Date()
    @State private var showForgotPasswordStep1 = false
    @State private var showForgotPasswordStep2 = false
    @State private var resetFailedMessage: String?

    @State private var lockoutTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isLockedOut: Bool {
        viewModel.lockoutEndTime != nil
    }

    private var lockoutSecondsRemaining: Int {
        guard let endTime = viewModel.lockoutEndTime else { return 0 }
        return max(0, Int(endTime.timeIntervalSince(lockoutTick).rounded(.up)))
    }

    private var formattedLockoutCountdown: String {
        let minutes = lockoutSecondsRemaining / 60
        let seconds = lockoutSecondsRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

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
            // HIGH-8: 本视图仅在锁定时才会挂载，因此挂载时 scenePhase 既可能已经是 .active
            // （冷启动直接锁定），也可能仍处于 .background/.inactive 过渡中（前台切后台触发锁定，
            // 此时视图恰好才被创建，无法观察到此前的 .active -> .background 迁移）。
            // 只在确认已处于前台时才立即触发 Face ID；否则标记为"待前台"，交由下方
            // onChange 在真正回到 .active 时触发，避免在应用尚未真正前台时弹出生物识别。
            if scenePhase == .active {
                triggerBiometricIfNeeded()
            } else {
                wasBackgrounded = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                wasBackgrounded = true
            case .active:
                // 与上方 onAppear 的触发条件互斥：只有此前记录过"离开前台"时才在这里触发，
                // 避免同一次回到前台被触发两次；同时天然过滤掉控制中心/通知中心等
                // 仅经过 .inactive、从未真正进入 .background 的短暂晃动
                if wasBackgrounded {
                    wasBackgrounded = false
                    triggerBiometricIfNeeded()
                }
            default:
                break
            }
        }
        .onReceive(lockoutTimer) { _ in
            lockoutTick = Date()
            viewModel.clearExpiredLockout()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let message = newValue {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        .alert(
            NSLocalizedString("auth.forgotPassword.step1.title", comment: ""),
            isPresented: $showForgotPasswordStep1
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("auth.forgotPassword.continue", comment: ""), role: .destructive)
            {
                showForgotPasswordStep2 = true
            }
        } message: {
            Text(NSLocalizedString("auth.forgotPassword.step1.message", comment: ""))
        }
        .alert(
            NSLocalizedString("auth.forgotPassword.step2.title", comment: ""),
            isPresented: $showForgotPasswordStep2
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("auth.forgotPassword.confirmDelete", comment: ""), role: .destructive)
            {
                // CRITICAL-6: resetAllData 可能失败（Core Data 或磁盘清理失败），
                // 失败时应用保持锁定状态不变，仅弹出错误提示
                do {
                    try AppState.shared.resetAllData()
                } catch {
                    resetFailedMessage = error.localizedDescription
                }
            }
        } message: {
            Text(NSLocalizedString("auth.forgotPassword.step2.message", comment: ""))
        }
        .alert(
            NSLocalizedString("auth.forgotPassword.resetFailed.title", comment: ""),
            isPresented: Binding(
                get: { resetFailedMessage != nil },
                set: { isPresented in
                    if !isPresented { resetFailedMessage = nil }
                }
            )
        ) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
        } message: {
            Text(resetFailedMessage ?? "")
        }
    }

    // MARK: - Biometric Trigger

    /// 自动触发生物识别；仅在未锁定且未在验证中时触发，避免重复弹出
    private func triggerBiometricIfNeeded() {
        guard viewModel.isBiometricAvailable, !isLockedOut, !viewModel.isVerifying else {
            if !viewModel.isBiometricAvailable {
                isPasswordFieldFocused = true
            }
            return
        }
        Task {
            let success = await viewModel.authenticateWithBiometric()
            if !success {
                isPasswordFieldFocused = true
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

            // 锁定倒计时 / 错误提示
            if isLockedOut {
                lockoutCountdownView
            } else if let error = viewModel.errorMessage {
                errorMessage(error)
            }

            // 剩余尝试次数（锁定期间不展示，避免与锁定文案矛盾）
            if viewModel.remainingAttempts < 5 && !isLockedOut {
                remainingAttemptsText
            }

            // 解锁按钮
            unlockButton

            // 忘记密码入口
            forgotPasswordButton
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
                .focused($isPasswordFieldFocused)
                .disabled(isLockedOut)
                .onSubmit {
                    Task { await attemptLogin() }
                }
            } else {
                SecureField(
                    NSLocalizedString("password.enter", comment: ""), text: $viewModel.passwordInput
                )
                .textContentType(.password)
                .submitLabel(.done)
                .focused($isPasswordFieldFocused)
                .disabled(isLockedOut)
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
            .accessibilityLabel(
                viewModel.showPassword
                    ? NSLocalizedString("accessibility.hidePassword", comment: "")
                    : NSLocalizedString("accessibility.showPassword", comment: ""))
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

    // MARK: - Lockout Countdown

    private var lockoutCountdownView: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text(
                String(
                    format: NSLocalizedString("auth.lockedOutCountdown", comment: ""),
                    formattedLockoutCountdown)
            )
            .font(.caption)
            .fontWeight(.semibold)
            .monospacedDigit()
        }
        .foregroundColor(DesignSystem.Colors.dangerRed)
        .multilineTextAlignment(.center)
    }

    // MARK: - Remaining Attempts

    private var remainingAttemptsText: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(
                String(
                    format: NSLocalizedString("auth.remainingAttempts", comment: ""),
                    viewModel.remainingAttempts)
            )
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(
            viewModel.remainingAttempts <= 2
                ? DesignSystem.Colors.dangerRed
                : Color(red: 0.72, green: 0.42, blue: 0.0)
        )
    }

    // MARK: - Forgot Password

    private var forgotPasswordButton: some View {
        Button {
            showForgotPasswordStep1 = true
        } label: {
            Text(NSLocalizedString("auth.forgotPassword", comment: ""))
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
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
        .disabled(viewModel.passwordInput.isEmpty || viewModel.isVerifying || isLockedOut)
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
