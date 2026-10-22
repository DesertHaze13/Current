import SwiftUI
import Foundation
import CryptoKit
import Security

extension Int { var rupiah: String { "Rp " + formatted(.number.grouping(.automatic)) } }

enum EntryKind: String, Codable, CaseIterable { case expense, income, transfer, settlement
    var title: String { self == .settlement ? "Bill paid" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .settlement: return "checkmark.seal"
        }
    }
    var tint: Color {
        switch self {
        case .expense: return .mint
        case .income: return .cyan
        case .transfer: return .orange
        case .settlement: return .purple
        }
    }
}

struct Entry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var source: String
    var title: String
    var amount: Int
    var kind: EntryKind
    var date: Date
    var fingerprint: String
    var note: String = ""
    var category: SpendingCategory? = nil
    var categoryRevision: CategoryRevision? = nil
    var categoryAssessment: CategoryAssessment? = nil
    // nil = infer only an unambiguous bank source; "" = explicitly not cash.
    var cashAccountID: String? = nil
    var destinationCashAccountID: String? = nil
    var requiresReview: Bool? = nil
    var isTemporaryAuthorization: Bool { AlertParser.isAuthorizationHold(title + "\n" + note) }
    var isConfirmed: Bool { requiresReview != true && !isTemporaryAuthorization }
}

/// A last-confirmed cash balance. Credit limits, paylater and reward points never belong here.
struct CashAccount: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var balanceMinor: Int64
    var confirmedAt: Date

    /// Empty account presets. Each must be confirmed by its owner before use.
    static var screenshotStartingBalances: [CashAccount] {
        [("brimo", "BRImo"), ("dana", "DANA"), ("flip", "Flip"),
         ("gopay", "GoPay"), ("mybca", "myBCA"), ("seabank", "SeaBank"),
         ("wondr", "wondr by BNI")].map {
            CashAccount(id: $0.0, name: $0.1, balanceMinor: 0, confirmedAt: .distantPast)
        }
    }

    static func rupiah(_ minor: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minor % 100 == 0 ? 0 : 2
        formatter.maximumFractionDigits = 2
        let value = NSDecimalNumber(decimal: Decimal(minor) / 100)
        return "Rp" + (formatter.string(from: value) ?? "0")
    }

    static func parseRupiah(_ raw: String) -> Int64? {
        let text = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !text.isEmpty else { return nil }
        let punctuation = text.lastIndex(where: { $0 == "." || $0 == "," })
        let fractionCount = punctuation.map { text.distance(from: text.index(after: $0), to: text.endIndex) } ?? 0
        let hasFraction = punctuation != nil && (1...2).contains(fractionCount)
        let integerPart = hasFraction ? String(text[..<punctuation!]) : text
        guard let whole = Int64(integerPart.filter(\.isNumber)), whole <= (Int64.max - 99) / 100 else { return nil }
        let fraction = hasFraction ? String(text[text.index(after: punctuation!)...]) : ""
        let cents = fraction.isEmpty ? 0 : Int64(fraction.padding(toLength: 2, withPad: "0", startingAt: 0))
        guard let cents else { return nil }
        return whole * 100 + cents
    }
}

/// A projection never mutates the bank-confirmed snapshot. Recomputing from
/// immutable entries avoids subtracting imports twice or accumulating rounding.
struct CashProjection {
    let account: CashAccount
    let movements: [(entry: Entry, deltaMinor: Int64)]
    var deltaMinor: Int64 { movements.reduce(0) { $0 + $1.deltaMinor } }
    var estimatedMinor: Int64 { account.balanceMinor + deltaMinor }

