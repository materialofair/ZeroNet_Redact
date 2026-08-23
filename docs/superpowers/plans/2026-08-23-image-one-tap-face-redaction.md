# Image One-Tap Face Redaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fully offline one-tap face detection to the image editor, with all faces selected by default, tap-to-exclude review, shared video stickers, and identical premium gating.

**Architecture:** Extract the video sticker catalog and opaque artwork generator into shared face-redaction units while retaining video compatibility aliases. Add a static-image Vision analyzer that emits UIKit image-space rectangles, carry stickers through `RedactionEffect`, and keep transient review selection in `EditorViewModel`; `SimpleBrushEditor` only renders and routes interaction.

**Tech Stack:** Swift 5, SwiftUI, UIKit, CoreGraphics/CoreImage, Vision, StoreKit 2 integration already present, XCTest, Xcode 26.6.

---

## File map

- Create `zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceRedactionSticker.swift`: shared sticker catalog and premium-safe selection state.
- Create `zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceStickerRenderer.swift`: shared opaque sticker artwork for image and video renderers.
- Create `zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceGeometry.swift`: privacy expansion, UIKit/Vision conversion, IoU.
- Create `zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition/ImageFaceAnalyzer.swift`: one-image Vision request and stable face ordering.
- Create `zeroNetRedact/zeroNetRedact/Views/BrushEditor/ImageFaceReviewBar.swift`: sticker picker and selection actions.
- Modify `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoModels.swift`: replace duplicated catalog with compatibility aliases.
- Modify `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoRedactionRenderer.swift`: consume shared opaque artwork.
- Modify `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/FaceTrackSmoother.swift`: remove geometry helpers moved to shared scope.
- Modify `zeroNetRedact/zeroNetRedact/Models/Enums/RedactionEffect.swift`: add `.faceSticker`.
- Modify `zeroNetRedact/zeroNetRedact/Models/Protocols/RedactionEditor.swift`: preserve sticker effect in edit operations.
- Modify `zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/ImageRedactionEditor.swift`: expose base image/effects and draw shared stickers.
- Modify `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift`: face-review state, detection, duplicate filtering, premium intent, batch apply.
- Modify `zeroNetRedact/zeroNetRedact/Views/BrushEditor/BrushEditorComponents.swift`: add one-tap face tool button.
- Modify `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift`: review overlay, gesture suppression, review bar, premium dismissal routing.
- Modify `zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`: localized UI/error/accessibility copy.
- Test `zeroNetRedact/zeroNetRedactTests/FaceStickerPolicyTests.swift`, `ImageFaceAnalyzerTests.swift`, `ImageFaceReviewStateTests.swift`, and existing video/image suites.

### Task 1: Shared sticker catalog without video regression

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceRedactionSticker.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoModels.swift`
- Create: `zeroNetRedact/zeroNetRedactTests/FaceStickerPolicyTests.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/VideoStickerPolicyTests.swift`

- [ ] **Step 1: Write failing shared-policy tests**

Add tests asserting `FaceRedactionSticker.allCases.count == 9`, free cases equal `[.orangeSmiley, .blueSmiley]`, and `FaceStickerSelectionState` retains its selected free sticker when a premium request is locked.

```swift
func testSharedCatalogKeepsVideoPricing() {
    XCTAssertEqual(FaceRedactionSticker.allCases.count, 9)
    XCTAssertEqual(
        FaceRedactionSticker.allCases.filter { !$0.requiresPremium },
        [.orangeSmiley, .blueSmiley]
    )
}

func testLockedSharedSelectionIsPendingOnly() {
    var state = FaceStickerSelectionState()
    XCTAssertTrue(state.request(.blueSmiley, hasUnlimitedAccess: false))
    XCTAssertFalse(state.request(.panda, hasUnlimitedAccess: false))
    XCTAssertEqual(state.selected, .blueSmiley)
    XCTAssertEqual(state.pendingPremiumSticker, .panda)
}
```

- [ ] **Step 2: Verify the new tests fail**

Run:

```bash
cd zeroNetRedact
xcodebuild test -project zeroNetRedact.xcodeproj -scheme zeroNetRedact \
  -destination 'platform=iOS Simulator,id=72367FCE-DFD3-4F3C-AE6D-2A64BD24976F' \
  -only-testing:zeroNetRedactTests/FaceStickerPolicyTests
