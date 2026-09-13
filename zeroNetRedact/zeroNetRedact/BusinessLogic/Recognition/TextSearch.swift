import Foundation
import PDFKit

struct TextSearchOptions {
    var caseSensitive = false
    static let `default` = TextSearchOptions()
}

extension TextRecognizer {
    func findOccurrences(of query: String, in texts: [RecognizedText],
                         options: TextSearchOptions = .default) -> [SensitiveRegion] {
        texts.flatMap { text in
            matchingRanges(query, in: text.text, options: options).map { range in
                SensitiveRegion(type: .custom,
                    boundingBox: text.substringBox?(range) ?? text.boundingBox,
                    confidence: text.confidence, pageIndex: text.pageIndex,
                    recognizedText: (text.text as NSString).substring(with: range))
            }
        }
    }

    func findOccurrences(of query: String, in document: PDFDocument,
                         options: TextSearchOptions = .default) -> [SensitiveRegion] {
        (0..<document.pageCount).flatMap { index -> [SensitiveRegion] in
            guard let page = document.page(at: index), let text = page.string else { return [] }
            return matchingRanges(query, in: text, options: options).flatMap { range -> [SensitiveRegion] in
                guard let selection = page.selection(for: range) else { return [] }
                // 多行匹配拆成行框，避免遮住两行之间的不相关内容。
                return selection.selectionsByLine().compactMap { line in
                    let bounds = line.bounds(for: page)
                    guard !bounds.isEmpty, !bounds.isNull else { return nil }
                    return SensitiveRegion(type: .custom, boundingBox: bounds, confidence: 1,
                        pageIndex: index, recognizedText: line.string)
                }
            }
        }
    }

    private func matchingRanges(_ query: String, in text: String, options: TextSearchOptions) -> [NSRange] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let source = text as NSString
        var cursor = 0
        var results: [NSRange] = []
        while cursor < source.length {
            let range = source.range(of: query, options: options.caseSensitive ? [.literal] : [.literal, .caseInsensitive],
                                     range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound, range.length > 0 else { break }
            results.append(range)
            cursor = NSMaxRange(range)
        }
        return results
    }
}
