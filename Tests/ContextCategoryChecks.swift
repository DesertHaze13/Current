import Foundation

@main struct ContextCategoryChecks {
    static func main() throws {
        var record = Entry(source: "myBCA", title: "Payment successful", amount: 50_000, kind: .expense, date: .now, fingerprint: "context-demo")
        let context = "Notification header and reference. Payment successful IDR 50,000.00 for laundry service."
        precondition(CategoryEvidence.checked(.other, confident: false, for: record, localContext: context).0 == .services)
        precondition(record.spendingCategory == .other)
        precondition(record.needsAutomaticCategory)
        record.categoryAssessment = CategoryAssessment(state: .manual, reason: "User override", at: .now)
        precondition(!record.needsAutomaticCategory)
        record.categoryAssessment = CategoryAssessment(state: .needsContext, reason: "No merchant", at: .now)
        precondition(!record.needsAutomaticCategory)
        record.categoryAssessment = CategoryAssessment(state: .pending, reason: "Wait", at: .distantPast)
        precondition(record.needsAutomaticCategory)
        record.categoryAssessment?.at = .now
        precondition(!record.needsAutomaticCategory)
        record.category = .services
        let encoded = try JSONEncoder().encode(record)
        precondition(!String(decoding: encoded, as: UTF8.self).contains("Notification header"))
        let restored = try JSONDecoder().decode(Entry.self, from: encoded)
        precondition(restored.category == .services && restored.categoryAssessment?.state == .pending)
        precondition(MerchantCategoryMemory.key(for: "Laundry") == "laundry")
        precondition(MerchantCategoryMemory.key(for: "Your Visa has been charged for booking A-DEMO") == nil)
        record.kind = .transfer
        precondition(!record.needsAutomaticCategory)
        precondition(AlertParser.parseNotification("Grab: Rp12345.00 is currently on hold. You'll only be charged the final amount after payment.") == nil)
        precondition(AlertParser.isAuthorizationHold("Amount is currently on hold"))
        // Both automatic capture and pasted/OCR text must reject authorization holds.
        for text in ["Rp12345.00 is currently on hold You'll only be charged the final amount …",
                     "Grab: Rp12.345 is currently\non hold.", "Amount Rp12.345 is on hold"] {
            precondition(AlertParser.parseNotification(text) == nil)
            precondition(AlertParser.parse(text) == nil)
        }
        var hold = Entry(source: "myBCA", title: "Rp12345.00 is currently on hold", amount: 12_345, kind: .expense, date: .now, fingerprint: "hold-fixture")
        hold.requiresReview = false // Legacy confirmation cannot turn a hold into a completed charge.
        precondition(hold.isTemporaryAuthorization && !hold.isConfirmed)
        precondition(MonthlyInsight(entries: [hold]).purchases == 0)
        precondition(SpendingBreakdown(entries: [hold]).total == 0)
        let bank = CashAccount(id: "mybca", name: "BCA", balanceMinor: 10_000_000, confirmedAt: .distantPast)
        precondition(CashProjection(account: bank, entries: [hold]).deltaMinor == 0)
        hold.title = "Payment notice"
        hold.note = "Temporary card authorization; final purchase is not confirmed."
        precondition(!hold.isConfirmed)
        let completed = "Your Visa 0000 has been charged Rp12.345 for booking A-FINALDEMO01."
        precondition(AlertParser.parseNotification(completed)?.kind == .expense)
        print("PASS: full-context evidence, status persistence, manual-choice protection, retry throttling, no raw context in synced Entry, merchant memory and movement exclusions.")
    }
}