```

Expected: compile failure because `FaceRedactionSticker` and `FaceStickerSelectionState` do not exist.

- [ ] **Step 3: Move the catalog and selection state into shared scope**

Define the existing nine cases and all existing computed properties under `FaceRedactionSticker`; define `FaceStickerSelectionState` with the current request/resolve/cancel behavior. In `VideoModels.swift`, remove the old declarations and retain source compatibility:

```swift
typealias VideoRedactionSticker = FaceRedactionSticker
typealias VideoStickerSelectionState = FaceStickerSelectionState
```

Do not change localization keys or the 2-free/7-premium policy.

- [ ] **Step 4: Run shared and existing video policy tests**

Run the command from Step 2 with both `-only-testing` filters. Expected: all `FaceStickerPolicyTests` and `VideoStickerPolicyTests` pass.

- [ ] **Step 5: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceRedactionSticker.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoModels.swift \
  zeroNetRedact/zeroNetRedactTests/FaceStickerPolicyTests.swift
git commit -m "refactor: share face sticker policy"
```

### Task 2: Shared opaque sticker renderer

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceStickerRenderer.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoRedactionRenderer.swift`
- Test: `zeroNetRedact/zeroNetRedactTests/VideoRedactionRendererTests.swift`
- Modify: `zeroNetRedact/zeroNetRedactTests/FaceStickerPolicyTests.swift`

- [ ] **Step 1: Write failing artwork opacity tests**

For every sticker, render a 64×64 image and assert the four corners and center have alpha 255. Also assert premium artwork assets load.

```swift
func testEverySharedStickerIsOpaqueAtPrivacySamplePoints() throws {
    let context = CIContext(options: [.useSoftwareRenderer: true])
    for sticker in FaceRedactionSticker.allCases {
        let image = FaceStickerRenderer.image(for: sticker, size: CGSize(width: 64, height: 64))
        let ci = try XCTUnwrap(CIImage(image: image))
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        context.render(
            ci,
            toBitmap: &bytes,
            rowBytes: 64 * 4,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 63, y: 0),
                      CGPoint(x: 0, y: 63), CGPoint(x: 63, y: 63),
                      CGPoint(x: 32, y: 32)] {
            let offset = (Int(point.y) * 64 + Int(point.x)) * 4
            XCTAssertEqual(bytes[offset + 3], 255, "\(sticker) leaked alpha")
        }
    }
}
```

- [ ] **Step 2: Verify failure**

Run the Task 1 command for `FaceStickerPolicyTests`. Expected: compile failure because `FaceStickerRenderer` is undefined.

- [ ] **Step 3: Implement the shared renderer and migrate video composition**

`FaceStickerRenderer.image(for:size:)` must create an opaque `UIGraphicsImageRenderer`, fill `backgroundColor(for:)`, draw the two generated smileys or aspect-fit the bundled asset, and leave the filled background intact when an asset is missing. Add `ciImage(for:)` as a convenience. Replace `VideoRedactionRenderer.makeStickerImage`, `backgroundColor`, `aspectFitRect`, and `drawSmiley` with calls to the shared renderer; preserve its immutable pre-generated cache.

- [ ] **Step 4: Run renderer suites**

Run:

```bash
cd zeroNetRedact
xcodebuild test -project zeroNetRedact.xcodeproj -scheme zeroNetRedact \
  -destination 'platform=iOS Simulator,id=72367FCE-DFD3-4F3C-AE6D-2A64BD24976F' \
  -only-testing:zeroNetRedactTests/FaceStickerPolicyTests \
  -only-testing:zeroNetRedactTests/VideoRedactionRendererTests
```

Expected: all tests pass and no pixel privacy assertions regress.

- [ ] **Step 5: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceStickerRenderer.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Video/VideoRedactionRenderer.swift \
  zeroNetRedact/zeroNetRedactTests/FaceStickerPolicyTests.swift
git commit -m "refactor: share opaque face sticker rendering"
```

