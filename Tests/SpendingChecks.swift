import Foundation

@main struct SpendingChecks {
    static func main() throws {
        func entry(_ title: String, _ amount: Int, _ kind: EntryKind = .expense) -> Entry {
            Entry(source: "Test", title: title, amount: amount, kind: kind, date: Date(), fingerprint: title)
        }
        let sample = [
            entry("GrabFood", 100), entry("Coffee", 50), entry("Ride to Puskesmas", 50),
            entry("Bank fee", 20), entry("Old credit bill", 1_000, .settlement),
            entry("Own transfer", 2_000, .transfer), entry("Salary", 5_000, .income),
            entry("Zero", 0)
        ]
        var uncertain = entry("Unverified card notice", 24_000, .income)
        uncertain.requiresReview = true
        let corrected = [entry("Clinic", 50_000), entry("Gym", 50_000), entry("Own wallet", 20_000, .transfer), uncertain]
        precondition(MonthlyInsight(entries: corrected).income == 0)
        precondition(MonthlyInsight(entries: corrected).purchases == 100_000)
        precondition(MonthlyInsight(entries: corrected).transfers == 20_000)
        precondition(SpendingBreakdown(entries: corrected).total == 100_000)
        let b = SpendingBreakdown(entries: sample)
        precondition(b.total == 220 && b.entries.count == 4)
        precondition(b.slices.first?.category == .food && b.slices.first?.amount == 150)
        precondition(b.category(at: 149.9) == .food)
        precondition(b.category(at: 150) == .transport)
        precondition(b.category(at: 220) == nil && b.category(at: -.infinity) == nil)
        precondition(SpendingCategory.suggested(for: "Ride to Puskesmas") == .transport)
        precondition(SpendingCategory.suggested(for: "Unknown merchant") == .other)
        precondition(SpendingCategory.suggested(for: "You spent IDR 75,000.00 at Health.") == .health)
        var adjusted = entry("GrabFood", 100)
        adjusted.category = .business
        precondition(adjusted.spendingCategory == .business)
        let restored = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(adjusted))
        precondition(restored.category == .business)
        adjusted.category = nil
        precondition(adjusted.spendingCategory == .food)
        let file = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/nonexistent-ledger")
        if FileManager.default.fileExists(atPath: file.path) {
            let legacy = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
            precondition(legacy.allSatisfy { $0.category == nil })
            let actual = SpendingBreakdown(entries: legacy)
            precondition(actual.total == legacy.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount })
            print("Legacy ledger: \(legacy.count) entries decoded; purchase total reconciles.")
        }
        precondition(SpendingBreakdown(entries: []).total == 0)
        print("PASS: classification, boundaries, exclusion of bills/transfers/income, override persistence, legacy decoding, empty state.")
    }
}
