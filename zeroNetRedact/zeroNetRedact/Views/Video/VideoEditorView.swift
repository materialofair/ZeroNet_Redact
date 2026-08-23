import AVKit
import SwiftUI
import UIKit

struct VideoEditorView: View {
    @StateObject private var viewModel: VideoEditorViewModel
    @ObservedObject private var appState = AppState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var editorOrientation: VideoEditorOrientation = .portrait
    @State private var initialOrientation: VideoEditorOrientation?
    @State private var showShareSheet = false

    init(video: OriginalVideo) {
        _viewModel = StateObject(wrappedValue: VideoEditorViewModel(video: video))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // 双栏布局：横屏，或 iPad 全屏竖屏（尺寸等级为 regular/regular）时并排展示。
                // 仅按宽高比判断会把 iPad 竖屏误当成手机单栏，导致控制区被推到首屏之下。
                let usesSplitLayout = geometry.size.width > geometry.size.height
                    || (horizontalSizeClass == .regular && verticalSizeClass == .regular)

                Group {
                    if usesSplitLayout {
                        // 横屏/分栏布局：预览列与控制列各自独立滚动，
                        // 调整遮挡效果或声音时预览始终保持在视野内。
                        splitContent(availableWidth: geometry.size.width)
                    } else {
                        portraitScrollContent
                    }
                }
                .scrollIndicators(.hidden)
                .background(DesignSystem.Colors.backgroundPrimary.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
                .onAppear {
                    syncOrientation(withSplitLayout: usesSplitLayout)
                }
                .onChange(of: usesSplitLayout) { _, isSplit in
                    editorOrientation = isSplit ? .landscape : .portrait
                }
                .onChange(of: editorOrientation) { _, orientation in
                    VideoOrientationController.request(orientation) {
                        // 系统拒绝了旋转请求（例如方向锁边缘情况）：把选择器
                        // 恢复为实际几何方向，避免 UI 展示设备并未采纳的布局。
                        editorOrientation = layoutOrientation(for: geometry.size)
                    }
                }
                .navigationTitle(NSLocalizedString("video.editor.title", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(NSLocalizedString("common.close", comment: ""))
                        .accessibilityHint(NSLocalizedString("video.accessibility.closeHint", comment: ""))
                    }
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .sheet(isPresented: $showShareSheet) {
            if let file = viewModel.exportedFile {
                ShareSheet(items: [file.fileURL])
            }
        }
        // 免费用户每日配额（图片+视频合并）已用完
        .alert(
            NSLocalizedString("usage.limit.title", comment: ""),
            isPresented: $viewModel.showUsageLimitAlert
        ) {
            Button(NSLocalizedString("usage.limit.upgrade", comment: "")) {
                viewModel.presentPremiumForExport()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("usage.limit.message", comment: ""))
        }
        // 视频超过免费大小限制（300MB），需要高级版
        .alert(
            NSLocalizedString("video.premium.required.title", comment: ""),
            isPresented: $viewModel.showPremiumSizeAlert
        ) {
            Button(NSLocalizedString("usage.limit.upgrade", comment: "")) {
                viewModel.presentPremiumForExport()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("video.premium.required.message", comment: ""))
        }
        // 高级版购买页；购买成功后自动重试导出
        .sheet(
            isPresented: $viewModel.showPremiumView,
            onDismiss: {
                viewModel.premiumViewDidDismiss()
            }
        ) {
            PremiumView()
        }
        .sensoryFeedback(.success, trigger: viewModel.phase == .completed)
        .task { viewModel.start() }
        .onDisappear {
            // 导出中不清理：后台任务保护导出继续完成（此前无条件 cleanup 会直接取消导出）
            viewModel.viewDidDisappear()
            if let initialOrientation {
                VideoOrientationController.request(initialOrientation) {}
            }
        }
    }

    private var isBusy: Bool {
        switch viewModel.phase {
        case .preparing, .analyzing, .exporting: return true
        case .ready, .completed, .failed, .cancelled: return false
        }
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// iPad 全屏竖屏/横屏（horizontal/vertical 均为 regular）时使用双栏布局，
    /// 并给预览列留出更多空间。
    private var usesiPadFullScreenLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    private var portraitContent: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            preview
            stateContent

            if viewModel.phase == .ready {
                protectionSection
                voiceSection
                reviewNotice
            }
        }
    }

    private var portraitScrollContent: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                if !isPad {
                    orientationPicker
                }
                portraitContent
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.sm)
            .padding(.bottom, DesignSystem.Spacing.xxxl)
        }
    }

    /// 横屏/分栏布局：左列只放预览（占满可用高度），右列承载
    /// 布局选择、状态与全部控制项并独立滚动。这样在横屏矮视口里，
    /// 预览整框常驻，滚动控制区不会把"选效果 → 看预览确认"的审查对象带走；
    /// 导出进度与取消按钮也在右列，处理中更容易被看到。
    private func splitContent(availableWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xl) {
            ScrollView {
                preview
            }
            .frame(maxWidth: .infinity, alignment: .top)

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    if !isPad {
                        orientationPicker
                    }
                    stateContent
                    if viewModel.phase == .ready {
                        protectionSection
                        voiceSection
                        reviewNotice
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.sm)
                .padding(.bottom, DesignSystem.Spacing.xxxl)
            }
            .frame(maxWidth: controlsMaxWidth(for: availableWidth), alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.sm)
        .padding(.bottom, DesignSystem.Spacing.xxxl)
    }

    private var orientationPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    orientationLabel
                    orientationControl
                }
            } else {
                HStack(spacing: DesignSystem.Spacing.md) {
                    orientationLabel
                    Spacer(minLength: DesignSystem.Spacing.sm)
                    orientationControl
                        .frame(maxWidth: 260)
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var orientationLabel: some View {
        Label(
            NSLocalizedString("video.orientation.title", comment: ""),
            systemImage: "rectangle.landscape.rotate"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(DesignSystem.Colors.textPrimary)
    }

    private var orientationControl: some View {
        Picker(
            NSLocalizedString("video.orientation.title", comment: ""),
            selection: $editorOrientation
        ) {
            ForEach(VideoEditorOrientation.allCases) { orientation in
                Label(orientation.displayName, systemImage: orientation.icon)
                    .tag(orientation)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint(NSLocalizedString("video.orientation.hint", comment: ""))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .fill(Color.black)

                if viewModel.phase == .ready || viewModel.phase == .completed {
                    VideoPlayer(player: viewModel.player)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                } else {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(NSLocalizedString("video.preview.protectedWorkspace", comment: ""))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }

                // 完成态播放的仍是脱敏预览合成，徽标与播放器同条件显示（此前仅 .ready，完成后徽标消失）
                if viewModel.phase == .ready || viewModel.phase == .completed {
                    Label(
                        NSLocalizedString("video.preview.redactionOn", comment: ""),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(DesignSystem.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(NSLocalizedString("video.accessibility.preview", comment: ""))

            if viewModel.phase == .ready || viewModel.phase == .completed {
                Label(
                    NSLocalizedString("video.preview.reviewHint", comment: ""),
                    systemImage: "hand.tap"
                )
                .font(.footnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.phase {
        case .preparing, .analyzing, .exporting:
            processingPanel
        case .ready:
            readyPanel
        case .completed:
            completedPanel
        case .failed:
            failedPanel
        case .cancelled:
            cancelledPanel
        }
    }

    private var processingPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(processingTitle)
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer(minLength: DesignSystem.Spacing.sm)
                Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryBlue)
                    .contentTransition(.numericText())
            }

            ProgressView(value: viewModel.progress)
                .tint(DesignSystem.Colors.primaryBlue)

            // 分析阶段显示剩余时间预估（按时长降采样 + 实测吞吐推算）
            if viewModel.phase == .analyzing,
                let remaining = viewModel.estimatedRemainingSeconds, remaining > 0
            {
                Text(
                    String(
                        format: NSLocalizedString("video.status.etaRemaining", comment: ""),
                        Duration.seconds(remaining).formatted(
                            .units(
                                allowed: [.hours, .minutes, .seconds],
                                width: .abbreviated,
                                maximumUnitCount: 2))
                    )
                )
                .font(.footnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                    .frame(width: 18)
                Text(NSLocalizedString("video.notice.offline", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                viewModel.cancelCurrentOperation()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(minHeight: 44)
        }
        .editorPanel()
    }

    private var readyPanel: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: viewModel.hasNoDetectedFaces ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(viewModel.hasNoDetectedFaces ? DesignSystem.Colors.warningOrange : DesignSystem.Colors.successGreen)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(
                    String(
                        format: NSLocalizedString("video.status.facesFound", comment: ""),
                        viewModel.faceCount
                    )
                )
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(NSLocalizedString("video.status.reviewBeforeExport", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .editorPanel(
            fill: viewModel.hasNoDetectedFaces
                ? DesignSystem.Colors.warningOrange.opacity(0.10)
                : DesignSystem.Colors.successGreen.opacity(0.08)
        )
    }

    private var completedPanel: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.successGreen)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(NSLocalizedString("video.status.completed", comment: ""))
                    .font(.headline)
                Text(NSLocalizedString("video.status.completedHint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DesignSystem.Colors.textPrimary)
        .editorPanel(fill: DesignSystem.Colors.successGreen.opacity(0.08))
    }

    private var failedPanel: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "xmark.octagon.fill")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.dangerRed)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(NSLocalizedString("video.status.failed", comment: ""))
                    .font(.headline)
                Text(viewModel.errorMessage ?? NSLocalizedString("common.error", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DesignSystem.Colors.textPrimary)
        .editorPanel(fill: DesignSystem.Colors.dangerRed.opacity(0.08))
    }

    private var cancelledPanel: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(NSLocalizedString("video.status.cancelledTitle", comment: ""))
                    .font(.headline)
                Text(NSLocalizedString("video.status.cancelledHint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DesignSystem.Colors.textPrimary)
        .editorPanel()
    }

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeading(
                title: NSLocalizedString("video.effect.title", comment: ""),
                subtitle: NSLocalizedString("video.effect.subtitle", comment: "")
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(VideoRedactionSticker.allCases) { sticker in
                        effectOption(sticker)
                    }
                }
                .padding(.trailing, DesignSystem.Spacing.sm)
            }
        }
    }

    /// 紧凑贴纸卡片：单行横向滑动选择。固定宽度、高度随内容自适应，
    /// 大字号辅助功能下名称可以换行而不裁切。
    private func effectOption(_ sticker: VideoRedactionSticker) -> some View {
        let isSelected = viewModel.sticker == sticker
        let isLocked = sticker.isLocked(hasUnlimitedAccess: appState.hasUnlimitedAccess)
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                viewModel.requestStickerSelection(sticker)
            }
        } label: {
            VStack(spacing: DesignSystem.Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    stickerArtwork(sticker)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(DesignSystem.Colors.warningOrange))
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(DesignSystem.Colors.primaryBlue)
                            .background(Circle().fill(DesignSystem.Colors.backgroundPrimary))
                    }
                }

                Text(sticker.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.primaryBlue : DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 84)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                isSelected
                    ? DesignSystem.Colors.primaryBlue.opacity(0.10)
                    : DesignSystem.Colors.backgroundSecondary,
                in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(
                        isSelected ? DesignSystem.Colors.primaryBlue : DesignSystem.Colors.separator,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sticker.displayName)
        .accessibilityValue(sticker.accessibilityValue(hasUnlimitedAccess: appState.hasUnlimitedAccess))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            NSLocalizedString(
                isLocked
                    ? "video.sticker.accessibility.premiumHint"
                    : "video.accessibility.effectHint",
                comment: ""
            )
        )
    }

    @ViewBuilder
    private func stickerArtwork(_ sticker: VideoRedactionSticker) -> some View {
        switch sticker.artwork {
        case .systemImage(let name):
            Image(systemName: name)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(
                    sticker == .orangeSmiley
                        ? DesignSystem.Colors.warningOrange
                        : DesignSystem.Colors.primaryBlue
                )
                .frame(width: 38, height: 38)
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeading(
                title: NSLocalizedString("voice.title", comment: ""),
                subtitle: NSLocalizedString("voice.subtitle", comment: "")
            )

            Menu {
                ForEach(VoicePreset.allCases) { preset in
                    Button {
                        viewModel.voicePreset = preset
                    } label: {
                        Label(preset.displayName, systemImage: preset.icon)
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: viewModel.voicePreset.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryBlue)
                        .frame(width: 30, height: 30)
                        .background(DesignSystem.Colors.primaryBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.voicePreset.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text(
                            viewModel.video.hasAudio
                                ? NSLocalizedString("voice.notice.fullTrack", comment: "")
                                : NSLocalizedString("voice.notice.noAudio", comment: "")
                        )
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: DesignSystem.Spacing.sm)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .stroke(DesignSystem.Colors.separator, lineWidth: 1)
                }
            }
            .disabled(!viewModel.video.hasAudio)
            .accessibilityLabel(NSLocalizedString("voice.title", comment: ""))
            .accessibilityValue(viewModel.voicePreset.displayName)
            .accessibilityHint(NSLocalizedString("video.accessibility.voiceHint", comment: ""))
            .opacity(viewModel.video.hasAudio ? 1 : 0.55)

            if viewModel.canPreviewVoice {
                voicePreviewButton
            }

            if let previewError = viewModel.voicePreviewError {
                Label(previewError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.dangerRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 试听当前变声/静音效果：处理中显示进度，试听中可一键恢复原声。
    private var voicePreviewButton: some View {
        Group {
            if viewModel.isPreparingVoicePreview {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(NSLocalizedString("voice.preview.processing", comment: ""))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            } else {
                Button {
                    viewModel.toggleVoicePreview()
                } label: {
                    Label(
                        viewModel.isVoicePreviewActive
                            ? NSLocalizedString("voice.preview.stop", comment: "")
                            : NSLocalizedString("voice.preview.play", comment: ""),
                        systemImage: viewModel.isVoicePreviewActive ? "stop.fill" : "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(
                    viewModel.isVoicePreviewActive
                        ? DesignSystem.Colors.dangerRed
                        : DesignSystem.Colors.primaryBlue
                )
                .accessibilityLabel(
                    viewModel.isVoicePreviewActive
                        ? NSLocalizedString("voice.preview.stop", comment: "")
                        : NSLocalizedString("voice.preview.play", comment: "")
                )
                .accessibilityHint(
                    NSLocalizedString("video.accessibility.voicePreviewHint", comment: "")
                )
            }
        }
    }

    private var reviewNotice: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: viewModel.hasNoDetectedFaces ? "exclamationmark.triangle.fill" : "eye.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(viewModel.hasNoDetectedFaces ? DesignSystem.Colors.warningOrange : DesignSystem.Colors.textSecondary)
                .frame(width: 20)
            Text(
                viewModel.hasNoDetectedFaces
                    ? NSLocalizedString("video.warning.noFaces", comment: "")
                    : NSLocalizedString("video.warning.review", comment: "")
            )
            .font(.footnote)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            viewModel.hasNoDetectedFaces
                ? DesignSystem.Colors.warningOrange.opacity(0.08)
                : DesignSystem.Colors.backgroundSecondary
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.phase {
        case .ready:
            footerContainer {
                Button(action: viewModel.export) {
                    Label(NSLocalizedString("video.action.export", comment: ""), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .completed:
            footerContainer {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                    Button {
                        showShareSheet = true
                    } label: {
                        Label(NSLocalizedString("video.action.share", comment: ""), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        case .failed:
            footerContainer {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button(NSLocalizedString("common.close", comment: "")) { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            viewModel.retry()
                        }
                    } label: {
                        Label(NSLocalizedString("video.action.retry", comment: ""), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        case .cancelled:
            footerContainer {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button(NSLocalizedString("common.close", comment: "")) { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            viewModel.retry()
                        }
                    } label: {
                        Label(NSLocalizedString("video.action.retry", comment: ""), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        case .preparing, .analyzing, .exporting:
            EmptyView()
        }
    }

    private func controlsMaxWidth(for availableWidth: CGFloat) -> CGFloat {
        if usesiPadFullScreenLayout { return 360 }
        // 手机横屏：控制列占可用宽度的 45%（340–420pt），窄屏（如 iPhone SE 横屏）
        // 下自动收紧，避免预览列被挤到看不清。
        let usable = max(0, availableWidth - 2 * DesignSystem.Spacing.lg)
        return min(420, max(340, usable * 0.45))
    }

    private var processingTitle: String {
        switch viewModel.phase {
        case .preparing: return NSLocalizedString("video.status.preparing", comment: "")
        case .analyzing: return NSLocalizedString("video.status.analyzing", comment: "")
        case .exporting: return NSLocalizedString("video.status.exporting", comment: "")
        case .ready, .completed, .failed, .cancelled: return ""
        }
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.sm)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignSystem.Colors.separator.opacity(0.65))
                    .frame(height: 0.5)
            }
    }

    private func syncOrientation(withSplitLayout isSplit: Bool) {
        let current: VideoEditorOrientation = isSplit ? .landscape : .portrait
        if initialOrientation == nil {
            initialOrientation = current
        }
        editorOrientation = current
    }

    private func layoutOrientation(for size: CGSize) -> VideoEditorOrientation {
        size.width > size.height ? .landscape : .portrait
    }
}

private enum VideoEditorOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portrait:
            return NSLocalizedString("video.orientation.portrait", comment: "")
        case .landscape:
            return NSLocalizedString("video.orientation.landscape", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .portrait: return "rectangle.portrait"
        case .landscape: return "rectangle"
        }
    }

    var mask: UIInterfaceOrientationMask {
        switch self {
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }
}

@MainActor
private enum VideoOrientationController {
    static func request(
        _ orientation: VideoEditorOrientation,
        onDenial: @escaping () -> Void
    ) {
        // iPad 的布局随窗口几何自动适配；强制旋转在 iPad 上经常被系统拒绝
        // （分屏多任务、方向锁），因此只在 iPhone 上发起几何更新请求。
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else { return }

        windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: orientation.mask
        )
        windowScene.requestGeometryUpdate(preferences) { _ in
            Task { @MainActor in onDenial() }
        }
    }
}

private struct EditorPanelModifier: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.separator.opacity(0.75), lineWidth: 1)
            }
    }
}

private extension View {
    func editorPanel(fill: Color = DesignSystem.Colors.backgroundSecondary) -> some View {
        modifier(EditorPanelModifier(fill: fill))
    }
}
