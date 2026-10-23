import SwiftUI
#if os(iOS)
import UIKit
#endif

enum CurrentPage: String, CaseIterable, Identifiable {
    case home = "Home", spending = "Spending", activity = "Activity", profile = "Profile"
    var id: String { rawValue }
    var symbol: String { switch self { case .home: "square.stack.3d.up.fill"; case .spending: "chart.pie.fill"; case .activity: "clock.arrow.circlepath"; case .profile: "person.crop.circle.fill" } }
}

/// Match the published visual reference: warm paper with distinct pastel fields.
/// Decorations remain behind the content and do not participate in hit testing.
struct CurrentCanvas: View {
    @Environment(\.colorScheme) private var scheme
    private var paper: Color {
        scheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.105) : Color(red: 249.0 / 255, green: 248.0 / 255, blue: 244.0 / 255)
    }
    private var lavender: Color {
        scheme == .dark ? Color(red: 0.14, green: 0.11, blue: 0.20) : Color(red: 246.0 / 255, green: 238.0 / 255, blue: 242.0 / 255)
    }
    private var mint: Color {
        scheme == .dark ? Color(red: 0.075, green: 0.15, blue: 0.14) : Color(red: 237.0 / 255, green: 244.0 / 255, blue: 239.0 / 255)
    }
    var body: some View {
        GeometryReader { geometry in
            let upperDiameter = min(600, max(300, geometry.size.width * 0.36))
            let lowerDiameter = min(520, max(280, geometry.size.width * 0.32))
            ZStack {
                paper
                Circle().fill(lavender)
                    .frame(width: upperDiameter, height: upperDiameter)
                    .position(x: geometry.size.width - upperDiameter * 0.20, y: upperDiameter * 0.16)
                Circle().fill(mint)
                    .frame(width: lowerDiameter, height: lowerDiameter)
                    .position(x: -lowerDiameter * 0.10, y: geometry.size.height * 0.62)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CurrentSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(22).background(scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(.primary.opacity(0.055), lineWidth: 1))
    }
}

struct CurrentPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduced ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduced ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct CurrentPageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(2.5).foregroundStyle(.secondary)
            Text(title).font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CurrentMonthControl: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous month")
            Spacer(minLength: 0)
            Text(ledger.selectedMonth.formatted(.dateTime.month(.wide).year())).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(scheme == .dark ? Color.white : Color.black).contentTransition(.numericText())
            Spacer(minLength: 0)
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next month")
        }.buttonStyle(CurrentPress()).foregroundStyle(.primary).padding(4).modifier(SpendingGlass())
    }
    private func move(_ direction: Int) {
        withAnimation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
            ledger.selectedMonth = Calendar.current.date(byAdding: .month, value: direction, to: ledger.selectedMonth) ?? ledger.selectedMonth
        }
    }
}

/// A tactile illustration. Its motion is decorative; it does not encode a balance or a score.
struct CurrentSculpture: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var turned = false
    let symbol: String
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 0.65, dampingFraction: 0.45)) { turned.toggle() } } label: {
            ZStack {
                Circle().fill(.white.opacity(0.10)).frame(width: 126, height: 126)
                RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.72, green: 0.91, blue: 0.48).gradient)
                    .frame(width: 78, height: 96).rotationEffect(.degrees(turned ? 25 : -19)).offset(x: -15, y: -5)
                RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [.white.opacity(0.85), Color(red: 0.68, green: 0.58, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 96).rotationEffect(.degrees(turned ? -19 : 17)).offset(x: 14, y: 5)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 8)
                Image(systemName: symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(Color(red: 0.22, green: 0.13, blue: 0.43))
                    .offset(x: 14, y: 5).rotationEffect(.degrees(turned ? -19 : 17))
            }.rotation3DEffect(.degrees(reduced ? 0 : turned ? 12 : -7), axis: (x: 0.3, y: 1, z: 0)).frame(width: 140, height: 140)
        }.buttonStyle(CurrentPress()).accessibilityLabel("Play with the wallet illustration")
            .accessibilityHint("Tilts the illustration. Your financial data stays the same.")
    }
}

