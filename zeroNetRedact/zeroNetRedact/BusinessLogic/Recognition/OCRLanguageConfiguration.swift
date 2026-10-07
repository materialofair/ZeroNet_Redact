import Foundation
import Vision

/// The recognition model, not the app's translated UI, determines OCR language support.
enum OCRLanguageConfiguration {
    static let preferenceKey = "redact.ocr.language"
    static let automatic = "auto"

    static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    static func configure(_ request: VNRecognizeTextRequest,
                          selection: String? = nil) throws {
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        let selected = selection ?? UserDefaults.standard.string(forKey: preferenceKey) ?? automatic
        request.customWords = []
        request.usesLanguageCorrection = true
        if selected != automatic, supported.contains(selected) {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [selected]
        } else {
            // Includes Apple's future additions, and safely handles a preference saved on a newer OS.
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = supported
        }
    }
}
