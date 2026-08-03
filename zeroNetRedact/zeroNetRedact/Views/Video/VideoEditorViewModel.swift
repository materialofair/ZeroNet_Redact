import AVFoundation
import AVKit
import Combine
import CoreData
import Foundation

@MainActor
final class VideoEditorViewModel: ObservableObject {
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

    /// 免费用户每日配额（图片+视频合并）已用完
    @Published var showUsageLimitAlert = false
    /// 视频超过免费大小限制（300MB），需要高级版
    @Published var showPremiumSizeAlert = false
    /// 高级版购买页
    @Published var showPremiumView = false
    @Published var sticker: VideoRedactionSticker = .orangeSmiley {
        didSet { refreshPreview() }
    }
    @Published var voicePreset: VoicePreset = .original {
        didSet {
            guard oldValue != voicePreset else { return }
            voicePreviewError = nil
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
    private var workTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
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
        guard workTask == nil else { return }
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
        start()
    }

    func export() {
        guard phase == .ready, let sourceURL, let workspace else { return }
        // 免费用户校验：大视频需会员 + 每日媒体配额（图片/视频合并）
        guard AppState.shared.hasUnlimitedAccess || canExportForFreeUser() else { return }
        beginExport(sourceURL: sourceURL, workspace: workspace)
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
        phase = .exporting
        progress = 0
        errorMessage = nil
        workTask = Task {
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
                        progress: { [weak self] value in
                            Task { @MainActor in self?.progress = 0.2 + value * 0.75 }
                        }
                    )
                    try? FileManager.default.removeItem(at: processedAudio)
                }
                try Task.checkCancellation()
                progress = 0.95

                let redacted = try persistExport(stagedURL: exportURL)
                if !AppState.shared.hasUnlimitedAccess {
                    UsageTracker.shared.recordMediaExport()
                }
                exportedFile = redacted
                phase = .completed
                progress = 1
            } catch is CancellationError {
                phase = .ready
                errorMessage = NSLocalizedString("video.status.cancelled", comment: "")
            } catch {
                phase = .failed
                errorMessage = error.localizedDescription
            }
            workTask = nil
        }
    }

    func cleanup() {
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
            timeline = try await VideoFaceAnalyzer().analyze(url: source) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            try Task.checkCancellation()
            faceCount = timeline.totalUniqueFaces
            refreshPreview()
            phase = .ready
            progress = 1
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
        guard let sourceURL, !timeline.frames.isEmpty else { return }
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
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = VideoCompositionFactory.make(
            asset: asset,
            timeline: timeline,
            sticker: sticker
        )
        let resumeTime = VideoPlaybackTime.resumeTime(from: player)
        player.replaceCurrentItem(with: item)
        if let resumeTime {
            player.seek(to: resumeTime)
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
