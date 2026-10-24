import AVFoundation
import Foundation

/// If a live compositor cannot feed a display layer, play a locally rendered protected copy.
/// Never substitute the unredacted source for a failed protected preview.
@MainActor
final class ProtectedVideoPreview {
    private let player: AVPlayer
    private let changed: (Bool, String?) -> Void
    private var observation: NSKeyValueObservation?
    private var renderTask: Task<Void, Never>?
    private var generation = 0
    private var renderedURL: URL?

    init(player: AVPlayer, changed: @escaping (Bool, String?) -> Void = { _, _ in }) {
        self.player = player
        self.changed = changed
    }

    func install(asset: AVAsset, composition: AVVideoComposition, workspace: URL, resumeTime: CMTime?,
                 latestRequestedTime: (() -> CMTime?)? = nil) {
        generation += 1
        let revision = generation
        renderTask?.cancel()
        renderTask = nil
        observation = nil
        changed(false, nil)
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        player.replaceCurrentItem(with: item)
        if let resumeTime { player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) }
        removeRenderedFile()
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.generation == revision,
                      self.player.currentItem === item else { return }
                // A paused item can become ready without a playback-time update. Notify the
                // owning observable model so its readiness label refreshes for VoiceOver too.
                if item.status == .readyToPlay { self.changed(false, nil); return }
                guard item.status == .failed, self.renderTask == nil else { return }
                self.observation = nil
                self.changed(true, nil)
                self.renderTask = Task {
                    await self.render(asset: asset, composition: composition, workspace: workspace,
                                      resumeTime: resumeTime, latestRequestedTime: latestRequestedTime, revision: revision)
                }
            }
        }
    }

    func invalidate() {
        generation += 1
        observation = nil
        renderTask?.cancel()
        renderTask = nil
        removeRenderedFile()
        changed(false, nil)
    }

    private func render(asset: AVAsset, composition: AVVideoComposition, workspace: URL,
                        resumeTime: CMTime?, latestRequestedTime: (() -> CMTime?)?, revision: Int) async {
        let output = workspace.appendingPathComponent("protected-preview-\(UUID()).mp4")
        var keepOutput = false
        defer {
            if !keepOutput { try? FileManager.default.removeItem(at: output) }
            if generation == revision { renderTask = nil }
        }
        do {
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                throw VideoProcessingError.unableToCreateExporter
            }
            session.outputURL = output
            session.outputFileType = .mp4
            session.metadata = []
            session.videoComposition = composition
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    session.exportAsynchronously {
                        switch session.status {
                        case .completed: continuation.resume()
                        case .cancelled: continuation.resume(throwing: CancellationError())
                        default: continuation.resume(throwing: session.error ?? VideoProcessingError.unableToCreateExporter)
                        }
                    }
                }
            } onCancel: { session.cancelExport() }
            try Task.checkCancellation()
            guard generation == revision else { return }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
            let item = AVPlayerItem(url: output)
            player.replaceCurrentItem(with: item)
            observation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.generation == revision, self.player.currentItem === item else { return }
                    if item.status == .readyToPlay, self.renderTask == nil { self.changed(false, nil) }
                    if item.status == .failed { self.changed(false, item.error?.localizedDescription ?? "Preview unavailable") }
                }
            }
            if let target = latestRequestedTime?() ?? resumeTime {
                await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            try Task.checkCancellation()
            guard generation == revision else { return }
            renderedURL = output
            keepOutput = true
            if item.status == .readyToPlay { changed(false, nil) }
        } catch is CancellationError {
            if generation == revision { changed(false, nil) }
        } catch {
            if generation == revision { changed(false, error.localizedDescription) }
        }
    }

    private func removeRenderedFile() {
        if let renderedURL { try? FileManager.default.removeItem(at: renderedURL) }
        renderedURL = nil
    }
}
