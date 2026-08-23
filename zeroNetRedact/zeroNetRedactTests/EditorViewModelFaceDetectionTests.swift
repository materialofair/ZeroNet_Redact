import CoreData
import UIKit
import XCTest

@testable import zeroNetRedact

@MainActor
final class EditorViewModelFaceDetectionTests: XCTestCase {
    private final class ControlledFaceAnalyzer: ImageFaceAnalyzing {
        private(set) var continuations: [CheckedContinuation<[CGRect], Error>] = []

        func analyze(image: UIImage) async throws -> [CGRect] {
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func completeRequest(_ index: Int, with rects: [CGRect]) {
            continuations[index].resume(returning: rects)
        }
    }

    private lazy var scratchContext: NSManagedObjectContext = {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator =
            PersistenceController.shared.container.persistentStoreCoordinator
        return context
    }()

    private func makeSubject(
        analyzer: ControlledFaceAnalyzer
    ) -> (EditorViewModel, ImageRedactionEditor) {
        let file = OriginalImage(context: scratchContext)
        file.fileType = .image
        let imageEditor = ImageRedactionEditor(file: file)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 200, height: 200),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        imageEditor.loadForTesting(image: image)
        let viewModel = EditorViewModel(
            file: file,
            editor: AnyRedactionEditor(imageEditor),
            faceAnalyzer: analyzer
        )
        return (viewModel, imageEditor)
    }

    private func waitUntil(
        _ message: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail(message)
    }

    func testLateCancelledDetectionCannotOverwriteNewDetection() async {
        let analyzer = ControlledFaceAnalyzer()
        let (viewModel, _) = makeSubject(analyzer: analyzer)
        let oldRect = CGRect(x: 10, y: 10, width: 30, height: 30)
        let newRect = CGRect(x: 90, y: 90, width: 40, height: 40)

        viewModel.startFaceDetection()
        await waitUntil("first request should start") { analyzer.continuations.count == 1 }
        viewModel.startFaceDetection()
        await waitUntil("second request should start") { analyzer.continuations.count == 2 }

        analyzer.completeRequest(0, with: [oldRect])
        await Task.yield()
        XCTAssertTrue(viewModel.isDetectingFaces)

        analyzer.completeRequest(1, with: [newRect])
        await waitUntil("latest request should enter review") { viewModel.isReviewingFaces }
        XCTAssertEqual(viewModel.faceCandidates.map(\.rect), [newRect])
    }

    func testDetectionFiltersAgainstLatestStickerHistory() async {
        let analyzer = ControlledFaceAnalyzer()
        let (viewModel, imageEditor) = makeSubject(analyzer: analyzer)
        let faceRect = CGRect(x: 40, y: 40, width: 50, height: 50)
        imageEditor.applyRedaction(at: faceRect, effect: .faceSticker(.orangeSmiley))

        viewModel.startFaceDetection()
        await waitUntil("request should start") { analyzer.continuations.count == 1 }
        imageEditor.undo()
        analyzer.completeRequest(0, with: [faceRect])

        await waitUntil("newly uncovered face should be reviewable") {
            viewModel.isReviewingFaces
        }
        XCTAssertEqual(viewModel.faceCandidates.map(\.rect), [faceRect])
    }

    func testSelectedSubsetIsAppliedAsOneUndoStep() async {
        let analyzer = ControlledFaceAnalyzer()
        let (viewModel, imageEditor) = makeSubject(analyzer: analyzer)
        let rects = [
            CGRect(x: 10, y: 10, width: 30, height: 30),
            CGRect(x: 70, y: 20, width: 30, height: 30),
            CGRect(x: 120, y: 80, width: 40, height: 40),
        ]

        viewModel.startFaceDetection()
        await waitUntil("request should start") { analyzer.continuations.count == 1 }
        analyzer.completeRequest(0, with: rects)
        await waitUntil("faces should be ready for review") { viewModel.isReviewingFaces }
        XCTAssertEqual(viewModel.selectedFaceCount, 3)

        viewModel.toggleFaceCandidate(viewModel.faceCandidates[0].id)
        viewModel.toggleFaceCandidate(viewModel.faceCandidates[2].id)
        viewModel.applySelectedFaceCandidates()

        XCTAssertEqual(imageEditor.getFaceStickerRegions(), [rects[1]])
        XCTAssertTrue(imageEditor.canUndo)
        imageEditor.undo()
        XCTAssertTrue(imageEditor.getFaceStickerRegions().isEmpty)
    }
}
