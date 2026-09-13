import AVFoundation
import AVKit
import Combine
import CoreData
import Foundation
import UIKit

@MainActor
final class VideoEditorViewModel: ObservableObject {
    @Published var showDraftRestore = false
    @Published var draftError: String?
    private var pendingDraft: EditorDraft?
    private var draftChecked = false
    private var draftSession: UUID?
    private var draftEnabled = false
    private var analyzedTimelineAvailable = false
    private var draftSaveTask: Task<Void, Never>?
    private var restoredPlaybackSeconds: Double?
    private var playbackTimeObserver: VideoPlaybackTimeObservation?
    private var isReviewScrubbing = false
    private var reviewSeekGeneration = 0
    private var pendingReviewSeek: Int?

    private func checkDraft() -> Bool {
        guard !draftChecked else { return !showDraftRestore }
        draftChecked = true
        do {
            pendingDraft = try EditorDraftStore.shared.load(id: video.id)
            draftSession = EditorDraftStore.shared.beginSession(for: video.id)
            if pendingDraft?.videoState != nil {
                showDraftRestore = true
                return false
            }
            draftEnabled = true
            return true
        } catch {
            draftError = NSLocalizedString("draft.restoreFailed", comment: "")
            return true
        }
    }

    func restoreDraft() {
        guard let state = pendingDraft?.videoState,
              let restoredSticker = VideoRedactionSticker(rawValue: state.sticker),
              let restoredVoice = VoicePreset(rawValue: state.voicePreset) else {
            draftError = NSLocalizedString("draft.restoreFailed", comment: "")
            return
        }
        sticker = restoredSticker
        voicePreset = restoredVoice
        manualRegions = state.manualRegions ?? []
        groups = state.groups ?? []
        if let restored = state.timeline {
            timeline = restored
            analyzedTimelineAvailable = restored.frames.allSatisfy { $0.normalizedRects.count == $0.trackIDs.count }
        }
        restoredPlaybackSeconds = state.playbackSeconds
        pendingDraft = nil
        showDraftRestore = false
        draftEnabled = true
        start()
    }

