//
//  BrushEditorComponents.swift
//  ZeroNet Redact
//
//  涂抹编辑器的可复用UI组件
//

import SwiftUI

// MARK: - Toolbar Button Components

/// 统一样式的工具栏按钮（带图标和文字）
struct ToolbarButton: View {
    let icon: String?
    let title: String
    var tintColor: Color = .blue
    var isProminent: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(isProminent ? .white : tintColor)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isProminent ? tintColor : tintColor.opacity(0.12))
            )
            .foregroundColor(isProminent ? .white : tintColor)
        }
        .buttonStyle(.plain)
    }
}

/// 统一样式的工具栏图标按钮（仅图标）
struct ToolbarIconButton: View {
    let icon: String
    var tintColor: Color = .primary
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                )
                .foregroundColor(isEnabled ? tintColor : .gray)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toast View

/// Toast 提示视图
struct ToastView: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(isSuccess ? .green : .red)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }
}

// MARK: - Effect Selector View

/// 效果选择栏
struct EffectSelectorView: View {
    @Binding var selectedEffect: BrushEffect
    @Binding var selectedBrushSize: BrushSize
    @Binding var isScaleBarVisible: Bool
    let onRotate: () -> Void
    let isRotateDisabled: Bool
    let isBrushSizeDisabled: Bool
    let hasRedactionRegions: Bool
    let onDetect: () -> Void
    let isDetecting: Bool
    let isDetectDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("effect.label", comment: ""))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrushEffect.allCases, id: \.self) { effect in
                        EffectButton(
                            effect: effect,
                            isSelected: selectedEffect == effect
                        ) {
                            selectedEffect = effect
                        }
                    }

                    // 分隔线
                    Divider()
                        .frame(height: 40)

                    // 画笔粗细选择
                    BrushSizeMenuButton(selectedSize: $selectedBrushSize)
                        .disabled(isBrushSizeDisabled)

                    // 旋转按钮
                    RotateButton(action: onRotate)
                        .disabled(isRotateDisabled)

                    // AI自动识别按钮
                    DetectButton(isDetecting: isDetecting, action: onDetect)
                        .disabled(isDetectDisabled)

                    // 缩放控制条切换按钮（有脱敏区域时显示）
                    if hasRedactionRegions {
                        ScaleBarToggleButton(isVisible: $isScaleBarVisible)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 6)
    }
}

/// 画笔粗细选择菜单按钮
struct BrushSizeMenuButton: View {
    @Binding var selectedSize: BrushSize

    var body: some View {
        Menu {
            ForEach(BrushSize.allCases, id: \.self) { size in
                Button {
                    selectedSize = size
                } label: {
                    if selectedSize == size {
                        Label(size.localizedName, systemImage: "checkmark")
                    } else {
                        Text(size.localizedName)
                    }
                }
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 34, height: 34)

                    Image(systemName: "pencil.tip")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }

                Text(selectedSize.localizedName)
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 46)
        }
        .accessibilityLabel(NSLocalizedString("brush.size.label", comment: ""))
    }
}

/// AI自动识别按钮
struct DetectButton: View {
    let isDetecting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 34, height: 34)

                    if isDetecting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                    }
                }

                Text(NSLocalizedString("editor.aiDetect", comment: ""))
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 46)
        }
    }
}

/// 缩放控制条显示/隐藏切换按钮
struct ScaleBarToggleButton: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible.toggle()
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isVisible ? Color.accentColor : Color(.systemGray5))
                        .frame(width: 34, height: 34)

                    Image(systemName: isVisible ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 14))
                        .foregroundColor(isVisible ? .white : .blue)
                }

                Text(NSLocalizedString("action.scaleBar", comment: "缩放"))
                    .font(.system(size: 10))
                    .fontWeight(isVisible ? .semibold : .regular)
                    .foregroundColor(isVisible ? .accentColor : .primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 46)
        }
    }
}

/// 单个效果按钮
struct EffectButton: View {
    let effect: BrushEffect
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                        .frame(width: 34, height: 34)

                    Image(systemName: effect.icon)
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : effect.previewColor)
                }

                Text(effect.localizedName)
                    .font(.system(size: 10))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 46)
        }
    }
}