    init(account: CashAccount, entries: [Entry]) {
        self.account = account
        movements = entries.compactMap { entry in
            guard entry.isConfirmed, entry.amount > 0, entry.date > account.confirmedAt else { return nil }
            let minor = Int64(entry.amount) * 100
            if entry.kind == .transfer {
                // Transfers need BOTH legs. The reporting app is not the bank.
                guard let from = entry.cashAccountID, !from.isEmpty,
                      let to = entry.destinationCashAccountID, !to.isEmpty, from != to else { return nil }
                if from == account.id { return (entry, -minor) }
                if to == account.id { return (entry, minor) }
                return nil
            }
            guard entry.resolvedCashAccountID == account.id else { return nil }
            return (entry, entry.kind == .income ? minor : -minor)
        }.sorted { $0.entry.date < $1.entry.date }
    }
}

extension Entry {
    var resolvedCashAccountID: String? {
        if let cashAccountID { return cashAccountID.isEmpty ? nil : cashAccountID }
        // Card receipts reported by a merchant/wallet do not identify cash funding.
        let text = (title + " " + note).lowercased()
        if kind == .expense && ["credit card", "unbilled credit", "charged", "paylater", "amex", "visa", "mastercard"].contains(where: text.contains) { return nil }
        switch source.lowercased() {
        case "mybca", "bca": return "mybca"
        case "brimo", "bri": return "brimo"
        case "seabank": return "seabank"
        case "wondr by bni", "wondr": return "wondr"
        // Wallet/app names alone may report purchases funded by another card.
        default: return nil
        }
    }
    var needsCashAssignment: Bool {
        guard isConfirmed else { return false }
        if kind == .transfer {
            return cashAccountID?.isEmpty != false || destinationCashAccountID?.isEmpty != false
        }
        if cashAccountID != nil { return false }
        let text = (title + " " + note).lowercased()
        if ["unbilled credit", "has been charged", "credit card"].contains(where: text.contains) { return false }
        return resolvedCashAccountID == nil
    }
}

/// A cash-flow view of recorded movements, not a bank balance or a complete financial audit.
struct MonthlyInsight {
    let income: Int
    let purchases: Int
    let billsPaid: Int
    let transfers: Int

    init(entries: [Entry]) {
        let entries = entries.filter(\.isConfirmed)
        income = entries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        purchases = entries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        billsPaid = entries.filter { $0.kind == .settlement }.reduce(0) { $0 + $1.amount }
        transfers = entries.filter { $0.kind == .transfer }.reduce(0) { $0 + $1.amount }
    }

    var cashOut: Int { purchases + billsPaid }
    var net: Int { income - cashOut }
    var retainedRate: Double? { income > 0 ? Double(net) / Double(income) : nil }
    var billRate: Double? { income > 0 ? Double(billsPaid) / Double(income) : nil }
    var hasMovements: Bool { income + purchases + billsPaid + transfers > 0 }

    var verdict: String {
        guard hasMovements else { return "No data yet" }
        guard income > 0 else { return "Income needed" }
        if net < 0 { return "Deficit" }
        if net == 0 { return "Break-even" }
        if billRate ?? 0 > 0.30 { return "Debt pressure" }
        if retainedRate ?? 0 >= 0.20 { return "Strong" }
        if retainedRate ?? 0 >= 0.10 { return "Good" }
        return "Tight"
    }

    var guidance: String {
        guard hasMovements else { return "Record income and outflows to see a monthly assessment." }
        guard income > 0 else { return "Record this month's income before rating the plan. Existing savings may fund these outflows." }
        if net < 0 { return "Recorded outflows exceed recorded income. Review purchases and upcoming bills." }
        if net == 0 { return "Recorded income exactly covers purchases and bills. There is no recorded buffer yet." }
        if billRate ?? 0 > 0.30 { return "Bill payments exceed 30% of recorded income. Check remaining debt and due dates." }
        if retainedRate ?? 0 >= 0.20 { return "At least 20% of recorded income remains after purchases and bill payments." }
        if retainedRate ?? 0 >= 0.10 { return "A cash buffer remains. Review upcoming bills before treating it as available to save." }
        return "Less than 10% of recorded income remains. Small new purchases may erase the buffer." 
    }
}

