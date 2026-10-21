import SwiftUI

struct TransactionEditorView: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    @State private var title: String
    @State private var source: String
    @State private var amount: String
    @State private var kind: EntryKind
    @State private var date: Date
    @State private var note: String
    @State private var saving = false
    @State private var requiresReview: Bool

    init(entry: Entry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _source = State(initialValue: entry.source)
        _amount = State(initialValue: String(entry.amount))
        _kind = State(initialValue: entry.kind)
        _date = State(initialValue: entry.date)
        _note = State(initialValue: entry.note)
        _requiresReview = State(initialValue: !entry.isConfirmed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CurrentCaptureWelcome(title: "Every detail matters.", subtitle: "Keep this money moment clear and accurate.")
                }
                TextField("Description", text: $title)
                TextField("Amount in rupiah", text: $amount)
                TextField("Source", text: $source)
                Picker("Movement", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                }
                DatePicker("Recorded at", selection: $date)
                TextField("Notes", text: $note, axis: .vertical).lineLimit(2...5)
                Toggle("Needs review — exclude from totals", isOn: $requiresReview)
                Text("Changing a source or movement corrects this record. It does not create another transaction or replace a confirmed bank balance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Edit transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = Int(amount.filter(\.isNumber)), value > 0,
                              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        saving = true
                        Task {
                            let saved = await ledger.edit(entry, title: title, source: source, amount: value, kind: kind, date: date, note: note, requiresReview: requiresReview)
                            saving = false
                            if saved { dismiss() }
                        }
                    }.disabled(saving || Int(amount.filter(\.isNumber)) == nil || title.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 550)
        #endif
    }
}
