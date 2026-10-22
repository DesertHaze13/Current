import SwiftUI

private let macInk = Color(red: 0.035, green: 0.075, blue: 0.105)
private let macMint = Color(red: 0.55, green: 1, blue: 0.82)

struct MacContentView: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sidebarSelection
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
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 300)
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

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Button { select(.home) } label: { MacSidebarBrand() }
                        .buttonStyle(.plain).accessibilityLabel("Current home")
                    VStack(alignment: .leading, spacing: 7) {
                        sidebarHeading("WORKSPACE", detail: "⌘ 1–4")
                        ForEach(Array(CurrentPage.allCases.enumerated()), id: \.element.id) { index, destination in
                            MacSidebarItem(title: destination.rawValue, subtitle: sidebarSubtitle(destination),
                                symbol: destination.symbol, colors: sidebarColors(destination), selected: page == destination,
                                selectionID: "workspace", namespace: sidebarSelection) { select(destination) }
                                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                                .help("\(destination.rawValue) · Command-\(index + 1)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        sidebarHeading("TIMELINE", detail: "\(months.count) months")
                        ForEach(months, id: \.self) { month in
                            let count = ledger.entries.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }.count
                            MacSidebarItem(title: month.formatted(.dateTime.month(.wide)),
                                subtitle: month.formatted(.dateTime.year()) + " · \(count) records",
                                symbol: "calendar", colors: [.teal, .cyan],
                                selected: Calendar.current.isDate(month, equalTo: ledger.selectedMonth, toGranularity: .month),
                                selectionID: "timeline", namespace: sidebarSelection, compact: true) {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                                    ledger.selectedMonth = month; filter = nil
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 15).padding(.top, 25).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
            VStack(spacing: 12) {
                MacSidebarSyncCard(status: ledger.syncStatus, signedIn: ledger.isSignedIn) {
                    if ledger.isSignedIn { Task { await ledger.refresh() } }
                    else { select(.profile) }
                }
                Button { showSettings = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .medium))
                        Text("App settings").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "gearshape").font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(MacSidebarPress()).help("Open Current settings")
            }.padding(.horizontal, 17).padding(.bottom, 17)
        }
        .background {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: colorScheme == .dark ? [.indigo.opacity(0.17), .clear, .teal.opacity(0.08)] : [.white.opacity(0.48), .indigo.opacity(0.045), .mint.opacity(0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.purple.opacity(colorScheme == .dark ? 0.17 : 0.10))
                    .frame(width: 180, height: 180).blur(radius: 65).offset(x: -75, y: 30)
            }.ignoresSafeArea()
        }
    }
    private func select(_ destination: CurrentPage) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { page = destination }
    }
    private func sidebarHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.8)
            Spacer()
            Text(detail).font(.system(size: 9, weight: .medium)).monospacedDigit()
        }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 5)
    }
    private func sidebarSubtitle(_ destination: CurrentPage) -> String {
        switch destination {
        case .home: "Your financial overview"
        case .spending: "Discover every category"
        case .activity: "Follow your money"
        case .profile: "Your personal space"
        }
    }
    private func sidebarColors(_ destination: CurrentPage) -> [Color] {
        switch destination {
        case .home: [.indigo, .purple]
        case .spending: [.pink, .orange]
        case .activity: [.teal, .cyan]
        case .profile: [.blue, .indigo]
        }
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


private struct MacSidebarItem: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    let selected: Bool
    let selectionID: String
    let namespace: Namespace.ID
    var compact = false
    let action: () -> Void
    @State private var hovering = false
    private var accent: Color { colors.first ?? .indigo }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 14 : 18, weight: .semibold))
                    .foregroundStyle(compact ? accent : .white)
                    .frame(width: compact ? 30 : 38, height: compact ? 30 : 38)
                    .background {
                        if compact { RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.10)) }
                        else {
                            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.26), lineWidth: 0.7))
                                .shadow(color: accent.opacity(selected || hovering ? 0.30 : 0.08), radius: hovering ? 10 : 5, y: 4)
                        }
                    }
                    .rotation3DEffect(.degrees(hovering && !reduced ? -10 : 0), axis: (x: 0, y: 1, z: 0))
                    .scaleEffect(hovering && !reduced ? 1.06 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: compact ? 12 : 13, weight: selected ? .bold : .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "circle.fill" : "chevron.right")
                    .font(.system(size: selected ? 5 : 9, weight: .bold))
                    .foregroundStyle(accent)
                    .opacity(selected || hovering ? 1 : 0)
                    .offset(x: hovering && !reduced ? 2 : 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, compact ? 9 : 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(LinearGradient(colors: [accent.opacity(scheme == .dark ? 0.24 : 0.13), accent.opacity(0.035)], startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(accent.opacity(0.18), lineWidth: 0.7))
                        .matchedGeometryEffect(id: selectionID, in: namespace)
                } else {
                    RoundedRectangle(cornerRadius: 17).fill(.primary.opacity(hovering ? 0.045 : 0))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(MacSidebarPress())
        .onHover { value in withAnimation(reduced ? nil : .spring(response: 0.32, dampingFraction: 0.75)) { hovering = value } }
        .accessibilityLabel(title + ", " + subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MacSidebarPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduced ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduced ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private struct MacSidebarBrand: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 17).fill(.indigo.opacity(0.16)).frame(width: 48, height: 48).rotationEffect(.degrees(hovering && !reduced ? -20 : -12))
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 43, height: 43)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: .indigo.opacity(0.28), radius: hovering ? 14 : 8, y: 5)
                Image(systemName: "waveform.path").font(.system(size: 23, weight: .medium)).foregroundStyle(.white)
                    .rotationEffect(.degrees(hovering && !reduced ? -8 : 0))
                Circle().fill(.mint.gradient).frame(width: 11, height: 11).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5)).offset(x: 20, y: -19)
            }.frame(width: 53, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT").font(.system(size: 16, weight: .black, design: .rounded)).tracking(2)
                Text("Your money, in motion.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.bottom, 4)
        .onHover { value in withAnimation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { hovering = value } }
    }
}

private struct MacSidebarSyncCard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let status: String
    let signedIn: Bool
    let sync: () -> Void
    @State private var hovering = false
    private var syncing: Bool { status == "Syncing…" }
    private var connected: Bool { status == "Firebase synced" }
    var body: some View {
        Button(action: sync) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill((connected ? Color.teal : Color.orange).opacity(0.13)).frame(width: 33, height: 33)
                    if syncing { ProgressView().controlSize(.small) }
                    else { Image(systemName: connected ? "checkmark.icloud" : "icloud.slash").font(.system(size: 15)).foregroundStyle(connected ? .teal : .orange) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(connected ? "All caught up" : syncing ? "Syncing your ledger" : signedIn ? "Check connection" : "Saved on this Mac").font(.system(size: 11, weight: .semibold))
                    Text(status).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(hovering && !reduced ? 30 : 0))
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.60), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(hovering ? 0.12 : 0.055), lineWidth: 0.8))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(MacSidebarPress()).disabled(syncing)
            .help(signedIn ? "Refresh your Firebase ledger" : "Sign in from Profile to sync your ledger")
            .onHover { value in withAnimation(reduced ? nil : .easeOut(duration: 0.2)) { hovering = value } }
    }
}
