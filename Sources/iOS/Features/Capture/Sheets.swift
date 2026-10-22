import SwiftUI
import UIKit
import PhotosUI
import Vision
import CryptoKit

struct AddView: View {
    @EnvironmentObject var ledger: Ledger
    @Environment(\.dismiss) var dismiss
    var onClose: (() -> Void)? = nil
    @State private var mode = 0
    @State private var source = "Auto detect"
    @State private var raw = ""
    @State private var amount = ""
    @State private var title = ""
    @State private var kind: EntryKind = .expense
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var readingScreenshot = false
    @State private var reviewedAmount = ""
    @State private var reviewedTitle = ""
    @State private var reviewedKind: EntryKind = .expense
    @State private var reviewedDate = Date()
    private var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    var body: some View {
        NavigationStack {
            ZStack {
                CurrentCanvas()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CurrentCaptureWelcome(title: "A new money moment", subtitle: "Paste a message or choose a screenshot. Check the details, then make it part of your story.")
                        Picker("Mode", selection: $mode) { Text("Paste alert").tag(0); Text("Manual").tag(1) }.pickerStyle(.segmented)
                        if mode == 0 {
                            TextEditor(text: $raw).scrollContentBackground(.hidden).frame(minHeight: 155).padding(12).background(surface, in: RoundedRectangle(cornerRadius: 22))
                            HStack(spacing: 16) {
                                Button { pasteClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard").font(.subheadline.bold()) }
                                PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                                    Label("Choose screenshot", systemImage: "photo.on.rectangle").font(.subheadline.bold())
                                }
                            }
                            if readingScreenshot { ProgressView("Reading screenshot…") }
                            if let preview = AlertParser.parse(raw, source: source) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("SUGGESTED FROM TEXT").font(.caption2.bold()).tracking(2).foregroundStyle(.mint)
                                    Text(preview.amount.rupiah).font(.title2.bold())
                                    Text("\(preview.kind.title) · \(preview.source)").foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(surface, in: RoundedRectangle(cornerRadius: 20))
                                TextField("Transaction description", text: $reviewedTitle)
                                    .padding(16).background(surface, in: RoundedRectangle(cornerRadius: 17))
                                TextField("Transaction amount in rupiah", text: $reviewedAmount).keyboardType(.numberPad)
                                    .padding(16).background(surface, in: RoundedRectangle(cornerRadius: 17))
                                Picker("Movement", selection: $reviewedKind) {
                                    ForEach(EntryKind.allCases, id: \.self) { item in Text(item == .settlement ? "Bill" : item.title).tag(item) }
                                }.pickerStyle(.segmented)
                                DatePicker("Transaction date", selection: $reviewedDate, displayedComponents: .date)
                                Text("Save one transaction at a time. A balance screen or a list of transactions needs your review; OCR can misread amounts and dates.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            TextField("Description", text: $title).textInputAutocapitalization(.words)
                                .padding(16).background(surface, in: RoundedRectangle(cornerRadius: 17))
                            TextField("Amount in rupiah", text: $amount).keyboardType(.numberPad)
                                .padding(16).background(surface, in: RoundedRectangle(cornerRadius: 17))
                            Picker("Movement", selection: $kind) { ForEach(EntryKind.allCases, id: \.self) { item in Text(item == .settlement ? "Bill" : item.title).tag(item) } }.pickerStyle(.segmented)
                        }
                        Menu {
                            ForEach(["Auto detect"] + AlertParser.sources + ["Credit card", "Other"], id: \.self) { item in Button(item) { source = item } }
                        } label: {
                            HStack { Text("Source"); Spacer(); Text(source).foregroundStyle(.mint); Image(systemName: "chevron.down") }
                                .padding(16).background(surface, in: RoundedRectangle(cornerRadius: 17))
                        }
                        Text("Current can’t read notification history itself. For new alerts, set up a Shortcuts Notification automation and pass its text to Current’s Record alert action. Otherwise, paste or share an alert here for review.").font(.caption).foregroundStyle(.secondary)
                        Button { Task { await save() } } label: { Text("Add to my story").font(.headline).frame(maxWidth: .infinity).padding(17).background(.indigo.gradient, in: Capsule()).foregroundStyle(.white) }
                    }.padding(22)
                }
            }.navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { close() } } }.tint(.mint)
                .onChange(of: raw) { _, _ in prepareReview() }
                .onChange(of: source) { _, _ in prepareReview() }
                .onChange(of: selectedScreenshot) { _, item in
                    guard let item else { return }
                    Task {
                        readingScreenshot = true
                        defer { readingScreenshot = false }
                        guard let data = try? await item.loadTransferable(type: Data.self) else {
                            ledger.errorMessage = "Could not open this screenshot. Try another image."
                            return
                        }
                        await importScreenshot(data)
                    }
                }
        }
    }
    private func pasteClipboard() {
        if let image = UIPasteboard.general.image, let data = image.pngData() {
            Task { await importScreenshot(data) }
        } else if let text = UIPasteboard.general.string, !text.isEmpty {
            raw = text
        } else {
            ledger.errorMessage = "No text or image found on the clipboard."
        }
    }
    private func importScreenshot(_ data: Data) async {
        readingScreenshot = true
        defer { readingScreenshot = false }
        do {
            let text = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(data: data, options: [:]).perform([request])
                return (request.results ?? [])
                    .sorted { left, right in
                        abs(left.boundingBox.midY - right.boundingBox.midY) > 0.015
                            ? left.boundingBox.midY > right.boundingBox.midY
                            : left.boundingBox.minX < right.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            }.value
            guard !text.isEmpty else { ledger.errorMessage = "No readable text found in this screenshot."; return }
            raw = text
        } catch {
            ledger.errorMessage = "Could not read this screenshot: \(error.localizedDescription)"
        }
    }
    private func prepareReview() {
        guard let suggestion = AlertParser.parse(raw, source: source) else {
            reviewedAmount = ""
            reviewedTitle = ""
            return
        }
        reviewedAmount = String(suggestion.amount)
        reviewedTitle = suggestion.title
        reviewedKind = suggestion.kind
        reviewedDate = suggestion.date
    }
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
    private func save() async {
        ledger.errorMessage = nil
        if mode == 0 {
            guard !AlertParser.isAuthorizationHold(raw) else {
                ledger.errorMessage = AlertParser.notificationSkipReason(raw); return
            }
            guard let suggestion = AlertParser.parse(raw, source: source),
                  let value = Int(reviewedAmount.filter(\.isNumber)), value > 0 else {
                ledger.errorMessage = "Choose a transaction and enter its amount before saving."
                return
            }
            let cleanTitle = reviewedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let day = Int(Calendar.current.startOfDay(for: reviewedDate).timeIntervalSince1970)
            let key = "\(suggestion.fingerprint)|\(value)|\(reviewedKind.rawValue)|\(day)|\(cleanTitle)"
            let fingerprint = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            LocalNotificationContext.shared.store(raw, for: fingerprint)
            await ledger.add(Entry(source: suggestion.source, title: cleanTitle.isEmpty ? suggestion.title : cleanTitle,
                                   amount: value, kind: reviewedKind, date: reviewedDate, fingerprint: fingerprint,
                                   note: "Reviewed from pasted text or screenshot."))
        }
        else if let value = Int(amount.filter(\.isNumber)), value > 0 {
            let entry = Entry(source: source == "Auto detect" ? "Manual" : source, title: title.isEmpty ? kind.title : title, amount: value, kind: kind, date: .now, fingerprint: UUID().uuidString)
            await ledger.add(entry)
        } else { ledger.errorMessage = "Enter an amount greater than zero."; return }
        if ledger.errorMessage == nil { Task { await ledger.processCategoryQueue() }; close() }
    }
}

