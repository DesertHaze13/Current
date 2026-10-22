import SwiftUI
import Charts

extension SpendingCategory {
    var color: Color {
        switch self {
        case .food: return Color(red: 0.94, green: 0.40, blue: 0.35)
        case .transport: return Color(red: 0.20, green: 0.57, blue: 0.95)
        case .services: return Color(red: 0.52, green: 0.42, blue: 0.91)
        case .subscriptions: return Color(red: 0.85, green: 0.35, blue: 0.67)
        case .shopping: return Color(red: 0.83, green: 0.55, blue: 0.12)
        case .health: return Color(red: 0.15, green: 0.65, blue: 0.51)
        case .home: return Color(red: 0.14, green: 0.63, blue: 0.69)
        case .giving: return Color(red: 0.76, green: 0.39, blue: 0.43)
        case .business: return Color(red: 0.38, green: 0.49, blue: 0.83)
        case .fees: return Color(red: 0.52, green: 0.55, blue: 0.60)
        case .entertainment: return Color(red: 0.71, green: 0.45, blue: 0.92)
        case .other: return Color(red: 0.42, green: 0.57, blue: 0.55)
        }
    }
}

/// Genuine Liquid Glass on supported OS versions; material fallback for older installs.
struct SpendingGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
    }
}

struct SpendingExplorerView: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: SpendingCategory?
    @State private var angle: Double?
    @State private var orbit = true
    @State private var sortByCount = false
    @State private var hovered: SpendingCategory?
    @State private var sourceFilter: String?

    private var breakdown: SpendingBreakdown { SpendingBreakdown(entries: ledger.monthEntries.filter { sourceFilter == nil || $0.source == sourceFilter }) }
    private var activeSlice: SpendingSlice? { breakdown.slices.first { $0.category == selected } }
    private var visibleEntries: [Entry] {
        breakdown.entries.filter { selected == nil || $0.spendingCategory == selected }
            .sorted { $0.date > $1.date }
    }
    private var previous: SpendingBreakdown {
        let date = Calendar.current.date(byAdding: .month, value: -1, to: ledger.selectedMonth) ?? ledger.selectedMonth
        return SpendingBreakdown(entries: ledger.entries.filter { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month) && (sourceFilter == nil || $0.source == sourceFilter) })
    }
    private var accent: Color { selected?.color ?? .teal }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.76) }
    private var ranked: [SpendingSlice] {
        sortByCount ? breakdown.slices.sorted { $0.count == $1.count ? $0.amount > $1.amount : $0.count > $1.count } : breakdown.slices
    }

    var body: some View {
        GeometryReader { layout in
        ZStack {
                CurrentCanvas()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                        CategoryAIPanel()
                        CurrentMonthControl()
                        Picker("Source", selection: $sourceFilter) {
                            Text("All sources").tag(String?.none)
                            ForEach(Array(Set(ledger.entries.filter { $0.kind == .expense }.map(\.source))).sorted(), id: \.self) { source in
                                Text(source).tag(String?.some(source))
                            }
                        }.pickerStyle(.menu)
                        if let selected {
                            Button { withAnimation(motion) { self.selected = nil; angle = nil } } label: {
                                Label("Show every category", systemImage: "arrow.uturn.backward").font(.subheadline.bold())
                            }.buttonStyle(CurrentPress()).tint(selected.color)
                        }
                        if breakdown.total == 0 {
                            ContentUnavailableView("No spending recorded", systemImage: "chart.pie",
                                description: Text("Purchases for this month will appear here. Transfers and payments of old bills are excluded."))
                                .frame(minHeight: 330)
                        } else {
                            if layout.size.width >= 1250 {
                                HStack(alignment: .top, spacing: 22) {
                                    chartCard.frame(width: 370)
                                    categoryCard.frame(width: 310)
                                    detailCard.frame(maxWidth: .infinity)
                                }
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .top, spacing: 24) {
                                        chartCard.frame(width: 370)
                                        categoryCard.frame(minWidth: 300, maxWidth: .infinity)
                                    }
                                    VStack(spacing: 22) { chartCard; categoryCard }
                                }
                                detailCard
                            }
                        }
                        Text("Recorded purchases only. Transfers, income and repayments of old bills are excluded. Categories are suggested from descriptions; you can change any transaction below.")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }.padding(22).frame(maxWidth: 1600).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Spending")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .animation(motion, value: selected)
            .animation(motion, value: orbit)
            .onChange(of: angle) { _, value in
                guard let value else { return }
                let next = breakdown.category(at: value)
                if next != selected { withAnimation(motion) { selected = next } }
            }
            .onChange(of: sourceFilter) { _, _ in selected = nil; angle = nil }
            .onChange(of: ledger.selectedMonth) { _, _ in selected = nil; angle = nil }
            .onChange(of: ledger.entries) { _, _ in
                if let selected, !breakdown.slices.contains(where: { $0.category == selected }) {
                    self.selected = nil; angle = nil
                }
            }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: selected)
            #endif
        }
        .frame(minWidth: 300)
    }

    private var heading: some View {
        CurrentPageTitle(eyebrow: "FOLLOW YOUR CURIOSITY", title: "Every slice has a story.", subtitle: "Tap or drag around the ring. Pick a color to discover the purchases inside.")
    }
    private var monthControl: some View {
        HStack(spacing: 10) {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }.accessibilityLabel("Previous month")
            Spacer()
            Text(ledger.selectedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline).contentTransition(.numericText())
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }.accessibilityLabel("Next month")
        }.buttonStyle(.plain).padding(6).modifier(SpendingGlass())
    }
    private func moveMonth(_ value: Int) {
        withAnimation(motion) {
            ledger.selectedMonth = Calendar.current.date(byAdding: .month, value: value, to: ledger.selectedMonth) ?? ledger.selectedMonth
            selected = nil; angle = nil
        }
    }

    private var chartCard: some View {
        VStack(spacing: 18) {
            HStack {
                Label(selected?.title ?? "All purchases", systemImage: selected?.symbol ?? "chart.pie.fill")
                    .font(.subheadline.bold()).foregroundStyle(accent)
                Spacer(minLength: 8)
                Button { withAnimation(motion) { orbit.toggle() } } label: {
                    Image(systemName: orbit ? "circle.lefthalf.filled" : "circle.circle")
                        .frame(width: 36, height: 36).background(accent.opacity(0.1), in: Circle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(orbit ? "Switch to pie chart" : "Switch to donut chart")
                    .help("Switch between pie and donut")
            }
            Chart(breakdown.slices) { slice in
                SectorMark(
                    angle: .value("Spending", slice.amount),
                    innerRadius: .ratio(orbit ? 0.66 : 0),
                    outerRadius: .ratio(selected == nil || selected == slice.category ? 0.98 : 0.86),
                    angularInset: min(3, CGFloat(slice.amount) / CGFloat(max(1, breakdown.total)) * 360 * 0.16)
                )
                .cornerRadius(7)
                .foregroundStyle(slice.category.color.gradient)
                .opacity(selected == nil || selected == slice.category ? 1 : 0.42)
                .accessibilityLabel(slice.category.title)
                .accessibilityValue("\(slice.amount.rupiah), \(percent(slice.amount)) percent, \(slice.count) transactions")
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $angle)
            .frame(height: 290)
            .overlay {
                if orbit {
                    VStack(spacing: 6) {
                        Image(systemName: selected?.symbol ?? "waveform.path")
                            .font(.title2).foregroundStyle(accent)
                        Text((activeSlice?.amount ?? breakdown.total).rupiah)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6).lineLimit(1).contentTransition(.numericText())
                        Text(activeSlice.map { "\(percent($0.amount))% of spending" } ?? "\(breakdown.entries.count) purchases")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(8).frame(width: 160).allowsHitTesting(false)
                }
            }
            .shadow(color: accent.opacity(scheme == .dark ? 0.25 : 0.12), radius: 18, y: 8)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected == nil ? "TOTAL PURCHASES" : "SELECTED CATEGORY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(.secondary)
                    Text((activeSlice?.amount ?? breakdown.total).rupiah)
                        .font(.system(size: 24, weight: .bold, design: .rounded)).contentTransition(.numericText())
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Show all") { selected = nil; angle = nil }
                    .font(.caption.bold()).disabled(selected == nil)
            }
            Divider()
            comparison
        }.padding(20).modifier(SpendingGlass())
    }

    private var comparison: some View {
        let currentAmount = activeSlice?.amount ?? breakdown.total
        let priorAmount = selected.flatMap { category in previous.slices.first { $0.category == category }?.amount } ?? (selected == nil ? previous.total : 0)
        return VStack(alignment: .leading, spacing: 5) {
            if let top = breakdown.slices.first {
                Text("\(top.category.title) leads · \(percent(top.amount))%")
                    .font(.subheadline.bold())
            }
            if priorAmount > 0 {
                let delta = currentAmount - priorAmount
                Text("\(delta >= 0 ? "↑" : "↓") \(abs(delta).rupiah) vs previous month")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No recorded purchases for this selection last month.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("This month so far compared with the entire previous month.")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your categories").font(.title3.bold())
                Spacer()
                Menu {
                    Button("Highest amount") { sortByCount = false }
                    Button("Most transactions") { sortByCount = true }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 32, height: 32)
                }.menuStyle(.borderlessButton).accessibilityLabel("Sort categories")
            }
            ForEach(ranked) { slice in
                Button {
                    withAnimation(motion) { selected = selected == slice.category ? nil : slice.category; angle = nil }
                } label: {
                    categoryRow(slice)
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? slice.category : nil }
                .accessibilityLabel("\(slice.category.title), \(slice.amount.rupiah), \(percent(slice.amount)) percent, \(slice.count) purchases")
                .accessibilityAddTraits(selected == slice.category ? .isSelected : [])
            }
        }.padding(20).modifier(SpendingGlass())
    }
    private func categoryRow(_ slice: SpendingSlice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: slice.category.symbol)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(slice.category.color)
                .frame(width: 42, height: 42).background(slice.category.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                .scaleEffect(selected == slice.category ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(slice.category.title).font(.subheadline.bold())
                    Spacer()
                    Text("\(percent(slice.amount))%").font(.caption.bold()).foregroundStyle(slice.category.color)
                }
                GeometryReader { proxy in
                    Capsule().fill(slice.category.color.opacity(0.12))
                    Capsule().fill(slice.category.color.gradient)
                        .frame(width: max(3, proxy.size.width * Double(slice.amount) / Double(max(1, breakdown.total))))
                }.frame(height: 4)
                HStack {
                    Text("\(slice.count) \(slice.count == 1 ? "purchase" : "purchases")").foregroundStyle(.secondary)
                    Spacer()
                    Text(slice.amount.rupiah).bold().monospacedDigit()
                }.font(.caption)
            }
        }.padding(10)
            .background(slice.category.color.opacity(selected == slice.category || hovered == slice.category ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(slice.category.color.opacity(selected == slice.category ? 0.35 : 0), lineWidth: 1))
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.map { "\($0.title) · details" } ?? "Every purchase").font(.title3.bold())
                    Text("\(visibleEntries.count) recorded · change a category using its menu")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected?.symbol ?? "list.bullet").foregroundStyle(accent)
            }
            ForEach(visibleEntries) { entry in
                VStack(alignment: .leading, spacing: 9) {
                    CurrentMovementRow(entry: entry)
                    HStack {
                        Spacer()
                        Menu {
                            Button("Use automatic category") { Task { await ledger.updateCategory(entry, category: nil) } }
                            Divider()
                            ForEach(SpendingCategory.allCases) { category in
                                Button {
                                    Task { await ledger.updateCategory(entry, category: category) }
                                } label: { Label(category.title, systemImage: category.symbol) }
                            }
                        } label: {
                            Label("\(entry.category == nil ? "Suggested" : "Chosen"): \(entry.spendingCategory.title)", systemImage: "slider.horizontal.3")
                                .font(.caption).foregroundStyle(entry.spendingCategory.color)
                        }.menuStyle(.borderlessButton)
                    }
                    Divider()
                }.id(entry.fingerprint)
            }
        }.padding(20).modifier(SpendingGlass())
    }

    private func percent(_ amount: Int) -> String {
        (Double(amount) / Double(max(1, breakdown.total)) * 100)
            .formatted(.number.precision(.fractionLength(1)))
    }
}

