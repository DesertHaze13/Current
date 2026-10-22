import Foundation

@main struct CategoryBatchChecks {
    static func main() throws {
        let original = Entry(source: "Other", title: "Laundry", amount: 50_000, kind: .expense, date: .now, fingerprint: "laundry")
        var explicit = Entry(source: "Other", title: "Internet package", amount: 30_000, kind: .expense, date: .now, fingerprint: "byu")
        explicit.category = .shopping
        var entries = [original, explicit]
        let proposals = [CategoryProposal(original: original, suggested: .home, reason: "test"), CategoryProposal(original: explicit, suggested: .home, reason: "Data plan")]
        let changed = CategoryBatch.apply(proposals, to: &entries)
        precondition(changed.count == 2)
        precondition(entries[0].amount == original.amount && entries[0].kind == original.kind && entries[0].cashAccountID == original.cashAccountID)
        let batch = entries[0].categoryRevision!.batchID
        precondition(batch == entries[1].categoryRevision?.batchID)
        entries = try JSONDecoder().decode([Entry].self, from: JSONEncoder().encode(entries))
        precondition(CategoryBatch.undo(batch, in: &entries, fingerprint: "laundry") == ["laundry"])
        precondition(entries[0].category == nil && entries[0].categoryRevision == nil)
        precondition(entries[1].category == .home)
        precondition(CategoryBatch.undo(batch, in: &entries) == ["byu"])
        precondition(entries[1].category == .shopping)
        precondition(CategoryBatch.undo(batch, in: &entries).isEmpty)
        entries[0].title = "New description"
        precondition(CategoryBatch.apply([proposals[0]], to: &entries).isEmpty) // stale proposal
        entries = [original]
        _ = CategoryBatch.apply([proposals[0]], to: &entries)
        let newBatch = entries[0].categoryRevision!.batchID
        entries[0].category = .health
        precondition(CategoryBatch.undo(newBatch, in: &entries).isEmpty) // later edit wins
        precondition(CategoryBatch.apply([CategoryProposal(original: original, suggested: .services, reason: "Same")], to: &entries).isEmpty)
        var gym = original; gym.title = "FIT HUB"
        precondition(CategoryEvidence.checked(.services, confident: true, for: gym).0 == .health)
        var dataPlan = original; dataPlan.title = "by.U data via ShopeePay"
        precondition(CategoryEvidence.checked(.shopping, confident: true, for: dataPlan).0 == .home)
        var generic = original; generic.title = "Your Visa has been charged for booking A-DEMO"
        precondition(CategoryEvidence.checked(.services, confident: true, for: generic).0 == generic.spendingCategory)
        var email = original; email.title = "BNI C to me Translate to English Yth. Bapak/Ibu"; email.category = .subscriptions
        precondition(CategoryEvidence.checked(.services, confident: true, for: email).0 == .subscriptions)
        print("PASS: category-only mutation, nil/manual category restoration, per-row and batch Undo, persistence, idempotence, stale-preview rejection, and later-edit protection.")
    }
}
