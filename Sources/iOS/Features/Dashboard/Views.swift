import SwiftUI
import Combine
import UIKit

private let ink = Color(red: 0.035, green: 0.075, blue: 0.105)
private let glow = Color(red: 0.55, green: 1, blue: 0.82)

struct RootView: View {
    @EnvironmentObject var ledger: Ledger
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAdd = false
    @State private var page: CurrentPage = .home
    @State private var showSettings = false
    @State private var showIcon = false
    @State private var editingCashAccount: CashAccount?
    @State private var selectedKind: EntryKind? = nil
    private var isDark: Bool { colorScheme == .dark }
    private var navigationAccent: Color {
        isDark ? Color(red: 0.73, green: 0.66, blue: 1) : Color(red: 0.39, green: 0.28, blue: 0.85)
    }
    private var canvas: Color { isDark ? ink : Color(red: 0.945, green: 0.975, blue: 0.975) }
    private var surface: Color { isDark ? .white.opacity(0.07) : .white.opacity(0.88) }
    private var line: Color { isDark ? .white.opacity(0.11) : ink.opacity(0.09) }
    private var accent: Color { isDark ? glow : Color(red: 0.02, green: 0.42, blue: 0.36) }
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                NavigationSplitView {
                    List {
                        Section {
                            Text("CURRENT").font(.system(.title3, design: .rounded, weight: .black)).tracking(3).foregroundStyle(.indigo).padding(.vertical, 16)
                        }
                        Section("Explore") {
                            ForEach(CurrentPage.allCases) { destination in
                                Button(destination.rawValue, systemImage: destination.symbol) { page = destination }
                                    .listRowBackground(page == destination ? Color.indigo.opacity(0.14) : .clear)
                            }
                        }
                        Section("Your space") {
                            Button("Add a money moment", systemImage: "plus.circle.fill") { showAdd = true }
                            Button("App settings", systemImage: "slider.horizontal.3") { showSettings = true }
                            Button("Icon playground", systemImage: "sparkles") { showIcon = true }
                        }
                        Text(ledger.syncStatus).font(.caption).foregroundStyle(.secondary)
                    }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                } detail: {
                    NavigationStack {
                        pageContent.toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showAdd = true } label: { Image(systemName: "plus") }
                                    .buttonBorderShape(.circle)
                                    .tint(navigationAccent)
                                    .accessibilityLabel("Add a money moment")
                            }
                        }
                    }
                }
            } else {
                nativeTabs(availableWidth: geometry.size.width)
            }
        }
        .sheet(isPresented: $showAdd) { AddView().environmentObject(ledger) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(ledger) }
        .sheet(isPresented: $showIcon) { IconComposerView() }
        .sheet(item: $editingCashAccount) { account in CashAccountEditor(account: account).environmentObject(ledger) }
        .alert("Current", isPresented: Binding(get: { ledger.errorMessage != nil }, set: { if !$0 { ledger.errorMessage = nil } })) {
            Button("OK") { ledger.errorMessage = nil }
        } message: { Text(ledger.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await ledger.refresh() } } }
        .onAppear { WatchSummaryBridge.shared.publish(entries: ledger.entries, cashAccounts: ledger.cashAccounts) }
        .onReceive(ledger.$entries) { WatchSummaryBridge.shared.publish(entries: $0, cashAccounts: ledger.cashAccounts) }
        .onReceive(ledger.$cashAccounts) { WatchSummaryBridge.shared.publish(entries: ledger.entries, cashAccounts: $0) }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active && ledger.isSignedIn { Task { await ledger.refresh() } }
        }
    }
    @ViewBuilder private func nativeTabs(availableWidth: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            NavigationStack { pageContent }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing: 8) {
                        CurrentNativePageBar(selection: $page, tint: navigationAccent)
                            .frame(width: max(180, availableWidth - 96), height: 64)
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass(.regular.tint(Color(red: 0.47, green: 0.34, blue: 0.91)).interactive()))
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(Color(red: isDark ? 0.49 : 0.39, green: isDark ? 0.36 : 0.28, blue: isDark ? 0.95 : 0.85))
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("Add a money moment")
                        .accessibilityHint("Opens a new transaction")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
        } else {
            TabView(selection: $page) {
                ForEach(CurrentPage.allCases) { destination in
                    NavigationStack {
                        content(for: destination)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button { showAdd = true } label: { Image(systemName: "plus") }
                                        .tint(navigationAccent)
                                        .accessibilityLabel("Add a money moment")
                                }
                            }
                    }
                    .tabItem { Label(destination.rawValue, systemImage: destination.symbol) }
                    .tag(destination)
                }
            }.tint(navigationAccent)
        }
    }

    private var pageContent: some View { content(for: page) }
    @ViewBuilder private func content(for destination: CurrentPage) -> some View {
        switch destination {
        case .home: CurrentOverview(editAccount: { editingCashAccount = $0 }, openActivity: { selectedKind = $0; page = .activity }, openSpending: { page = .spending }, add: { showAdd = true })
        case .spending: SpendingExplorerView()
        case .activity: CurrentActivity(kind: $selectedKind)
        case .profile: CurrentProfileView(openSettings: { showSettings = true })
        }
    }

}