    private func scheduleDraftSave() {
        guard draftEnabled else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.flushDraft()
        }
    }

    @discardableResult
    func flushDraft() -> Bool {
        draftSaveTask?.cancel()
        guard draftEnabled, let session = draftSession else { return false }
        do {
            var state = DraftVideoState(sticker: sticker, voice: voicePreset,
                                        timeline: analyzedTimelineAvailable ? timeline : nil,
                                        playbackSeconds: player.currentTime().seconds)
            state.manualRegions = manualRegions
            state.groups = groups
            let draft = EditorDraft(originalID: video.id, masks: [], pageIndex: 0,
                                    recognition: [], selectedEffect: try DraftEffect(.solidBlack), videoState: state)
            try EditorDraftStore.shared.save(draft, session: session)
            return true
        } catch { draftError = NSLocalizedString("draft.saveFailed", comment: ""); return false }
    }

    @discardableResult
    func discardDraft(startFresh: Bool = false) -> Bool {
        draftEnabled = false
        draftSaveTask?.cancel()
        do {
            try EditorDraftStore.shared.delete(id: video.id)
            pendingDraft = nil
            showDraftRestore = false
            if startFresh {
                draftSession = EditorDraftStore.shared.beginSession(for: video.id)
                draftEnabled = true
                start()
            }
            return true
        } catch {
            draftError = NSLocalizedString("draft.deleteFailed", comment: "")
            return false
        }
    }

    enum Phase: Equatable {
        case preparing
        case analyzing
        case ready
        case exporting
        case completed
        case failed
        case cancelled
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var progress = 0.0
    @Published private(set) var faceCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var exportedFile: RedactedFile?
    @Published private(set) var exportAudioTrackCount: Int?
    @Published private(set) var exportMetadataCount: Int?
    @Published private(set) var exportedVoicePreset: VoicePreset?
    @Published private(set) var manualRegions: [VideoManualRegion] = []
    @Published private(set) var groups: [VideoPersonGroup] = []
    @Published var selectedTrackIDs: Set<Int> = []

    func highlightedTracks(at seconds: Double) -> [(id: Int, rect: CGRect)] {
        guard let frame = timeline.frame(at: seconds) else { return [] }
        return zip(frame.trackIDs, frame.normalizedRects).compactMap { id, rect in
            selectedTrackIDs.contains(id) ? (id: id, rect: rect) : nil
        }
    }
    @Published var reviewSeconds = 0.0
    private var pendingGroupTrackIDs: Set<Int>?

    var trackIDs: [Int] { Array(Set(timeline.frames.flatMap(\.trackIDs))).sorted() }
    var automaticCoverage: Int { timeline.frame(at: reviewSeconds)?.normalizedRects.count ?? 0 }
    var manualCoverage: Int { manualRegions.filter { $0.contains(reviewSeconds) }.count }
    func coverageIntervals(manual: Bool) -> [ClosedRange<Double>] {
        if manual { return manualRegions.map { $0.start...$0.end } }
        var intervals: [ClosedRange<Double>] = []
        for index in timeline.frames.indices where !timeline.frames[index].normalizedRects.isEmpty {
            let start = index == 0 ? 0 : (timeline.frames[index - 1].seconds + timeline.frames[index].seconds) / 2
            let end = index + 1 == timeline.frames.count ? video.duration : (timeline.frames[index].seconds + timeline.frames[index + 1].seconds) / 2
            guard end > start else { continue }
            if let previous = intervals.last, previous.upperBound >= start {
                intervals[intervals.count - 1] = previous.lowerBound...end
            } else { intervals.append(start...end) }
        }
        return intervals
    }

    func trackRange(_ id: Int) -> ClosedRange<Double>? {
        let frames = timeline.frames.filter { $0.trackIDs.contains(id) }
        guard let first = frames.first, let last = frames.last else { return nil }
        return first.seconds...min(video.duration, last.seconds + 1 / max(1, timeline.frameRate))
    }

    func seekReview(_ seconds: Double) {
        reviewSeconds = seconds
        player.pause()
        reviewSeekGeneration += 1
        let generation = reviewSeekGeneration
        pendingReviewSeek = generation
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pendingReviewSeek == generation else { return }
                self.pendingReviewSeek = nil
            }
        }
    }

    func reviewScrubbingChanged(_ isEditing: Bool) {
        isReviewScrubbing = isEditing
    }

    func synchronizeReviewTime(_ seconds: Double) {
        guard !isReviewScrubbing, pendingReviewSeek == nil, seconds.isFinite else { return }
        reviewSeconds = min(video.duration, max(0, seconds))
    }

    private func observePlaybackTime() {
        guard playbackTimeObserver == nil else { return }
        playbackTimeObserver = VideoPlaybackTimeObservation(player: player) { [weak self] time in
            Task { @MainActor in self?.synchronizeReviewTime(time.seconds) }
        }
    }

    private func removePlaybackTimeObserver() {
        playbackTimeObserver = nil
        pendingReviewSeek = nil
        isReviewScrubbing = false
    }

    func saveRegion(rect: CGRect, start: Double, end: Double, replacing: UUID? = nil, effect: String = "blur") -> Bool {
        guard var region = VideoManualRegion(rect: rect, start: start, end: end, duration: video.duration) else { return false }
        region.effect = effect
        if let replacing { region.id = replacing; manualRegions.removeAll { $0.id == replacing } }
        manualRegions.append(region)
        scheduleDraftSave()
        refreshPreview()
        return true
    }

    func removeRegion(_ id: UUID) {
        manualRegions.removeAll { $0.id == id }
        scheduleDraftSave()
        refreshPreview()
    }

    func applyGroupEffect(_ effect: String) {
        guard !selectedTrackIDs.isEmpty else { return }
        if let requested = VideoRedactionSticker(rawValue: effect), requested.isLocked(hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess) {
            pendingGroupTrackIDs = selectedTrackIDs
            requestStickerSelection(requested)
            return
        }
        for index in groups.indices { groups[index].trackIDs.removeAll { selectedTrackIDs.contains($0) } }
        groups.removeAll { $0.trackIDs.isEmpty }
        groups.append(VideoPersonGroup(trackIDs: selectedTrackIDs.sorted(), effect: effect))
        scheduleDraftSave()
        refreshPreview()
    }
    /// 分析阶段剩余时间预估（秒）；nil 表示无预估（分析中会持续更新）
    @Published private(set) var estimatedRemainingSeconds: TimeInterval?

    /// 免费用户每日配额（图片+视频合并）已用完
    @Published var showUsageLimitAlert = false
    /// 视频超过免费大小限制（300MB），需要高级版
    @Published var showPremiumSizeAlert = false
    /// 高级版购买页
    @Published var showPremiumView = false
    @Published private(set) var sticker: VideoRedactionSticker = .orangeSmiley
    @Published var voicePreset: VoicePreset = .original {
        didSet {
            guard oldValue != voicePreset else { return }
            voicePreviewError = nil
            scheduleDraftSave()
            // 正在试听/生成试听时切换预设会与播放内容不一致，先恢复为原声预览。
            if isVoicePreviewActive || isPreparingVoicePreview {
                stopVoicePreview()
            }
        }
    }
    @Published private(set) var isVoicePreviewActive = false
    @Published private(set) var isPreparingVoicePreview = false
    @Published private(set) var voicePreviewError: String?
    @Published var player = AVPlayer()

    let video: OriginalVideo
    private var workspace: URL?
    private var sourceURL: URL?
    private var timeline = VideoFaceTimeline.empty
    private var stickerSelection = VideoStickerSelectionState()
    private var premiumIntent = VideoPremiumIntentState()
    private var workTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// 导出后台任务标识（导出期间退后台保护）
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// 视图是否仍在前台（onDisappear 后置 false；导出在视图离开后完成时需要自行清理）
    private var isViewVisible = true
    /// 试听模式下用于预览的组合：画面脱敏 + 处理后的音轨（或静音无音轨）。
    private var previewAsset: AVAsset?
    private let context = PersistenceController.shared.container.viewContext

    init(video: OriginalVideo) {
        self.video = video
    }

    var hasNoDetectedFaces: Bool { phase == .ready && faceCount == 0 }
    var canExport: Bool { phase == .ready }
    /// 试听按钮是否可用：就绪、有音轨且不是原声。
    var canPreviewVoice: Bool { phase == .ready && video.hasAudio && voicePreset != .original }

    func start() {
        guard workTask == nil, phase == .preparing, checkDraft() else { return }
        configurePlaybackAudioSession()
        workTask = Task { await prepareAndAnalyze() }
    }

    func cancelCurrentOperation() {
        workTask?.cancel()
    }

    func retry() {
        guard workTask == nil else { return }
        cleanup()
        phase = .preparing
        progress = 0
        faceCount = 0
        errorMessage = nil
        timeline = .empty
        analyzedTimelineAvailable = false
        start()
    }

    /// 视图离开：非导出状态立即清理；导出中保留任务继续完成，
    /// 否则 onDisappear 路径会误杀正在后台受保护的导出
    func viewDidDisappear() {
        isViewVisible = false
        flushDraft()
        if phase != .exporting {
            cleanup()
        }
    }

    func export() {
        guard phase == .ready, let sourceURL, let workspace else { return }
        let effects = groups.map(\.effect) + manualRegions.map(\.effect)
        if let locked = effects.compactMap(VideoRedactionSticker.init(rawValue:)).first(where: { $0.isLocked(hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess) }) {
            requestStickerSelection(locked)
            return
        }
        guard !sticker.isLocked(hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess) else {
            requestStickerSelection(sticker)
            return
        }
        // 免费用户校验：大视频需会员 + 每日媒体配额（图片/视频合并）
        guard AppState.shared.hasUnlimitedAccess || canExportForFreeUser() else { return }
        beginExport(sourceURL: sourceURL, workspace: workspace)
    }

    func requestStickerSelection(_ requestedSticker: VideoRedactionSticker) {
        if stickerSelection.request(
            requestedSticker,
            hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess
        ) {
            applySelectedSticker(stickerSelection.selected)
        } else {
            premiumIntent.present(.sticker(requestedSticker))
            showPremiumView = true
        }
    }

    func presentPremiumForExport() {
        stickerSelection.cancelPremiumRequest()
        premiumIntent.present(.export)
        showPremiumView = true
    }

    func premiumViewDidDismiss() {
        let action = premiumIntent.resolveDismissal(
            hasUnlimitedAccess: AppState.shared.hasUnlimitedAccess,
            selection: &stickerSelection
        )
        switch action {
        case .applySticker(let selected):
            if let tracks = pendingGroupTrackIDs {
                selectedTrackIDs = tracks
                applyGroupEffect(selected.rawValue)
            } else { applySelectedSticker(selected) }
        case .retryExport:
            export()
        case .none:
            break
        }
        pendingGroupTrackIDs = nil
    }

    private func applySelectedSticker(_ selected: VideoRedactionSticker) {
        guard sticker != selected else { return }
        sticker = selected
        scheduleDraftSave()
        refreshPreview()
    }

    /// 免费用户导出校验；通过则返回 true。
    /// 超过 300MB 的视频要求高级版；每日媒体配额与图片共用（3 次/天）。
    private func canExportForFreeUser() -> Bool {
        if video.fileSize > UsageTracker.freeVideoSizeLimit {
            showPremiumSizeAlert = true
            return false
        }
        guard UsageTracker.shared.canExportMedia() else {
            showUsageLimitAlert = true
            return false
        }
        return true
    }

    private func beginExport(sourceURL: URL, workspace: URL) {
        // 避免预览与导出同时解码、合成视频而争用设备资源。
        player.pause()
        phase = .exporting
        progress = 0
        errorMessage = nil
        estimatedRemainingSeconds = nil
        // 导出期间退后台保护：申请系统后台宽限期，避免进程被挂起后导出无声失败
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "videoExport") {
            [weak self] in
            // 宽限期到期：无法继续保证完成，主动取消收尾
            self?.workTask?.cancel()
        }
        workTask = Task {
            defer {
                // 导出结束（无论成败/取消）释放后台任务
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            do {
                let exportURL = workspace.appendingPathComponent("redacted-export.mp4")
                switch voicePreset {
                case .original:
                    try await VideoExporter().export(
                        sourceURL: sourceURL,
                        destinationURL: exportURL,
                        timeline: timeline,
                        sticker: sticker,
                        audio: .original,
                        manualRegions: manualRegions, groups: groups,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.progress = value * 0.95 }
                        }
                    )
                case .mute:
                    // 静音导出在导出阶段直接去掉音轨，避免先带音导出再二次转码。
                    try await VideoExporter().export(
                        sourceURL: sourceURL,
                        destinationURL: exportURL,
                        timeline: timeline,
                        sticker: sticker,
                        audio: .mute,
                        manualRegions: manualRegions, groups: groups,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.progress = value * 0.95 }
                        }
                    )
                case .anonymousMale, .anonymousFemale, .robot:
                    let processedAudio = workspace.appendingPathComponent("processed-audio.m4a")
                    let audioURL = try await VideoAudioProcessor().process(
                        sourceVideoURL: sourceURL,
                        destinationURL: processedAudio,
                        preset: voicePreset,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.progress = value * 0.2 }
                        }
                    )
                    try Task.checkCancellation()
                    guard let audioURL else { throw VideoProcessingError.missingAudioTrack }
                    // 处理后的音轨直接并入本次导出，视频只编码一次。
                    try await VideoExporter().export(
                        sourceURL: sourceURL,
                        destinationURL: exportURL,
                        timeline: timeline,
                        sticker: sticker,
                        audio: .replace(audioURL),
                        manualRegions: manualRegions, groups: groups,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.progress = 0.2 + value * 0.75 }
                        }
                    )
                    try? FileManager.default.removeItem(at: processedAudio)
                }
                try Task.checkCancellation()
                progress = 0.95

                let audioTracks = try? await AVURLAsset(url: exportURL).loadTracks(withMediaType: .audio)
                let metadata = try? await AVURLAsset(url: exportURL).load(.metadata)
                exportMetadataCount = metadata?.count
                exportedVoicePreset = video.hasAudio ? voicePreset : .mute
                let redacted = try persistExport(stagedURL: exportURL)
                if !AppState.shared.hasUnlimitedAccess {
                    UsageTracker.shared.recordMediaExport()
                }
                exportedFile = redacted
                exportAudioTrackCount = audioTracks?.count
                phase = .completed
                progress = 1
            } catch is CancellationError {
                // 导出取消统一落到 .cancelled（此前落 .ready，取消面板永远无法出现），
                // 与准备/分析阶段取消的语义一致，.cancelled 面板提供重试入口。
                phase = .cancelled
                errorMessage = NSLocalizedString("video.status.cancelled", comment: "")
            } catch {
                phase = .failed
                errorMessage = error.localizedDescription
            }
            // 视图已离开且导出自行完成：清理明文工作副本（正常路径由 onDisappear→cleanup 处理）
            if !isViewVisible {
                removePlaybackTimeObserver()
                player.pause()
                player.replaceCurrentItem(with: nil)
                releasePlaybackAudioSession()
                StorageManager.shared.removeVideoWorkspace(workspace)
                if self.workspace == workspace {
                    self.workspace = nil
                    self.sourceURL = nil
                }
            }
            workTask = nil
        }
    }

    func cleanup() {
        removePlaybackTimeObserver()
        workTask?.cancel()
        previewTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        releasePlaybackAudioSession()
        previewTask = nil
        previewAsset = nil
        isVoicePreviewActive = false
        isPreparingVoicePreview = false
        voicePreviewError = nil
        if let workspace {
            StorageManager.shared.removeVideoWorkspace(workspace)
        }
        self.workspace = nil
        sourceURL = nil
    }

    /// 试听/停止试听当前变声预设；处理预设需要先生成试听音频。
    func toggleVoicePreview() {
        guard canPreviewVoice, !isPreparingVoicePreview else { return }
        if isVoicePreviewActive {
            stopVoicePreview()
        } else {
            startVoicePreview()
        }
    }

    func stopVoicePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewAsset = nil
        isPreparingVoicePreview = false
        isVoicePreviewActive = false
        installSourcePreview()
    }

    private func startVoicePreview() {
        guard let sourceURL, let workspace, video.hasAudio else { return }
        voicePreviewError = nil
        isPreparingVoicePreview = true
        previewTask = Task { [weak self] in
            await self?.generateVoicePreview(sourceURL: sourceURL, workspace: workspace)
        }
    }

    private func generateVoicePreview(sourceURL: URL, workspace: URL) async {
        defer {
            isPreparingVoicePreview = false
            previewTask = nil
        }
        do {
            let composition: AVAsset
            switch voicePreset {
            case .original:
                refreshPreview()
                return
            case .mute:
                composition = try await makePreviewComposition(
                    sourceURL: sourceURL,
                    audioURL: nil
                )
            case .anonymousMale, .anonymousFemale, .robot:
                let audioURL = workspace.appendingPathComponent(
                    "preview-audio-\(UUID().uuidString).m4a"
                )
                let processed = try await VideoAudioProcessor().process(
                    sourceVideoURL: sourceURL,
                    destinationURL: audioURL,
                    preset: voicePreset
                )
                try Task.checkCancellation()
                guard let processed else {
                    throw VideoProcessingError.exportFailed(
                        NSLocalizedString("voice.error.render", comment: "")
                    )
                }
                composition = try await makePreviewComposition(
                    sourceURL: sourceURL,
                    audioURL: processed
                )
            }
            try Task.checkCancellation()
            previewAsset = composition
            isVoicePreviewActive = true
            installPreviewItem(asset: composition)
        } catch is CancellationError {
            // 主动取消试听：恢复原声预览，不展示错误。
            stopVoicePreview()
        } catch {
            voicePreviewError = error.localizedDescription
            refreshPreview()
        }
    }

    /// 把画面脱敏后的音轨（或空）与源视频画面合成一个预览组合，保证音画同步。
    private func makePreviewComposition(sourceURL: URL, audioURL: URL?) async throws -> AVAsset {
        try await VideoMuxer.makeComposition(videoURL: sourceURL, audioURL: audioURL)
    }

    /// 预览/试听播放需要显式使用 `.playback` 分类：默认的 `.soloAmbient`
    /// 跟随静音拨片，会导致相册里有声的视频进入工作区后播放无声。
    private func configurePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func releasePlaybackAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func prepareAndAnalyze() async {
        do {
            let workspace = try StorageManager.shared.createVideoWorkspace()
            self.workspace = workspace
            let source = try await VideoImportService.decryptVideo(video, into: workspace)
            try Task.checkCancellation()
            sourceURL = source
            phase = .analyzing
            progress = 0
            estimatedRemainingSeconds = nil
            if !analyzedTimelineAvailable {
                timeline = try await VideoFaceAnalyzer().analyze(
                url: source,
                progress: { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                },
                eta: { [weak self] value in
                    Task { @MainActor in self?.estimatedRemainingSeconds = value }
                }
            )
            }
            analyzedTimelineAvailable = true
            try Task.checkCancellation()
            estimatedRemainingSeconds = nil
            faceCount = timeline.totalUniqueFaces
            refreshPreview()
            phase = .ready
            progress = 1
            if let seconds = restoredPlaybackSeconds {
                await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                synchronizeReviewTime(player.currentTime().seconds)
                restoredPlaybackSeconds = nil
            }
            flushDraft()
        } catch is CancellationError {
            // 主动取消是中性状态，不应被渲染成处理失败。
            phase = .cancelled
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
        workTask = nil
    }

    private func refreshPreview() {
        guard let sourceURL else { return }
        let asset: AVAsset
        if isVoicePreviewActive, let previewAsset {
            asset = previewAsset
        } else {
            asset = AVURLAsset(url: sourceURL)
        }
        installPreviewItem(asset: asset)
    }

    private func installSourcePreview() {
        guard let sourceURL else { return }
        installPreviewItem(asset: AVURLAsset(url: sourceURL))
    }

    private func installPreviewItem(asset: AVAsset) {
        observePlaybackTime()
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = VideoCompositionFactory.make(
            asset: asset,
            timeline: timeline,
            sticker: sticker,
            manualRegions: manualRegions,
            groups: groups
        )
        let resumeTime = VideoPlaybackTime.resumeTime(from: player)
        player.replaceCurrentItem(with: item)
        if let resumeTime {
            player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func persistExport(stagedURL: URL) throws -> RedactedFile {
        let id = UUID()
        var finalURL: URL?
        var thumbnailURL: URL?
        var insertedRedacted: RedactedFile?
        do {
            finalURL = try StorageManager.shared.commitRedactedFile(
                from: stagedURL,
                id: id,
                type: .video
            )
            let thumbnail = try VideoThumbnailGenerator.jpegData(from: finalURL!)
            thumbnailURL = try StorageManager.shared.saveRedactedThumbnail(
                data: thumbnail,
                id: id,
                type: .video
            )
            let redacted = RedactedFile.create(
                in: context,
                id: id,
                fileType: .video,
                filePath: finalURL!.path,
                fileSize: StorageManager.shared.getFileSize(at: finalURL!),
                originalFile: video
            )
            insertedRedacted = redacted
            redacted.thumbnailPath = thumbnailURL?.path ?? ""
            redacted.group = video.group
            try context.save()
            return redacted
        } catch {
            if let insertedRedacted, insertedRedacted.managedObjectContext != nil {
                context.delete(insertedRedacted)
            }
            if let finalURL { try? FileManager.default.removeItem(at: finalURL) }
            if let thumbnailURL { try? FileManager.default.removeItem(at: thumbnailURL) }
            throw error
        }
    }
}

/// Holds the player used to register the token, so both explicit cleanup and
/// model deallocation remove the observer from that exact player.
private nonisolated final class VideoPlaybackTimeObservation {
    private let player: AVPlayer
    private let token: Any

    init(player: AVPlayer, update: @escaping @Sendable (CMTime) -> Void) {
        self.player = player
        token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main, using: update)
    }

    deinit { player.removeTimeObserver(token) }
}
