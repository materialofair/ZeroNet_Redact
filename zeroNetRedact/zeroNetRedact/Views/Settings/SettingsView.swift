import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var usageTracker = UsageTracker.shared

    @State private var showAboutView = false
    @State private var showPremiumView = false
    @State private var showOnboarding = false
    @State private var isRestoring = false
    @State private var showRestoreResult = false
    @State private var restoreMessage = ""

    // 审核模式相关
    @State private var iconTapCount = 0
    @State private var showReviewCodeInput = false
    @State private var reviewCodeInput = ""
    @State private var showReviewModeSuccess = false
    @State private var showReviewModeError = false

    var body: some View {
        NavigationStack {
            List {
                premiumSection
                securitySection
                helpSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
            .alert(NSLocalizedString("premium.restore", comment: ""), isPresented: $showRestoreResult) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(restoreMessage)
            }
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
            .alert(
                NSLocalizedString("settings.disablePassword.errorTitle", comment: ""),
                isPresented: $viewModel.showDisablePasswordError
            ) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(
                    viewModel.disablePasswordErrorMessage
                        ?? NSLocalizedString("settings.disablePassword.errorMessage", comment: ""))
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

    private var premiumSection: some View {
        Section(NSLocalizedString("settings.section.membership", comment: "")) {
            if appState.isPremium || appState.isReviewModeActive {
                LabeledContent {
                    Image(systemName: "infinity")
                        .foregroundStyle(.secondary)
                } label: {
                    Label(NSLocalizedString("settings.premium.unlocked", comment: ""), systemImage: "checkmark.seal")
                }
            } else {
                LabeledContent(NSLocalizedString("settings.quota.media", comment: "")) {
                    Text("\(usageTracker.usedMediaExports)/\(UsageTracker.dailyMediaLimit)")
                        .monospacedDigit()
                }
                LabeledContent(NSLocalizedString("settings.quota.documents", comment: "")) {
                    Text("\(usageTracker.usedDocExports)/\(UsageTracker.dailyDocLimit)")
                        .monospacedDigit()
                }
                Button {
                    showPremiumView = true
                } label: {
                    Label(NSLocalizedString("settings.premium.upgrade", comment: ""), systemImage: "crown")
                }
            }
            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    Label(NSLocalizedString("premium.restore", comment: ""), systemImage: "arrow.clockwise")
                    Spacer()
                    if isRestoring { ProgressView() }
                }
            }
            .disabled(isRestoring)
        }
    }

    private var securitySection: some View {
        Section(NSLocalizedString("settings.section.privacyStorage", comment: "")) {
            Toggle(NSLocalizedString("settings.passwordProtection", comment: ""), isOn: $viewModel.passwordProtectionEnabled)
                .onChange(of: viewModel.passwordProtectionEnabled) { _, newValue in
                    if newValue {
                        viewModel.showPasswordSetup = true
                    } else {
                        viewModel.showDisablePasswordAlert = true
                    }
                }
            if viewModel.passwordProtectionEnabled {
                Button(NSLocalizedString("settings.changePassword", comment: "")) {
                    viewModel.showChangePassword = true
                }
            }
            if viewModel.passwordProtectionEnabled && viewModel.isBiometricAvailable {
                Toggle(viewModel.biometricTypeText, isOn: $viewModel.biometricEnabled)
                    .onChange(of: viewModel.biometricEnabled) { _, newValue in
                        viewModel.updateBiometricSetting(newValue)
                    }
            }
            Toggle(NSLocalizedString("settings.autoLock", comment: ""), isOn: $viewModel.autoLock)
            if viewModel.autoLock {
                Picker(NSLocalizedString("settings.lockTimeout", comment: ""), selection: $viewModel.lockTimeout) {
                    Text(NSLocalizedString("settings.lockTimeout.immediate", comment: "")).tag(0)
                    Text(NSLocalizedString("settings.lockTimeout.1min", comment: "")).tag(60)
                    Text(NSLocalizedString("settings.lockTimeout.5min", comment: "")).tag(300)
                    Text(NSLocalizedString("settings.lockTimeout.15min", comment: "")).tag(900)
                }
                .tint(.secondary)
            }
            LabeledContent(NSLocalizedString("settings.storage", comment: "")) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.usedStorageText)
                    Text(String(format: NSLocalizedString("settings.fileCount", comment: ""), viewModel.fileCount))
                        .font(.caption)
                }
            }
        }
    }

    private var helpSection: some View {
        Section(NSLocalizedString("settings.section.help", comment: "")) {
            Button {
                showOnboarding = true
            } label: {
                Label(NSLocalizedString("settings.guide", comment: ""), systemImage: "questionmark.circle")
            }
            Link(destination: URL(string: "https://github.com/materialofair/ZeroNet-Redact/issues")!) {
                Label(NSLocalizedString("about.feedback", comment: ""), systemImage: "bubble.left")
            }
        }
    }

    private var aboutSection: some View {
        Section(NSLocalizedString("settings.section.about", comment: "")) {
            HStack {
                // Keep the existing seven-tap review-mode entry on the app icon.
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        iconTapCount += 1
                        if iconTapCount >= 7 {
                            iconTapCount = 0
                            showReviewCodeInput = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if iconTapCount < 7 { iconTapCount = 0 }
                        }
                    }
                    .accessibilityLabel("ZeroNet Redact")
                Text("ZeroNet Redact")
                Spacer()
                Text("v\(Bundle.main.appVersion)")
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label(NSLocalizedString("about.privacy", comment: ""), systemImage: "hand.raised")
            }
            Button {
                showAboutView = true
            } label: {
                Label(NSLocalizedString("settings.aboutApp", comment: ""), systemImage: "info.circle")
            }
        }
    }

    @MainActor
    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        let storeManager = StoreManager.shared
        await storeManager.restorePurchases()
        if storeManager.isPremium {
            restoreMessage = NSLocalizedString("premium.success.message", comment: "")
        } else if let error = storeManager.errorMessage, !error.isEmpty {
            restoreMessage = error
        } else {
            restoreMessage = NSLocalizedString("premium.restore.notFound", comment: "")
        }
        showRestoreResult = true
    }
}

#Preview {
    SettingsView()
}
