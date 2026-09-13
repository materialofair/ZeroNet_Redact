import Combine
import CoreData
import CryptoKit
import Foundation

struct BatchRecipe: Codable, Equatable {
    var types: [SensitiveType]
    var keyword: String
    var fingerprint: String {
        let canonical = "v1|black|" + types.map(\.rawValue).sorted().joined(separator: ",") + "|" + keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct BatchRedactionItem: Codable, Identifiable {
    enum State: String, Codable { case waiting, analyzing, review, succeeded, failed }
    let id: UUID
    let originalID: UUID
    let key: String
    let exportID: UUID
    var state: State = .waiting
    var candidates: [DraftRecognition] = []
    var error: String?
}

struct BatchJob: Codable {
    var version = 1
    let recipe: BatchRecipe
    var items: [BatchRedactionItem]

    init(recipe: BatchRecipe, sources: [(UUID, String)]) {
        self.recipe = recipe
        var seen = Set<String>()
        items = sources.compactMap { id, hash in
            let key = hash + ":" + recipe.fingerprint
            guard seen.insert(key).inserted else { return nil }
            return BatchRedactionItem(id: UUID(), originalID: id, key: key, exportID: UUID())
        }
    }

    mutating func recover(completed: Set<UUID>) {
        for index in items.indices {
            if completed.contains(items[index].exportID) { items[index].state = .succeeded }
            else if items[index].state == .analyzing { items[index].state = .waiting }
        }
    }
}

@MainActor
final class BatchRedactionQueue: ObservableObject {
    static let shared = BatchRedactionQueue()
    @Published private(set) var job: BatchJob?
    @Published private(set) var running = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var canWrite = true
    private let url: URL

    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImageBatch.enc")) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                job = try JSONDecoder().decode(BatchJob.self, from: CryptoEngine.shared.decrypt(data: Data(contentsOf: url)))
                guard job?.version == 1 else { throw CocoaError(.coderReadCorrupt) }
                reconcile()
            }
        } catch { self.error = error.localizedDescription; canWrite = false }
    }

    func create(recipe: BatchRecipe, files: [OriginalFile]) {
        guard !running, canWrite else { return }
        do {
            let sources = try files.filter { $0.fileType == .image }.map { file -> (UUID, String) in
                let hash: String
                if let value = file.contentHash { hash = value }
                else {
                    let bytes = try CryptoEngine.shared.decrypt(data: StorageManager.shared.loadEncryptedOriginal(id: file.id, type: .image))
                    hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                }
                return (file.id, hash)
            }
            guard !sources.isEmpty else { return }
            job = BatchJob(recipe: recipe, sources: sources)
            try save()
        } catch { self.error = error.localizedDescription }
    }

    func start() {
        guard !running, job != nil, canWrite else { return }
        running = true
        task = Task { @MainActor in
            defer { running = false; task = nil }
            guard let count = job?.items.count else { return }
            for index in 0..<count {
                if Task.isCancelled { break }
                guard let state = job?.items[index].state, state == .waiting || state == .failed else { continue }
                do {
                    job?.items[index].state = .analyzing
                    job?.items[index].error = nil
                    try save()
                    guard let item = job?.items[index], let recipe = job?.recipe,
                          let file = try original(id: item.originalID) else { throw CocoaError(.fileNoSuchFile) }
                    let texts = try await TextRecognizer.shared.recognizeText(in: file)
                    try Task.checkCancellation()
                    var candidates = TextRecognizer.shared.detectSensitiveRegions(in: texts).filter { recipe.types.contains($0.type) }
                    candidates += TextRecognizer.shared.findOccurrences(of: recipe.keyword, in: texts)
                    job?.items[index].candidates = candidates.map(DraftRecognition.init)
                    job?.items[index].state = .review
                    try save()
                } catch is CancellationError {
                    job?.items[index].state = .waiting
                    do { try save() } catch { self.error = error.localizedDescription }
                    break
                } catch {
                    job?.items[index].state = .failed
                    job?.items[index].error = error.localizedDescription
                    do { try save() } catch { self.error = error.localizedDescription; break }
                }
            }
        }
    }

    func cancel() { task?.cancel() }

    func reconcile() {
        guard job != nil else { return }
        do {
            let request: NSFetchRequest<RedactedFile> = RedactedFile.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", job!.items.map(\.exportID))
            request.includesPendingChanges = false
            let completed = try PersistenceController.shared.container.viewContext.fetch(request)
            job?.recover(completed: Set(completed.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }.map(\.id)))
            try save()
        } catch { self.error = error.localizedDescription }
    }

    func original(id: UUID) throws -> OriginalFile? {
        let request = OriginalFile.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try PersistenceController.shared.container.viewContext.fetch(request).first
    }

    func clear() {
        guard !running else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            job = nil; error = nil; canWrite = true
        } catch { self.error = error.localizedDescription }
    }

    private func save() throws {
        guard canWrite, let job else { return }
        let encrypted = try CryptoEngine.shared.encrypt(data: JSONEncoder().encode(job))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
