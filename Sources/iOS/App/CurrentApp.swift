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
                        await ledger.refresh()
                        do { try await Task.sleep(for: .seconds(30)) } catch { break }
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
    static var description = IntentDescription("Classify and sync one clear bank transaction alert to Current. Ambiguous alerts are skipped.")

    @Parameter(title: "Notification text") var notificationText: String
    @Parameter(title: "App", default: .autoDetect) var source: TrackedFinancialApp

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let parsed = AlertParser.parseNotification(notificationText, source: source.sourceName) else {
            return .result(dialog: "Not recorded: \(AlertParser.notificationSkipReason(notificationText))")
        }

        let ledger = Ledger.shared
        ledger.errorMessage = nil
        await ledger.add(Entry(source: parsed.source, title: parsed.title, amount: parsed.amount, kind: parsed.kind, date: parsed.date, fingerprint: parsed.fingerprint))
        if let message = ledger.errorMessage {
            return .result(dialog: "Current could not record this alert: \(message)")
        }
        if ledger.syncStatus != "Firebase synced" {
            return .result(dialog: "Saved on this device, but not synced yet. Open Current to check Firebase sign-in and connection.")
        }
        return .result(dialog: "Recorded and synced \(parsed.kind.title.lowercased()) from \(parsed.source).")
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
