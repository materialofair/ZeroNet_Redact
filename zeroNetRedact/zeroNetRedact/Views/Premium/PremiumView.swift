import SwiftUI
import StoreKit

/// 付费解锁页面
struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xxl) {
                    // MARK: - 顶部图标
                    headerSection

                    // MARK: - 功能列表
                    featuresSection

                    // MARK: - 价格按钮
                    purchaseSection

                    // MARK: - 恢复购买
                    restoreSection

                    // MARK: - 条款链接
                    legalLinksSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("premium.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .accessibilityLabel(NSLocalizedString("common.close", comment: ""))
                }
            }
            .alert(NSLocalizedString("premium.error.title", comment: ""), isPresented: $showError) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert(NSLocalizedString("premium.success.title", comment: ""), isPresented: $showSuccessAlert) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("premium.success.message", comment: ""))
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // 图标
            ZStack {
                Circle()
                    .fill(DesignSystem.Gradients.primary)
                    .frame(width: 100, height: 100)

                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .shadow(color: DesignSystem.Colors.primaryBlue.opacity(0.4), radius: 20, x: 0, y: 10)

            // 标题
            Text(NSLocalizedString("premium.header.title", comment: ""))
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // 副标题
            Text(NSLocalizedString("premium.header.subtitle", comment: ""))
                .font(.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DesignSystem.Spacing.xl)
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            FeatureRow(
                icon: "photo.stack.fill",
                iconColor: DesignSystem.Colors.primaryBlue,
                title: NSLocalizedString("premium.feature.unlimitedImages", comment: ""),
                subtitle: NSLocalizedString("premium.feature.unlimitedImages.desc", comment: "")
            )

            FeatureRow(
                icon: "doc.fill",
                iconColor: DesignSystem.Colors.warningOrange,
                title: NSLocalizedString("premium.feature.unlimitedDocs", comment: ""),
                subtitle: NSLocalizedString("premium.feature.unlimitedDocs.desc", comment: "")
            )

            FeatureRow(
                icon: "infinity",
                iconColor: DesignSystem.Colors.successGreen,
                title: NSLocalizedString("premium.feature.lifetime", comment: ""),
                subtitle: NSLocalizedString("premium.feature.lifetime.desc", comment: "")
            )

            FeatureRow(
                icon: "heart.fill",
                iconColor: DesignSystem.Colors.dangerRed,
                title: NSLocalizedString("premium.feature.support", comment: ""),
                subtitle: NSLocalizedString("premium.feature.support.desc", comment: "")
            )
        }
        .cardStyle()
    }

    // MARK: - Purchase Section

    private var purchaseSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if let product = storeManager.premiumProduct {
                Button {
                    Task {
                        await purchase(product)
                    }
                } label: {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }

                        VStack(spacing: 4) {
                            Text(product.displayPrice)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(NSLocalizedString("premium.purchase.oneTime", comment: ""))
                                .font(.caption)
                                .opacity(0.9)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.lg)
                    .background(DesignSystem.Gradients.primary)
                    .cornerRadius(DesignSystem.CornerRadius.large)
                }
                .disabled(isPurchasing || storeManager.isPremium)
            } else if storeManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.lg)
            } else {
                // 产品加载失败
                Button {
                    Task {
                        await storeManager.loadProducts()
                    }
                } label: {
                    Text(NSLocalizedString("premium.purchase.retry", comment: ""))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.primaryBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                        .background(DesignSystem.Colors.primaryBlue.opacity(0.1))
                        .cornerRadius(DesignSystem.CornerRadius.large)
                }
            }

            // 已购买提示
            if storeManager.isPremium {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(DesignSystem.Colors.successGreen)
                    Text(NSLocalizedString("premium.alreadyPurchased", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.successGreen)
                }
                .padding(.top, DesignSystem.Spacing.sm)
            }
        }
    }

    // MARK: - Restore Section

    private var restoreSection: some View {
        Button {
            Task {
                await restorePurchases()
            }
        } label: {
            Text(NSLocalizedString("premium.restore", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .underline()
        }
        .disabled(isPurchasing)
    }

    // MARK: - Legal Links Section

    private var legalLinksSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Text(NSLocalizedString("about.privacy", comment: ""))
            }

            Text("·")
                .foregroundColor(DesignSystem.Colors.textTertiary)

            Link(
                NSLocalizedString("premium.terms", comment: ""),
                destination: URL(
                    string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
            )
        }
        .font(.caption)
        .foregroundColor(DesignSystem.Colors.textSecondary)
        .padding(.top, DesignSystem.Spacing.xs)
    }

    // MARK: - Actions

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let success = try await storeManager.purchase(product)
            if success {
                showSuccessAlert = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }

        await storeManager.restorePurchases()

        if storeManager.isPremium {
            showSuccessAlert = true
        } else {
            errorMessage = NSLocalizedString("premium.restore.notFound", comment: "")
            showError = true
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(DesignSystem.Colors.successGreen)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
    }
}

// MARK: - Preview

#Preview {
    PremiumView()
}