/// 旋转按钮
struct RotateButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 34, height: 34)

                    Image(systemName: "rotate.right")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                }

                Text(NSLocalizedString("action.rotate", comment: "旋转"))
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 46)
        }
    }
}

// MARK: - Scale Control Bar

/// 左侧缩放控制条
struct ScaleControlBar: View {
    let isDragMode: Bool
    let hasSelection: Bool
    let onScaleUp: () -> Void
    let onScaleDown: () -> Void
    let onDelete: () -> Void
    /// 点击提示文字时直接切换到拖拽模式，降低进入编辑的门槛
    var onEnableDrag: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            // 标题
            Text(NSLocalizedString("scale.title", comment: "缩放"))
                .font(.caption2)
                .foregroundColor(.secondary)

            // 提示：需要先开启拖拽模式并选中区域
            if !isDragMode {
                Button {
                    onEnableDrag?()
                } label: {
                    Text(NSLocalizedString("scale.enableDragHint", comment: "开启拖拽"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .underline()
                }
                .buttonStyle(.plain)
            } else if !hasSelection {
                Text(NSLocalizedString("scale.selectHint", comment: "点击选中"))
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // 放大按钮
            Button(action: onScaleUp) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasSelection ? .blue : .gray)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            .accessibilityLabel(NSLocalizedString("action.scaleUp", comment: ""))

            // 缩放指示器
            VStack(spacing: 3) {
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(hasSelection ? (0.3 + Double(4 - i) * 0.15) : 0.2))
                        .frame(width: 14, height: 3)
                }
            }
            .padding(.vertical, 6)

            // 缩小按钮
            Button(action: onScaleDown) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasSelection ? .blue : .gray)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            .accessibilityLabel(NSLocalizedString("action.scaleDown", comment: ""))

            Spacer()

            // 删除选中区域按钮
            Button(action: onDelete) {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasSelection ? .red : .gray)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            .accessibilityLabel(NSLocalizedString("action.deleteRegion", comment: ""))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(width: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 2, y: 0)
        )
        .padding(.leading, 8)
        .padding(.vertical, 20)
    }
}

// MARK: - Detection Result Bar

/// AI检测结果条：展示检测到的敏感区域，支持逐条应用/忽略或全部应用
struct DetectionResultBar: View {
    let regions: [SensitiveRegion]
    /// 其他页面尚未处理的检测区域数量（图片文件恒为0）
    var otherPagesCount: Int = 0
    let onApply: (SensitiveRegion) -> Void
    let onIgnore: (SensitiveRegion) -> Void
    let onApplyAll: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: NSLocalizedString("editor.detectedRegions", comment: ""),
                            regions.count)
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if otherPagesCount > 0 {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "editor.detectedRegions.otherPages", comment: ""),
                                otherPagesCount)
                        )
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button(NSLocalizedString("editor.detect.applyAll", comment: "")) {
                    onApplyAll()
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(minHeight: 44)
                .disabled(regions.isEmpty)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)

            if !regions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(regions) { region in
                            DetectionChip(
                                region: region,
                                onApply: { onApply(region) },
                                onIgnore: { onIgnore(region) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }
}

/// 单个检测结果卡片
struct DetectionChip: View {
    let region: SensitiveRegion
    let onApply: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(region.type.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Button(action: onApply) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button(action: onIgnore) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - PDF Page Navigator

/// PDF页面导航栏
struct PDFPageNavigator: View {
    let currentPage: Int
    let totalPages: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onPrevious) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text(NSLocalizedString("pdf.prevPage", comment: ""))
                        .font(.subheadline)
                }
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == 0)

            Spacer()

            VStack(spacing: 2) {
                Text(
                    String(
                        format: NSLocalizedString("pdf.pageInfo", comment: ""),
                        currentPage + 1,
                        totalPages
                    )
                )
                .font(.headline)
                Text(NSLocalizedString("pdf.switchHint", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onNext) {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("pdf.nextPage", comment: ""))
                        .font(.subheadline)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .disabled(currentPage >= totalPages - 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }
}

// MARK: - Loading View

/// 加载状态视图
struct EditorLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            Text(NSLocalizedString("editor.loading", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Error View

/// 加载失败视图
struct EditorErrorView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            Text(NSLocalizedString("editor.loadFailed", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("editor.loadFailedHint", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
