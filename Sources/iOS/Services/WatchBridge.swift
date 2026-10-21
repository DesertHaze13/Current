import Foundation
import WatchConnectivity

final class WatchSummaryBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSummaryBridge()
    private var pendingContext: [String: Any]?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(entries: [Entry], cashAccounts: [CashAccount]) {
        guard WCSession.isSupported() else { return }
        let monthEntries = entries.filter { $0.isConfirmed && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
        var summary = WatchSummary(
            month: Date.now.formatted(.dateTime.month(.wide).year()),
            spent: monthEntries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount },
            earned: monthEntries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount },
            settled: monthEntries.filter { $0.kind == .settlement }.reduce(0) { $0 + $1.amount },
            moved: monthEntries.filter { $0.kind == .transfer }.reduce(0) { $0 + $1.amount },
            updatedAt: .now,
            recent: monthEntries.sorted { $0.date > $1.date }.prefix(5).map {
                WatchMovement(id: $0.fingerprint, title: $0.title, amount: $0.amount, kind: $0.kind.rawValue)
            }
        )
        summary.confirmedCashMinor = cashAccounts.reduce(0) { $0 + $1.balanceMinor }
        summary.cashConfirmedAt = cashAccounts.map(\.confirmedAt).filter { $0 > .distantPast }.min()
        guard let data = try? JSONEncoder().encode(summary) else { return }
        pendingContext = ["summary": data]
        sendPendingContext()
    }

    private func sendPendingContext() {
        guard WCSession.default.activationState == .activated,
              let pendingContext else { return }
        do {
            try WCSession.default.updateApplicationContext(pendingContext)
            self.pendingContext = nil
        } catch {
            // Keep the most recent month summary for the next activation.
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.sendPendingContext() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
