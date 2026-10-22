import Foundation

enum SpendingCategory: String, Codable, CaseIterable, Identifiable {
    case food, transport, services, subscriptions, shopping, health, home, giving, business, fees, entertainment, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: return "Food & drinks"
        case .transport: return "Transport"
        case .services: return "Services"
        case .subscriptions: return "Subscriptions"
        case .shopping: return "Shopping"
        case .health: return "Health"
        case .home: return "Home & utilities"
        case .giving: return "Giving"
        case .business: return "Business"
        case .fees: return "Bank fees"
        case .entertainment: return "Entertainment"
        case .other: return "Other"
        }
    }
    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "tram.fill"
        case .services: return "sparkles"
        case .subscriptions: return "repeat"
        case .shopping: return "bag.fill"
        case .health: return "cross.case.fill"
        case .home: return "house.fill"
        case .giving: return "heart.fill"
        case .business: return "briefcase.fill"
        case .fees: return "building.columns.fill"
        case .entertainment: return "party.popper.fill"
        case .other: return "ellipsis"
        }
    }
    /// Merchant descriptions suggest categories; a user override always wins.
    static func suggested(for title: String) -> SpendingCategory {
        let text = title.lowercased()
        let rules: [(SpendingCategory, [String])] = [
            (.food, ["grabfood", "gofood", "shopeefood", "restaurant", "restoran", "cafe", "coffee", "kopi", "makan", "chezmoi", "food"]),
            (.subscriptions, ["spotify", "apple music", "app store", "netflix", "youtube premium", "icloud", "subscription", "langganan", "disney", "chatgpt"]),
            (.fees, ["biaya admin", "transfer charges", "transfer fee", "admin fee", "bank fee", "biaya transfer"]),
            (.transport, ["goride", "gocar", "grabcar", "grabbike", "ride to", "gojek to", "perjalanan", "transport", "taxi", "taksi", "ojek", "bensin", "parkir", "parking", "kereta", "flight", "pertamina"]),
            (.services, ["laundry", "salon", "barber", "cleaning", "repair", "servis", "jasa"]),
            (.business, ["meta ads", "google ads", "advertising", "iklan"]),
            (.shopping, ["uniqlo", "belanja", "shopping", "tokopedia", "shopee", "lazada"]),
            (.home, ["by.u", "byu", "pulsa", "paket data", "internet", "pln", "listrik", "pdam", "sewa", "rent"]),
            (.giving, ["masjid", "donasi", "donation", "sedekah", "zakat", "charity"]),
            (.health, ["fit hub", "fitness", "gym", "health", "medical", "obat", "apotek", "pharmacy", "hospital", "rumah sakit", "dokter", "clinic", "klinik", "puskesmas"]),
            (.entertainment, ["funifun", "cinema", "bioskop", "movie", "game", "concert"])
        ]
        return rules.first { $0.1.contains(where: text.contains) }?.0 ?? .other
    }
}

extension Entry {
    var categoryContext: String { title + "\n" + note }
    var spendingCategory: SpendingCategory { category ?? SpendingCategory.suggested(for: categoryContext) }
}

struct SpendingSlice: Identifiable {
    let category: SpendingCategory
    let amount: Int
    let count: Int
    var id: SpendingCategory { category }
}

