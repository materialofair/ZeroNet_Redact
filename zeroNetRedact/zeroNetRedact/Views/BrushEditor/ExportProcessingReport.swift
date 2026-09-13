import Foundation
import ImageIO
import PDFKit

struct ExportProcessingReport {
    let format: String
    let size: Int
    let regionCount: Int
    let verifiedAbsentFields: [String]

    static func inspect(data: Data, isPDF: Bool, regionCount: Int) -> Self {
        var absent: [String] = []
        if isPDF, let document = PDFDocument(data: data) {
            let attributes = document.documentAttributes ?? [:]
            for (key, label) in [(PDFDocumentAttribute.authorAttribute, "report.author"),
                                 (.subjectAttribute, "report.subject"), (.keywordsAttribute, "report.keywords")] {
                if attributes[key] == nil { absent.append(label) }
            }
        } else if let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if properties[kCGImagePropertyGPSDictionary] == nil { absent.append("report.gps") }
            if properties[kCGImagePropertyExifDictionary] == nil { absent.append("report.exif") }
        }
        return Self(format: isPDF ? "PDF" : "PNG", size: data.count,
                    regionCount: regionCount, verifiedAbsentFields: absent)
    }
}