### Task 3: Static-image face geometry and Vision analyzer

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceGeometry.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Video/FaceTrackSmoother.swift`
- Create: `zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition/ImageFaceAnalyzer.swift`
- Create: `zeroNetRedact/zeroNetRedactTests/ImageFaceAnalyzerTests.swift`

- [ ] **Step 1: Write failing deterministic geometry tests**

Cover Vision-to-UIKit conversion, 1.3 expansion/clamping, IoU, and stable top-to-bottom ordering:

```swift
func testVisionRectConvertsToUIKitImageSpace() {
    let result = ImageFaceAnalyzer.imageRect(
        fromVisionRect: CGRect(x: 0.10, y: 0.70, width: 0.20, height: 0.10),
        imageSize: CGSize(width: 1000, height: 500),
        expansionScale: 1
    )
    XCTAssertEqual(result, CGRect(x: 100, y: 100, width: 200, height: 50))
}

func testIntersectionOverUnion() {
    XCTAssertEqual(
        CGRect(x: 0, y: 0, width: 10, height: 10)
            .intersectionOverUnion(with: CGRect(x: 0, y: 0, width: 10, height: 10)),
        1,
        accuracy: 0.0001
    )
}
```

- [ ] **Step 2: Verify failure**

Run the standard test command with `-only-testing:zeroNetRedactTests/ImageFaceAnalyzerTests`. Expected: new types/helpers are undefined.

- [ ] **Step 3: Implement shared geometry and one-shot analyzer**

Move `clampedToUnitSquare` and `expandedForPrivacy(scale:)` unchanged into `FaceGeometry.swift`; add `intersectionOverUnion(with:)`. Implement:

```swift
struct ImageFaceAnalyzer: Sendable {
    static let analysisMaximumDimension: CGFloat = 2048

    func analyze(image: UIImage) async throws -> [CGRect]
    static func imageRect(
        fromVisionRect rect: CGRect,
        imageSize: CGSize,
        expansionScale: CGFloat = 1.3
    ) -> CGRect
}
```

The detached analysis task downsizes only the Vision input, runs `VNDetectFaceRectanglesRequest`, checks cancellation before and after the request, converts results using the original image size, drops non-finite/subpixel rectangles, and sorts by `minY` then `minX` with a small row tolerance.

- [ ] **Step 4: Run analyzer and video smoother tests**

Expected: `ImageFaceAnalyzerTests` and `FaceTrackSmootherTests` pass.

- [ ] **Step 5: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/BusinessLogic/Redaction/FaceGeometry.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Recognition/ImageFaceAnalyzer.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Video/FaceTrackSmoother.swift \
  zeroNetRedact/zeroNetRedactTests/ImageFaceAnalyzerTests.swift
git commit -m "feat: detect faces in static images"
```

### Task 4: Carry stickers through image edit history and rendering

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/Models/Enums/RedactionEffect.swift`
- Modify: `zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/ImageRedactionEditor.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift`
- Modify: `zeroNetRedact/zeroNetRedactTests/ImageRedactionEditorRenderTests.swift`

- [ ] **Step 1: Write failing image sticker history tests**

Add tests that `.faceSticker(.orangeSmiley)` changes pixels, two face rects batch as one undo step, and `getRedactionRegions()` returns the sticker effect.

```swift
func testFaceStickersBatchAsOneUndoStep() async throws {
    let editor = makeEditor(image: makeTestImage())
    let original = editor.currentImage?.pngData()
    editor.applyRedactions(
        at: [CGRect(x: 10, y: 10, width: 40, height: 40),
             CGRect(x: 120, y: 120, width: 50, height: 50)],
        effect: .faceSticker(.orangeSmiley)
    )
    await editor.waitForPendingRender()
    XCTAssertNotEqual(editor.currentImage?.pngData(), original)
    editor.undo()
    await editor.waitForPendingRender()
    XCTAssertEqual(editor.currentImage?.pngData(), original)
}
```

- [ ] **Step 2: Verify failure**

Run `ImageRedactionEditorRenderTests`. Expected: `.faceSticker` is not defined.

- [ ] **Step 3: Implement sticker effect and base-image access**

Add `.faceSticker(FaceRedactionSticker)` to equality/hash/display/icon handling. In `ImageRedactionEditor.draw`, draw the shared opaque sticker image into `operation.region`. Change `getRedactionRegions()` to return `(index, bounds, effect)`, update ViewModel tuple consumers, and expose a read-only `imageForFaceAnalysis` returning the normalized `originalImage`.

- [ ] **Step 4: Run image render tests**

Expected: all `ImageRedactionEditorRenderTests` pass, including existing mosaic/blur behavior.

- [ ] **Step 5: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/Models/Enums/RedactionEffect.swift \
  zeroNetRedact/zeroNetRedact/BusinessLogic/Editor/ImageRedactionEditor.swift \
  zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift \
  zeroNetRedact/zeroNetRedactTests/ImageRedactionEditorRenderTests.swift
git commit -m "feat: render face stickers in image history"
```

