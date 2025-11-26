import SwiftUI

/// 密码强度指示器
struct PasswordStrengthView: View {
    let password: String
    let passwordManager = PasswordManager.shared

    var strength: PasswordStrength {
        passwordManager.evaluateStrength(password)
    }

    var body: some View {
        VStack(spacing: 6) {
            // 强度标题和等级
            HStack {
                Text("密码强度")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Spacer()

                Text(strength.description)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(strengthColor)
            }

            // 强度进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    // 进度
                    RoundedRectangle(cornerRadius: 2)
                        .fill(strengthColor)
                        .frame(width: geometry.size.width * strengthPercentage)
                        .animation(.easeInOut(duration: 0.3), value: strengthPercentage)
                }
            }
            .frame(height: 4)
        }
    }

    private var strengthColor: Color {
        switch strength {
        case .weak: return DesignSystem.Colors.dangerRed
        case .fair: return DesignSystem.Colors.warningOrange
        case .good: return DesignSystem.Colors.successMint
        case .strong: return DesignSystem.Colors.successGreen
        }
    }

    private var strengthPercentage: Double {
        switch strength {
        case .weak: return 0.25
        case .fair: return 0.5
        case .good: return 0.75
        case .strong: return 1.0
        }
    }
}

/// 密码要求检查行
struct PasswordRequirementRow: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(
                    isMet ? DesignSystem.Colors.successGreen : DesignSystem.Colors.textTertiary)

            Text(text)
                .font(.caption)
                .foregroundColor(
                    isMet ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
        }
    }
}

/// 密码要求列表
struct PasswordRequirementsView: View {
    let password: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PasswordRequirementRow(
                text: "至少6个字符",
                isMet: password.count >= 6
            )

            PasswordRequirementRow(
                text: "建议12+字符更安全",
                isMet: password.count >= 12
            )

            PasswordRequirementRow(
                text: "包含字母和数字",
                isMet: password.contains(where: { $0.isLetter })
                    && password.contains(where: { $0.isNumber })
            )
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PasswordStrengthView(password: "123")
        PasswordStrengthView(password: "abcd1234")
        PasswordStrengthView(password: "MyPassword123")

        Divider()

        PasswordRequirementsView(password: "MyPassword123")
    }
    .padding()
}
