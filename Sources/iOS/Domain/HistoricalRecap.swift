import Foundation

/// Public builds do not bundle personal financial records.
enum HistoricalRecap {
    static let importKey = "publicEmptyLedgerV1"
    static let entries: [Entry] = []
}
