import Foundation

struct WatchMovement: Codable, Identifiable {
    let id: String
    let title: String
    let amount: Int
    let kind: String
}

struct WatchSummary: Codable {
    let month: String
    let spent: Int
    let earned: Int
    let settled: Int
    let moved: Int
    let updatedAt: Date
    let recent: [WatchMovement]
    var confirmedCashMinor: Int64? = nil
    var cashConfirmedAt: Date? = nil
}
