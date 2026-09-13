import PDFKit
import SwiftUI

enum PendingRegionNavigation {
    static func next(in regions: [SensitiveRegion], currentPage: Int, after selectedID: UUID?) -> SensitiveRegion? {
        let ordered = regions.enumerated().sorted {
            let lhs = $0.element.pageIndex ?? -1
            let rhs = $1.element.pageIndex ?? -1
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
        guard !ordered.isEmpty else { return nil }
        if let index = ordered.firstIndex(where: { $0.id == selectedID }) {
            return ordered[(index + 1) % ordered.count]
        }
        return ordered.first(where: { ($0.pageIndex ?? -1) >= currentPage }) ?? ordered.first
    }
}

struct PDFReviewNavigator: View {
    let document: PDFDocument
    let regions: [SensitiveRegion]
    let currentPage: Int
    let selectedID: UUID?
    let onLocate: (SensitiveRegion) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(DetectionReviewPage.grouped(regions, isPDF: true)) { group in
                        if let index = group.pageIndex, let region = group.regions.first {
                            Button { onLocate(region) } label: {
                                VStack(spacing: 4) {
                                    if let page = document.page(at: index) {
                                        Image(uiImage: page.thumbnail(of: CGSize(width: 44, height: 58), for: .mediaBox))
                                            .resizable().scaledToFit().frame(width: 44, height: 58)
                                    }
                                    Text(String(format: NSLocalizedString("editor.review.page", comment: ""), index + 1, group.regions.count))
                                        .font(.caption)
                                }
                                .padding(6)
                                .background(index == currentPage ? Color.accentColor.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(index == currentPage ? .isSelected : [])
                        }
                    }
                }.padding(.horizontal, 12)
            }
            Button("review.next") {
                if let region = PendingRegionNavigation.next(in: regions, currentPage: currentPage, after: selectedID) {
                    onLocate(region)
                }
            }
            .frame(minHeight: 44)
            .disabled(regions.isEmpty)
        }
    }
}