### Task 5: Face review state, duplicate filtering, and premium intent

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/Views/Editor/ImageFaceReviewState.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift`
- Create: `zeroNetRedact/zeroNetRedactTests/ImageFaceReviewStateTests.swift`

- [ ] **Step 1: Write failing review-state tests**

Test default-all selection, multiple exclusions/restores, select-none/all, locked sticker pending behavior, export-vs-sticker premium dismissal, and IoU ≥ 0.70 duplicate filtering.

```swift
func testCandidatesStartSelectedAndCanExcludeMany() {
    let candidates = [ImageFaceCandidate(rect: CGRect(x: 0, y: 0, width: 10, height: 10)),
                      ImageFaceCandidate(rect: CGRect(x: 20, y: 0, width: 10, height: 10))]
    var state = ImageFaceReviewState(candidates: candidates)
    state.toggle(candidates[0].id)
    state.toggle(candidates[1].id)
    XCTAssertTrue(state.selectedIDs.isEmpty)
    state.toggle(candidates[0].id)
    XCTAssertEqual(state.selectedIDs, [candidates[0].id])
}
```

- [ ] **Step 2: Verify failure**

Run `ImageFaceReviewStateTests`. Expected: review types are undefined.

- [ ] **Step 3: Implement pure state models**

Define `ImageFaceCandidate`, `ImageFaceReviewState`, `ImageEditorPremiumIntent`, and `ImageEditorPremiumDismissalAction`. Keep candidate IDs in memory only. Premium dismissal returns `.retryExport`, `.applySticker(sticker)`, or `.none` and consumes the intent exactly once.

- [ ] **Step 4: Integrate ViewModel**

Add published phase/candidates/selection/sticker/error state and methods:

```swift
func startFaceDetection()
func cancelFaceDetection()
func toggleFaceCandidate(_ id: UUID)
func selectAllFaceCandidates()
func deselectAllFaceCandidates()
func applySelectedFaceCandidates()
func cancelFaceReview()
func requestFaceSticker(_ sticker: FaceRedactionSticker)
func presentPremiumForExport()
func premiumViewDidDismiss() -> ImageEditorPremiumDismissalAction
```

Filter only existing `.faceSticker` operations at IoU ≥ 0.70. Applying uses one `applyRedactions` call. Refactor the existing paywall alert/sheet path so a sticker purchase never triggers export and an export purchase still retries export.

- [ ] **Step 5: Run state tests**

Expected: all review and premium-intent tests pass.

- [ ] **Step 6: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/Views/Editor/ImageFaceReviewState.swift \
  zeroNetRedact/zeroNetRedact/Views/Editor/EditorViewModel.swift \
  zeroNetRedact/zeroNetRedactTests/ImageFaceReviewStateTests.swift
git commit -m "feat: manage image face review state"
```

### Task 6: One-tap tool, tappable face overlays, and review controls

**Files:**
- Create: `zeroNetRedact/zeroNetRedact/Views/BrushEditor/ImageFaceReviewBar.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/BrushEditor/BrushEditorComponents.swift`
- Modify: `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift`

- [ ] **Step 1: Add the image-only face tool to `EffectSelectorView`**

Extend the component with `showsFaceDetection`, `onDetectFaces`, `isDetectingFaces`, and `isFaceDetectDisabled`. Render a 44pt `FaceDetectButton` after text AI detection only when `showsFaceDetection` is true. Pass `viewModel.isImageFile` from `SimpleBrushEditor`, so PDF is unchanged.

- [ ] **Step 2: Add the review bar**

`ImageFaceReviewBar` receives the catalog, selected sticker/IDs/count, access state, and closures. It shows X/Y, all/none/cancel/apply actions, horizontal sticker cards with lock badges, and disables Apply at zero selected.

