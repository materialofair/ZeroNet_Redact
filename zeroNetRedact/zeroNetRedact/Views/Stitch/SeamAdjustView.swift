//
//  SeamAdjustView.swift
//  ZeroNet Redact
//
//  拼缝精调:上下两图在拼缝处的局部对照 + 两条裁剪滑杆
//

import SwiftUI

struct SeamAdjustView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StitchViewModel
    /// 下图索引(调整 items[index-1].cropBottom 与 items[index].cropTop)
    let index: Int

    var body: some View {
        NavigationStack {
            Group {
                if let plan = viewModel.plan,
                    plan.items.indices.contains(index), index > 0
                {
                    content(plan: plan)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(NSLocalizedString("stitch.seam.adjust", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func content(plan: StitchPlan) -> some View {
        let upperItem = plan.items[index - 1]
        let lowerItem = plan.items[index]
        let upperSource = viewModel.sources[index - 1]
        let lowerSource = viewModel.sources[index]

        return VStack(spacing: 20) {
            // 拼缝局部对照
            VStack(spacing: 0) {
                SeamEdgeWindow(source: upperSource, item: upperItem, edge: .bottom)
                Rectangle()
                    .fill(DesignSystem.Colors.primaryBlue)
                    .frame(height: 2)
                SeamEdgeWindow(source: lowerSource, item: lowerItem, edge: .top)
            }
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .padding(.horizontal, DesignSystem.Spacing.lg)

            // 上图底部裁剪
            sliderRow(
                title: NSLocalizedString("stitch.seam.upperCrop", comment: ""),
                value: Binding(
                    get: { upperItem.cropBottom },
                    set: { viewModel.updateSeam(at: index, upperCropBottom: $0) }),
                range: 0...(upperItem.pixelSize.height - upperItem.cropTop - 50))

            // 下图顶部裁剪
            sliderRow(
                title: NSLocalizedString("stitch.seam.lowerCrop", comment: ""),
                value: Binding(
                    get: { lowerItem.cropTop },
                    set: { viewModel.updateSeam(at: index, cropTop: $0) }),
                range: 0...(lowerItem.pixelSize.height - lowerItem.cropBottom - 50))

            Spacer()
        }
        .padding(.top, 16)
    }

    private func sliderRow(
        title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue))px")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            Slider(value: value, in: range)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

/// 某一段在拼缝一侧的局部窗口(180pt 高)
struct SeamEdgeWindow: View {
    enum Edge { case top, bottom }

    let source: StitchSource
    let item: StitchItem
    let edge: Edge
    private let windowHeight: CGFloat = 180

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / item.pixelSize.width
            Image(uiImage: source.preview)
                .resizable()
                .frame(
                    width: item.pixelSize.width * scale,
                    height: item.pixelSize.height * scale
                )
                .offset(
                    y: edge == .top
                        ? -item.cropTop * scale
                        : windowHeight - (item.pixelSize.height - item.cropBottom) * scale)
        }
        .frame(height: windowHeight)
        .clipped()
    }
}
