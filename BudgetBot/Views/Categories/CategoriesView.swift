import SwiftUI
import SwiftData

/// Manage your category catalogue. Lists all `TxCategory` rows grouped
/// by kind (expense / income), lets you add your own, edit emoji /
/// name, or remove categories that you didn't create *and* aren't
/// referenced by any transaction.
///
/// Deletion safety: deleting a category is `.nullify` on the
/// `Transaction.category` relationship (Swift Data default for our
/// schema) so existing transactions lose their tag but otherwise
/// survive. The UI still warns the user when a category is in use.
struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(sort: \TxCategory.name) private var categories: [TxCategory]
    @State private var showNew = false

    var body: some View {
        List {
            Section("Expense") {
                ForEach(categories.filter { $0.kind == .expense }) { c in
                    row(c)
                }
            }
            Section("Income") {
                ForEach(categories.filter { $0.kind == .income }) { c in
                    row(c)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityIdentifier("categories.add")
            }
        }
        .sheet(isPresented: $showNew) {
            NewCategorySheet()
        }
    }

    private func row(_ c: TxCategory) -> some View {
        NavigationLink {
            EditCategorySheet(category: c)
        } label: {
            HStack {
                Text(c.emoji).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.body)
                    Text("\(c.transactions?.count ?? 0) tx")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - New

struct NewCategorySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var emoji: String = "🏷️"
    @State private var kind: CategoryKind = .expense

    /// A scattered grab-bag of category-shaped emojis — better than a
    /// freeform keyboard for the 95% case of "pick a familiar icon"
    /// while still letting the user paste any character into `emoji`
    /// via the text field.
    private let emojiChips: [String] = [
        "🏷️", "🛒", "🍔", "☕️", "🍷", "⛽️", "🚌", "🚕", "🅿️",
        "🏠", "⚡️", "🔥", "💧", "🌐", "📱", "📺", "🔁", "🛡️",
        "💊", "🩺", "💇", "🐾", "👶", "🎬", "🛍️", "👕", "🔌",
        "📚", "🎨", "✈️", "🎓", "🤝", "🎀", "💵", "💼", "📈",
        "🎁", "🏛️", "💰", "🧘", "🏋️", "🎰", "🎯", "🪴"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        Text("Expense").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Name") {
                    TextField("e.g. Pilates, Side hustle, Garden",
                              text: $name)
                }
                Section("Emoji") {
                    HStack {
                        Text(emoji).font(.system(size: 36))
                            .frame(width: 56, height: 56)
                            .background(.thinMaterial,
                                        in: RoundedRectangle(cornerRadius: 12))
                        TextField("Paste any emoji", text: $emoji)
                            .font(.title3)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))],
                              spacing: 6) {
                        ForEach(emojiChips, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.title2)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        emoji == e
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.gray.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                        .accessibilityIdentifier("categories.create")
                }
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !emoji.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Lightweight dedup — if a category with this name + kind
        // already exists, just dismiss. Avoids "Pets" / "pets" / "Pets "
        // forking.
        let existing = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
        if existing.contains(where: {
            $0.kind == kind
                && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            dismiss()
            return
        }
        let c = TxCategory(name: trimmed, kind: kind,
                           emoji: emoji.trimmingCharacters(in: .whitespaces))
        context.insert(c)
        try? context.save()
        dismiss()
    }
}

// MARK: - Edit

struct EditCategorySheet: View {
    @Bindable var category: TxCategory
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $category.name)
            }
            Section("Emoji") {
                TextField("Emoji", text: $category.emoji)
                    .font(.title3)
            }
            Section("Usage") {
                HStack {
                    Text("Transactions")
                    Spacer()
                    Text("\(category.transactions?.count ?? 0)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Section {
                Button("Delete category", role: .destructive) {
                    showDeleteConfirm = true
                }
            } footer: {
                Text("Existing transactions tagged with this category will become Uncategorised — they aren't deleted.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    try? context.save()
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(category.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(category)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing transactions keep their data — they just lose this tag.")
        }
    }
}
