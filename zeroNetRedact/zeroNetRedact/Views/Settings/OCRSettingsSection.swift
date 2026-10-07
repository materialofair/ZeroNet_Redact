import SwiftUI

struct OCRSettingsSection: View {
    @AppStorage(OCRLanguageConfiguration.preferenceKey) private var selection = OCRLanguageConfiguration.automatic
    private let supported = OCRLanguageConfiguration.supportedLanguages()

    private var supportedSelection: Binding<String> {
        Binding(get: {
            supported.contains(selection) ? selection : OCRLanguageConfiguration.automatic
        }, set: { selection = $0 })
    }

    var body: some View {
        Section {
            Picker("ocr.language", selection: supportedSelection) {
                Text("ocr.automatic").tag(OCRLanguageConfiguration.automatic)
                ForEach(supported.sorted(by: { name($0).localizedStandardCompare(name($1)) == .orderedAscending }), id: \.self) { language in
                    Text(name(language)).tag(language)
                }
            }
            .pickerStyle(.navigationLink)
            Text("ocr.documentScope").font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("ocr.section")
        } footer: {
            Text("ocr.languageScope")
        }
    }

    private func name(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