struct ParsedAlert {
    var source: String
    var title: String
    var amount: Int
    var kind: EntryKind
    var date: Date
    var fingerprint: String
}
enum AlertParser {
    static let sources = ["BRImo", "DANA", "Flip", "GoPay", "Jenius", "LinkAja", "myBCA", "SeaBank", "Yup", "Honest", "wondr by BNI", "Grab", "Gojek", "Shopee"]
    /// Conservative parser for notification automations: one monetary amount plus a
    /// recognizable completed movement. Summary and balance notices are ignored.
    static func parseNotification(_ raw: String, source: String? = nil, at date: Date = .now) -> ParsedAlert? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1_200, !isAuthorizationHold(text) else { return nil }
        let pattern = #"(?i)(?:Rp\s*|IDR\s*)[\d.,]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard regex.matches(in: text, range: range).count == 1 else { return nil }
        let lower = text.lowercased()
        // Reject unsuccessful/future movements before considering generic payment wording.
        let notCompleted = ["payment failed", "transaction failed", "payment declined", "card declined",
                            "not been charged", "has not been charged", "will be charged",
                            "transaksi gagal", "pembayaran gagal", "belum dibayar", "akan ditagih",
                            "payment pending", "refund pending", "menunggu pembayaran"]
        guard !notCompleted.contains(where: lower.contains) else { return nil }
        let completedCharge = text.range(of: #"(?i)\b(?:(?:has|have) been charged|(?:was|were) charged|successfully charged|berhasil didebit|berhasil dibebankan)\b"#, options: .regularExpression) != nil
        let promotion = ["promo", "cashback", "diskon", "discount", "voucher", "pesanan terjadwal",
                         "besok repot", "your next payment", "transaksi berikutnya"]
        let completedWording = ["payment successful", "payment completed", "successfully paid", "berhasil membayar",
                                "pembayaran berhasil", "telah dibayar", "has been paid",
                                "cashback received", "cashback credited", "cashback diterima",
                                "refund received", "refund credited", "refund diterima"]
        if promotion.contains(where: lower.contains) && !completedCharge && !completedWording.contains(where: lower.contains) {
            return nil
        }
        let billTerms = ["tagihan", "cicilan", "bill", "statement", "repayment"]
        let billPaid = ["dibayar", "terbayar", "lunas", "melunasi", "bayar", "paid", "payment successful", "repayment", "settled"]
        let incoming = ["diterima", "menerima", "received", "credited", "dana masuk", "uang masuk", "gaji", "salary", "refund", "pengembalian"]
        let outgoing = ["debit", "purchase", "pembayaran", "payment", "paid", "berhasil membayar", "berhasil melakukan transaksi", "transaksi", "withdrawal", "penarikan", "transfer", "send money", "kirim uang"]
        let internalTransfer = ["rekening sendiri", "own account", "to myself", "to my own", "ke rekening saya", "rekening atas nama anda", "top up", "top-up", "topup"]
        let isPaidBill = billTerms.contains(where: lower.contains) && billPaid.contains(where: lower.contains)
        let isIncoming = incoming.contains(where: lower.contains)
        let isInternalTransfer = internalTransfer.contains(where: lower.contains)
        let isSavingsWithdrawal = ["dana+ withdrawal", "dana plus withdrawal", "dana+ penarikan", "dana plus penarikan"].contains(where: lower.contains)
        guard completedCharge || isPaidBill || isIncoming || isInternalTransfer || isSavingsWithdrawal || outgoing.contains(where: lower.contains) else { return nil }
        guard let parsed = parse(text, source: source, at: date) else { return nil }
        let kind: EntryKind = isPaidBill ? .settlement : ((isInternalTransfer || isSavingsWithdrawal) ? .transfer : (isIncoming ? .income : .expense))
        // Booking IDs survive device-specific headers and delayed delivery.
        if completedCharge, let reference = bookingReference(in: text) {
            let provider = (source == nil || source == "Auto detect") && reference.hasPrefix("A-") ? "Grab" : parsed.source
            let key = "booking-charge|\(reference)|\(parsed.amount)|\(kind.rawValue)"
            let fingerprint = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            return ParsedAlert(source: provider, title: text, amount: parsed.amount, kind: kind, date: parsed.date, fingerprint: fingerprint)
        }
        return ParsedAlert(source: parsed.source, title: parsed.title, amount: parsed.amount, kind: kind, date: parsed.date, fingerprint: parsed.fingerprint)
    }