/// Shared inline workspace on iPhone, iPad and native Mac.
struct CategoryAIPanel: View {
    @EnvironmentObject private var ledger: Ledger
    @StateObject private var ai = CategoryAI()
    @State private var included = Set<String>()
    @State private var applying = false
    @State private var result: String?
    private var changes: [CategoryProposal] { ai.proposals.filter(\.changesCategory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A fresh perspective.").font(.headline)
                    Text("Review categories across every month.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("On-device AI and merchant checks review transaction titles, sources and notes. Preview changes before applying; amounts and account balances stay the same.")
                .font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { scanButton; undoButton }
                VStack(alignment: .leading) { scanButton; undoButton }
            }
            if let reason = ai.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            if ai.scanning {
                ProgressView(value: Double(ai.progress), total: Double(max(1, ai.total)))
                HStack {
                    Text("Reviewed \(ai.progress) of \(ai.total) purchases…").font(.caption).monospacedDigit()
                    Spacer()
                    Button("Cancel") { ai.cancel() }
                }
            }
            if let message = ai.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let result { Text(result).font(.subheadline.bold()).foregroundStyle(.teal).accessibilityAddTraits(.updatesFrequently) }
            if !ai.proposals.isEmpty {
                Text("\(changes.count) suggested changes · \(ai.proposals.count - changes.count) kept as before")
                    .font(.subheadline.bold())
                DisclosureGroup("See categories kept as before") {
                    ForEach(ai.proposals.filter { !$0.changesCategory }) { proposal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(proposal.original.title).font(.caption.bold()).lineLimit(2)
                            Text(proposal.suggested.title + " · " + proposal.reason).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                }
                if !changes.isEmpty {
                    DisclosureGroup("Review suggested changes") {
                        ForEach(changes) { proposal in
                            Toggle(isOn: Binding(get: { included.contains(proposal.id) }, set: { value in
                                if value { included.insert(proposal.id) } else { included.remove(proposal.id) }
                            })) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(proposal.original.title).font(.subheadline.bold()).lineLimit(2)
                                    Text("\(proposal.original.spendingCategory.title) → \(proposal.suggested.title)")
                                        .font(.caption).foregroundStyle(proposal.suggested.color)
                                    Text(proposal.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 7).disabled(applying)
                        }
                    }
                    HStack {
                        Button("Apply \(included.count) changes") {
                            applying = true
                            Task {
                                let expected = included.count
                                let count = await ledger.applyCategoryProposals(changes.filter { included.contains($0.id) })
                                result = "Applied \(count) categories." + (count < expected ? " Some records changed since scanning; scan again to review them." : " Undo is available.")
                                ai.proposals = []; included = []; applying = false
                            }
                        }.buttonStyle(.borderedProminent).disabled(included.isEmpty || applying)
                        Button("Discard") { ai.proposals = []; included = []; result = "Kept your previous categories." }.disabled(applying)
                    }
                }
            }
            if let batch = ledger.latestCategoryBatch {
                DisclosureGroup("Undo individual AI changes") {
                    ForEach(ledger.entries.filter { $0.categoryRevision?.batchID == batch.batchID }) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.title).lineLimit(1)
                                Text(entry.spendingCategory.title).foregroundStyle(.secondary)
                            }.font(.caption)
                            Spacer()
                            Button("Undo") { Task { await ledger.undoCategoryBatch(batch.batchID, fingerprint: entry.fingerprint) } }
                                .disabled(applying || ai.scanning)
                        }.padding(.vertical, 4)
                    }
                }.font(.caption)
            }
        }.padding(22).modifier(SpendingGlass())
            .onChange(of: ai.proposals.map { $0.id + $0.suggested.rawValue }) { _, _ in included = Set(changes.map(\.id)) }
            .onDisappear { ai.cancel() }
    }
    private var scanButton: some View {
        Button {
            result = nil
            Task { await ledger.refresh(); ai.scan(ledger.entries) }
        } label: { Label(ai.scanning ? "Scanning…" : "Sync with AI", systemImage: "sparkles") }
            .buttonStyle(.borderedProminent).tint(.indigo)
            .disabled(ai.scanning || applying || ai.unavailableReason != nil || ledger.entries.isEmpty)
    }
    @ViewBuilder private var undoButton: some View {
        if let batch = ledger.latestCategoryBatch {
            Button { Task { await ledger.undoCategoryBatch(batch.batchID); result = "Restored the previous categories." } }
            label: { Label("Undo last AI update", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.bordered).disabled(ai.scanning || applying)
        }
    }
}
