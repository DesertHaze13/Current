import SwiftUI

private let macInk = Color(red: 0.035, green: 0.075, blue: 0.105)
private let macMint = Color(red: 0.55, green: 1, blue: 0.82)

struct MacContentView: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAdd = false
    @State private var page: CurrentPage = .home
    @State private var showSettings = false
    @State private var editingCashAccount: CashAccount?
    @State private var filter: EntryKind?
    private var accent: Color { colorScheme == .dark ? macMint : Color(red: 0.02, green: 0.42, blue: 0.36) }
    private var canvas: Color { colorScheme == .dark ? macInk : Color(red: 0.945, green: 0.975, blue: 0.975) }
    private var surface: Color { colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.9) }

    private var months: [Date] {
        var seen = Set<String>()
        let dates = ledger.entries.map(\.date) + [.now]
        return dates.sorted(by: >).filter { seen.insert($0.formatted(.dateTime.year().month())).inserted }
    }
    private var visible: [Entry] {
        ledger.monthEntries.filter { filter == nil || $0.kind == filter }
    }

    var body: some View {
        NavigationSplitView {
            List {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT").font(.system(size: 15, weight: .black, design: .rounded)).tracking(3).foregroundStyle(accent)
                    Text("Make room for life.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
                Section("Explore") {
                    ForEach(CurrentPage.allCases) { destination in
                        Button(destination.rawValue, systemImage: destination.symbol) { page = destination }
                            .listRowBackground(page == destination ? Color.indigo.opacity(0.14) : .clear)
                    }
                }
                Section("Months") {
                    ForEach(months, id: \.self) { month in
                        Button {
                            ledger.selectedMonth = month
                            filter = nil
                        } label: {
                            Label(month.formatted(.dateTime.month(.wide).year()), systemImage: "calendar")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Calendar.current.isDate(month, equalTo: ledger.selectedMonth, toGranularity: .month) ? accent.opacity(0.15) : .clear)
                    }
                }
                Section("Account") {
                    Button("App settings", systemImage: "slider.horizontal.3") { showSettings = true }
                    Text(ledger.syncStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
        } detail: {
            Group {
                switch page {
                case .home:
                    CurrentOverview(editAccount: { editingCashAccount = $0 }, openActivity: { filter = $0; page = .activity }, openSpending: { page = .spending }, add: { showAdd = true })
                case .spending: SpendingExplorerView()
                case .activity: CurrentActivity(kind: $filter)
                case .profile: CurrentProfileView(openSettings: { showSettings = true })
                }
            }
            .toolbar {
                Button("Sync", systemImage: "arrow.triangle.2.circlepath") { Task { await ledger.refresh() } }
                Button("Add movement", systemImage: "plus") { showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) { MacAddView().environmentObject(ledger) }
        .sheet(isPresented: $showSettings) { MacSettingsView().environmentObject(ledger) }
        .sheet(item: $editingCashAccount) { account in MacCashAccountEditor(account: account).environmentObject(ledger) }
        .alert("Current", isPresented: Binding(get: { ledger.errorMessage != nil }, set: { if !$0 { ledger.errorMessage = nil } })) {
            Button("OK") { ledger.errorMessage = nil }
        } message: { Text(ledger.errorMessage ?? "") }
        .task { await ledger.refresh() }
    }

}

private struct MacAddView: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    @State private var source = "Manual"
    @State private var note = ""
    @State private var title = ""
    @State private var amount = ""
    @State private var kind: EntryKind = .expense
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CurrentCaptureWelcome(title: "A new money moment", subtitle: "A purchase, an income, or just moving your own money?")
            Form {
                TextField("Description", text: $title)
                TextField("Amount in rupiah", text: $amount)
                TextField("Source", text: $source)
                Picker("Movement", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { item in Text(item.title).tag(item) }
                }
                DatePicker("Date", selection: $date)
                TextField("Notes", text: $note)
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    guard let value = Int(amount.filter(\.isNumber)), value > 0 else {
                        ledger.errorMessage = "Enter an amount greater than zero."
                        return
                    }
                    let item = Entry(source: source, title: title.isEmpty ? kind.title : title,
                                     amount: value, kind: kind, date: date, fingerprint: UUID().uuidString, note: note)
                    Task { await ledger.add(item); if ledger.errorMessage == nil { dismiss() } }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 460, height: 460)
    }
}

private struct MacCashAccountEditor: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    let account: CashAccount
    @State private var amount = ""
    @State private var confirmedAt = Date()
    @State private var invalidAmount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Update \(account.name)").font(.title2.bold())
            Text("Only money you own is included. Credit limits, paylater and reward points stay out.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                TextField("Confirmed balance in rupiah", text: $amount)
                DatePicker("Confirmed at", selection: $confirmedAt)
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    guard let minor = CashAccount.parseRupiah(amount) else { invalidAmount = true; return }
                    Task { await ledger.updateCashAccount(id: account.id, balanceMinor: minor, at: confirmedAt); dismiss() }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 420, height: 265)
            .alert("Enter a valid balance", isPresented: $invalidAmount) { Button("OK") {} }
            .onAppear {
                amount = CashAccount.rupiah(account.balanceMinor)
                confirmedAt = account.confirmedAt
            }
    }
}

private struct MacSettingsView: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var balance = ""
    @State private var balanceDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CurrentCaptureWelcome(title: "Make yourself at home.", subtitle: "Your account, your devices, your money.")
            Form {
                Section("Your account & sync") {
                    Text(ledger.hasFirebaseConfig ? "Cloud sync is ready" : "Cloud sync needs configuration")
                    if ledger.isSignedIn {
                        Text("Signed in as \(ledger.accountEmail)")
                        Button("Sync now") { Task { await ledger.refresh() } }
                    } else {
                        TextField("Email", text: $email)
                        SecureField("Password", text: $password)
                        HStack {
                            Button("Sign in") { Task { await ledger.signIn(email: email, password: password, create: false); password = "" } }
                            Button("Create account") { Task { await ledger.signIn(email: email, password: password, create: true); password = "" } }
                        }
                    }
                    Text(ledger.syncStatus).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Advanced: net position estimate") {
                    TextField("Starting total in rupiah", text: $balance)
                    DatePicker("As of", selection: $balanceDate)
                    Button("Save snapshot") {
                        guard let amount = Int(balance.filter(\.isNumber)) else { ledger.errorMessage = "Enter a balance."; return }
                        Task { await ledger.setBalanceSnapshot(amount: balance.contains("-") ? -amount : amount, date: balanceDate) }
                    }
                    Text("This older estimate is separate from the confirmed own-money banner. Update individual accounts from the expanded banner.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                    }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Done") { dismiss() } }
        }.padding(24).frame(width: 520, height: 550)
            .onAppear {
                email = ledger.accountEmail
                if let snapshot = ledger.balanceSnapshot { balance = String(snapshot.amount); balanceDate = snapshot.date }
            }
    }
}
