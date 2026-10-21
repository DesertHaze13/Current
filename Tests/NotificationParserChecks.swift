import Foundation

@main struct NotificationParserChecks {
    static func main() {
        let body = "Your Amex 0000 has been charged RP 36.380,00 for booking A-DEMOBOOKING001."
        let time = Date(timeIntervalSince1970: 1_792_563_163)
        guard let p = AlertParser.parseNotification(body, at: time) else { fatalError("Grab charge rejected") }
        precondition(p.amount == 36_380 && p.kind == .expense && p.source == "Grab")
        precondition(AlertParser.bookingReference(in: p.title) == "A-DEMOBOOKING001")
        let again = AlertParser.parseNotification("Grab\n" + body, at: time.addingTimeInterval(86400))
        precondition(again?.fingerprint == p.fingerprint, "Same booking must dedupe across delivery headers/days")
        let alternate = AlertParser.parseNotification(body.replacingOccurrences(of: "RP 36.380,00", with: "IDR 36,380.00"), at: time)
        precondition(alternate?.amount == 36_380 && alternate?.fingerprint == p.fingerprint)
        let next = AlertParser.parseNotification(body.replacingOccurrences(of: "DEMOBOOKING001", with: "DIFFERENT1234"), at: time)
        precondition(next != nil && next?.fingerprint != p.fingerprint, "Equal amounts on separate bookings must remain separate")
        precondition(AlertParser.parseNotification("Your card has been charged Rp45.000", at: time)?.amount == 45_000)
        precondition(AlertParser.parseNotification("Besok repot? Atur sekarang! Pesanan Terjadwal bikin kamu bebas pesan makan hingga dua hari ke depan.", at: time) == nil)
        precondition(AlertParser.parseNotification("Grab promo: Cashback Rp10.000 for your next payment.", at: time) == nil)
        precondition(AlertParser.parseNotification("Promo diskon Rp20.000 untuk transaksi berikutnya", at: time) == nil)
        precondition(AlertParser.parseNotification("Your card has not been charged Rp36.380", at: time) == nil)
        precondition(AlertParser.parseNotification("Your card will be charged Rp36.380", at: time) == nil)
        precondition(AlertParser.parseNotification("Card declined. Payment failed Rp36.380", at: time) == nil)
        precondition(AlertParser.parseNotification("Payment pending Rp36.380", at: time) == nil)
        precondition(AlertParser.parseNotification("Payment successful Rp36.380. Balance Rp500.000", at: time) == nil)
        precondition(AlertParser.parseNotification("DANA pembayaran berhasil Rp30.000", at: time)?.kind == .expense)
        precondition(AlertParser.parseNotification("DANA top up Rp90.000 ke rekening sendiri", at: time)?.kind == .transfer)
        precondition(AlertParser.parseNotification("Salary received IDR5,000,000.00", at: time)?.kind == .income)
        precondition(AlertParser.parseNotification("Cashback received Rp5.000", at: time)?.kind == .income)
        print("PASS: exact Grab Amex receipt, source, amount formats, booking deduplication, separate bookings, promotions, failed/future/pending payments, multiple amounts, and existing transaction types.")
    }
}