    static func bookingReference(in text: String) -> String? {
        let pattern = #"(?i)\bbooking\s+(A-[A-Z0-9]{6,40})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).uppercased()
    }

    static func isAuthorizationHold(_ text: String) -> Bool {
        let lower = text.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return ["currently on hold", "is on hold", "only be charged the final", "pre-authorisation", "pre-authorization", "preauthorisation", "preauthorization", "temporary card authorization"].contains(where: lower.contains)
    }

    static func notificationSkipReason(_ text: String) -> String {
        if isAuthorizationHold(text) { return "This is a temporary card hold, not a completed purchase. Wait for the final charge." }
        let count = (try? NSRegularExpression(pattern: #"(?i)(?:Rp\s*|IDR\s*)[\d.,]+"#))?
            .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
        if count == 0 { return "No rupiah transaction amount was provided by Shortcuts." }
        if count > 1 { return "Several amounts were found. Review the alert in Current to choose the transaction amount." }
        return "The message does not identify a supported completed transaction, or describes a promotion, pending or failed payment. Paste it into Current for review."
    }

    static func parse(_ raw: String, source chosen: String? = nil, at date: Date = .now) -> ParsedAlert? {
        let text = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAuthorizationHold(text) else { return nil }
        let source = (chosen == "Auto detect" ? nil : chosen) ?? sources.first(where: { text.localizedCaseInsensitiveContains($0) }) ?? "Other"
        let pattern = #"(?i)(?:Rp\s*|IDR\s*)([\d.,]+)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let numeric = text[range].replacingOccurrences(of: #"(?i)^(rp|idr)\s*"#, with: "", options: .regularExpression)
        let whole = numeric.replacingOccurrences(of: #"[,.]\d{2}$"#, with: "", options: .regularExpression)
        let digits = whole.filter(\.isNumber)
        guard let amount = Int(digits), amount > 0 else { return nil }
        let lower = text.lowercased()
        let transferWords = ["rekening sendiri", "own account", "pemindahan", "pindah dana", "top up saldo saya", "top-up saldo saya"]
        let incomeWords = ["diterima", "received", "masuk", "kredit", "refund", "pengembalian", "gaji"]
        let kind: EntryKind = transferWords.contains(where: lower.contains) ? .transfer : (incomeWords.contains(where: lower.contains) ? .income : .expense)
        let heading = text.count > 72 ? String(text.prefix(72)) + "…" : text
        let normalized = lower.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let day = Calendar(identifier: .gregorian).startOfDay(for: date).timeIntervalSince1970
        let key = "\(source.lowercased())|\(amount)|\(kind.rawValue)|\(Int(day))|\(normalized)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return ParsedAlert(source: source, title: heading, amount: amount, kind: kind, date: date, fingerprint: hash)
    }
}

extension JSONEncoder { static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
enum Keychain {
    static func save(_ value: String, as key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        #if os(macOS)
        let extra: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        #else
        let extra: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        #endif
        let attributes = query.merging(extra) { _, new in new }
        SecItemAdd(attributes as CFDictionary, nil)
    }
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Identity changes must never move a local financial ledger to another Firebase owner.
enum AccountIdentityPolicy {
    static func accepts(existingUID: String?, incomingUID: String) -> Bool {
        !incomingUID.isEmpty && (existingUID == nil || existingUID == incomingUID)
    }
    static func acceptsGoogleEmail(existingUID: String?, currentEmail: String, incomingEmail: String?) -> Bool {
        guard existingUID != nil else { return true }
        guard let incomingEmail, !incomingEmail.isEmpty, !currentEmail.isEmpty else { return false }
        return incomingEmail.caseInsensitiveCompare(currentEmail) == .orderedSame
    }
}
