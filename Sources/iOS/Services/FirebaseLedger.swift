import Foundation
import SwiftUI
import GoogleSignIn
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private struct AuthReply: Decodable {
    let idToken: String
    let refreshToken: String
    let localId: String
    let email: String?
    let expiresIn: String
}
private struct RefreshReply: Decodable {
    let id_token: String
    let refresh_token: String
    let user_id: String
    let expires_in: String
}
private struct FirestoreList: Decodable {
    let documents: [FirestoreDocument]?
    let nextPageToken: String?
}
private struct FirestoreDocument: Decodable {
    let name: String
    let fields: [String: FirestoreValue]?
}
private struct FirestoreValue: Decodable {
    let stringValue: String?
    let booleanValue: Bool?
}
struct BalanceSnapshot: Codable {
    let amount: Int
    let date: Date
}

enum FirebaseError: LocalizedError {
    case missingConfiguration, notSignedIn, accountMismatch, quotaExceeded, server(String)
    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Firebase configuration is missing. Add GoogleService-Info.plist to the app target."
        case .quotaExceeded: return "Firebase quota reached. Changes are saved on this device; cloud sync will retry later."
        case .notSignedIn: return "Sign in to sync across your devices."
        case .accountMismatch: return "This device has local data linked to another Firebase account."
        case .server(let message): return "Firebase: \(message.replacingOccurrences(of: "_", with: " ").lowercased())"
        }
    }
}

struct GoogleProfile: Codable, Equatable {
    let firebaseUID: String
    let name: String
    let email: String
    let photoURL: URL?
}
private struct AccountLookup: Decodable {
    struct User: Decodable {
        struct Provider: Decodable {
            let providerId: String
            let displayName: String?
            let email: String?
            let photoUrl: String?
        }
        let localId: String
        let email: String?
        let providerUserInfo: [Provider]?
    }
    let users: [User]?
}

