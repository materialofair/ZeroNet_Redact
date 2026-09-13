import SwiftUI

struct EditorExportCompletionView: View {
    let fileURL: URL
    var report: ExportProcessingReport? = nil
    let onContinueEditing: () -> Void
    let onDone: () -> Void
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    Text(NSLocalizedString("export.success.detail", comment: ""))
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let report {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("report.title").font(.headline)
                            Text("\(report.format) · \(ByteCountFormatter.string(fromByteCount: Int64(report.size), countStyle: .file))")
                            Text(String(format: NSLocalizedString("report.regions", comment: ""), report.regionCount))
                            ForEach(report.verifiedAbsentFields, id: \.self) { key in
                                Text(String(format: NSLocalizedString("report.absent", comment: ""), NSLocalizedString(key, comment: "")))
                            }
                            Text("report.reviewReminder").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        showShareSheet = true
                    } label: {
                        Label(NSLocalizedString("editor.export.shareCopy", comment: ""),
                              systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("editor.shareCopy")

                    Button(action: onContinueEditing) {
                        Text(NSLocalizedString("editor.discardConfirm.keepEditing", comment: ""))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("editor.continueEditing")
                }
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(NSLocalizedString("editor.export.savedTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.done", comment: ""), action: onDone)
                        .accessibilityIdentifier("editor.finishEditing")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // 分享或取消只收起系统面板；再次分享复用已保存副本，不重复导出或扣配额。
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [fileURL])
        }
    }
}
