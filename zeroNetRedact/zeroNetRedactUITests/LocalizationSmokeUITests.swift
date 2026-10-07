import XCTest

/// Run only on the dedicated localization simulator with no personal content.
/// Navigates onboarding, Settings, and Premium; does not purchase or restore an account.
final class LocalizationSmokeUITests: XCTestCase {
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
