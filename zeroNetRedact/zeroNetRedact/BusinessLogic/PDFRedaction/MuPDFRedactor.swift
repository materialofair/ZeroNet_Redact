//
//  MuPDFRedactor.swift
//  ZeroNet Redact
//
//  PDF 真删除 Swift 封装：遮盖区域内的文字从内容流中物理删除。
//  底层为 MuPDF（AGPL-3.0，见 THIRD_PARTY_NOTICES.md），
//  每次调用创建独立 fz_context，线程安全，应在后台线程调用。
//

import Foundation
import CoreGraphics

/// PDF 真删除区域。
/// 坐标空间与 PDFKit 的页面空间相同（`PDFAnnotation.bounds` / `PDFSelection.bounds`，
/// 即 PDF user space：左下原点、y 向上、未旋转），直接传递即可，旋转页亦无需转换。
struct PDFRedactionRegion: Sendable {
    let pageIndex: Int
    let rect: CGRect
}

enum MuPDFRedactorError: LocalizedError {
    case redactionFailed(String)

    var errorDescription: String? {
        switch self {
        case .redactionFailed(let message):
            return message.isEmpty ? "未知 MuPDF 错误" : message
        }
    }
}

struct MuPDFRedactor {
    /// 对 PDF 数据应用真删除，返回处理后的 PDF 数据。
    /// regions 为空时原样返回输入。
    nonisolated static func redact(pdfData: Data, regions: [PDFRedactionRegion]) throws -> Data {
        guard !regions.isEmpty else { return pdfData }

        var floats: [Float] = []
        floats.reserveCapacity(regions.count * 5)
        for region in regions {
            floats.append(Float(region.pageIndex))
            floats.append(Float(region.rect.minX))
            floats.append(Float(region.rect.minY))
            floats.append(Float(region.rect.maxX))
            floats.append(Float(region.rect.maxY))
        }

        return try pdfData.withUnsafeBytes { rawBuffer -> Data in
            let inputPtr = rawBuffer.bindMemory(to: UInt8.self)
            var outPtr: UnsafeMutablePointer<UInt8>?
            var outLen: Int = 0
            var errorBuf = [CChar](repeating: 0, count: 1024)

            let result = floats.withUnsafeBufferPointer { regionBuffer -> Int32 in
                errorBuf.withUnsafeMutableBufferPointer { errorPtr -> Int32 in
                    mupdf_redact_pdf(
                        inputPtr.baseAddress, rawBuffer.count,
                        regionBuffer.baseAddress, regions.count,
                        &outPtr, &outLen,
                        errorPtr.baseAddress, errorPtr.count)
                }
            }

            guard result == 0, let outputPtr = outPtr else {
                throw MuPDFRedactorError.redactionFailed(String(cString: errorBuf))
            }
            defer { mupdf_free(outputPtr) }
            return Data(bytes: outputPtr, count: outLen)
        }
    }
}