struct CurrentOverview: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.accessibilityReduceMotion) private var reduced
    let editAccount: (CashAccount) -> Void
    let openActivity: (EntryKind?) -> Void
    let openSpending: () -> Void
    let add: () -> Void
    @State private var walletsOpen = false
    @State private var hidden = false
    @State private var story = 0
    private var insight: MonthlyInsight { ledger.monthlyInsight }
    private var top: SpendingSlice? { SpendingBreakdown(entries: ledger.monthEntries).slices.first }
    private var isTablet: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isTablet {
                        // Keep widget identity and column count stable when the native
                        // sidebar changes the content width. AnyLayout preserves state.
                        let wide = geometry.size.width >= 620
                        let header = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                        header {
                            welcome
                            CurrentMonthControl().frame(width: wide ? 290 : nil)
                        }
                        let dashboard = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 22)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
                        dashboard {
                            VStack(spacing: 22) { wallet; discovery }.frame(maxWidth: .infinity)
                            VStack(spacing: 22) { monthStory; latest }.frame(maxWidth: .infinity)
                        }
                    } else if geometry.size.width >= 780 {
                        HStack(alignment: .center, spacing: 24) {
                            welcome
                            CurrentMonthControl().frame(width: 290)
                        }
                        if geometry.size.width >= 1220 {
                            HStack(alignment: .top, spacing: 22) {
                                VStack(spacing: 22) { wallet; discovery }.frame(maxWidth: .infinity)
                                monthStory.frame(maxWidth: .infinity)
                                latest.frame(maxWidth: .infinity)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 22) {
                                VStack(spacing: 22) { wallet; discovery }.frame(maxWidth: .infinity)
                                VStack(spacing: 22) { monthStory; latest }.frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        welcome
                        CurrentMonthControl()
                        wallet
                        monthStory
                        discovery
                        latest
                    }
                    Button { Task { await ledger.refresh() } } label: {
                        Label(ledger.syncStatus, systemImage: ledger.syncStatus == "Firebase synced" ? "checkmark.icloud" : "arrow.triangle.2.circlepath").font(.caption).frame(maxWidth: .infinity).padding(8)
                    }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityHint("Refresh your records")
                }.padding(isTablet ? 28 : geometry.size.width >= 780 ? 28 : 22).frame(maxWidth: 1600).frame(maxWidth: .infinity)
            }
        }.background(CurrentCanvas()).buttonStyle(CurrentPress())
    }
    private var welcome: some View {
        CurrentPageTitle(eyebrow: "CURRENT / YOUR MONEY, IN MOTION", title: "Make room for life.", subtitle: "A clearer picture. One small money moment at a time.")
    }
    private var latest: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your latest moments").font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Button("See all") { openActivity(nil) }.font(.subheadline.bold())
            }
            if ledger.monthEntries.isEmpty {
                Button(action: add) { Label("Add your first money moment", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(25) }
            } else {
                ForEach(ledger.monthEntries.prefix(5)) { CurrentMovementRow(entry: $0) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var wallet: some View {
        VStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Money you own", systemImage: "sparkle").font(.subheadline.bold())
                    Text("Estimated cash from bank confirmations.\nNo credit limits.").font(.caption).foregroundStyle(.white.opacity(0.78))
                }
                Spacer(minLength: 4)
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye").frame(width: 44, height: 44) }
                    .accessibilityLabel(hidden ? "Show balances" : "Hide balances")
                CurrentSculpture(symbol: "wallet.bifold.fill").scaleEffect(0.72).frame(width: 90, height: 90)
            }
            Text(hidden ? "••••••" : CashAccount.rupiah(ledger.projectedCashMinor))
                .font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.5).lineLimit(1).minimumScaleFactor(0.55).contentTransition(.numericText())
            Text("Confirmed total " + (hidden ? "••••" : CashAccount.rupiah(ledger.confirmedCashMinor)))
                .font(.caption).foregroundStyle(.white.opacity(0.78))
            Text(ledger.cashSnapshotSummary).font(.caption2.bold()).foregroundStyle(.white.opacity(0.78))
            Button { withAnimation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { walletsOpen.toggle() } } label: {
                HStack {
                    HStack(spacing: -5) {
                        ForEach(Array(ledger.cashAccounts.prefix(4).enumerated()), id: \.element.id) { index, account in
                            Text(String(account.name.prefix(1))).font(.caption2.bold()).frame(width: 26, height: 26)
                                .background([Color.indigo, .teal, .orange, .pink][index], in: Circle()).overlay(Circle().stroke(.white.opacity(0.5)))
                        }
                    }
                    Text(walletsOpen ? "Tuck away accounts" : "Where is my money?").font(.caption.bold())
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(walletsOpen ? 180 : 0))
                }.padding(13).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            }.accessibilityHint("Expand balances for each bank and wallet")
        }.foregroundStyle(.white).padding(23)
            .background(LinearGradient(colors: [Color(red: 0.32, green: 0.24, blue: 0.63), Color(red: 0.13, green: 0.16, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 34))
            .shadow(color: .indigo.opacity(0.18), radius: 18, y: 12)
                if walletsOpen {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(ledger.cashAccounts) { account in
                            let projection = CashProjection(account: account, entries: ledger.entries)
                            Button { editAccount(account) } label: {
                                VStack(spacing: 7) {
                                    HStack {
                                        Text(account.name).font(.subheadline.bold()); Spacer()
                                        Text(hidden ? "••••" : CashAccount.rupiah(projection.estimatedMinor)).font(.subheadline.bold()).monospacedDigit()
                                        Image(systemName: "pencil.circle").foregroundStyle(.secondary)
                                    }
                                    GeometryReader { proxy in
                                        Capsule().fill(.indigo.opacity(0.09))
                                        Capsule().fill(.indigo.gradient).frame(width: proxy.size.width * CGFloat(max(0, min(1, Double(account.balanceMinor) / Double(max(1, ledger.confirmedCashMinor))))))
                                    }.frame(height: 5).accessibilityHidden(true)
                                    Text("Confirmed " + (hidden ? "••••" : CashAccount.rupiah(account.balanceMinor)) + " · " + String(projection.movements.count) + " later movements")
                                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(account.confirmedAt == .distantPast ? "Not set · tap to update" : account.confirmedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.buttonStyle(CurrentPress())
                            if !projection.movements.isEmpty {
                                DisclosureGroup("Balance calculation · " + account.name) {
                                    ForEach(projection.movements, id: \.entry.fingerprint) { movement in
                                        HStack {
                                            Text(movement.entry.title).lineLimit(2)
                                            Spacer()
                                            Text(hidden ? "••••" : CashAccount.rupiah(movement.deltaMinor)).monospacedDigit()
                                        }.font(.caption).padding(.vertical, 3)
                                    }
                                }.font(.caption)
                            }
                        }
                        if !ledger.unassignedCashEntries.isEmpty {
                            Text("\(ledger.unassignedCashEntries.count) recent movements need a funding account. Estimates may be incomplete.")
                                .font(.caption.bold()).foregroundStyle(.orange)
                            ForEach(ledger.unassignedCashEntries) { entry in
                                CurrentMovementRow(entry: entry)
                            }
                        }
                        Text("Estimates apply only assigned movements after each confirmation. Tap an account to confirm a newer bank balance; tap a transaction to assign its funding account. Unassigned movements and missing bank activity can leave a difference.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.modifier(CurrentSurface()).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
    }
    private var monthStory: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("The month, made simple").font(.system(.title3, design: .rounded, weight: .bold)); Spacer()
                Image(systemName: insight.net < 0 ? "cloud.sun.fill" : "sun.max.fill").symbolRenderingMode(.multicolor).font(.title2)
            }
            Picker("Money story", selection: $story) { Text("Flow").tag(0); Text("Health").tag(1); Text("Carryover").tag(2) }.pickerStyle(.segmented)
            if story == 0 {
                Text(insight.income == 0 ? "Your income is still missing." : insight.net < 0 ? "More going out than coming in." : "You have a little breathing room.")
                    .font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text((insight.net < 0 ? "−" : "+") + abs(insight.net).rupiah).font(.system(size: 30, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text("Recorded income − purchases − bills paid").font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    flowLine("In", amount: insight.income, color: .teal, kind: .income)
                    flowLine("Spent", amount: insight.purchases, color: .pink, kind: .expense)
                    flowLine("Bills paid", amount: insight.billsPaid, color: .indigo, kind: .settlement)
                }
                Text("Tap a row to see its records. Moving your own money is excluded.").font(.caption).foregroundStyle(.secondary)
            } else if story == 1 {
                Label(insight.verdict, systemImage: insight.net < 0 ? "umbrella.fill" : "leaf.fill").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(insight.net < 0 ? .orange : .teal)
                Text(insight.guidance).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let retained = insight.retainedRate {
                    Text("\(Int((retained * 100).rounded()))% retained after recorded outflows").font(.subheadline.bold())
                }
                Text("A snapshot of recorded cash flow, not a grade for you. Older savings can fund this month's spending; missing records change the result.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Last month still matters.").font(.system(.title2, design: .rounded, weight: .bold))
                if let opening = ledger.trackedOpening, let closing = ledger.trackedClosing {
                    storyLine("Brought forward", opening); storyLine("This month's change", insight.net); Divider(); storyLine("Tracked remainder", closing)
                } else { Text("Add earlier income and transactions to begin your money trail.").foregroundStyle(.secondary) }
                Text("Starts at your earliest recorded income. A transaction trail is different from a bank balance: earlier funds and missing records are unknown.").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(CurrentSurface())
    }
    private func storyLine(_ text: String, _ amount: Int) -> some View {
        HStack { Text(text).foregroundStyle(.secondary); Spacer(); Text(amount.rupiah).bold().monospacedDigit() }.font(.subheadline)
    }
    private func flowLine(_ title: String, amount: Int, color: Color, kind: EntryKind) -> some View {
        Button { openActivity(kind) } label: {
            VStack(spacing: 7) {
                HStack { Text(title); Spacer(); Text(amount.rupiah).bold().monospacedDigit(); Image(systemName: "arrow.up.right").font(.caption) }.font(.subheadline)
                GeometryReader { proxy in
                    Capsule().fill(color.opacity(0.1))
                    Capsule().fill(color.gradient).frame(width: proxy.size.width * CGFloat(Double(amount) / Double(max(1, max(insight.income, max(insight.purchases, insight.billsPaid))))))
                }.frame(height: 6).accessibilityHidden(true)
            }.padding(.vertical, 5)
        }.buttonStyle(CurrentPress()).foregroundStyle(.primary)
    }
    private var discovery: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("Follow your curiosity").font(.system(.title3, design: .rounded, weight: .bold))
            Button(action: openSpending) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Image(systemName: top?.category.symbol ?? "chart.pie.fill").font(.system(size: 36)).foregroundStyle(top?.category.color ?? .purple); Spacer(); Image(systemName: "arrow.up.right.circle.fill").font(.title) }
                    Text(top.map { "\($0.category.title) leads the way." } ?? "Every slice tells a story.").font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.leading)
                    Text(top.map { "\($0.amount.rupiah) · \($0.count) purchases" } ?? "Your spending categories will grow here.").font(.subheadline)
                    Label("Play with your spending", systemImage: "hand.draw.fill").font(.caption.bold())
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background((top?.category.color ?? .purple).opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(CurrentPress()).foregroundStyle(.primary)
            Button { openActivity(.transfer) } label: { Label("\(ledger.moved.rupiah) moved, not spent", systemImage: "arrow.left.arrow.right").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
            let reviews = ledger.monthEntries.filter { !$0.isConfirmed }.count
            if reviews > 0 {
                Button { openActivity(nil) } label: { Label("\(reviews) record\(reviews == 1 ? " needs" : "s need") a second look", systemImage: "questionmark.bubble.fill").font(.subheadline.bold()).foregroundStyle(.orange) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(CurrentSurface())
    }
}

struct CurrentMovementRow: View {
    @EnvironmentObject private var ledger: Ledger
    let entry: Entry
    var onSelect: ((Entry) -> Void)? = nil
    @State private var editing = false
    private var color: Color { entry.kind == .expense ? entry.spendingCategory.color : entry.kind == .income ? .teal : entry.kind == .transfer ? .orange : .indigo }
    private var title: String {
        if entry.title.localizedCaseInsensitiveContains("has been charged") { return "\(entry.source) card payment" }
        return entry.title
    }
    var body: some View {
        Button { if let onSelect { onSelect(entry) } else { editing = true } } label: {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: entry.kind == .expense ? entry.spendingCategory.symbol : entry.kind.symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 46, height: 46).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(entry.source) · \(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))").font(.caption2).foregroundStyle(.secondary)
                    if let status = entry.categoryStatusText { Text(status).font(.caption2).foregroundStyle(.secondary) }
                    if !entry.isConfirmed { Text(entry.isTemporaryAuthorization ? "Temporary authorization · not deducted · outside totals" : "Needs review · outside totals").font(.caption2.bold()).foregroundStyle(.orange) }
                }
                Spacer(minLength: 2)
                Text((entry.isTemporaryAuthorization ? "Hold " : entry.kind == .income ? "+" : entry.kind == .expense ? "−" : entry.kind == .transfer ? "↔ " : "✓ ") + entry.amount.rupiah)
                    .font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }.padding(15).background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 23)).contentShape(RoundedRectangle(cornerRadius: 23))
        }.buttonStyle(CurrentPress()).foregroundStyle(.primary).accessibilityHint("Open transaction details and edit")
            .sheet(isPresented: $editing) { TransactionEditorView(entry: entry).environmentObject(ledger) }
            .contextMenu {
                Button("Edit details", systemImage: "pencil") { editing = true }
                ForEach(EntryKind.allCases, id: \.self) { kind in
                    Button("Mark as \(kind.title)") { Task { await ledger.update(entry, kind: kind) } }
                }
                Button("Delete", role: .destructive) { Task { await ledger.remove(entry) } }
            }
    }
}

