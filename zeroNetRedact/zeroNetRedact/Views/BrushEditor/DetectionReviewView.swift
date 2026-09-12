import SwiftUI

struct DetectionReviewPage: Identifiable {
    let pageIndex: Int?
    let regions: [SensitiveRegion]
    var id: Int { pageIndex ?? -1 }

    static func grouped(_ regions: [SensitiveRegion], isPDF: Bool) -> [DetectionReviewPage] {
        guard !regions.isEmpty else { return [] }
        guard isPDF else { return [DetectionReviewPage(pageIndex: nil, regions: regions)] }
        return Dictionary(grouping: regions, by: \.pageIndex)
            .map { DetectionReviewPage(pageIndex: $0.key, regions: $0.value) }
            .sorted { $0.id < $1.id }
    }
}

struct DetectionReviewView: View {
    let regions: [SensitiveRegion]
    let isPDF: Bool
    let onLocate: (SensitiveRegion) -> Void
    let onIgnore: (SensitiveRegion) -> Void
    /// 用户明确忽略剩余候选后导出；候选为空时直接导出。
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var pages: [DetectionReviewPage] {
        DetectionReviewPage.grouped(regions, isPDF: isPDF)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary)
                        .font(.headline)
                        .accessibilityIdentifier("editor.reviewSummary")
                    Text(NSLocalizedString("editor.review.explanation", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(pages) { page in
                    Section {
                        ForEach(page.regions) { region in
                            Button {
                                onLocate(region)
                            } label: {
                                HStack {
                                    Image(systemName: region.type.icon)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(region.type.displayName)
                                        if let text = region.recognizedText, !text.isEmpty {
                                            Text(text)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 44)
                            }
                            .accessibilityHint(NSLocalizedString("editor.review.locateHint", comment: ""))
                            .swipeActions {
                                Button(NSLocalizedString("editor.review.ignore", comment: "")) {
                                    onIgnore(region)
                                }
                                .tint(.orange)
                            }
                        }
                    } header: {
                        Text(pageTitle(page))
                    }
                }

                Section {
                    Button(action: onExport) {
                        Text(regions.isEmpty
                             ? NSLocalizedString("editor.review.export", comment: "")
                             : String(format: NSLocalizedString("editor.review.ignoreAndExport", comment: ""), regions.count))
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("editor.reviewExport")
                }
            }
            .navigationTitle(NSLocalizedString("editor.review.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("editor.discardConfirm.keepEditing", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var summary: String {
        if isPDF {
            return String(format: NSLocalizedString("editor.review.pdfSummary", comment: ""),
                          regions.count, pages.count)
        }
        return String(format: NSLocalizedString("editor.review.imageSummary", comment: ""), regions.count)
    }

    private func pageTitle(_ page: DetectionReviewPage) -> String {
        if let index = page.pageIndex {
            return String(format: NSLocalizedString("editor.review.page", comment: ""),
                          index + 1, page.regions.count)
        }
        return NSLocalizedString("editor.review.regions", comment: "")
    }
}
