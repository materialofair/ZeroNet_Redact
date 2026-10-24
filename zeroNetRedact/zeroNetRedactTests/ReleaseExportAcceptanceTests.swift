import AVFoundation
import CoreData
import PDFKit
import UIKit
import XCTest
@testable import zeroNetRedact

/// Keeps small, synthetic production-export artifacts for independent inspection.
/// Does not change purchase state, usage counters, existing records or the app's key.
@MainActor
final class ReleaseExportAcceptanceTests: XCTestCase {
    private func evidenceDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReleaseExportAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("RELEASE_EXPORT_EVIDENCE \(directory.path)")
        return directory
    }

    private func keep(_ data: Data, at url: URL) throws {
        try data.write(to: url, options: .atomic)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPhotoExportPreservesPixelDimensionsAndOpaqueMask() async throws {
        let directory = try evidenceDirectory()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            "SYNTHETIC SECRET".draw(at: CGPoint(x: 80, y: 90), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let editor = ImageRedactionEditor(file: OriginalImage(context: context))
        editor.loadForTesting(image: source)
        editor.applyRedaction(at: CGRect(x: 60, y: 70, width: 280, height: 80), effect: .solidBlack)
        let data = try await editor.exportRedactedFile()
        try keep(data, at: directory.appendingPathComponent("photo-redacted.png"))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 800)
        XCTAssertEqual(image.height, 600)
        // Core Image's pixel origin is bottom-left; UIKit brush coordinates are top-left.
        let covered = pixel(image, x: 400, y: image.height - 220 - 1)
        XCTAssertLessThan(covered[0], 5)
        XCTAssertLessThan(covered[1], 5)
        XCTAssertLessThan(covered[2], 5)
        XCTAssertEqual(covered[3], 255)
        XCTAssertGreaterThan(pixel(image, x: 20, y: 20)[0], 250)
    }

    func testPDFEditorExportPhysicallyRemovesTextAndPreservesPages() async throws {
        let directory = try evidenceDirectory()
        let source = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            for page in 0..<2 {
                ctx.beginPage()
                let text = page == 0 ? "SYNTHETIC-SECRET" : "PAGE-TWO-PUBLIC"
                text.draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
                "PUBLIC-KEEP".draw(at: CGPoint(x: 60, y: 160), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
        let sourceDocument = try XCTUnwrap(PDFDocument(data: source))
        let sourcePage = try XCTUnwrap(sourceDocument.page(at: 0))
        let selection = try XCTUnwrap(sourceDocument.findString("SYNTHETIC-SECRET", withOptions: []).first)
        let id = UUID()
        _ = try StorageManager.shared.saveEncryptedOriginal(data: CryptoEngine.shared.encrypt(data: source), id: id, type: .pdf)
        defer { try? StorageManager.shared.deleteOriginal(id: id, type: .pdf) }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let file = OriginalPDF.create(in: context, id: id, encryptedDataPath: "", encryptedThumbnailPath: "", fileSize: Int64(source.count), pageCount: 2, title: "Synthetic acceptance", author: "", creator: "", isEncrypted: false)
        let editor = PDFRedactionEditor(file: file)
        try await editor.loadFile(file)
        editor.applyRedaction(at: selection.bounds(for: sourcePage).insetBy(dx: -5, dy: -5), effect: .solidBlack)
        let data = try await editor.exportRedactedFile(progress: nil)
        try keep(data, at: directory.appendingPathComponent("document-redacted.pdf"))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertFalse((document.string ?? "").contains("SYNTHETIC-SECRET"))
        XCTAssertTrue((document.string ?? "").contains("PUBLIC-KEEP"))
        XCTAssertTrue((document.string ?? "").contains("PAGE-TWO-PUBLIC"))
        let thumbnail = try XCTUnwrap(document.page(at: 0)).thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        try keep(try XCTUnwrap(thumbnail.pngData()), at: directory.appendingPathComponent("document-page-one.png"))
        let rendered = try XCTUnwrap(thumbnail.cgImage)
        let covered = pixel(rendered, x: 140, y: 720)
        XCTAssertLessThan(covered[0], 5)
        XCTAssertLessThan(covered[1], 5)
        XCTAssertLessThan(covered[2], 5)
        for index in 0..<2 {
            let page = try XCTUnwrap(document.page(at: index))
            XCTAssertEqual(page.bounds(for: .mediaBox), CGRect(x: 0, y: 0, width: 612, height: 792))
            // The editor deliberately adds a color-only Square overlay after physical deletion.
            // Removing that overlay must never recover the underlying secret.
            for annotation in page.annotations { page.removeAnnotation(annotation) }
        }
        XCTAssertFalse((document.string ?? "").contains("SYNTHETIC-SECRET"))
    }

    func testVideoExportDecodesEveryFrameAndHonorsTimeRange() async throws {
        let directory = try evidenceDirectory()
        let source = directory.appendingPathComponent("video-source.mp4")
        let output = directory.appendingPathComponent("video-redacted.mp4")
        try await VideoTestFixture.makeVideo(at: source, frameCount: 60, frameRate: 30)
        var region = try XCTUnwrap(VideoManualRegion(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), start: 0.5, end: 1.5, duration: 2))
        region.effect = VideoRedactionSticker.orangeSmiley.rawValue
        try await VideoExporter().export(sourceURL: source, destinationURL: output, timeline: .empty, sticker: .blueSmiley, audio: .mute, manualRegions: [region])
        try keep(Data(contentsOf: output), at: output)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let dimensions = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(dimensions, CGSize(width: 320, height: 240))
        XCTAssertEqual(Double(rate), 30, accuracy: 0.1)
        XCTAssertEqual(duration, 2, accuracy: 0.04)
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(readerOutput)
        XCTAssertTrue(reader.startReading())
        var frames = 0
        var maskedFrames = 0
        while let sample = readerOutput.copyNextSampleBuffer() {
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let offset = 120 * CVPixelBufferGetBytesPerRow(buffer) + 160 * 4
            let blue = Int(base[offset])
            let red = Int(base[offset + 2])
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            if seconds >= 0.5 && seconds < 1.5 {
                XCTAssertGreaterThan(red, blue + 60, "Missing mask at encoded timestamp \(seconds)")
                maskedFrames += 1
            } else {
                XCTAssertEqual(red, blue, accuracy: 10, "Mask outside its interval at \(seconds)")
            }
            frames += 1
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(frames, 60, "Every encoded frame must be decodable")
        XCTAssertEqual(maskedFrames, 30)
        for seconds in [0.4, 0.5, 1.0, 1.5] {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
            let center = pixel(image, x: 160, y: 120)
            if seconds >= 0.5 && seconds < 1.5 {
                XCTAssertGreaterThan(Int(center[0]), Int(center[2]) + 60)
            } else {
                XCTAssertEqual(Int(center[0]), Int(center[2]), accuracy: 10)
            }
            try keep(try XCTUnwrap(UIImage(cgImage: image).pngData()), at: directory.appendingPathComponent("video-frame-\(seconds).png"))
        }
        let report: [String: Any] = ["width": dimensions.width, "height": dimensions.height, "frames": frames, "maskPixelCheckedFrames": frames, "maskedFrames": maskedFrames, "fps": rate, "duration": duration, "redactionStart": 0.5, "redactionEndExclusive": 1.5]
        try keep(JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), at: directory.appendingPathComponent("video-report.json"))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        CIContext().render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return bytes
    }
}

/// Explicit, separately selected preparation for the ordinary-device UI export check.
/// Imports only this synthetic PDF through the normal import service; leaves it for UI use.
@MainActor
final class ReleaseExportUIFixtureTests: XCTestCase {
    func testPrepareSyntheticImageForUI() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
            "CLOAKMARK SYNTHETIC IMAGE SECRET".draw(at: CGPoint(x: 260, y: 370), withAttributes: [.font: UIFont.systemFont(ofSize: 32)])
        }
        _ = try await ImportManager.shared.importFileWithDuplicateCheck(from: .imageData(try XCTUnwrap(image.pngData())))
    }

    func testPrepareSyntheticPDFForUI() async throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            ctx.beginPage()
            "CLOAKMARK SYNTHETIC PDF SECRET".draw(at: CGPoint(x: 80, y: 320), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            "PUBLIC EXPORT ACCEPTANCE".draw(at: CGPoint(x: 80, y: 500), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        let result = try await ImportManager.shared.importFileWithDuplicateCheck(from: .pdfData(data))
        switch result {
        case .success(let file): XCTAssertEqual(file.fileType, .pdf)
        case .duplicate(let file): XCTAssertEqual(file.fileType, .pdf)
        }
    }
}