struct CashAccountEditor: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    let account: CashAccount
    @State private var amount = ""
    @State private var confirmedAt = Date()
    @State private var invalidAmount = false

    var body: some View {
        NavigationStack {
            Form {
                Section(account.name) {
                    TextField("Confirmed balance in rupiah", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Confirmed at", selection: $confirmedAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Text("Only money you own belongs in this balance. Credit limits, paylater availability, and reward points are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Update balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let minor = CashAccount.parseRupiah(amount) else { invalidAmount = true; return }
                        Task { await ledger.updateCashAccount(id: account.id, balanceMinor: minor, at: confirmedAt); dismiss() }
                    }.fontWeight(.bold)
                }
            }
            .alert("Enter a valid balance", isPresented: $invalidAmount) { Button("OK") {} }
            .onAppear {
                amount = CashAccount.rupiah(account.balanceMinor)
                confirmedAt = account.confirmedAt
            }
        }
        .tint(.mint)
    }
}

struct SettingsView: View {
    @EnvironmentObject var ledger: Ledger
    @Environment(\.dismiss) var dismiss
    @State private var iconPlayground = false
    @State private var email = ""
    @State private var password = ""
    @State private var startingBalance = ""
    @State private var balanceDate = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CurrentCaptureWelcome(title: "Make yourself at home.", subtitle: "Your account, your devices, your money.")
                }.listRowBackground(Color.clear)
                Section("Your account & sync") {
                    Text(ledger.hasFirebaseConfig ? "Cloud sync is ready" : "Cloud sync needs configuration")
                    if ledger.isSignedIn {
                        Text("Signed in as \(ledger.accountEmail)")
                        Button("Sync now") { Task { await ledger.refresh() } }
                    } else {
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                        Button("Sign in") { Task { await ledger.signIn(email: email, password: password, create: false); password = "" } }
                        Button("Create account") { Task { await ledger.signIn(email: email, password: password, create: true); password = "" } }
                    }
                    Text(ledger.syncStatus).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Advanced: separate net position estimate") {
                    TextField("Starting total in rupiah", text: $startingBalance).keyboardType(.numbersAndPunctuation)
                    DatePicker("Balance as of", selection: $balanceDate, displayedComponents: [.date, .hourAndMinute])
                    Button("Save balance snapshot") {
                        let digits = startingBalance.filter(\.isNumber)
                        guard let amount = Int(digits) else { ledger.errorMessage = "Enter a starting balance in rupiah."; return }
                        let signed = startingBalance.contains("-") ? -amount : amount
                        Task { await ledger.setBalanceSnapshot(amount: signed, date: balanceDate) }
                    }
                    Text("This older estimate is separate from the confirmed own-money banner. It may include debt and projects from a starting figure using incomplete transactions. Update individual account balances from the expanded banner for the money you actually own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                    }
                Section("A little play") {
                    Button("Open icon playground", systemImage: "sparkles") { iconPlayground = true }
                }
                Section("Your starting point") {
                    Text("This public build starts with an empty transaction ledger. Add and review your own transactions. Own-account transfers and debt repayments are kept separate from new purchases.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("How capture works") {
                    Text("iOS does not give this app access to notifications from BRImo, DANA, Flip, GoPay, Jenius, LinkAja, myBCA, SeaBank, Yup, Honest, or wondr by BNI. Paste transaction text or a screenshot, choose a screenshot from Photos, or add entries manually.")
                    Text("Credit card emails and SMS can be pasted here. Direct mailbox imports require an account connection and permission that this starter does not include.")
                    Text("Own-account transfers and bill settlements are excluded from new spending. Review any alert marked as a transfer, especially payments to another person.")
                }
                Section("Privacy") { Text("Entries stay on this iPhone until you sign in. Firebase Authentication stores your account, and Firestore syncs your entries. Your sign-in session is stored in Keychain.") }
            }.sheet(isPresented: $iconPlayground) { IconComposerView() }.scrollContentBackground(.hidden).background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("App settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .tint(.mint)
                .onAppear {
                    email = ledger.accountEmail
                    if let snapshot = ledger.balanceSnapshot {
                        startingBalance = String(snapshot.amount)
                        balanceDate = snapshot.date
                    }
                }
        }
    }
}