- [ ] **Step 3: Add tappable overlays and suppress editor gestures**

Inside the image-sized ZStack, overlay one 44pt-minimum button per candidate. Convert the candidate image rect with `CoordinateConverter.imageRectToScreen`; selected candidates show `FaceStickerRenderer.image`, a blue outline, and a checkmark; excluded candidates show a dashed outline and `xmark`. Add accessibility labels “Face N, selected/excluded, double-tap to toggle.” Disable brush/drag/zoom gesture routing while the review phase is active.

- [ ] **Step 4: Route paywall dismissal and lifecycle cancellation**

Replace direct `showPremiumView = true` for export with `presentPremiumForExport()`. On sheet dismissal, call `premiumViewDidDismiss()` and only call `performExport()` for `.retryExport`. Cancel face analysis/review on view disappearance and before rotation.

- [ ] **Step 5: Build**

Run:

```bash
cd zeroNetRedact
xcodebuild build -project zeroNetRedact.xcodeproj -scheme zeroNetRedact \
  -destination 'platform=iOS Simulator,id=72367FCE-DFD3-4F3C-AE6D-2A64BD24976F'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/Views/BrushEditor/ImageFaceReviewBar.swift \
  zeroNetRedact/zeroNetRedact/Views/BrushEditor/BrushEditorComponents.swift \
  zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift
git commit -m "feat: add one-tap face review UI"
```

### Task 7: Localization, privacy guidance, and recovery states

**Files:**
- Modify: `zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings`
- Modify: `zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings`
- Modify: `zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift`

- [ ] **Step 1: Add matching English and Simplified Chinese keys**

Add explicit keys for the one-tap button, local-analysis progress, no faces, failure, selected X/Y, select all/none, apply count, cancel, selected/excluded candidate accessibility, automatic-detection review warning, and premium hint. Ensure both localization files contain the identical key set.

- [ ] **Step 2: Show recoverable status**

Display no-face and failure messages through the existing toast path; failure includes retry via the face button. The review bar includes the “automatic detection may miss faces; review the whole image before export” notice. Cancellation leaves edit history unchanged.

- [ ] **Step 3: Validate localization parity**

Run:

```bash
comm -3 \
  <(rg -o '^"[^"]+"' zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings | sort) \
  <(rg -o '^"[^"]+"' zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings | sort)
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add zeroNetRedact/zeroNetRedact/en.lproj/Localizable.strings \
  zeroNetRedact/zeroNetRedact/zh-Hans.lproj/Localizable.strings \
  zeroNetRedact/zeroNetRedact/Views/SimpleBrushEditor.swift
git commit -m "feat: localize image face redaction"
```

### Task 8: Full regression verification

**Files:**
- Test only; fix only files implicated by failures.

- [ ] **Step 1: Run focused tests**

Run all new suites plus `VideoStickerPolicyTests`, `VideoRedactionRendererTests`, `ImageRedactionEditorRenderTests`, `DetectionCoordinateTests`, and `RedactionRenderScaleTests`. Expected: all pass.

- [ ] **Step 2: Run the full unit test target**

```bash
cd zeroNetRedact
xcodebuild test -project zeroNetRedact.xcodeproj -scheme zeroNetRedact \
  -destination 'platform=iOS Simulator,id=72367FCE-DFD3-4F3C-AE6D-2A64BD24976F' \
  -only-testing:zeroNetRedactTests
```

Expected: `** TEST SUCCEEDED **` with zero failures.

- [ ] **Step 3: Review diff and repository cleanliness**

```bash
git diff --check
git status --short
git diff --stat HEAD~7..HEAD
```

Expected: no whitespace errors; only scoped feature/test/localization files plus pre-existing user-owned Xcode state changes are present.

- [ ] **Step 4: Manual simulator acceptance**

Verify one image with multiple faces: all selected initially; exclude at least two; restore one; switch between both free stickers; confirm a premium sticker opens the existing paywall without applying/exporting; apply; delete one applied face; undo/redo the batch; export and inspect the resulting PNG. Repeat no-face and rotated-image cases.

- [ ] **Step 5: Final fix commit if verification required changes**

```bash
git add -p
git commit -m "fix: harden image face redaction"
```

Skip this commit when verification required no changes.
