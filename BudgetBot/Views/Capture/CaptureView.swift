import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Capture flow. The user adds attachments + an optional note, taps a single
/// "Process in background" CTA, the batch is persisted as a `CaptureJob`, and
/// the queue service handles AI extraction off-screen. The screen clears
/// immediately so the user can queue another batch.
struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase)   private var scenePhase
    @Environment(FXService.self) private var fx
    @Environment(CaptureQueueService.self) private var queue

    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var vm = CaptureViewModel()
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showPDFImporter = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var justQueued = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if queue.processingCount > 0 || queue.queuedCount > 0 || queue.awaitingReviewCount > 0 {
                        statusPill
                    }
                    intro
                    actionTiles

                    if !vm.images.isEmpty { photosSection }
                    if !vm.pdfs.isEmpty   { pdfsSection }
                    notesSection

                    if let err = vm.lastError {
                        Label(err, systemImage: "exclamationmark.circle.fill")
                            .font(.callout).foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    submitBar
                }
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Capture")
            .appHeaderToolbar()
            .onAppear { hydrate() }
            .onChange(of: scenePhase) { _, new in
                if new == .active {
                    vm.ingestPending()
                    queue.pump()
                }
            }
            .sheet(isPresented: $showScanner) {
                DocumentScannerView(onScan: { imgs in vm.images.append(contentsOf: imgs) })
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(onPick: { img in vm.images.append(img) })
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        vm.pdfs.append((data, url.lastPathComponent))
                    }
                }
            }
            .onChange(of: photoSelection) { _, newItems in
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            vm.images.append(img)
                        }
                    }
                    photoSelection.removeAll()
                }
            }
        }
    }

    // MARK: - Sub-sections

    private var statusPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(pillTitle).font(.subheadline.bold())
                Text(pillSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if queue.processingCount > 0 {
                ProgressView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .themedCard()
        .padding(.horizontal, 16)
    }

    private var pillTitle: String {
        // Offline + queued: the receipts aren't "queued for the bot",
        // they're parked waiting for a connection. Say so plainly.
        let offlineWaiting = !NetworkMonitor.shared.isOnline && queue.queuedCount > 0
        let queuedLabel = offlineWaiting
            ? "\(queue.queuedCount) waiting for connection"
            : "\(queue.queuedCount) queued"
        let parts = [
            queue.processingCount > 0 ? "\(queue.processingCount) processing"     : nil,
            queue.queuedCount     > 0 ? queuedLabel                               : nil,
            queue.awaitingReviewCount > 0 ? "\(queue.awaitingReviewCount) ready to review" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "Idle" : parts.joined(separator: " · ")
    }

    private var pillSubtitle: String {
        if !NetworkMonitor.shared.isOnline && queue.queuedCount > 0 {
            return "Captured offline — the bot reads these the moment you're back online."
        }
        if queue.awaitingReviewCount > 0 {
            return "Open Notifications when you're done capturing."
        }
        if queue.processingCount > 0 || queue.queuedCount > 0 {
            return "Keep going — the bot's reading these in the background."
        }
        return ""
    }

    private var intro: some View {
        Text(vm.yoloMode
             ? "YOLO mode is on — the AI will auto-save what it finds. Toggle in Settings."
             : "Snap, scan, attach PDFs or describe what happened. The bot processes in the background; you'll review each batch in Notifications when it's done.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }

    private var actionTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile(title: "Scan Receipt", icon: "doc.viewfinder.fill") { showScanner = true }
            tile(title: "Camera",       icon: "camera.fill")          { showCamera = true }
            PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                tileLabel(title: "Photos", icon: "photo.on.rectangle.angled")
            }
            .accessibilityLabel("Pick photos from your library")
            tile(title: "Add PDF",      icon: "doc.fill")             { showPDFImporter = true }
        }
        .padding(.horizontal, 16)
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Photos · \(vm.images.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(vm.images.enumerated()), id: \.offset) { idx, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button {
                                vm.images.remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .padding(6)
                            }
                            .accessibilityLabel("Remove photo \(idx + 1)")
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var pdfsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "PDFs · \(vm.pdfs.count)")
            VStack(spacing: 8) {
                ForEach(Array(vm.pdfs.enumerated()), id: \.offset) { idx, item in
                    HStack {
                        Image(systemName: "doc.richtext.fill").foregroundStyle(.tint)
                        Text(item.1).lineLimit(1)
                        Spacer()
                        Button {
                            vm.pdfs.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Remove \(item.1)")
                    }
                    .padding(12)
                    .themedCard()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Note (optional)")
            TextEditor(text: $vm.textNote)
                .frame(minHeight: 90)
                .padding(8)
                .themedCard()
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var submitBar: some View {
        VStack(spacing: 10) {
            Button {
                vm.queueForProcessing(in: context) { queue.pump() }
                justQueued = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    justQueued = false
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: justQueued ? "checkmark.circle.fill" : "paperplane.circle.fill")
                        .font(.title3)
                    Text(justQueued ? "Queued!" : (vm.yoloMode ? "Process in background (YOLO)" : "Process in background"))
                        .font(.callout.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!vm.hasInput)

            if vm.hasInput {
                Button(role: .destructive) {
                    vm.reset()
                } label: {
                    Text("Clear").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
    }

    private func tile(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title: title, icon: icon) }
            .buttonStyle(.pressable)
            .accessibilityLabel(title)
    }

    private func tileLabel(title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title)
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding()
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.tint)
    }

    private func hydrate() {
        let p = profiles.first
        vm.defaultCurrency = p?.defaultCurrency ?? Currencies.localeDefault
        vm.baseCurrency = p?.baseCurrency ?? Currencies.localeDefault
        vm.aiModel = p?.aiModel ?? AIService.defaultModel
        vm.yoloMode = p?.yoloMode ?? false
        vm.critiqueMode = p?.critiqueMode ?? false
        vm.defaultAccountID = accounts.first?.id
        vm.ingestPending()
        queue.pump()
    }
}