struct BrandMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(LinearGradient(colors: [Color(red: 0.66, green: 1, blue: 0.88), .teal, Color(red: 0.06, green: 0.16, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.62), lineWidth: size * 0.035).frame(width: size * 0.58).blur(radius: size * 0.01)
            Circle().stroke(.white.opacity(0.55), lineWidth: size * 0.03).frame(width: size * 0.37).offset(x: size * 0.09, y: -size * 0.07)
            Circle().fill(.white).frame(width: size * 0.16).offset(x: size * 0.12, y: -size * 0.09).blur(radius: size * 0.022)
            RoundedRectangle(cornerRadius: size * 0.03).fill(.white.opacity(0.8)).frame(width: size * 0.45, height: size * 0.055).rotationEffect(.degrees(-37)).offset(x: -size * 0.025, y: size * 0.12)
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.29))
            .overlay(RoundedRectangle(cornerRadius: size * 0.29).stroke(.white.opacity(0.5), lineWidth: size * 0.012))
    }
}

struct IconComposerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var tilt = false
    @State private var radiance = true
    var body: some View {
        ZStack {
            CurrentCanvas()
            VStack(spacing: 27) {
                HStack { Text("ICON COMPOSER").font(.caption.bold()).tracking(3).foregroundStyle(.mint); Spacer(); Button("Done") { dismiss() } }.padding(.horizontal, 25)
                Spacer()
                BrandMark(size: 240).rotation3DEffect(.degrees(tilt ? 11 : -11), axis: (x: 0.7, y: 1, z: 0))
                    .shadow(color: .mint.opacity(radiance ? 0.55 : 0.12), radius: radiance ? 60 : 15)
                    .animation(.spring(response: 0.7, dampingFraction: 0.55), value: tilt)
                    .animation(.easeInOut(duration: 0.35), value: radiance)
                Text("A living current").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("The inner orbit is the money you keep. The flowing line is every move you make.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 42)
                HStack(spacing: 12) {
                    Button { tilt.toggle() } label: { Label("Tilt", systemImage: "rotate.3d").frame(maxWidth: .infinity).padding(14) }
                    Button { radiance.toggle() } label: { Label("Glow", systemImage: "sparkles").frame(maxWidth: .infinity).padding(14) }
                }.buttonStyle(.bordered).tint(.mint).padding(.horizontal, 24)
                Spacer()
            }.padding(.vertical, 24)
        }
    }
}