struct CurrentActivity: View {
    @EnvironmentObject private var ledger: Ledger
    @Binding var kind: EntryKind?
    @State private var search = ""
    @State private var reviewOnly = false
    @State private var selection: String?
    private var results: [Entry] {
        ledger.monthEntries.filter { (kind == nil || $0.kind == kind) && (!reviewOnly || !$0.isConfirmed) && (search.isEmpty || ($0.title + " " + $0.source + " " + String($0.amount)).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        CurrentPageTitle(eyebrow: "THE DETAILS / ALL IN ONE PLACE", title: "Little moments. Real life.", subtitle: "Find a payment, follow a transfer, or give a record a second look.")
                        CurrentMonthControl()
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find merchant, bank, or amount", text: $search)
                            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                        }.padding(16).modifier(SpendingGlass())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { filter("All", nil); ForEach(EntryKind.allCases, id: \.self) { filter($0 == .settlement ? "Bills paid" : $0.title, $0) } }
                        }
                        Toggle("Only records needing review", isOn: $reviewOnly).font(.caption).toggleStyle(.switch)
                        HStack { Text("\(results.count) moments").font(.headline); Spacer(); Text(geometry.size.width >= 980 ? "Select a record to inspect" : "Tap any record to edit").font(.caption).foregroundStyle(.secondary) }
                        if results.isEmpty { ContentUnavailableView("Nothing here yet", systemImage: "sparkle.magnifyingglass", description: Text("Try another search, filter, or month.")) }
                        ForEach(results) { entry in
                            if geometry.size.width >= 980 {
                                CurrentMovementRow(entry: entry, onSelect: { selection = $0.fingerprint })
                                    .overlay(RoundedRectangle(cornerRadius: 23).stroke(selection == entry.fingerprint ? Color.indigo.opacity(0.6) : .clear, lineWidth: 2))
                            } else { CurrentMovementRow(entry: entry) }
                        }
                        Text("Transfers move money between your accounts. Bills paid settle earlier debt. Neither counts as a new purchase.").font(.caption).foregroundStyle(.secondary)
                    }.padding(24)
                }.frame(maxWidth: .infinity)
                if geometry.size.width >= 980 {
                    Divider()
                    CurrentTransactionInspector(entry: ledger.entries.first { $0.fingerprint == selection }).frame(width: 330).padding(22)
                }
            }
        }.background(CurrentCanvas()).onChange(of: ledger.selectedMonth) { _, _ in selection = nil }
    }
    private func filter(_ name: String, _ value: EntryKind?) -> some View {
        Button { kind = value } label: {
            Text(name).font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 44)
                .background(kind == value ? Color.indigo.opacity(0.18) : Color.secondary.opacity(0.07), in: Capsule())
        }.buttonStyle(CurrentPress()).foregroundStyle(.primary).accessibilityAddTraits(kind == value ? .isSelected : [])
    }
}

