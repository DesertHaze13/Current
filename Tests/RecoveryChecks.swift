import Foundation

@main struct RecoveryChecks {
    @MainActor static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = Entry(source: "Demo Bank", title: "Demo purchase", amount: 12000, kind: .expense, date: now, fingerprint: "demo-id")
        let trash = DeletedEntry(entry: entry, deletedAt: now)
        precondition(!trash.isExpired(at: now.addingTimeInterval(30 * 86400 - 1)))
        precondition(trash.isExpired(at: now.addingTimeInterval(30 * 86400)))
        let restored = try JSONDecoder().decode(DeletedEntry.self, from: JSONEncoder().encode(trash))
        precondition(restored.entry == entry && restored.id == entry.fingerprint)
        let url = dir.appendingPathComponent("inbox.json")
        let store = CaptureInbox(url: url)
        let capture = try store.receive("Demo payment Rp12.000", source: "Demo Bank", at: now)
        let duplicate = try store.receive("Demo payment Rp12.000", source: "Demo Bank", at: now)
        precondition(duplicate.id == capture.id)
        let reopened = CaptureInbox(url: url)
        precondition(reopened.items.count == 1 && reopened.items[0].receivedAt == now)
        try reopened.finish(capture, fingerprint: nil, message: "Needs review")
        precondition(CaptureInbox(url: url).items[0].recordedFingerprint == nil)
        try reopened.finish(capture, fingerprint: entry.fingerprint, message: "Saved")
        precondition(CaptureInbox(url: url).items[0].recordedFingerprint == entry.fingerprint)
        precondition(NotificationCapture.identity(text: capture.text, source: capture.source, at: now.addingTimeInterval(86400)) != capture.id)
        // Failed writes must throw, never claim that the capture was saved.
        let bad = CaptureInbox(url: dir) // A directory cannot be overwritten by a JSON file.
        do { _ = try bad.receive("Payment Rp10", source: nil); preconditionFailure("Expected a durable-write error") }
        catch { precondition(bad.items.isEmpty) }
        print("Recovery checks passed: retention boundary, identity, restart, review and disk failure")
    }
}
