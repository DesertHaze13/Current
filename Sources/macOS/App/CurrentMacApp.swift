import SwiftUI
import GoogleSignIn

@main struct CurrentMacApp: App {
    @StateObject private var ledger = Ledger.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MacContentView().environmentObject(ledger)
                .onOpenURL { _ = GIDSignIn.sharedInstance.handle($0) }
                .frame(minWidth: 850, minHeight: 590)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await ledger.refresh(force: false)
                        await ledger.processCategoryQueue()
                        do { try await Task.sleep(for: .seconds(60)) } catch { break }
                    }
                }
        }
    }
}
