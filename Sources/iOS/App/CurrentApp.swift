import SwiftUI
import GoogleSignIn
import Foundation
import CryptoKit
import Security
import AppIntents

@main struct CurrentApp: App {
    @StateObject private var ledger = Ledger.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(ledger)
                .onOpenURL { _ = GIDSignIn.sharedInstance.handle($0) }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    CurrentAppShortcuts.updateAppShortcutParameters()
                    while !Task.isCancelled {
                        await ledger.refresh(force: false)
                        await ledger.processCategoryQueue()
                        do { try await Task.sleep(for: .seconds(60)) } catch { break }
                    }
                }
        }
    }
}



/// A bank/app notification supplied by the user's Shortcuts automation.
enum TrackedFinancialApp: String, AppEnum {
    case autoDetect, brimo, dana, flip, gopay, jenius, linkaja, myBCA, seaBank, yup, honest, wondrByBNI

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Financial app")
    static var caseDisplayRepresentations: [TrackedFinancialApp: DisplayRepresentation] = [
        .autoDetect: DisplayRepresentation(title: "Auto detect"), .brimo: DisplayRepresentation(title: "BRImo"),
        .dana: DisplayRepresentation(title: "DANA"), .flip: DisplayRepresentation(title: "Flip"),
        .gopay: DisplayRepresentation(title: "GoPay"), .jenius: DisplayRepresentation(title: "Jenius"),
        .linkaja: DisplayRepresentation(title: "LinkAja"), .myBCA: DisplayRepresentation(title: "myBCA"),
        .seaBank: DisplayRepresentation(title: "SeaBank"), .yup: DisplayRepresentation(title: "Yup"),
        .honest: DisplayRepresentation(title: "Honest"), .wondrByBNI: DisplayRepresentation(title: "wondr by BNI")
    ]
    var sourceName: String? {
        switch self {
        case .autoDetect: return nil
        case .brimo: return "BRImo"
        case .dana: return "DANA"
        case .flip: return "Flip"
        case .gopay: return "GoPay"
        case .jenius: return "Jenius"
        case .linkaja: return "LinkAja"
        case .myBCA: return "myBCA"
        case .seaBank: return "SeaBank"
        case .yup: return "Yup"
        case .honest: return "Honest"
        case .wondrByBNI: return "wondr by BNI"
        }
    }
}

/// Exposed as an action in Shortcuts. The automation passes notification text here;
/// ambiguous or non-transaction notices are rejected instead of guessed.
struct RecordTransactionFromAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Record transaction from alert"
    static var description = IntentDescription("Classify and sync one clear bank transaction alert to Current. Unclear alerts are kept in the device’s Recovery Inbox for review.")

    @Parameter(title: "Notification text") var notificationText: String
    @Parameter(title: "App", default: .autoDetect) var source: TrackedFinancialApp

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let inbox = CaptureInbox.shared
        let capture = try inbox.receive(notificationText, source: source.sourceName)
        if capture.recordedFingerprint != nil { return .result(dialog: "This alert is already recorded. Check Activity or Recently Deleted.") }
        guard let parsed = AlertParser.parseNotification(capture.text, source: capture.source, at: capture.receivedAt) else {
            let reason = AlertParser.notificationSkipReason(capture.text)
            try inbox.finish(capture, fingerprint: nil, message: reason)
            return .result(dialog: "Saved in Current’s Recovery Inbox for review: \(reason)")
        }
        let ledger = Ledger.shared
        ledger.errorMessage = nil
        LocalNotificationContext.shared.store(capture.text, for: parsed.fingerprint)
        if !ledger.entries.contains(where: { $0.fingerprint == parsed.fingerprint }) && !ledger.recentlyDeleted.contains(where: { $0.id == parsed.fingerprint }) {
            await ledger.add(Entry(source: parsed.source, title: parsed.title, amount: parsed.amount, kind: parsed.kind, date: parsed.date, fingerprint: parsed.fingerprint))
        }
        guard ledger.isDurablyRecorded(parsed.fingerprint) else {
            try inbox.finish(capture, fingerprint: nil, message: "Not saved. Open Recovery Inbox to retry.")
            return .result(dialog: "Alert kept in Current’s Recovery Inbox. Open Current to review it.")
        }
        try inbox.finish(capture, fingerprint: parsed.fingerprint, message: "Saved locally. Cloud sync retries independently.")
        // Persist the journal result before optional AI enrichment can be interrupted.
        await ledger.classifyRecordedAlert(parsed.fingerprint)
        if ledger.syncStatus != "Firebase synced" {
            return .result(dialog: "Saved on this device. Cloud sync is pending and will retry when Current is open.")
        }

        let category = ledger.entries.first { $0.fingerprint == parsed.fingerprint }?.categoryStatusText ?? ""
        return .result(dialog: "Recorded and synced \(parsed.kind.title.lowercased()) from \(parsed.source). \(category)")
    }
}

struct CurrentAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordTransactionFromAlertIntent(),
            phrases: ["Record a transaction from an alert with \(.applicationName)"],
            shortTitle: "Record alert",
            systemImageName: "arrow.down.doc"
        )
    }
}
