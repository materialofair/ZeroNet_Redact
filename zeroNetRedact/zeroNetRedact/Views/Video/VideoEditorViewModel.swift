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
    @Published var effect: VideoRedactionEffect = .strongBlur {
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
        phase = .exporting
        progress = 0
        errorMessage = nil
        workTask = Task {
            do {
                let staged = workspace.appendingPathComponent("redacted-with-source-audio.mp4")
                try await VideoExporter().export(
                    sourceURL: sourceURL,
                    destinationURL: staged,
                    timeline: timeline,
                    effect: effect,
                    progress: { [weak self] value in
                        Task { @MainActor in self?.progress = value * 0.72 }
                    }
                )
                try Task.checkCancellation()
                let finalStaged: URL
                switch voicePreset {
                case .original:
                    finalStaged = staged
                case .mute:
                    let muted = workspace.appendingPathComponent("redacted-muted.mp4")
                    try await VideoMuxer().replaceAudio(
                        videoURL: staged,
                        audioURL: nil,
                        destinationURL: muted
                    )
                    try? FileManager.default.removeItem(at: staged)
                    finalStaged = muted
                    progress = 0.95
                case .anonymousMale, .anonymousFemale, .robot:
                    let processedAudio = workspace.appendingPathComponent("processed-audio.m4a")
                    let audioURL = try await VideoAudioProcessor().process(
                        sourceVideoURL: sourceURL,
                        destinationURL: processedAudio,
                        preset: voicePreset,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.progress = 0.72 + value * 0.18 }
                        }
                    )
                    let voiced = workspace.appendingPathComponent("redacted-voiced.mp4")
                    try await VideoMuxer().replaceAudio(
                        videoURL: staged,
                        audioURL: audioURL,
                        destinationURL: voiced
                    )
                    try? FileManager.default.removeItem(at: staged)
                    try? FileManager.default.removeItem(at: processedAudio)
                    finalStaged = voiced
                    progress = 0.95
                }

                let redacted = try persistExport(stagedURL: finalStaged)
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
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(
                  withMediaType: .video,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              )
        else { throw VideoProcessingError.missingVideoTrack }
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideo,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        if let audioURL {
            let audioAsset = AVURLAsset(url: audioURL)
            if let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
                let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            {
                let audioDuration = min(duration, try await audioAsset.load(.duration))
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioDuration),
                    of: sourceAudio,
                    at: .zero
                )
            }
        }
        return composition
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
            effect: effect
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
