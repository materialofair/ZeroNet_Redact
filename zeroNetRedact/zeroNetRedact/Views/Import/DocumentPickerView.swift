import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }

            print("📄 DocumentPicker: 用户选择了文件: \(url.lastPathComponent)")

            Task { @MainActor in
                await parent.viewModel.importDocument(url)
                parent.dismiss()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