@MainActor final class Ledger: ObservableObject {
    /// The app UI and in-process App Intents must observe and mutate the same ledger.
    static let shared = Ledger()
    @Published var entries: [Entry] = []
    @Published var syncStatus = "On this device"
    @Published private(set) var syncIssue: String?
    private var quotaFailures = 0
    private var quotaRetryKey: String { "firebaseQuotaRetry-" + firebaseProjectID + "-" + (Keychain.read("firebaseUID") ?? "anonymous") }
    private var quotaRetryAfter: Date {
        get { UserDefaults.standard.object(forKey: quotaRetryKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: quotaRetryKey) }
    }
    @Published var selectedMonth = Date()
    @Published var errorMessage: String?
    @Published private(set) var googleProfile: GoogleProfile?
    @Published private(set) var connectingGoogle = false
    @Published var profileMessage: String?
    private var profileCheckedAt: Date?
    @Published var accountEmail = UserDefaults.standard.string(forKey: "firebaseEmail") ?? ""
    @Published var balanceSnapshot: BalanceSnapshot?
    @Published var cashAccounts: [CashAccount] = []
    private var idToken = ""
    private var tokenExpiry = Date.distantPast
    private var pending = Set(UserDefaults.standard.stringArray(forKey: "firebasePending") ?? [])
    private var pendingDeletes = Set(UserDefaults.standard.stringArray(forKey: "firebasePendingDeletes") ?? [])
    private var syncInProgress = false
    private var categoryEnrichmentInProgress = false
    private static var storageDirectory: URL {
        #if os(macOS)
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Current", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }
    private let localURL = Ledger.storageDirectory.appendingPathComponent("ledger.json")
    private let balanceURL = Ledger.storageDirectory.appendingPathComponent("balance.json")
    private let cashAccountsURL = Ledger.storageDirectory.appendingPathComponent("cash-accounts.json")
    private var balancePending = UserDefaults.standard.bool(forKey: "firebaseBalancePending")
    private var cashAccountsPending = UserDefaults.standard.bool(forKey: "firebaseCashAccountsPending")
    private let config: [String: Any] = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: "verifiedGoogleProfile"),
           let profile = try? JSONDecoder().decode(GoogleProfile.self, from: data),
           profile.firebaseUID == Keychain.read("firebaseUID") { googleProfile = profile }
        if let data = try? Data(contentsOf: localURL), let saved = try? JSONDecoder().decode([Entry].self, from: data) { entries = saved }
        if let data = try? Data(contentsOf: balanceURL), let saved = try? JSONDecoder().decode(BalanceSnapshot.self, from: data) { balanceSnapshot = saved }
        if let data = try? Data(contentsOf: cashAccountsURL), let saved = try? JSONDecoder().decode([CashAccount].self, from: data) {
            cashAccounts = saved
        } else {
            cashAccounts = CashAccount.screenshotStartingBalances
            saveCashAccounts()
        }
        migrateRecapLabels()
        importHistoricalRecapIfNeeded()
        markTemporaryHoldsForReview()
    }
    private func markTemporaryHoldsForReview() {
        var changed = false
        for index in entries.indices {
            let entry = entries[index]
            let context = LocalNotificationContext.shared.text(for: entry.fingerprint) ?? ""
            guard entry.requiresReview != true, entry.isTemporaryAuthorization || AlertParser.isAuthorizationHold(context) else { continue }
            entries[index].requiresReview = true
            let explanation = "Temporary card authorization; final purchase is not confirmed. Excluded from confirmed totals pending review."
            if !entries[index].note.contains(explanation) {
                entries[index].note += (entries[index].note.isEmpty ? "" : "\n") + explanation
            }
            pending.insert(entries[index].fingerprint); changed = true
        }
        if changed { savePending(); save() }
    }

    private func migrateRecapLabels() {
        var changed = false
        for canonical in HistoricalRecap.entries {
            guard let index = entries.firstIndex(where: { $0.fingerprint == canonical.fingerprint }) else { continue }
            if entries[index].title != canonical.title || entries[index].source != canonical.source || entries[index].note != canonical.note {
                entries[index].title = canonical.title
                entries[index].source = canonical.source
                entries[index].note = canonical.note
                pending.insert(canonical.fingerprint)
                changed = true
            }
        }
        guard changed else { return }
        savePending()
        save()
    }
    private func importHistoricalRecapIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: HistoricalRecap.importKey) else { return }
        for candidate in HistoricalRecap.entries {
            let duplicate = entries.contains { existing in
                existing.fingerprint == candidate.fingerprint ||
                (existing.amount == candidate.amount && existing.kind == candidate.kind &&
                 Calendar.current.isDate(existing.date, inSameDayAs: candidate.date) &&
                 (existing.source == candidate.source || existing.source == "Manual"))
            }
            if !duplicate {
                entries.append(candidate)
            }
        }
        entries.sort { $0.date > $1.date }
        savePending()
        save()
        UserDefaults.standard.set(true, forKey: HistoricalRecap.importKey)
    }
    var firebaseProjectID: String { config["PROJECT_ID"] as? String ?? "" }
    private var apiKey: String { config["API_KEY"] as? String ?? "" }
    var hasFirebaseConfig: Bool {
        guard !apiKey.isEmpty && !firebaseProjectID.isEmpty else { return false }
        #if os(macOS)
        return true // REST uses the same Firebase project; register a separate Mac app for production.
        #else
        return config["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier
        #endif
    }
    var isSignedIn: Bool { Keychain.read("firebaseRefreshToken") != nil && Keychain.read("firebaseUID") != nil }
    var monthEntries: [Entry] { entries.filter { Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }.sorted { $0.date > $1.date } }
    var spent: Int { monthEntries.filter { $0.isConfirmed && $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    var earned: Int { monthEntries.filter { $0.isConfirmed && $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    var moved: Int { monthEntries.filter { $0.isConfirmed && $0.kind == .transfer }.reduce(0) { $0 + $1.amount } }
    var settled: Int { monthEntries.filter { $0.isConfirmed && $0.kind == .settlement }.reduce(0) { $0 + $1.amount } }
    var monthlyInsight: MonthlyInsight { MonthlyInsight(entries: monthEntries) }
    /// Cash movement since the earliest confirmed recorded income. This is not an account balance:
    /// money held before that salary and any missing transactions are outside the calculation.
    var trackedOpening: Int? {
        guard let salary = entries.filter({ $0.isConfirmed && $0.kind == .income }).min(by: { $0.date < $1.date }),
              let month = Calendar.current.dateInterval(of: .month, for: selectedMonth),
              let firstMonth = Calendar.current.dateInterval(of: .month, for: salary.date),
              month.start >= firstMonth.start else { return nil }
        return entries.filter { $0.isConfirmed && $0.date >= salary.date && $0.date < month.start }.reduce(0) { total, entry in
            switch entry.kind {
            case .income: return total + entry.amount
            case .expense, .settlement: return total - entry.amount
            case .transfer: return total
            }
        }
    }
    var trackedClosing: Int? { trackedOpening.map { $0 + monthlyInsight.net } }
    var cashProjections: [CashProjection] { cashAccounts.map { CashProjection(account: $0, entries: entries) } }
    var projectedCashMinor: Int64 { cashProjections.reduce(0) { $0 + $1.estimatedMinor } }
    var unassignedCashEntries: [Entry] {
        guard let oldest = oldestCashConfirmation else { return [] }
        return entries.filter { $0.date > oldest && $0.needsCashAssignment }
    }
    var confirmedCashMinor: Int64 { cashAccounts.reduce(0) { $0 + $1.balanceMinor } }
    var oldestCashConfirmation: Date? { cashAccounts.map(\.confirmedAt).min() }
    var latestCashConfirmation: Date? { cashAccounts.map(\.confirmedAt).max() }

    var cashSnapshotSummary: String {
        guard let oldest = cashAccounts.map(\.confirmedAt).filter({ $0 > .distantPast }).min(), let latest = latestCashConfirmation, latest > .distantPast else { return "Set your account balances · not live" }
        let first = oldest.formatted(.dateTime.day().month(.abbreviated))
        let last = latest.formatted(.dateTime.day().month(.abbreviated))
        return Calendar.current.isDate(oldest, inSameDayAs: latest) ?
            "Confirmed \(last) · not live" : "Mixed dates: \(first) – \(last) · not live"
    }

    func edit(_ entry: Entry, title: String, source: String, amount: Int, kind: EntryKind, date: Date, note: String, requiresReview: Bool, cashAccountID: String? = nil, destinationCashAccountID: String? = nil) async -> Bool {
        guard amount > 0, let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) else {
            errorMessage = "This transaction is no longer available, or its amount is invalid."
            return false
        }
        if (entries[index].title != title || entries[index].note != note), entries[index].categoryAssessment?.state != .manual {
            entries[index].categoryAssessment = CategoryAssessment(state: .pending, reason: "Description updated; queued for local AI.", at: .distantPast)
        }
        entries[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].amount = amount
        entries[index].kind = kind
        entries[index].date = date
        entries[index].note = note
        entries[index].requiresReview = requiresReview
        entries[index].cashAccountID = cashAccountID
        entries[index].destinationCashAccountID = destinationCashAccountID
        errorMessage = nil
        pending.insert(entry.fingerprint); savePending(); save()
        if isSignedIn { await refresh() }
        return true
    }

    func updateCashAccount(id: String, balanceMinor: Int64, at date: Date = .now) async {
        guard balanceMinor >= 0, let index = cashAccounts.firstIndex(where: { $0.id == id }) else { return }
        cashAccounts[index].balanceMinor = balanceMinor
        cashAccounts[index].confirmedAt = date
        saveCashAccounts()
        cashAccountsPending = true
        UserDefaults.standard.set(true, forKey: "firebaseCashAccountsPending")
        if isSignedIn { await refresh() }
    }
    var estimatedBalance: Int? {
        guard let snapshot = balanceSnapshot else { return nil }
        return entries.filter { $0.isConfirmed && $0.date > snapshot.date }.reduce(snapshot.amount) { total, entry in
            switch entry.kind {
            case .income: return total + entry.amount
            case .expense: return total - entry.amount
            case .transfer, .settlement: return total
            }
        }
    }

    func setBalanceSnapshot(amount: Int, date: Date) async {
        balanceSnapshot = BalanceSnapshot(amount: amount, date: date)
        saveBalance()
        balancePending = true
        UserDefaults.standard.set(true, forKey: "firebaseBalancePending")
        if isSignedIn { await refresh() }
    }

    func signIn(email: String, password: String, create: Bool) async {
        guard hasFirebaseConfig else { errorMessage = FirebaseError.missingConfiguration.localizedDescription; return }
        do {
            let endpoint = create ? "accounts:signUp" : "accounts:signInWithPassword"
            let url = URL(string: "https://identitytoolkit.googleapis.com/v1/\(endpoint)?key=\(apiKey)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "returnSecureToken": true])
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response, data: data)
            let auth = try JSONDecoder().decode(AuthReply.self, from: data)
            if let previousUID = Keychain.read("firebaseUID"), previousUID != auth.localId { throw FirebaseError.accountMismatch }
            Keychain.save(auth.refreshToken, as: "firebaseRefreshToken")
            Keychain.save(auth.localId, as: "firebaseUID")
            idToken = auth.idToken
            tokenExpiry = Date().addingTimeInterval(TimeInterval(auth.expiresIn) ?? 3600)
            accountEmail = auth.email ?? email
            UserDefaults.standard.set(accountEmail, forKey: "firebaseEmail")
            if !UserDefaults.standard.bool(forKey: "firebaseInitialUploadPrepared") {
                UserDefaults.standard.set(true, forKey: "firebaseInitialUploadPrepared")
                savePending()
            }
            await refreshGoogleProfile(force: true)
            await refresh()
        } catch { errorMessage = error.localizedDescription; syncStatus = "Sign-in failed" }
    }
    var googleConfigurationMessage: String? {
        guard hasFirebaseConfig else { return "Firebase configuration is missing." }
        guard let clientID = config["CLIENT_ID"] as? String, !clientID.isEmpty else {
            return "The configuration bundled with this app has no Google OAuth client ID. Add the updated Firebase Apple configuration for this app and rebuild Current."
        }
        guard config["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier else {
            return "Register this app's bundle ID in Firebase and add its Google Sign-In configuration."
        }
        let reverse = clientID.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        guard types.contains(where: { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(reverse) }) else {
            return "The Google callback URL is missing. Apply the updated Firebase configuration and rebuild Current."
        }
        return nil
    }

    func connectGoogleProfile() async {
        guard !connectingGoogle else { return }
        guard googleConfigurationMessage == nil, let clientID = config["CLIENT_ID"] as? String else {
            profileMessage = googleConfigurationMessage; return
        }
        connectingGoogle = true
        profileMessage = nil
        defer { connectingGoogle = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
                throw FirebaseError.server("Open Current before connecting Google.")
            }
            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            #else
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
                throw FirebaseError.server("Open a Current window before connecting Google.")
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            #endif
            guard let token = result.user.idToken?.tokenString else { throw FirebaseError.server("Google did not return a sign-in token.") }
            let priorUID = Keychain.read("firebaseUID")
            if !AccountIdentityPolicy.acceptsGoogleEmail(existingUID: priorUID, currentEmail: accountEmail, incomingEmail: result.user.profile?.email) {
                throw FirebaseError.server("Choose the same Google email as your Current account to keep your financial history together.")
            }
            var body: [String: Any] = ["requestUri": "http://localhost", "returnSecureToken": true, "returnIdpCredential": true]
            var post = URLComponents()
            post.queryItems = [URLQueryItem(name: "id_token", value: token), URLQueryItem(name: "providerId", value: "google.com")]
            body["postBody"] = post.percentEncodedQuery
            if priorUID != nil, googleProfile == nil { body["idToken"] = try await validIDToken() }
            var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response, data: data)
            let auth = try JSONDecoder().decode(AuthReply.self, from: data)
            guard AccountIdentityPolicy.accepts(existingUID: priorUID, incomingUID: auth.localId) else { throw FirebaseError.accountMismatch }
            Keychain.save(auth.refreshToken, as: "firebaseRefreshToken")
            Keychain.save(auth.localId, as: "firebaseUID")
            idToken = auth.idToken
            tokenExpiry = Date().addingTimeInterval(TimeInterval(auth.expiresIn) ?? 3600)
            accountEmail = auth.email ?? result.user.profile?.email ?? ""
            UserDefaults.standard.set(accountEmail, forKey: "firebaseEmail")
            UserDefaults.standard.set(true, forKey: "firebaseInitialUploadPrepared")
            await refreshGoogleProfile(force: true)
            await refresh()
        } catch {
            let ns = error as NSError
            if ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue { return }
            GIDSignIn.sharedInstance.signOut()
            profileMessage = error.localizedDescription
        }
    }

    func refreshGoogleProfile(force: Bool = false) async {
        guard isSignedIn, hasFirebaseConfig else { return }
        if !force, let checked = profileCheckedAt, Date().timeIntervalSince(checked) < 600 { return }
        do {
            var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(apiKey)")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": try await validIDToken()])
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response, data: data)
            let lookup = try JSONDecoder().decode(AccountLookup.self, from: data)
            guard let user = lookup.users?.first, user.localId == Keychain.read("firebaseUID") else { throw FirebaseError.accountMismatch }
            if let provider = user.providerUserInfo?.first(where: { $0.providerId == "google.com" }) {
                let photo = provider.photoUrl.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
                let profile = GoogleProfile(firebaseUID: user.localId, name: provider.displayName ?? "Google profile", email: provider.email ?? user.email ?? accountEmail, photoURL: photo)
                googleProfile = profile
                UserDefaults.standard.set(try JSONEncoder().encode(profile), forKey: "verifiedGoogleProfile")
            } else {
                googleProfile = nil
                UserDefaults.standard.removeObject(forKey: "verifiedGoogleProfile")
            }
            profileMessage = nil
            profileCheckedAt = .now
        } catch { if force { profileMessage = error.localizedDescription } }
    }

    func add(_ entry: Entry) async {
        let booking = AlertParser.bookingReference(in: entry.title)
        guard !entries.contains(where: {
            $0.fingerprint == entry.fingerprint ||
            (booking != nil && AlertParser.bookingReference(in: $0.title) == booking &&
             $0.amount == entry.amount && $0.kind == entry.kind)
        }) else { errorMessage = "Already in your ledger"; return }
        entries.insert(entry, at: 0)
        pending.insert(entry.fingerprint)
        if entry.kind != .transfer, let match = entries.firstIndex(where: {
            $0.id != entry.id && $0.source != entry.source && $0.amount == entry.amount &&
            abs($0.date.timeIntervalSince(entry.date)) < 48 * 3600 &&
            (($0.kind == .income && entry.kind == .expense) || ($0.kind == .expense && entry.kind == .income)) &&
            ($0.title.localizedCaseInsensitiveContains("transfer") || entry.title.localizedCaseInsensitiveContains("transfer") ||
             $0.title.localizedCaseInsensitiveContains("top up") || entry.title.localizedCaseInsensitiveContains("top up"))
        }) {
            entries[0].kind = .transfer
            entries[match].kind = .transfer
            pending.insert(entries[match].fingerprint)
        }
        savePending(); save()
        if isSignedIn { await refresh() }
    }
    func retryCategory(_ fingerprint: String) async {
        guard let index = entries.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        entries[index].categoryAssessment = nil
        pending.insert(fingerprint); savePending(); save()
        await classifyRecordedAlert(fingerprint)
    }

    func classifyRecordedAlert(_ fingerprint: String) async {
        await processCategoryQueue(only: fingerprint)
    }

    /// AI reads raw context only from a device-local sidecar. Firestore continues
    /// to receive the existing financial record plus category/result metadata.
    func processCategoryQueue(only fingerprint: String? = nil) async {
        guard !categoryEnrichmentInProgress else { return }
        let candidates = entries.filter { entry in
            if let fingerprint {
                return entry.fingerprint == fingerprint && entry.kind == .expense && entry.isConfirmed && entry.categoryAssessment == nil
            }
            return entry.needsAutomaticCategory || (entry.kind == .expense && entry.isConfirmed && entry.category == nil && entry.categoryAssessment == nil && LocalNotificationContext.shared.text(for: entry.fingerprint) != nil)
        }.prefix(fingerprint == nil ? 8 : 1)
        guard !candidates.isEmpty else { return }
        let engine = CategoryAI()
        if let reason = engine.unavailableReason {
            for candidate in candidates where candidate.categoryAssessment == nil {
                guard let index = entries.firstIndex(where: { $0.fingerprint == candidate.fingerprint }) else { continue }
                entries[index].categoryAssessment = CategoryAssessment(state: .pending, reason: reason, at: .now)
                pending.insert(candidate.fingerprint)
            }
            savePending(); save()
            if isSignedIn { await refresh() }
            return
        }
        categoryEnrichmentInProgress = true
        defer { categoryEnrichmentInProgress = false }
        var changed = false
        for original in candidates {
            do {
                let proposal = try await CategoryAI.classify(original, history: entries)
                guard let index = entries.firstIndex(where: { $0.fingerprint == original.fingerprint }), entries[index] == original else { continue }
                if proposal.suggested != .other && (proposal.changesCategory || original.category == nil) {
                    entries[index].categoryRevision = CategoryRevision(batchID: UUID(), appliedAt: .now, previousCategory: original.category, appliedCategory: proposal.suggested)
                    entries[index].category = proposal.suggested
                }
                let uncertain = proposal.suggested == .other || proposal.reason.localizedCaseInsensitiveContains("kept")
                entries[index].categoryAssessment = CategoryAssessment(state: uncertain ? .needsContext : .classified, reason: String(proposal.reason.prefix(240)), at: .now)
                pending.insert(original.fingerprint); changed = true
            } catch {
                guard let index = entries.firstIndex(where: { $0.fingerprint == original.fingerprint }), entries[index] == original else { continue }
                entries[index].categoryAssessment = CategoryAssessment(state: .pending, reason: "AI could not finish. Transaction saved; retry when Current is open.", at: .now)
                pending.insert(original.fingerprint); changed = true
                break
            }
        }
        if changed {
            savePending(); save()
            if isSignedIn { await refresh() }
        }
    }

    func addAlert(_ text: String, source: String? = nil) async {
        guard let parsed = AlertParser.parse(text, source: source) else { errorMessage = "No rupiah amount found. Add it manually instead."; return }
        LocalNotificationContext.shared.store(text, for: parsed.fingerprint)
        await add(Entry(source: parsed.source, title: parsed.title, amount: parsed.amount, kind: parsed.kind, date: parsed.date, fingerprint: parsed.fingerprint))
    }
    func update(_ entry: Entry, kind: EntryKind) async {
        guard let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) else { return }
        entries[index].kind = kind
        pending.insert(entry.fingerprint); savePending(); save()
        if isSignedIn { await refresh() }
    }
    var latestCategoryBatch: CategoryRevision? {
        entries.compactMap(\.categoryRevision).max { $0.appliedAt < $1.appliedAt }
    }
    func applyCategoryProposals(_ proposals: [CategoryProposal]) async -> Int {
        let changed = CategoryBatch.apply(proposals, to: &entries)
        pending.formUnion(changed); savePending(); save()
        if isSignedIn { await refresh() }
        return changed.count
    }
    func undoCategoryBatch(_ id: UUID, fingerprint: String? = nil) async {
        let changed = CategoryBatch.undo(id, in: &entries, fingerprint: fingerprint)
        pending.formUnion(changed); savePending(); save()
        if isSignedIn { await refresh() }
    }
    func updateCategory(_ entry: Entry, category: SpendingCategory?) async {
        guard let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) else { return }
        entries[index].category = category
        entries[index].categoryRevision = nil
        entries[index].categoryAssessment = CategoryAssessment(state: .manual, reason: "Category selected by you.", at: .now)
        pending.insert(entry.fingerprint); savePending(); save()
        if isSignedIn { await refresh() }
    }
    func remove(_ entry: Entry) async {
        entries.removeAll { $0.fingerprint == entry.fingerprint }
        pending.remove(entry.fingerprint)
        pendingDeletes.insert(entry.fingerprint)
        savePending(); save()
        if isSignedIn { await refresh() }
    }
    func refresh() async {
        guard hasFirebaseConfig else { syncStatus = "Firebase setup needed"; return }
        guard isSignedIn else { syncStatus = "On this device"; return }
        guard Date() >= quotaRetryAfter else {
            syncStatus = "Cloud quota reached · saved locally"
            syncIssue = "Cloud sync will retry after " + quotaRetryAfter.formatted(date: .omitted, time: .shortened) + ". Pending changes remain on this device."
            return
        }
        guard !syncInProgress else { return }
        syncInProgress = true
        defer { syncInProgress = false }
        syncStatus = "Syncing…"
        do {
            let remote = try await fetchDocuments()
            var remoteEntries: [String: Entry] = [:]
            var deleted = pendingDeletes
            var remoteCashAccountsFound = false
            for document in remote {
                let fingerprint = document.name.components(separatedBy: "/").last ?? ""
                if fingerprint == "__cash_accounts" {
                    if let payload = document.fields?["payload"]?.stringValue,
                       let accounts = try? JSONDecoder.iso.decode([CashAccount].self, from: Data(payload.utf8)) {
                        remoteCashAccountsFound = true
                        // Different devices may confirm different banks. Never replace
                        // a newer bank confirmation with an older portfolio document.
                        var reconciled = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
                        var hasNewerLocal = false
                        for local in cashAccounts {
                            if let remote = reconciled[local.id], remote.confirmedAt >= local.confirmedAt { continue }
                            reconciled[local.id] = local
                            hasNewerLocal = true
                        }
                        let order = cashAccounts.map(\.id) + accounts.map(\.id).filter { id in !cashAccounts.contains { $0.id == id } }
                        cashAccounts = order.compactMap { reconciled[$0] }
                        if hasNewerLocal {
                            cashAccountsPending = true
                            UserDefaults.standard.set(true, forKey: "firebaseCashAccountsPending")
                        }
                        saveCashAccounts()
                    }
                    continue
                }
                if fingerprint == "__balance_snapshot" {
                    if !balancePending, let payload = document.fields?["payload"]?.stringValue,
                       let snapshot = try? JSONDecoder.iso.decode(BalanceSnapshot.self, from: Data(payload.utf8)) {
                        balanceSnapshot = snapshot
                        saveBalance()
                    }
                    continue
                }
                if document.fields?["deleted"]?.booleanValue == true { deleted.insert(fingerprint); continue }
                if let payload = document.fields?["payload"]?.stringValue,
                   let entry = try? JSONDecoder.iso.decode(Entry.self, from: Data(payload.utf8)) { remoteEntries[fingerprint] = entry }
            }
            if !remoteCashAccountsFound {
                cashAccountsPending = true
                UserDefaults.standard.set(true, forKey: "firebaseCashAccountsPending")
            }
            var merged = remoteEntries
            for entry in entries where !deleted.contains(entry.fingerprint) {
                if remoteEntries[entry.fingerprint] == nil { pending.insert(entry.fingerprint) }
                if pending.contains(entry.fingerprint) { merged[entry.fingerprint] = entry }
            }
            entries = Array(merged.values).sorted { $0.date > $1.date }
                markTemporaryHoldsForReview()
            save(); savePending()
            for fingerprint in pendingDeletes { try await writeDocument(fingerprint: fingerprint, entry: nil, deleted: true); pendingDeletes.remove(fingerprint); savePending() }
            for fingerprint in pending {
                guard let entry = entries.first(where: { $0.fingerprint == fingerprint }), !deleted.contains(fingerprint) else { pending.remove(fingerprint); continue }
                try await writeDocument(fingerprint: fingerprint, entry: entry, deleted: false)
                pending.remove(fingerprint); savePending()
            }
            if balancePending, let balanceSnapshot {
                try await writeBalanceSnapshot(balanceSnapshot)
                balancePending = false
                UserDefaults.standard.set(false, forKey: "firebaseBalancePending")
            }
            if cashAccountsPending {
                try await writeCashAccounts()
                cashAccountsPending = false
                UserDefaults.standard.set(false, forKey: "firebaseCashAccountsPending")
            }
            syncStatus = pending.isEmpty && pendingDeletes.isEmpty && !cashAccountsPending ? "Firebase synced" : "Sync paused"
            quotaFailures = 0
            quotaRetryAfter = .distantPast
            syncIssue = nil
        } catch FirebaseError.quotaExceeded {
            quotaFailures += 1
            quotaRetryAfter = Date().addingTimeInterval(CloudRetryPolicy.quotaDelay(attempt: quotaFailures))
            syncStatus = "Cloud quota reached · saved locally"
            syncIssue = "Cloud sync will retry after " + quotaRetryAfter.formatted(date: .omitted, time: .shortened) + ". Pending changes remain on this device."
        } catch { syncStatus = "Sync paused"; errorMessage = error.localizedDescription }
    }
    private func fetchDocuments() async throws -> [FirestoreDocument] {
        var all: [FirestoreDocument] = []
        var pageToken: String?
        repeat {
            var url = URLComponents(string: collectionURL)!
            var items = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            url.queryItems = items
            let request = try await firestoreRequest(url: url.url!)
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response, data: data)
            let page = try JSONDecoder().decode(FirestoreList.self, from: data)
            all.append(contentsOf: page.documents ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }
    private func writeDocument(fingerprint: String, entry: Entry?, deleted: Bool) async throws {
        let encodedID = fingerprint.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fingerprint
        var request = try await firestoreRequest(url: URL(string: collectionURL + "/" + encodedID)!)
        request.httpMethod = "PATCH"
        let payload = entry.flatMap { try? String(data: JSONEncoder.iso.encode($0), encoding: .utf8) } ?? ""
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": [
            "payload": ["stringValue": payload],
            "deleted": ["booleanValue": deleted]
        ]])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
    }
    private func writeBalanceSnapshot(_ snapshot: BalanceSnapshot) async throws {
        var request = try await firestoreRequest(url: URL(string: collectionURL + "/__balance_snapshot")!)
        request.httpMethod = "PATCH"
        let payload = String(data: try JSONEncoder.iso.encode(snapshot), encoding: .utf8) ?? ""
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": [
            "payload": ["stringValue": payload],
            "deleted": ["booleanValue": false]
        ]])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
    }
    private func writeCashAccounts() async throws {
        var request = try await firestoreRequest(url: URL(string: collectionURL + "/__cash_accounts")!)
        request.httpMethod = "PATCH"
        let payload = String(data: try JSONEncoder.iso.encode(cashAccounts), encoding: .utf8) ?? ""
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": [
            "payload": ["stringValue": payload],
            "deleted": ["booleanValue": false]
        ]])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
    }
    private var collectionURL: String {
        let uid = Keychain.read("firebaseUID") ?? ""
        return "https://firestore.googleapis.com/v1/projects/\(firebaseProjectID)/databases/(default)/documents/users/\(uid)/entries"
    }
    private func firestoreRequest(url: URL) async throws -> URLRequest {
        let token = try await validIDToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func validIDToken() async throws -> String {
        if !idToken.isEmpty && tokenExpiry > Date().addingTimeInterval(90) { return idToken }
        guard let refreshToken = Keychain.read("firebaseRefreshToken") else { throw FirebaseError.notSignedIn }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: refreshToken)]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        let auth = try JSONDecoder().decode(RefreshReply.self, from: data)
        idToken = auth.id_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(auth.expires_in) ?? 3600)
        Keychain.save(auth.refresh_token, as: "firebaseRefreshToken")
        Keychain.save(auth.user_id, as: "firebaseUID")
        return idToken
    }
    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw FirebaseError.server("No response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = body?["error"] as? [String: Any]
            let message = detail?["message"] as? String ?? "HTTP \(http.statusCode)"
            if CloudRetryPolicy.isQuota(statusCode: http.statusCode, status: detail?["status"] as? String, message: message) {
                throw FirebaseError.quotaExceeded
            }
            throw FirebaseError.server(message)
        }
    }
    private func savePending() {
        UserDefaults.standard.set(Array(pending), forKey: "firebasePending")
        UserDefaults.standard.set(Array(pendingDeletes), forKey: "firebasePendingDeletes")
    }
    private func save() { if let data = try? JSONEncoder().encode(entries) { try? data.write(to: localURL, options: .atomic) } }
    private func saveBalance() { if let balanceSnapshot, let data = try? JSONEncoder().encode(balanceSnapshot) { try? data.write(to: balanceURL, options: .atomic) } }
    private func saveCashAccounts() { if let data = try? JSONEncoder().encode(cashAccounts) { try? data.write(to: cashAccountsURL, options: .atomic) } }
}
