//
//  PDFPreviewView.swift
//  ZeroNet Redact
//
//  PDF预览组件 - 使用原生PDFView
//

import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let pdfDocument: PDFDocument
    var file: RedactedFile?
    var viewModel: AlbumViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    init(pdfDocument: PDFDocument, file: RedactedFile? = nil, viewModel: AlbumViewModel? = nil) {
        self.pdfDocument = pdfDocument
        self.file = file
        self.viewModel = viewModel
        print("📄 [PDFPreviewView] 初始化，文档页数: \(pdfDocument.pageCount)")
    }

    var body: some View {
        let _ = print("📄 [PDFPreviewView] body被调用")

        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .accessibilityLabel(NSLocalizedString("common.close", comment: ""))

                Spacer()

                Text(
                    String(
                        format: NSLocalizedString("pdf.preview", comment: ""), pdfDocument.pageCount
                    )
                )
                .font(.headline)

                Spacer()

                if let file, let viewModel {
                    FilePreviewActionsMenu(file: file, viewModel: viewModel) {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                    .padding(.trailing, 12)
                }

                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .accessibilityLabel(NSLocalizedString("album.shareFile", comment: ""))
            }
            .padding()
            .background(Color(.systemBackground))

            // 使用原生PDFView
            PDFKitView(document: pdfDocument)
        }
        .sheet(isPresented: $showShareSheet) {
            if let pdfData = pdfDocument.dataRepresentation() {
                ShareSheet(items: [pdfData])
            }
        }
    }
}

// MARK: - PDFKit视图包装器

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    init(document: PDFDocument) {
        self.document = document
        print("📄 [PDFKitView] 初始化")
    }

    func makeUIView(context: Context) -> PDFView {
        print("📄 [PDFKitView] makeUIView被调用")

        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground

        print("📄 [PDFKitView] PDFView配置完成")
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        print("📄 [PDFKitView] updateUIView被调用")
    }
}

// MARK: - 预览

#Preview {
    if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf"),
        let document = PDFDocument(url: url)
    {
        PDFPreviewView(pdfDocument: document)
    } else {
        Text(NSLocalizedString("pdf.loadFailed", comment: ""))
    }
}
