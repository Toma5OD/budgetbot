import UIKit
import UniformTypeIdentifiers
import SwiftUI

/// System Share Sheet target. Accepts images, PDFs and plain text from any
/// host app (Revolut, Mail, Files, Photos, Safari, …), drops them in the
/// App Group queue, and exits. Does NOT call the network — the main app does
/// extraction when the user next opens BudgetBot.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Saving to BudgetBot…"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -16)
        ])

        Task { await self.ingestAndDismiss() }
    }

    // MARK: - Ingest

    private func ingestAndDismiss() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var saved = 0
        var failed = 0

        for item in items {
            for provider in (item.attachments ?? []) {
                if await tryIngest(provider) {
                    saved += 1
                } else {
                    failed += 1
                }
            }
        }

        await MainActor.run {
            self.spinner.stopAnimating()
            switch (saved, failed) {
            case (0, 0):
                self.statusLabel.text = "Nothing to share."
            case (let n, 0):
                self.statusLabel.text = "Queued \(n) for BudgetBot."
            case (let n, let f):
                self.statusLabel.text = "Queued \(n), couldn't read \(f)."
            }
        }

        // Brief pause so the user sees the result, then dismiss.
        try? await Task.sleep(nanoseconds: 600_000_000)
        await MainActor.run {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Returns true if we successfully wrote at least one queue entry from this provider.
    private func tryIngest(_ provider: NSItemProvider) async -> Bool {
        // PDF first — sometimes images also conform to data, but PDFs are most specific.
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            if let data = await loadData(provider, UTType.pdf.identifier) {
                let name = provider.suggestedName
                if let _ = try? PendingCaptureStore.writePDF(data, filename: name) { return true }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await loadImageData(provider) {
                let name = provider.suggestedName
                if let _ = try? PendingCaptureStore.writeImage(data, filename: name) { return true }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadString(provider, UTType.plainText.identifier),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let _ = try? PendingCaptureStore.writeText(text) { return true }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(provider) {
                if let _ = try? PendingCaptureStore.writeText("URL: \(url.absoluteString)") { return true }
            }
        }
        return false
    }

    // MARK: - NSItemProvider helpers

    private func loadData(_ provider: NSItemProvider, _ type: String) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                if let data = value as? Data { cont.resume(returning: data); return }
                if let url = value as? URL, let data = try? Data(contentsOf: url) {
                    cont.resume(returning: data); return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private func loadImageData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { value, _ in
                if let data = value as? Data { cont.resume(returning: data); return }
                if let url = value as? URL, let data = try? Data(contentsOf: url) {
                    cont.resume(returning: data); return
                }
                if let img = value as? UIImage, let data = img.jpegData(compressionQuality: 0.85) {
                    cont.resume(returning: data); return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private func loadString(_ provider: NSItemProvider, _ type: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                if let s = value as? String { cont.resume(returning: s); return }
                if let url = value as? URL, let s = try? String(contentsOf: url) {
                    cont.resume(returning: s); return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                cont.resume(returning: value as? URL)
            }
        }
    }
}
