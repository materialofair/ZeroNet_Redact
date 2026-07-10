import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.allowsMultipleSelection = true
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
            guard !urls.isEmpty else { return }

            print("📄 DocumentPicker: 用户选择了 \(urls.count) 个文件")

            // 先关闭 sheet 再导入，让 ImportView 的进度遮罩可见、可取消（与 Photos 路径一致）。
            // 安全作用域 URL 的访问权限由 startAccessingSecurityScopedResource 控制，与 picker
            // 是否已 dismiss 无关（FileImportProcessor 内部会配对调用 start/stopAccessing），因此这里
            // 提前 dismiss 不影响后续 Task 中读取 urls。
            parent.dismiss()
            Task { @MainActor in
                await parent.viewModel.importDocuments(urls)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
