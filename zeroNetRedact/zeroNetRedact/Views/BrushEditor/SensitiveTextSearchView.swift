import PDFKit
import SwiftUI

struct SensitiveTextSearchView: View {
    let image: UIImage?
    let document: PDFDocument?
    let currentPageIndex: Int
    let onApply: ([SensitiveRegion]) -> Void
    let onLocate: (SensitiveRegion) -> Void
    let onKeepPending: ([SensitiveRegion]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var caseSensitive = false
    @State private var texts: [RecognizedText] = []
    @State private var results: [SensitiveRegion] = []
    @State private var selected = Set<UUID>()
    @State private var isLoading = false
    @State private var error: String?
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("search.query", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(search)
                    Toggle("search.caseSensitive", isOn: $caseSensitive)
                    Button("search.find", action: search)
                        .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isLoading { ProgressView("search.recognizing") }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if searched && !isLoading {
                    Section {
                        Text(String(format: NSLocalizedString("search.count", comment: ""), results.count))
                        if !results.isEmpty {
                            Button("search.selectAll") { selected = Set(results.map(\.id)) }
                            if document != nil {
                                Button("search.selectPage") {
                                    selected = Set(results.filter { $0.pageIndex == currentPageIndex }.map(\.id))
                                }
                            }
                            Button("search.ignoreSelected") {
                                results.removeAll { selected.contains($0.id) }
                                selected.removeAll()
                            }.disabled(selected.isEmpty)
                        }
                    }
                    ForEach(DetectionReviewPage.grouped(results, isPDF: document != nil)) { page in
                        Section {
                            ForEach(page.regions) { region in
                                HStack {
                                    Button {
                                        if !selected.insert(region.id).inserted { selected.remove(region.id) }
                                    } label: {
                                        Label(region.recognizedText ?? query,
                                              systemImage: selected.contains(region.id) ? "checkmark.circle.fill" : "circle")
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    Spacer()
                                    Button {
                                        onKeepPending(results)
                                        onLocate(region)
                                        dismiss()
                                    } label: {
                                        Image(systemName: "scope").frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text("search.locate"))
                                }
                            }
                        } header: {
                            if let index = page.pageIndex {
                                Text(String(format: NSLocalizedString("editor.review.page", comment: ""), index + 1, page.regions.count))
                            }
                        }
                    }
                    if !results.isEmpty {
                        Section {
                            Button("search.applySelected") {
                                onKeepPending(results)
                                onApply(results.filter { selected.contains($0.id) })
                                dismiss()
                            }.disabled(selected.isEmpty)
                            Button("search.keepPending") {
                                onKeepPending(results)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("search.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .task {
                guard document == nil, let data = image?.pngData() else { return }
                isLoading = true
                defer { isLoading = false }
                do {
                    texts = try await ImageOCRRecognizer().recognizeText(in: data, fileType: .image)
                    try Task.checkCancellation()
                } catch is CancellationError {
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .onChange(of: query) { _, _ in results = []; selected = []; searched = false }
            .onChange(of: caseSensitive) { _, _ in results = []; selected = []; searched = false }
        }
    }

    private func search() {
        guard !isLoading else { return }
        let options = TextSearchOptions(caseSensitive: caseSensitive)
        if let document {
            results = TextRecognizer.shared.findOccurrences(of: query, in: document, options: options)
        } else {
            results = TextRecognizer.shared.findOccurrences(of: query, in: texts, options: options)
        }
        selected = Set(results.map(\.id))
        searched = true
    }
}
