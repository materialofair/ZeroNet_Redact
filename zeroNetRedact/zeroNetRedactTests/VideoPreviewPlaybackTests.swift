import AVFoundation
import CoreData
import CoreImage
import UIKit
import XCTest
@testable import zeroNetRedact

@MainActor
final class VideoPreviewPlaybackTests: XCTestCase {
    func testProtectedPreviewPublishesReadinessForPausedPlayer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewReadiness-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp4")
        try await VideoTestFixture.makeVideo(at: source)
        let asset = AVURLAsset(url: source)
        let player = AVPlayer()
        var publishedReady = false
        let preview = ProtectedVideoPreview(player: player) { preparing, error in
            if !preparing, error == nil, player.currentItem?.status == .readyToPlay { publishedReady = true }
        }
        defer { player.replaceCurrentItem(with: nil); preview.invalidate() }
        preview.install(asset: asset, composition: VideoCompositionFactory.make(asset: asset, timeline: .empty, sticker: .orangeSmiley), workspace: directory, resumeTime: nil)
        let deadline = Date().addingTimeInterval(15)
        while player.currentItem?.status != .readyToPlay && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(player.currentItem?.status, .readyToPlay)
        while !publishedReady && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(publishedReady, "Paused preview readiness must refresh the SwiftUI accessibility value without a seek or play action")
    }

    func testKnownReservationDraftRemainsPlayableAfterSavingRegion() async throws {
        // Only this exact locally generated synthetic fixture is eligible; never inspect user videos.
        let request = NSFetchRequest<OriginalVideo>(entityName: "OriginalVideo")
        request.predicate = NSPredicate(format: "contentHash == %@", "85dc1daafdc23110e828c94dfc435c604c54f2ba6ec2b78609428841c234961b")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        guard let video = try PersistenceController.shared.container.viewContext.fetch(request).first else {
            throw XCTSkip("Known synthetic reservation fixture is not imported on this device")
        }
        let model = VideoEditorViewModel(video: video)
        var addedRegionID: UUID?
        defer {
            if let addedRegionID { model.removeRegion(addedRegionID) }
            model.flushDraft()
            model.cleanup()
        }
        model.start()
        if model.showDraftRestore { model.restoreDraft() }
        let deadline = Date().addingTimeInterval(15)
        while (model.phase == .preparing || model.phase == .analyzing) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.phase, .ready, String(describing: model.errorMessage))
        try await assertPlayable(model.player, context: "restored synthetic draft")
        let previous = (model.player.currentItem?.asset as? AVURLAsset)?.url
        XCTAssertTrue(model.saveRegion(rect: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4), start: 0.5, end: 2))
        addedRegionID = model.manualRegions.last?.id
        model.seekReview(0.5)
        XCTAssertEqual(model.manualEditorEntrySeconds, 0.5, accuracy: 0.15)
        try await assertPlayable(model.player, context: "after saving region", expectedResume: 0.5)
        if let previous, previous.lastPathComponent.hasPrefix("protected-preview-") {
            XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path), "Superseded preview must be removed")
        }
    }

    func testSyntheticSourceAndRedactedPreviewBecomePlayable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewPlayback-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp4")
        try await VideoTestFixture.makeVideo(at: source, frameCount: 90, frameRate: 30)
        for redacted in [false, true] {
            let asset = AVURLAsset(url: source)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer()
            let protected = ProtectedVideoPreview(player: player)
            if redacted {
                var region = try XCTUnwrap(VideoManualRegion(rect: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4), start: 0.5, end: 2, duration: 3))
                region.effect = VideoRedactionSticker.orangeSmiley.rawValue
                protected.install(asset: asset, composition: VideoCompositionFactory.make(asset: asset, timeline: .empty, sticker: .orangeSmiley, manualRegions: [region]), workspace: directory, resumeTime: nil)
            } else {
                player.replaceCurrentItem(with: item)
            }
            defer { player.pause(); player.replaceCurrentItem(with: nil); protected.invalidate() }
            try await assertPlayable(player, context: "generated source redacted=\(redacted)")
            if redacted {
                let preview = AVAssetImageGenerator(asset: try XCTUnwrap(player.currentItem?.asset))
                preview.videoComposition = player.currentItem?.videoComposition
                let original = AVAssetImageGenerator(asset: asset)
                for seconds in [0.2, 1.0, 2.2] {
                    let actual = try pixel(preview, at: seconds)
                    let sourcePixel = try pixel(original, at: seconds)
                    let difference = (0..<3).reduce(0) { $0 + abs(Int(actual[$1]) - Int(sourcePixel[$1])) }
                    if seconds == 1 { XCTAssertGreaterThan(difference, 50, "Protected preview must contain the mask") }
                    else { XCTAssertLessThan(difference, 45, "Preview must respect the half-open interval") }
                }
                let cached = (player.currentItem?.asset as? AVURLAsset)?.url
                player.replaceCurrentItem(with: nil)
                protected.invalidate()
                if let cached, cached.lastPathComponent.hasPrefix("protected-preview-") {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: cached.path))
                }
            }
        }
    }

    private func pixel(_ generator: AVAssetImageGenerator, at seconds: Double) throws -> [UInt8] {
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext().render(CIImage(cgImage: image), toBitmap: &rgba, rowBytes: 4,
                           bounds: CGRect(x: 128, y: 96, width: 1, height: 1), format: .RGBA8,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return rgba
    }

    private func assertPlayable(_ player: AVPlayer, context: String, expectedResume: Double? = nil) async throws {
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let layer = AVPlayerLayer(player: player)
        layer.frame = host.bounds
        host.layer.addSublayer(layer)
        window.addSubview(host)
        defer { layer.player = nil; host.removeFromSuperview() }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if player.currentItem?.status == .readyToPlay {
                player.play()
                if layer.isReadyForDisplay { break }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let item = try XCTUnwrap(player.currentItem)
        XCTAssertEqual(item.status, .readyToPlay, "\(context); error=\(String(describing: item.error)); log=\(String(describing: item.errorLog()?.events))")
        guard item.status == .readyToPlay else { return }
        if let expectedResume { XCTAssertEqual(player.currentTime().seconds, expectedResume, accuracy: 0.15, context) }
        let sought = await player.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(sought, context)
        player.play()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertGreaterThan(player.currentTime().seconds, 1.1, "\(context); error=\(String(describing: item.error))")
        XCTAssertTrue(layer.isReadyForDisplay, "\(context); no displayed frame; status=\(item.status.rawValue); error=\(String(describing: item.error))")
        player.pause()
    }
}