struct SpendingBreakdown {
    let entries: [Entry]
    let slices: [SpendingSlice]
    let total: Int
    init(entries: [Entry]) {
        self.entries = entries.filter { $0.isConfirmed && $0.kind == .expense && $0.amount > 0 }
        let groups = Dictionary(grouping: self.entries, by: \.spendingCategory)
        slices = groups.map { SpendingSlice(category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.amount == $1.amount ? $0.category.rawValue < $1.category.rawValue : $0.amount > $1.amount }
        total = slices.reduce(0) { $0 + $1.amount }
    }
    func category(at angleValue: Double) -> SpendingCategory? {
        guard angleValue.isFinite, angleValue >= 0, angleValue < Double(total) else { return nil }
        var end = 0
        for slice in slices {
            end += slice.amount
            if angleValue < Double(end) { return slice.category }
        }
        return nil
    }
}

/// Stored with the entry so Undo survives restart and follows Firebase sync.
struct CategoryRevision: Codable, Hashable {
    let batchID: UUID
    let appliedAt: Date
    let previousCategory: SpendingCategory?
    let appliedCategory: SpendingCategory
}

struct CategoryProposal: Identifiable {
    let original: Entry
    let suggested: SpendingCategory
    let reason: String
    var id: String { original.fingerprint }
    var changesCategory: Bool { original.spendingCategory != suggested }
}

struct CategoryBatch {
    static func apply(_ proposals: [CategoryProposal], to entries: inout [Entry], at date: Date = .now) -> [String] {
        let batch = UUID()
        var changed: [String] = []
        for proposal in proposals where proposal.changesCategory {
            guard let index = entries.firstIndex(where: { $0.fingerprint == proposal.id }),
                  entries[index] == proposal.original else { continue } // stale preview
            entries[index].categoryRevision = CategoryRevision(batchID: batch, appliedAt: date,
                previousCategory: entries[index].category, appliedCategory: proposal.suggested)
            entries[index].category = proposal.suggested
            entries[index].categoryAssessment = CategoryAssessment(state: .classified, reason: proposal.reason, at: date)
            changed.append(proposal.id)
        }
        return changed
    }
    static func undo(_ batchID: UUID, in entries: inout [Entry], fingerprint: String? = nil) -> [String] {
        var changed: [String] = []
        for index in entries.indices {
            guard let revision = entries[index].categoryRevision, revision.batchID == batchID,
                  fingerprint == nil || fingerprint == entries[index].fingerprint,
                  entries[index].category == revision.appliedCategory else { continue }
            entries[index].category = revision.previousCategory // restore nil, too
            entries[index].categoryRevision = nil
            entries[index].categoryAssessment = CategoryAssessment(state: .manual, reason: "Previous category restored with Undo.", at: .now)
            changed.append(entries[index].fingerprint)
        }
        return changed
    }
}

/// Domain checks constrain an AI suggestion; a booking/card code is not evidence
/// of what was bought. Explicit product wording is stronger than a vague model answer.
struct CategoryEvidence {
    static func checked(_ proposed: SpendingCategory, confident: Bool, for entry: Entry, localContext: String = "") -> (SpendingCategory, String?) {
        let text = (entry.categoryContext + " " + localContext).lowercased()
        let productRules: [(SpendingCategory, [String])] = [
            (.home, ["by.u", "byu data", "mobile data", "paket data", "electricity", "pln listrik"]),
            (.health, ["fit hub", "fitness", "gym", "apotek", "pharmacy"]),
            (.food, ["grabfood", "gofood", "shopeefood"]),
            (.transport, ["goride", "gocar", "grabcar", "grabbike", "ride to"]),
            (.services, ["laundry", "barber", "salon"]),
            (.business, ["meta ads", "google ads"]),
            (.subscriptions, ["spotify", "apple music", "netflix", "youtube premium"])
        ]
        if let match = productRules.first(where: { $0.1.contains(where: text.contains) }) {
            return (match.0, match.0 == proposed && confident ? nil : "Verified against the explicit product description.")
        }
        if ["translate to english", "yth. bapak/ibu", "show less"].contains(where: text.contains) {
            return (entry.spendingCategory, "Screenshot or email interface text is not a merchant description; kept the previous category.")
        }
        if text.contains("has been charged") || text.contains("for booking") {
            return (entry.spendingCategory, "A card or booking reference does not identify the purchase; kept the previous category.")
        }
        return confident ? (proposed, nil) : (entry.spendingCategory, "Insufficient detail — kept previous category.")
    }
}

struct CategoryAssessment: Codable, Hashable {
    enum State: String, Codable { case pending, classified, needsContext, manual }
    var state: State
    var reason: String
    var at: Date
}

extension Entry {
    var needsAutomaticCategory: Bool {
        guard kind == .expense, isConfirmed else { return false }
        if let assessment = categoryAssessment {
            return assessment.state == .pending && Date().timeIntervalSince(assessment.at) > 60
        }
        return category == nil && spendingCategory == .other
    }
    var categoryStatusText: String? {
        guard kind == .expense else { return nil }
        switch categoryAssessment?.state {
        case .pending: return "Category queued for on-device AI"
        case .needsContext: return "Category needs more context"
        case .classified: return "AI · " + spendingCategory.title
        case .manual: return "Your choice · " + spendingCategory.title
        case nil: return spendingCategory == .other ? "Category not reviewed yet" : nil
        }
    }
}

struct MerchantCategoryMemory {
    static func key(for title: String) -> String? {
        let lower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["has been charged", "booking", "financial diary", "payment", "transfer", "bni credit", "translate to english"]
        guard lower.count <= 80, !generic.contains(where: lower.contains) else { return nil }
        let key = lower.replacingOccurrences(of: "[^a-z]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return key.count >= 3 ? key : nil
    }
}
