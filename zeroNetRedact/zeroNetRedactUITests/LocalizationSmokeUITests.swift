import XCTest

/// Run only on the dedicated localization simulator with no personal content.
/// Navigates onboarding, Settings, and Premium; does not purchase or restore an account.
final class LocalizationSmokeUITests: XCTestCase {
    @MainActor
    func testTenLanguagesBrandScreenshots() {
        continueAfterFailure = false
        let rows: [(String, String, String, String)] = [
            ("en", "Set Up Later", "Skip", "Settings"),
            ("zh-Hans", "稍后设置", "跳过", "设置"),
            ("zh-Hant", "稍後設定", "跳過", "設定"),
            ("ja", "あとで設定", "スキップ", "設定"),
            ("pl", "Ustaw później", "Pomiń", "Ustawienia"),
            ("de", "Später einrichten", "Überspringen", "Einstellungen"),
            ("fr", "Configurer plus tard", "Ignorer", "Réglages"),
            ("es", "Configurar más tarde", "Omitir", "Ajustes"),
            ("pt-BR", "Configurar depois", "Pular", "Ajustes"),
            ("id", "Atur nanti", "Lewati", "Pengaturan")
        ]
        for row in rows {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(row.0))", "-AppleLocale", row.0]
            app.launch()
            let later = app.buttons[row.1]
            if later.waitForExistence(timeout: 3) && later.isHittable { later.tap() }
            let skip = app.buttons[row.2]
            if skip.waitForExistence(timeout: 2) && skip.isHittable { skip.tap() }
            let settings = app.tabBars.buttons[row.3]
            XCTAssertTrue(settings.waitForExistence(timeout: 5), row.0)
            settings.tap()
            let brand = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Cloakmark")).firstMatch
            for _ in 0..<6 {
                if brand.exists && brand.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(brand.exists && brand.isHittable, row.0)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Cloakmark-brand-\(row.0)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    @MainActor
    func testNewLanguagesInOnboardingSettingsAndPremium() {
        continueAfterFailure = false
        let samples: [String: [String]] = [
            "zh-Hant": ["zh_TW", "稍後設定", "跳過", "設定", "回復購買", "升級到 Pro", "解鎖無限遮蔽", "關閉"],
            "ja": ["ja_JP", "あとで設定", "スキップ", "設定", "購入を復元", "Proへアップグレード", "制限を解除", "閉じる"],
            "pl": ["pl_PL", "Ustaw później", "Pomiń", "Ustawienia", "Przywróć zakup", "Przejdź na Pro", "Odblokuj brak limitów", "Zamknij"],
            "de": ["de_DE", "Später einrichten", "Überspringen", "Einstellungen", "Kauf wiederherstellen", "Auf Pro upgraden", "Unbegrenzt freischalten", "Schließen"],
            "fr": ["fr_FR", "Configurer plus tard", "Ignorer", "Réglages", "Restaurer l’achat", "Passer à Pro", "Débloquer l’illimité", "Fermer"],
            "es": ["es_ES", "Configurar más tarde", "Omitir", "Ajustes", "Restaurar compra", "Actualizar a Pro", "Desbloquear sin límites", "Cerrar"],
            "pt-BR": ["pt_BR", "Configurar depois", "Pular", "Ajustes", "Restaurar compra", "Obter Pro", "Desbloquear sem limites", "Fechar"],
            "id": ["id_ID", "Atur nanti", "Lewati", "Pengaturan", "Pulihkan pembelian", "Tingkatkan ke Pro", "Buka akses tanpa batas", "Tutup"]
        ]
        for language in ["zh-Hant", "ja", "pl", "de", "fr", "es", "pt-BR", "id"] {
            let sample = samples[language]!
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", sample[0]]
            app.launch()
            let later = app.buttons[sample[1]]
            if later.waitForExistence(timeout: 5) && later.isHittable { later.tap() }
            let skip = app.buttons[sample[2]]
            if skip.waitForExistence(timeout: 3) && skip.isHittable { skip.tap() }
            let settings = app.tabBars.buttons[sample[3]]
            XCTAssertTrue(settings.waitForExistence(timeout: 5), language)
            settings.tap()
            XCTAssertTrue(app.buttons[sample[4]].waitForExistence(timeout: 5), language)
            let upgrade = app.buttons[sample[5]]
            XCTAssertTrue(upgrade.waitForExistence(timeout: 5), language)
            upgrade.tap()
            XCTAssertTrue(app.staticTexts[sample[6]].waitForExistence(timeout: 5), language)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Premium-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons[sample[7]].tap()
            app.terminate()
        }
    }
}
