import SwiftUI
import WatchConnectivity

@main struct CurrentWatchApp: App {
    @StateObject private var store = WatchSummaryStore()
    var body: some Scene {
        WindowGroup { WatchHome().environmentObject(store) }
    }
}

final class WatchSummaryStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var summary: WatchSummary?
    @Published var connected = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        receive(WCSession.default.receivedApplicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.connected = activationState == .activated }
        receive(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context["summary"] as? Data, let value = try? JSONDecoder().decode(WatchSummary.self, from: data) else { return }
        DispatchQueue.main.async { self.summary = value }
    }
}

private let currentMint = Color(red: 0.55, green: 1, blue: 0.82)

struct WatchHome: View {
    @EnvironmentObject private var store: WatchSummaryStore
    private func rupiah(_ amount: Int) -> String { "Rp " + amount.formatted(.number.grouping(.automatic)) }
    private func rupiahMinor(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = amount % 100 == 0 ? 0 : 2
        formatter.maximumFractionDigits = 2
        return "Rp" + (formatter.string(from: NSDecimalNumber(decimal: Decimal(amount) / 100)) ?? "0")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary = store.summary {
                        Text(summary.month.uppercased()).font(.caption2.bold()).tracking(1.5).foregroundStyle(currentMint)
                        if let cash = summary.confirmedCashMinor {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("YOUR MONEY · LAST KNOWN").font(.caption2.bold()).tracking(1).foregroundStyle(currentMint)
                                Text(rupiahMinor(cash)).font(.system(size: 21, weight: .bold, design: .rounded))
                                    .minimumScaleFactor(0.6).lineLimit(1)
                                if let date = summary.cashConfirmedAt {
                                    Text("Oldest balance: \(date.formatted(.dateTime.day().month(.abbreviated))) · not live")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SPENT").font(.caption2.bold()).tracking(2).foregroundStyle(currentMint)
                            Text(rupiah(summary.spent)).font(.system(size: 25, weight: .bold, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(currentMint.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
                        let flow = summary.earned - summary.spent - summary.settled
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CASH FLOW").font(.caption2.bold()).tracking(1.5).foregroundStyle(currentMint)
                            Text((flow >= 0 ? "+" : "−") + rupiah(abs(flow)))
                                .font(.headline).monospacedDigit()
                            Text("Income − spent − bills").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                        metric("Income", summary.earned, "arrow.down.left", .cyan)
                        metric("Bills paid", summary.settled, "checkmark.seal", .purple)
                        metric("Moved", summary.moved, "arrow.left.arrow.right", .orange)
                        if !summary.recent.isEmpty {
                            Text("RECENT").font(.caption2.bold()).tracking(1.5).foregroundStyle(.secondary)
                            ForEach(summary.recent) { entry in
                                HStack {
                                    Text(entry.title).lineLimit(1)
                                    Spacer(minLength: 3)
                                    Text(rupiah(entry.amount)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                }.font(.caption2)
                            }
                        }
                        Text("Updated from paired iPhone · \(summary.updatedAt.formatted(.dateTime.hour().minute()))")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.title2).foregroundStyle(currentMint)
                        Text("Open Current on your paired iPhone to sync this watch.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 8).padding(.vertical, 10)
            }
            .background(Color(red: 0.035, green: 0.075, blue: 0.105))
            .navigationTitle("Current")
        }
    }

    private func metric(_ title: String, _ value: Int, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(rupiah(value)).lineLimit(1).minimumScaleFactor(0.7)
        }.font(.caption).padding(11).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
