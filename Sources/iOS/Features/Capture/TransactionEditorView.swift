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
    @State private var cashAccountID: String
    @State private var destinationCashAccountID: String
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
        _cashAccountID = State(initialValue: entry.cashAccountID ?? "auto")
        _destinationCashAccountID = State(initialValue: entry.destinationCashAccountID ?? "")
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
                Section("Balance impact") {
                    Picker(kind == .income ? "Money received in" : "Paid from", selection: $cashAccountID) {
                        Text("Infer from bank source / unassigned").tag("auto")
                        Text("Credit / no cash impact").tag("")
                        ForEach(ledger.cashAccounts) { Text($0.name).tag($0.id) }
                    }
                    if kind == .transfer {
                        Picker("Transfer destination", selection: $destinationCashAccountID) {
                            Text("Not assigned").tag("")
                            ForEach(ledger.cashAccounts) { Text($0.name).tag($0.id) }
                        }
                    }
                    Text("Only movements after each bank confirmation affect its estimate. Transfers need both accounts; card purchases do not reduce cash until the bill is paid.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DatePicker("Recorded at", selection: $date)
                TextField("Notes", text: $note, axis: .vertical).lineLimit(2...5)
                if let assessment = entry.categoryAssessment {
                    Section("Category context") {
                        Text(entry.categoryStatusText ?? entry.spendingCategory.title).font(.headline)
                        Text(assessment.reason).font(.caption).foregroundStyle(.secondary)
                        Button("Retry local AI with these details") {
                            saving = true
                            Task {
                                _ = await ledger.edit(entry, title: title, source: source, amount: Int(amount.filter(\.isNumber)) ?? entry.amount, kind: kind, date: date, note: note, requiresReview: requiresReview, cashAccountID: cashAccountID == "auto" ? nil : cashAccountID, destinationCashAccountID: destinationCashAccountID.isEmpty ? nil : destinationCashAccountID)
                                await ledger.retryCategory(entry.fingerprint)
                                saving = false
                                dismiss()
                            }
                        }.disabled(saving)
                    }
                }
                if let context = LocalNotificationContext.shared.text(for: entry.fingerprint) {
                    DisclosureGroup("Original notification · only on this device") { Text(context).font(.caption).textSelection(.enabled) }
                }
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
                            let saved = await ledger.edit(entry, title: title, source: source, amount: value, kind: kind, date: date, note: note, requiresReview: requiresReview, cashAccountID: cashAccountID == "auto" ? nil : cashAccountID, destinationCashAccountID: kind == .transfer && !destinationCashAccountID.isEmpty ? destinationCashAccountID : nil)
                            saving = false
                            if saved { dismiss() }
                        }
                    }.disabled(saving || Int(amount.filter(\.isNumber)) == nil || title.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 600, height: 740)
        #endif
    }
}