/// A public UIKit tab bar retains Apple's item rendering, hit testing and accessibility.
/// Add is a separate prominent glass Button, so its whole surface can carry the brand tint.
private struct CurrentNativePageBar: UIViewRepresentable {
    @Binding var selection: CurrentPage
    let tint: Color

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeUIView(context: Context) -> UITabBar {
        let bar = CurrentInsetFreeTabBar()
        bar.directionalLayoutMargins = .zero
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.items = CurrentPage.allCases.enumerated().map { index, page in
            UITabBarItem(title: page.rawValue, image: UIImage(systemName: page.symbol), tag: index)
        }
        return bar
    }
    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        bar.tintColor = UIColor(tint)
        if let index = CurrentPage.allCases.firstIndex(of: selection), let items = bar.items {
            bar.selectedItem = items[index]
        }
    }
    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<CurrentPage>
        init(selection: Binding<CurrentPage>) { self.selection = selection }
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard CurrentPage.allCases.indices.contains(item.tag) else { return }
            selection.wrappedValue = CurrentPage.allCases[item.tag]
        }
    }
}

/// SwiftUI already places the dock above the home-indicator safe area. Allowing
/// UITabBar to inset itself again compresses icons and labels inside the capsule.
private final class CurrentInsetFreeTabBar: UITabBar {
    override var safeAreaInsets: UIEdgeInsets { .zero }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 64) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: 64) }
}

struct EntryRow: View {
    @EnvironmentObject var ledger: Ledger
    let entry: Entry
    @State private var editing = false
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: entry.kind.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(entry.kind.tint)
                .frame(width: 46, height: 46).background(entry.kind.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.source).font(.system(size: 14, weight: .bold))
                Text(entry.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if !entry.isConfirmed { Text(entry.isTemporaryAuthorization ? "Temporary authorization · not deducted · excluded from totals" : "Needs review · excluded from totals").font(.caption).foregroundStyle(.orange) }
                if !entry.note.isEmpty {
                    Text(entry.note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 3)
            Text((entry.isTemporaryAuthorization ? "Hold " : entry.kind == .expense ? "−" : entry.kind == .income ? "+" : entry.kind == .settlement ? "✓" : "↔") + entry.amount.rupiah)
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(entry.kind.tint).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(13).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .sheet(isPresented: $editing) { TransactionEditorView(entry: entry).environmentObject(ledger) }
            .contextMenu {
                Button("Edit details", systemImage: "pencil") { editing = true }
                ForEach(EntryKind.allCases, id: \.self) { kind in Button("Mark as \(kind.title)") { Task { await ledger.update(entry, kind: kind) } } }
                Button("Delete", role: .destructive) { Task { await ledger.remove(entry) } }
            }
    }
}

struct PulseOrb: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().stroke(glow.opacity(0.55), lineWidth: 1).scaleEffect(pulse ? 1.3 : 0.7).opacity(pulse ? 0 : 1)
            Circle().fill(RadialGradient(colors: [Color.white, glow, Color.teal.opacity(0.4)], center: .init(x: 0.35, y: 0.32), startRadius: 1, endRadius: 35)).padding(11)
                .shadow(color: glow.opacity(0.65), radius: 17)
        }.onAppear { withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulse = true } }
    }
}