struct CurrentTransactionInspector: View {
    @EnvironmentObject private var ledger: Ledger
    let entry: Entry?
    @State private var editing = false
    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 20) {
                    Text("TRANSACTION DETAIL").font(.caption2.bold()).tracking(2).foregroundStyle(.secondary)
                    Image(systemName: entry.kind == .expense ? entry.spendingCategory.symbol : entry.kind.symbol)
                        .font(.system(size: 34)).foregroundStyle(.indigo).padding(20).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
                    Text(entry.amount.rupiah).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Text(entry.title).font(.headline).textSelection(.enabled)
                    LabeledContent("Account", value: entry.source)
                    LabeledContent("Movement", value: entry.kind.title)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if !entry.isConfirmed { Label("Needs review · excluded from totals", systemImage: "questionmark.circle.fill").foregroundStyle(.orange) }
                    if !entry.note.isEmpty { Divider(); Text(entry.note).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                    Button { editing = true } label: { Label("Edit this moment", systemImage: "pencil").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.borderedProminent).tint(.indigo)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("A closer look", systemImage: "cursorarrow.click.2", description: Text("Select a money moment to keep its details beside your activity."))
            }
        }.sheet(isPresented: $editing) { if let entry { TransactionEditorView(entry: entry).environmentObject(ledger) } }
    }
}

