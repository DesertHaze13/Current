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
    var spendingCategory: SpendingCategory { category ?? SpendingCategory.suggested(for: title) }
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
