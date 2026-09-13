import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private var providers: [NSItemProvider] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        statusLabel.text = NSLocalizedString("share.instructions", comment: "")
        statusLabel.numberOfLines = 0
        saveButton.setTitle(NSLocalizedString("share.save", comment: ""), for: .normal)
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle(NSLocalizedString("common.close", comment: ""), for: .normal)
        cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [statusLabel, saveButton, cancel])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func close() { extensionContext?.completeRequest(returningItems: nil) }

    @objc private func save() {
        saveButton.isEnabled = false
        guard !providers.isEmpty, providers.count <= ShareInbox.maximumAttachments else {
            statusLabel.text = NSLocalizedString("share.countLimit", comment: "")
            return
        }
        Task {
            var saved = 0
            do {
                let inbox = try ShareInbox.live()
                for provider in providers {
                    let type: UTType
                    if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) { type = .pdf }
                    else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { type = .image }
                    else { throw ShareInbox.InboxError.unsupported }
                    try await store(provider: provider, type: type, inbox: inbox)
                    saved += 1
                }
                statusLabel.text = String(format: NSLocalizedString("share.saved", comment: ""), saved)
            } catch {
                statusLabel.text = String(format: NSLocalizedString("share.partial", comment: ""), saved, error.localizedDescription)
            }
        }
    }

    private func store(provider: NSItemProvider, type: UTType, inbox: ShareInbox) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw ShareInbox.InboxError.unsupported }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= ShareInbox.maximumBytes else { throw ShareInbox.InboxError.tooLarge }
                    // Provider owns this temporary URL; finish reading before returning from its callback.
                    try inbox.enqueue(data: Data(contentsOf: url), type: type.identifier)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
