import CoreData
import SwiftUI

/// Imports only while the authenticated app is in the foreground. Failed entries remain encrypted for retry.
struct ShareInboxModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @Environment(\.scenePhase) private var phase
    @State private var importing = false
    @State private var message: String?
    @State private var selectedFile: OriginalFile?

    func body(content: Content) -> some View {
        content
            .task(id: "\(phase)-\(appState.isAuthenticated)-\(appState.isFirstLaunch)-\(appState.hasSeenOnboarding)") {
                await Task.yield()
                await consume()
            }
            .alert("Shared files", isPresented: Binding(get: { message != nil && !appState.shouldAuthenticate() },
                                                       set: { if !$0 { message = nil } })) {
                Button("share.retry") { message = nil; Task { await consume() } }
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .sheet(item: $selectedFile) { file in
                if !appState.shouldAuthenticate() { SimpleBrushEditor(file: file) }
                else { AuthenticationView() }
            }
    }

    @MainActor private func consume() async {
        guard phase == .active, !appState.shouldAuthenticate(), !appState.isFirstLaunch,
              appState.hasSeenOnboarding, !importing else { return }
        importing = true
        defer { importing = false }
        do {
            let inbox = try ShareInbox.live()
            let entries = try inbox.entries()
            guard !entries.isEmpty else { return }
            var imported = 0
            var failed = 0
            var singleID: UUID?
            for entry in entries {
                guard phase == .active, !appState.shouldAuthenticate() else { break }
                do {
                    let payload = try await Task.detached { try inbox.read(entry) }.value
                    guard phase == .active, !appState.shouldAuthenticate() else { break }
                    let result = try await ImportManager.shared.importFileWithDuplicateCheck(
                        from: payload.type == "com.adobe.pdf" ? .pdfData(payload.data) : .imageData(payload.data))
                    switch result {
                    case .success(let file): singleID = file.id
                    case .duplicate(let file): singleID = file.id
                    }
                    try FileManager.default.removeItem(at: entry)
                    imported += 1
                } catch { failed += 1 }
            }
            guard phase == .active, !appState.shouldAuthenticate() else { return }
            if entries.count == 1, imported == 1, let id = singleID {
                let request: NSFetchRequest<OriginalFile> = OriginalFile.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                selectedFile = try PersistenceController.shared.container.viewContext.fetch(request).first
            } else {
                message = String(format: NSLocalizedString("share.importResult", comment: ""), imported, failed)
            }
        } catch {
            // Missing shared capability is a deployment problem; do not disturb users with no inbox.
            if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.groupID),
               FileManager.default.fileExists(atPath: container.appendingPathComponent("ShareInbox").path) {
                message = NSLocalizedString("share.importFailed", comment: "")
            }
        }
    }
}
