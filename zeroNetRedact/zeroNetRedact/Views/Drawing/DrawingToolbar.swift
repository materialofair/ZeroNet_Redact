//
//  DrawingToolbar.swift
//  ZeroNet Redact
//
//  绘制工具栏 - 模式切换、效果选择、撤销/重做
//

import SwiftUI

/// 绘制工具栏
struct DrawingToolbar: View {
    @ObservedObject var drawingTool: ManualDrawingTool
    @Binding var showEffectPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 绘制模式切换
            drawingModeSection

            Divider()

            // 脱敏效果选择
            effectSection

            Divider()

            // 操作按钮
            actionSection
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }

    // MARK: - Sections

    /// 绘制模式选择
    private var drawingModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("绘制模式")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                ForEach(DrawingMode.allCases, id: \.self) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: drawingTool.currentMode == mode
                    ) {
                        drawingTool.currentMode = mode
                    }
                }
            }
        }
        .padding()
    }

    /// 脱敏效果选择
    private var effectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("脱敏效果")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                showEffectPicker = true
            } label: {
                HStack {
                    Image(systemName: drawingTool.currentEffect.icon)
                    Text(drawingTool.currentEffect.displayName)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundColor(.primary)
            }
        }
        .padding()
    }

    /// 操作按钮
    private var actionSection: some View {
        HStack(spacing: 16) {
            ActionButton(
                icon: "arrow.uturn.backward",
                label: "撤销",
                isEnabled: drawingTool.canUndo
            ) {
                drawingTool.undoLast()
            }

            ActionButton(
                icon: "trash",
                label: "清空",
                isEnabled: drawingTool.canUndo
            ) {
                drawingTool.clearAll()
            }
        }
        .padding()
    }
}

// MARK: - Subviews

/// 模式按钮
private struct ModeButton: View {
    let mode: DrawingMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.title2)
                Text(mode.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
    }
}

/// 操作按钮
private struct ActionButton: View {
    let icon: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isEnabled ? Color(.systemGray6) : Color(.systemGray5))
            .foregroundColor(isEnabled ? .primary : .secondary)
            .cornerRadius(8)
        }
        .disabled(!isEnabled)
    }
}

/// 脱敏效果选择器
struct EffectPickerSheet: View {
    @ObservedObject var drawingTool: ManualDrawingTool
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                Section("常用效果") {
                    effectRow(.solidBlack, isSelected: drawingTool.currentEffect == .solidBlack)
                    effectRow(.mosaic(pixelSize: 20), isSelected: isMosaicSelected)
                    effectRow(.blur(radius: 10), isSelected: isBlurSelected)
                }

                Section("自定义遮盖") {
                    effectRow(
                        .rectangle(color: .white, opacity: 1.0), label: "白色遮盖",
                        isSelected: isWhiteRectSelected)
                    effectRow(
                        .rectangle(color: .red, opacity: 0.8), label: "红色遮盖",
                        isSelected: isRedRectSelected)
                }
            }
            .navigationTitle("选择脱敏效果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func effectRow(_ effect: RedactionEffect, label: String? = nil, isSelected: Bool)
        -> some View
    {
        Button {
            drawingTool.currentEffect = effect
            isPresented = false
        } label: {
            HStack {
                Image(systemName: effect.icon)
                    .foregroundColor(.accentColor)
                Text(label ?? effect.displayName)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    // Helper computed properties
    private var isMosaicSelected: Bool {
        if case .mosaic = drawingTool.currentEffect { return true }
        return false
    }

    private var isBlurSelected: Bool {
        if case .blur = drawingTool.currentEffect { return true }
        return false
    }

    private var isWhiteRectSelected: Bool {
        if case .rectangle(let color, _) = drawingTool.currentEffect,
            color == .white
        {
            return true
        }
        return false
    }

    private var isRedRectSelected: Bool {
        if case .rectangle(let color, _) = drawingTool.currentEffect,
            color == .red
        {
            return true
        }
        return false
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var drawingTool = ManualDrawingTool()
        @State private var showEffectPicker = false

        var body: some View {
            VStack {
                Spacer()

                DrawingToolbar(
                    drawingTool: drawingTool,
                    showEffectPicker: $showEffectPicker
                )
                .padding()
            }
            .sheet(isPresented: $showEffectPicker) {
                EffectPickerSheet(
                    drawingTool: drawingTool,
                    isPresented: $showEffectPicker
                )
            }
        }
    }

    return PreviewWrapper()
}