struct CurrentCaptureWelcome: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "viewfinder.circle.fill").font(.system(size: 44)).symbolRenderingMode(.palette).foregroundStyle(.indigo, .indigo.opacity(0.12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.title2, design: .rounded, weight: .bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

struct CurrentProfileView: View {
    @EnvironmentObject private var ledger: Ledger
    let openSettings: () -> Void
    private var profile: GoogleProfile? { ledger.googleProfile }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    CurrentPageTitle(eyebrow: "YOUR SPACE / PERSONALLY YOURS", title: "Hello, \(firstName).", subtitle: "Your profile, your connected account, your money story.")
                    if geometry.size.width >= 800 {
                        HStack(alignment: .top, spacing: 24) { identity.frame(width: 350); controls.frame(maxWidth: .infinity) }
                    } else { identity; controls }
                }.padding(24).frame(maxWidth: 1150).frame(maxWidth: .infinity)
            }
        }.background(CurrentCanvas()).task { await ledger.refreshGoogleProfile(force: true) }
    }
    private var firstName: String { profile?.name.split(separator: " ").first.map(String.init) ?? "you" }
    private var identity: some View {
        VStack(spacing: 19) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: profile?.photoURL) { image in image.resizable().scaledToFill() } placeholder: {
                    ZStack {
                        LinearGradient(colors: [.indigo.opacity(0.8), .purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        if let name = profile?.name { Text(String(name.prefix(1))).font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(.white) }
                        else { Image(systemName: "person.crop.circle.fill").font(.system(size: 70)).foregroundStyle(.white.opacity(0.9)) }
                    }
                }.frame(width: 112, height: 112).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 4))
                Image(systemName: profile == nil ? "person.fill.questionmark" : "checkmark.seal.fill")
                    .font(.title2).foregroundStyle(profile == nil ? Color.secondary : Color.teal).padding(5).background(.regularMaterial, in: Circle())
            }.accessibilityLabel(profile == nil ? "Google profile not connected" : "Google profile photo")
            VStack(spacing: 7) {
                Text(profile?.name ?? "Your profile").font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                if !(profile?.email ?? ledger.accountEmail).isEmpty {
                    Text(profile?.email ?? ledger.accountEmail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Label(profile == nil ? "Connect your Google identity" : "Profile from Google", systemImage: profile == nil ? "link" : "checkmark.shield.fill")
                    .font(.caption.bold()).foregroundStyle(profile == nil ? Color.secondary : .teal)
            }
            Divider()
            if profile == nil {
                Text("Bring your name and photo from Google. Your Current history stays with the same account.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                Button { Task { await ledger.connectGoogleProfile() } } label: {
                    HStack { if ledger.connectingGoogle { ProgressView().controlSize(.small) }; Text(ledger.isSignedIn ? "Connect Google profile" : "Continue with Google").font(.subheadline.bold()) }
                        .frame(maxWidth: .infinity).padding(12)
                }.buttonStyle(.borderedProminent).tint(.indigo).disabled(ledger.connectingGoogle)
            } else {
                Button { Task { await ledger.refreshGoogleProfile(force: true) } } label: { Label("Refresh Google profile", systemImage: "arrow.clockwise").frame(minHeight: 44) }.buttonStyle(.bordered)
            }
            if let message = ledger.profileMessage {
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            } else if profile == nil, let setup = ledger.googleConfigurationMessage {
                Label("Google connection needs setup", systemImage: "wrench.and.screwdriver").font(.caption.bold()).foregroundStyle(.orange)
                Text(setup).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity).modifier(CurrentSurface())
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 15) {
                Label("One account. Your devices.", systemImage: "person.crop.circle.badge.checkmark").font(.system(.title3, design: .rounded, weight: .bold))
                Text(ledger.isSignedIn ? "Your financial records belong to your existing Current account. Connecting Google keeps that account and history together." : "Sign in to Current to sync your financial records across your devices.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label(ledger.syncStatus, systemImage: "icloud").font(.subheadline.bold())
                Button { Task { await ledger.refresh() } } label: { Label("Sync my records", systemImage: "arrow.triangle.2.circlepath").frame(minHeight: 44) }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(CurrentSurface())
            VStack(alignment: .leading, spacing: 15) {
                Label("Only what makes it yours", systemImage: "hand.raised.fill").font(.system(.title3, design: .rounded, weight: .bold))
                Text("Google supplies your basic profile: name, email, and photo. This connection does not request access to Gmail messages, contacts, Drive, or bank accounts.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: openSettings) { Label("App settings & account access", systemImage: "slider.horizontal.3").frame(minHeight: 44) }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(CurrentSurface())
        }
    }
}
