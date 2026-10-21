# Google Profile

Current uses the official Google Sign-In SDK and Firebase Authentication. Add your own target-specific GoogleService-Info.plist to each platform's Resources folder. These files are Git-ignored; only empty examples are committed.

The build phase generates the reversed client-ID callback scheme automatically. An absent client ID or a configuration belonging to another bundle ID leaves the connection in a visible setup state instead of invoking an invalid SDK configuration.

For an existing Current session, Google is linked to the same Firebase UID. Owner continuity and email checks prevent accepting a different account over an existing local ledger. Linking conflicts do not move financial records between users. Profile metadata comes from the verified google.com provider in Firebase accounts:lookup and is cached locally against the Firebase UID.

Only basic profile information is requested: name, email and photo. There are no Gmail, contacts or Drive scopes. Once an account is linked, another device signed into that same Firebase account can fetch its Google profile without repeating the consent flow. Initiating Google sign-in on native Mac still requires a matching Mac OAuth client.

[Google integration guide](https://developers.google.com/identity/sign-in/ios/sign-in) · [Firebase account linking](https://firebase.google.com/docs/reference/rest/auth#section-link-with-oauth-credential)
