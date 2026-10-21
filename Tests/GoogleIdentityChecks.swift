import Foundation

@main struct GoogleIdentityChecks {
    static func main() {
        precondition(AccountIdentityPolicy.accepts(existingUID: nil, incomingUID: "new-owner"))
        precondition(AccountIdentityPolicy.accepts(existingUID: "owner", incomingUID: "owner"))
        precondition(!AccountIdentityPolicy.accepts(existingUID: "owner", incomingUID: "other-owner"))
        precondition(!AccountIdentityPolicy.accepts(existingUID: nil, incomingUID: ""))
        precondition(AccountIdentityPolicy.acceptsGoogleEmail(existingUID: "owner", currentEmail: "Me@example.com", incomingEmail: "me@example.com"))
        precondition(!AccountIdentityPolicy.acceptsGoogleEmail(existingUID: "owner", currentEmail: "me@example.com", incomingEmail: "other@example.com"))
        precondition(!AccountIdentityPolicy.acceptsGoogleEmail(existingUID: "owner", currentEmail: "me@example.com", incomingEmail: nil))
        precondition(AccountIdentityPolicy.acceptsGoogleEmail(existingUID: nil, currentEmail: "", incomingEmail: "new@example.com"))
        print("PASS: owner continuity, first login, email case handling and rejection of different or incomplete Google identities.")
    }
}
