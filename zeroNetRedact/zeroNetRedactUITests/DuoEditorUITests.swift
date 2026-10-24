import XCTest

/// Reuse an idle simulator prepared with the newest synthetic Cloakmark-Duo-Fixture.png.
/// Does not erase data, change purchase state or access App Store Connect.
final class DuoEditorUITests: XCTestCase {
    @MainActor
    func testImageRedactionSurvivesRotationUndoRedoAndExport() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let later = app.buttons["Set Up Later"]
        if later.waitForExistence(timeout: 3), later.isHittable { later.tap() }
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2), skip.isHittable { skip.tap() }

        let existing = app.descendants(matching: .any).matching(identifier: "files.original.image").firstMatch
        if existing.waitForExistence(timeout: 3) {
            existing.tap()
        } else {
            let selectPhotos = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Select Photos")).firstMatch
            if !selectPhotos.waitForExistence(timeout: 3) || !selectPhotos.isHittable { app.buttons["Add Files"].tap() }
            XCTAssertTrue(selectPhotos.waitForExistence(timeout: 5), app.debugDescription)
            selectPhotos.tap()
            selectNewestMedia(in: app)
            let edit = app.buttons["Edit the Imported File"]
            XCTAssertTrue(edit.waitForExistence(timeout: 30), app.debugDescription)
            edit.tap()
        }
        let resume = app.alerts.buttons["Resume Editing"]
        if resume.waitForExistence(timeout: 2) { resume.tap() }
        let gotIt = app.buttons["Got It"]
        if gotIt.waitForExistence(timeout: 2) { gotIt.tap() }
        let image = app.images["editor.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "photo-portrait-before-stroke")
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.43))
            .press(forDuration: 0.1, thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.43)))
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.isEnabled)
        capture(app, "photo-portrait-masked")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(undo.isEnabled)
        capture(app, "photo-landscape-masked")
        XCTAssertTrue(app.buttons["editor.export"].isHittable, app.debugDescription)
        undo.tap()
        let redo = app.buttons["Redo"].firstMatch
        XCTAssertTrue(redo.isEnabled)
        redo.tap()
        XCTAssertTrue(undo.isEnabled)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        capture(app, "photo-portrait-restored")
        app.buttons["editor.export"].tap()
        let complete = app.buttons["editor.continueEditing"]
        XCTAssertTrue(complete.waitForExistence(timeout: 20), app.debugDescription)
        capture(app, "photo-export-complete")
        app.buttons["editor.shareCopy"].tap()
        verifySaveToFilesIsAvailable(in: app, name: "photo-share-save")
    }

    @MainActor
    func testVideoRegionIntervalSurvivesRotationAndExport() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let later = app.buttons["Set Up Later"]
        if later.waitForExistence(timeout: 3), later.isHittable { later.tap() }
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2), skip.isHittable { skip.tap() }
        let selectVideo = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Video")).firstMatch
        if !selectVideo.waitForExistence(timeout: 3) || !selectVideo.isHittable { app.buttons["Add Files"].tap() }
        XCTAssertTrue(selectVideo.waitForExistence(timeout: 5), app.debugDescription)
        selectVideo.tap()
        app.buttons["Photos"].firstMatch.tap()
        selectNewestMedia(in: app)
        let duplicate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Import Anyway")).firstMatch
        if duplicate.waitForExistence(timeout: 3) { duplicate.tap() }
        let video = app.descendants(matching: .any).matching(identifier: "files.original.video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 30), app.debugDescription)
        video.tap()
        let addCover = app.buttons["video.manual.add"]
        XCTAssertTrue(addCover.waitForExistence(timeout: 60), app.debugDescription)
        let preview = app.descendants(matching: .any).matching(identifier: "video.preview").firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Protected preview ready"), object: preview)], timeout: 30), .completed, app.debugDescription)
        capture(app, "video-portrait-preview")
        addCover.tap()
        XCTAssertTrue(app.buttons["video.manual.save"].waitForExistence(timeout: 10))
        app.buttons["Choose range"].tap()
        let startSlider = app.sliders["Start"]
        XCTAssertTrue(startSlider.waitForExistence(timeout: 3))
        startSlider.adjust(toNormalizedSliderPosition: 0.2)
        let startValue = startSlider.value as? String
        capture(app, "video-manual-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.buttons["video.manual.save"].isHittable)
        XCTAssertEqual(startSlider.value as? String, startValue)
        capture(app, "video-manual-landscape")
        app.buttons["video.manual.save"].tap()
        XCTAssertTrue(addCover.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Protected preview ready"), object: preview)], timeout: 30), .completed, app.debugDescription)
        capture(app, "video-landscape-region")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        let export = app.buttons["Export Redacted Video"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(app.staticTexts["Saved to Redacted Files"].waitForExistence(timeout: 90), app.debugDescription)
        capture(app, "video-export-complete")
        app.buttons["Share Copy"].tap()
        verifySaveToFilesIsAvailable(in: app, name: "video-share-save")
    }

    @MainActor
    func testPDFExportAndSystemSaveAvailability() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let pdf = app.descendants(matching: .any).matching(identifier: "files.original.pdf").firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 15), "Prepare the synthetic PDF with ReleaseExportUIFixtureTests")
        pdf.tap()
        let resume = app.alerts.buttons["Resume Editing"]
        if resume.waitForExistence(timeout: 2) { resume.tap() }
        let gotIt = app.buttons["Got It"]
        if gotIt.waitForExistence(timeout: 2) { gotIt.tap() }
        let image = app.images["editor.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 20), app.debugDescription)
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.43))
            .press(forDuration: 0.1, thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.43)))
        capture(app, "pdf-masked")
        app.buttons["editor.export"].tap()
        XCTAssertTrue(app.buttons["editor.continueEditing"].waitForExistence(timeout: 30), app.debugDescription)
        capture(app, "pdf-export-complete")
        app.buttons["editor.shareCopy"].tap()
        verifySaveToFilesIsAvailable(in: app, name: "pdf-share-save")
    }

    @MainActor
    func testSavedCopiesOpenSystemSaveWithoutAnotherExport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        for type in ["Image", "PDF", "Video"] {
            // Restart only our app between system sheets; preserve all saved files and counters.
            // Compact-phone popovers can leave an invisible dismiss region after cancelling.
            app.launch()
            app.buttons["Redacted"].firstMatch.tap()
            let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", type + ", ")).firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
            file.press(forDuration: 1)
            let share = app.buttons["Share File"].firstMatch
            XCTAssertTrue(share.waitForExistence(timeout: 5), app.debugDescription)
            share.tap()
            verifySaveToFilesIsAvailable(in: app, name: type.lowercased() + "-saved-copy-share")
        }
    }

    @MainActor
    private func verifySaveToFilesIsAvailable(in app: XCUIApplication, name: String) {
        // iOS 26 exposes activity actions as cells and uses the system's language.
        let save = app.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "Save to Files", "保存到“文件”")).firstMatch
        if !save.waitForExistence(timeout: 5) {
            let more = app.cells.matching(NSPredicate(format: "label IN %@", ["查看更多", "Show More", "View More"])).firstMatch
            if more.exists { more.tap() }
        }
        if save.exists, !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(save.isHittable, app.debugDescription)
        capture(app, name)
        save.tap()
        let saveDestination = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "存储", "保存"])).firstMatch
        XCTAssertTrue(saveDestination.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, name + "-destination")
        // Save only to the observed on-device location, never a cloud or person destination.
        let local = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", ".*(On My|我的).*i(Pad|Phone).*"))
        XCTAssertTrue(local.firstMatch.exists, app.debugDescription)
        XCTAssertTrue(saveDestination.isEnabled)
        saveDestination.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saveDestination)], timeout: 15), .completed, app.debugDescription)
        capture(app, name + "-local-save-complete")
    }

    @MainActor
    func testRestoredSyntheticVideoPreviewAndSaveBecomeReady() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let video = app.descendants(matching: .any).matching(identifier: "files.original.video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 15), "Prepare only the known synthetic video on this device")
        video.tap()
        let resume = app.alerts.buttons["Resume Editing"]
        if resume.waitForExistence(timeout: 3) { resume.tap() }
        let addCover = app.buttons["video.manual.add"]
        XCTAssertTrue(addCover.waitForExistence(timeout: 60), app.debugDescription)
        let preview = app.descendants(matching: .any).matching(identifier: "video.preview").firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Protected preview ready"), object: preview)], timeout: 40), .completed, app.debugDescription)
        capture(app, "video-fixed-main-ready")
        addCover.tap()
        XCTAssertTrue(app.buttons["video.manual.save"].waitForExistence(timeout: 10))
        app.buttons["From here"].tap()
        capture(app, "video-fixed-source-positioning")
        app.buttons["video.manual.save"].tap()
        XCTAssertTrue(addCover.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Protected preview ready"), object: preview)], timeout: 40), .completed, app.debugDescription)
        capture(app, "video-fixed-after-save-ready")
    }

    @MainActor
    func testZChineseEditorCapture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let existing = app.descendants(matching: .any).matching(identifier: "files.original.image").firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 15), app.debugDescription)
        existing.tap()
        let resume = app.alerts.buttons["继续编辑"]
        if resume.waitForExistence(timeout: 2) { resume.tap() }
        let gotIt = app.buttons["知道了"]
        if gotIt.waitForExistence(timeout: 2) { gotIt.tap() }
        XCTAssertTrue(app.images["editor.image"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        capture(app, "zh-photo-wide-canvas")
        XCTAssertTrue(app.buttons["editor.export"].isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["撤销"].firstMatch.exists)
    }

    @MainActor
    private func selectNewestMedia(in app: XCUIApplication) {
        // iOS 26 PhotosPicker exposes thumbnails as images; collection cells also include album navigation.
        let thumbnail = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "system-picker-prepared")
        if thumbnail.isHittable {
            thumbnail.tap()
        } else {
            // The phone's virtual Photos grid reports no AX hit point; use its observed visible frame.
            thumbnail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let done = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Done", "Add")).firstMatch
        if done.waitForExistence(timeout: 2), done.isHittable, done.isEnabled { done.tap() }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Leave selected states visible for independent, native simctl captures.
        if ["photo-portrait-restored", "zh-photo-wide-canvas", "video-manual-landscape", "video-portrait-preview", "video-landscape-region", "video-fixed-main-ready", "video-fixed-after-save-ready"].contains(name) {
            Thread.sleep(forTimeInterval: 5)
        }
    }
}
