import SwiftUI

struct BatchRedactionView: View {
    let files: [OriginalFile]
    @StateObject private var queue = BatchRedactionQueue.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var types: Set<SensitiveType> = [.phoneNumber, .email, .idCard, .bankCard]
    @State private var keyword = ""
    @State private var review: BatchRedactionItem?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                if let job = queue.job {
                    Section {
                        Text("batch.reviewHint")
                        Text(String(format: NSLocalizedString("batch.progress", comment: ""), job.items.filter { $0.state == .succeeded }.count, job.items.count))
                        Button(queue.running ? "batch.pause" : "batch.prepare") {
                            if queue.running { queue.cancel() } else { queue.start() }
                        }
                    }
                    ForEach(Array(job.items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: NSLocalizedString("batch.item", comment: ""), index + 1))
                            Text(LocalizedStringKey("batch.state." + item.state.rawValue))
                                .font(.caption).foregroundStyle(.secondary)
                            if let error = item.error { Text(error).font(.caption).foregroundStyle(.red) }
                            if item.state == .review {
                                Text(String(format: NSLocalizedString("search.count", comment: ""), item.candidates.count))
                                Button("batch.review") { review = item }.disabled(queue.running)
                            }
                        }
                    }
                    Button("batch.clear", role: .destructive) { confirmClear = true }.disabled(queue.running)
                } else {
                    Section("batch.rules") {
                        ForEach([SensitiveType.phoneNumber, .email, .idCard, .bankCard], id: \.rawValue) { type in
                            Toggle(type.displayName, isOn: Binding(get: { types.contains(type) }, set: {
                                if $0 { types.insert(type) } else { types.remove(type) }
                            }))
                        }
                        TextField("search.query", text: $keyword)
                        Text("batch.blackHint").font(.caption)
                    }
                    Section("batch.images") {
                        Button("search.selectAll") { selected = Set(files.map(\.id)) }
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            Toggle(String(format: NSLocalizedString("batch.item", comment: ""), index + 1), isOn: Binding(get: { selected.contains(file.id) }, set: {
                                if $0 { selected.insert(file.id) } else { selected.remove(file.id) }
                            }))
                        }
                    }
                    Button("batch.create") {
                        queue.create(recipe: BatchRecipe(types: Array(types), keyword: keyword), files: files.filter { selected.contains($0.id) })
                        queue.start()
                    }.disabled(selected.isEmpty || (types.isEmpty && keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .navigationTitle("batch.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.close") { queue.cancel(); dismiss() } } }
            .sheet(item: $review, onDismiss: queue.reconcile) { item in
                if let file = try? queue.original(id: item.originalID) {
                    SimpleBrushEditor(file: file, batchItem: item)
                } else { ContentUnavailableView("batch.missing", systemImage: "photo.badge.exclamationmark") }
            }
            .alert("common.error", isPresented: Binding(get: { queue.error != nil }, set: { if !$0 { queue.error = nil } })) {
                Button("common.ok", role: .cancel) { queue.error = nil }
            } message: { Text(queue.error ?? "") }
            .confirmationDialog("batch.clearConfirm", isPresented: $confirmClear) {
                Button("batch.clear", role: .destructive) { queue.clear() }
            }
            .onDisappear { queue.cancel() }
        }
    }
}
