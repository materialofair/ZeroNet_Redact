//
//  OnboardingView.swift
//  ZeroNet Redact
//
//  新手引导：3 步说明"脱敏如何工作"，首启密码流程结束后自动呈现，
//  也可从导入页工具栏随时回看。调性对齐 PRODUCT.md：信任、冷静、直接。
//

import SwiftUI

struct OnboardingView: View {
    /// 完成后回调（首启流程标记已读；回看场景不传，不写入状态）
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    struct Step {
        let icon: String
        let iconColor: Color
        let title: String
        let description: String
    }

    private static let steps: [Step] = [
        Step(
            icon: "square.and.arrow.down.on.square",
            iconColor: DesignSystem.Colors.primaryBlue,
            title: NSLocalizedString("onboarding.step1.title", comment: ""),
            description: NSLocalizedString("onboarding.step1.description", comment: "")
        ),
        Step(
            icon: "paintbrush.pointed.fill",
            iconColor: DesignSystem.Colors.successGreen,
            title: NSLocalizedString("onboarding.step2.title", comment: ""),
            description: NSLocalizedString("onboarding.step2.description", comment: "")
        ),
        Step(
            icon: "checkmark.shield.fill",
            iconColor: DesignSystem.Colors.warningOrange,
            title: NSLocalizedString("onboarding.step3.title", comment: ""),
            description: NSLocalizedString("onboarding.step3.description", comment: "")
        ),
    ]

    private var isLastStep: Bool { currentStep == Self.steps.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()

                // 步骤内容
                VStack(spacing: DesignSystem.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(Self.steps[currentStep].iconColor.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: Self.steps[currentStep].icon)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Self.steps[currentStep].iconColor)
                    }

                    Text(Self.steps[currentStep].title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(Self.steps[currentStep].description)
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)

                Spacer()

                // 步骤圆点
                HStack(spacing: 8) {
                    ForEach(0..<Self.steps.count, id: \.self) { index in
                        Circle()
                            .fill(
                                index == currentStep
                                    ? DesignSystem.Colors.primaryBlue
                                    : DesignSystem.Colors.separator)
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityLabel(
                    String(
                        format: NSLocalizedString("onboarding.pageIndicator", comment: ""),
                        currentStep + 1, Self.steps.count)
                )

                // 操作按钮
                HStack {
                    Button(NSLocalizedString("onboarding.skip", comment: "")) {
                        finish()
                    }
                    .font(.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .contentShape(Rectangle())

                    Spacer()

                    Button(
                        isLastStep
                            ? NSLocalizedString("onboarding.done", comment: "")
                            : NSLocalizedString("onboarding.next", comment: "")
                    ) {
                        if isLastStep {
                            finish()
                        } else {
                            currentStep += 1
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .frame(minHeight: 44)
                    .background(
                        DesignSystem.Colors.primaryBlue,
                        in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    )
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
        }
    }

    private func finish() {
        onFinish?()
        dismiss()
    }
}

#Preview {
    OnboardingView()
}
