import Foundation

@main struct CashBalanceChecks {
    static func main() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let bca = CashAccount(id: "mybca", name: "BCA", balanceMinor: 100_000_050, confirmedAt: t)
        let dana = CashAccount(id: "dana", name: "DANA", balanceMinor: 2_000_000, confirmedAt: t)
        func entry(_ amount: Int, _ kind: EntryKind = .expense, source: String = "myBCA", title: String = "Laundry", seconds: Double = 60) -> Entry {
            Entry(source: source, title: title, amount: amount, kind: kind, date: t.addingTimeInterval(seconds), fingerprint: UUID().uuidString)
        }
        let laundry = entry(50_000)
        let projected = CashProjection(account: bca, entries: [laundry])
        precondition(projected.estimatedMinor == 95_000_050)
        precondition(bca.balanceMinor == 100_000_050) // immutable confirmed cents
        precondition(CashProjection(account: bca, entries: [laundry]).estimatedMinor == projected.estimatedMinor)
        let old = entry(200_000, seconds: -1)
        let exact = entry(20_000, seconds: 0)
        var review = entry(24_000, .income); review.requiresReview = true
        let card = entry(12_345, source: "Grab", title: "Your Amex has been charged")
        let unknown = entry(349_000, source: "Other")
        let otherBank = entry(5_000, source: "SeaBank")
        precondition(CashProjection(account: bca, entries: [laundry,old,exact,review,card,unknown,otherBank]).estimatedMinor == 95_000_050)
        precondition(unknown.needsCashAssignment && !card.needsCashAssignment)
        var transfer = entry(100_000, .transfer)
        precondition(CashProjection(account: bca, entries: [transfer]).deltaMinor == 0)
        transfer.cashAccountID = "mybca"; transfer.destinationCashAccountID = "dana"
        precondition(CashProjection(account: bca, entries: [transfer]).deltaMinor == -10_000_000)
        precondition(CashProjection(account: dana, entries: [transfer]).deltaMinor == 10_000_000)
        let newerDana = CashAccount(id: "dana", name: "DANA", balanceMinor: 1, confirmedAt: t.addingTimeInterval(120))
        precondition(CashProjection(account: newerDana, entries: [transfer]).deltaMinor == 0)
        precondition(CashProjection(account: bca, entries: [entry(500, .income),entry(1_000,.settlement)]).deltaMinor == -50_000)
        let refreshed = CashAccount(id: "mybca", name: "BCA", balanceMinor: 95_000_050, confirmedAt: t.addingTimeInterval(120))
        precondition(CashProjection(account: refreshed, entries: [laundry]).estimatedMinor == 95_000_050)
        var explicitCard = laundry; explicitCard.cashAccountID = ""
        precondition(CashProjection(account: bca, entries: [explicitCard]).deltaMinor == 0)
        let roundtrip = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(transfer))
        precondition(roundtrip.cashAccountID == "mybca" && roundtrip.destinationCashAccountID == "dana")
        print("PASS: BCA reconciliation, cents, snapshot cutoff, immutable replay, unknown/card/review exclusions, bill cash impact, two transfer legs, mixed snapshot dates, funding persistence.")
    }
}
