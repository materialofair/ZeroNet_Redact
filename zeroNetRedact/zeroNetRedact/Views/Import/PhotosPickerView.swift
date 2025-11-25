import PhotosUI
import SwiftUI

struct PhotosPickerView: View {
    @ObservedObject var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 10,
            matching: .images
        ) {
            VStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text("选择照片")
                    .font(.headline)
                Text("最多选择10张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: selectedItems) { newItems in
            if !newItems.isEmpty {
                Task {
                    await viewModel.importPhotos(newItems)
                    dismiss()
                }
            }
        }
    }
}
