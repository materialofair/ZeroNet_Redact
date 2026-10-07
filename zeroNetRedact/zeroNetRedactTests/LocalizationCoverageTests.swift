import XCTest
import CoreData
@testable import zeroNetRedact

final class LocalizationCoverageTests: XCTestCase {
    private let languages = ["en", "zh-Hans", "zh-Hant", "ja", "pl", "de", "fr", "id", "es", "pt-BR"]

    func testAllDeclaredLanguagesArePackagedWithCompleteStringsAndPermission() throws {
        let app = Bundle.main
        let english = try languageBundle("en", in: app)
        let baseline = try strings(in: english)
        XCTAssertEqual(baseline.count, 718)
        for language in languages {
            let bundle = try languageBundle(language, in: app)
            let values = try strings(in: bundle)
            XCTAssertEqual(Set(values.keys), Set(baseline.keys), language)
            XCTAssertTrue(values.values.allSatisfy { !$0.isEmpty }, language)
            for key in ["ocr.section", "ocr.language", "ocr.automatic", "ocr.documentScope", "ocr.languageScope"] {
                XCTAssertNotNil(values[key], "\(language): \(key)")
            }
            let pluralURL = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "stringsdict"), language)
            let plurals = try XCTUnwrap(NSDictionary(contentsOf: pluralURL) as? [String: Any], language)
            XCTAssertEqual(plurals.count, 7, language)
            let countEntry = try XCTUnwrap(plurals["settings.fileCount"] as? [String: Any])
            let forms = try XCTUnwrap(countEntry["count"] as? [String: Any])
            XCTAssertNotNil(forms["other"], language)
            if language == "pl" {
                for category in ["one", "few", "many", "other"] { XCTAssertNotNil(forms[category], category) }
            }
            let infoURL = try XCTUnwrap(bundle.url(forResource: "InfoPlist", withExtension: "strings"), language)
            let info = try XCTUnwrap(NSDictionary(contentsOf: infoURL) as? [String: String], language)
            XCTAssertFalse(try XCTUnwrap(info["NSFaceIDUsageDescription"], language).isEmpty)
            XCTAssertNotEqual(bundle.localizedString(forKey: "list.sort.label", value: nil, table: nil), "list.sort.label")
            XCTAssertNotEqual(bundle.localizedString(forKey: "share.error.unsupported", value: nil, table: nil), "share.error.unsupported")
            XCTAssertNotEqual(bundle.localizedString(forKey: "search.languageScope", value: nil, table: nil), "search.languageScope")
            for count in [0, 1, 2, 5, 21] {
                for key in ["settings.fileCount", "group.fileCount", "search.count", "pdf.preview"] {
                    let rendered = String(format: bundle.localizedString(forKey: key, value: nil, table: nil), locale: Locale(identifier: language), count)
                    XCTAssertTrue(rendered.contains(String(count)), "\(language) \(key): \(rendered)")
                    XCTAssertFalse(rendered.contains("%d"), rendered)
                }
            }
            for count in [1, 2, 5, 21] {
                let page = String(format: bundle.localizedString(forKey: "editor.review.page", value: nil, table: nil), locale: Locale(identifier: language), 3, count)
                XCTAssertTrue(page.contains("3"), page)
                XCTAssertTrue(page.contains(String(count)), page)
                XCTAssertFalse(page.contains("%"), page)
            }
            if language == "en" {
                XCTAssertEqual(String(format: bundle.localizedString(forKey: "editor.review.page", value: nil, table: nil), locale: Locale(identifier: "en"), 3, 1), "Page 3 · 1 item")
                XCTAssertEqual(String(format: bundle.localizedString(forKey: "editor.review.page", value: nil, table: nil), locale: Locale(identifier: "en"), 3, 2), "Page 3 · 2 items")
                XCTAssertEqual(String(format: bundle.localizedString(forKey: "pdf.preview", value: nil, table: nil), locale: Locale(identifier: "en"), 1), "PDF Preview · 1 page")
                XCTAssertEqual(String(format: bundle.localizedString(forKey: "pdf.preview", value: nil, table: nil), locale: Locale(identifier: "en"), 2), "PDF Preview · 2 pages")
            }
            let scope = bundle.localizedString(forKey: "search.languageScope", value: nil, table: nil)
            XCTAssertFalse(scope.contains("search.languageScope"))
            let purchase = bundle.localizedString(forKey: "premium.restore", value: nil, table: nil)
            XCTAssertFalse(purchase.contains("premium.restore"))
        }
    }

    func testShareExtensionContainsEveryDeclaredLanguage() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let share = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("RedactShare.appex")))
        for language in languages {
            let bundle = try languageBundle(language, in: share)
            let values = try strings(in: bundle)
            XCTAssertEqual(values.count, 718, language)
            for key in ["share.instructions", "share.save", "share.saved", "share.error.size", "common.ok"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key, language)
            }
        }
    }

    @MainActor func testDefaultGroupDisplayUsesCurrentLanguageWithoutMutatingStoredName() {
        let context = PersistenceController.shared.container.viewContext
        let group = FileGroup(context: context)
        defer { context.delete(group) }
        group.id = GroupManager.defaultGroupID
        group.name = "Default Group"
        XCTAssertEqual(group.localizedDisplayName, NSLocalizedString("group.default", comment: ""))
        XCTAssertEqual(group.name, "Default Group")
        group.name = "My renamed default group"
        XCTAssertEqual(group.localizedDisplayName, "My renamed default group")
        XCTAssertEqual(group.name, "My renamed default group")
        group.id = UUID()
        group.name = "My custom name"
        XCTAssertEqual(group.localizedDisplayName, "My custom name")
    }

    private func languageBundle(_ language: String, in bundle: Bundle) throws -> Bundle {
        let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"), language)
        return try XCTUnwrap(Bundle(path: path), language)
    }

    private func strings(in bundle: Bundle) throws -> [String: String] {
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }
}
