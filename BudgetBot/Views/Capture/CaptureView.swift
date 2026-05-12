import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase)   private var scenePhase
    @Environment(FXService.self) private var fx

    @Query(filter: #Predicate<Account> { !$0.archived }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(filter: #Predicate<Transaction> { $0.confirmed }, sort: \Transaction.date, order: .reverse)
    private var existing: [Transaction]

    @State private var vm = CaptureViewModel()
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showPDFImporter = false
    @State private var photoSelection: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ZStack {
                switch vm.stage {
                case .idle, .error:
                    inputContent
                case .extracting:
                    extractingView
                case .review(let drafts, let dupes):
                    ReviewExtractionView(
                        drafts: drafts,
                        duplicates: dupes,
                        accounts: accounts,
                        onConfirm: { confirmed, defaultAccount in
                            let cats = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
                            let base = profiles.first?.baseCurrency ?? profiles.first?.defaultCurrency ?? "USD"
                            vm.commit(
                                drafts: confirmed,
                                defaultAccount: defaultAccount,
                                accounts: accounts,
                                categories: cats,
                                baseCurrency: base,
                                fxRates: fx.rates,
                                in: context
                            )
                        },
                        onCancel: { vm.reset() }
                    )
                }
            }
            .navigationTitle("Capture")
            .onAppear { hydrate() }
            .onChange(of: scenePhase) { _, new in
                if new == .active { vm.ingestPending() }
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

    private func hydrate() {
        vm.defaultCurrency = profiles.first?.defaultCurrency ?? "USD"
        vm.aiModel = profiles.first?.aiModel ?? AIService.defaultModel
        vm.ingestPending()
    }

    private var extractingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Asking the AI…").foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) { vm.cancel() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
    }

    private var inputContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Snap, scan, attach a PDF, or just type what happened — the AI will turn it into transactions you can review.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Use the buttons below to add receipts, photos, PDFs or text")

                actionTiles

                if !vm.images.isEmpty {
                    sectionLabel("Photos (\(vm.images.count))")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(vm.images.enumerated()), id: \.offset) { idx, img in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 160)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .accessibilityLabel("Photo \(idx + 1) of \(vm.images.count)")
                                    Button {
                                        vm.images.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .padding(6)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .accessibilityLabel("Remove photo \(idx + 1)")
                                }
                            }
                        }
                    }
                }

                if !vm.pdfs.isEmpty {
                    sectionLabel("PDFs (\(vm.pdfs.count))")
                    VStack(alignment: .leading, spacing: 8) {
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
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                sectionLabel("Or describe it")
                TextEditor(text: $vm.textNote)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Description of the transaction")

                if case .error(let msg) = vm.stage {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(msg)")
                }

                Button {
                    Task {
                        await vm.extract(accounts: accounts, existing: existing)
                    }
                } label: {
                    Text("Extract with AI")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.hasInput)
                .accessibilityHint("Sends your attachments and notes to the AI for parsing")

                if vm.hasInput {
                    Button(role: .destructive) {
                        vm.reset()
                    } label: {
                        Text("Clear").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    private var actionTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile(title: "Scan Receipt", icon: "doc.viewfinder.fill") { showScanner = true }
            tile(title: "Camera", icon: "camera.fill") { showCamera = true }
            PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                tileLabel(title: "Photos", icon: "photo.on.rectangle.angled")
            }
            .accessibilityLabel("Pick photos from your library")
            tile(title: "Add PDF", icon: "doc.fill") { showPDFImporter = true }
        }
    }

    @ViewBuilder
    private func tile(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title: title, icon: icon) }
            .buttonStyle(.plain)
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

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.subheadline.bold()).foregroundStyle(.secondary)
    }
}
