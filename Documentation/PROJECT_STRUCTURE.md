# Platform structure

```text
Sources/
  iOS/
    App/             Universal iPhone/iPad entry point and App Intents
    Features/        Dashboard, Spending, Capture and transaction editing
    DesignSystem/    Shared adaptive pages and interaction components
    Services/        Firebase REST ledger and WatchConnectivity bridge
    Domain/          Entries, categories, summary and empty import scaffold
  Watch/App/         Read-only watchOS companion
  macOS/             Native Mac entry point and platform-specific forms
Resources/           Icon Composer artwork, assets and Firebase examples
Shortcuts/           Signed companion workflow, XML source and installation guide
Scripts/             Configuration generation and local checks
Tests/               Fictional parser, spending and identity fixtures
```

`Current` builds one universal iOS/iPadOS app and embeds `CurrentWatch`. `CurrentMac` is a separate native macOS app, not a stretched iOS binary. Domain/services and shared SwiftUI pages are members of the appropriate iOS/Mac targets. WatchSummary is shared with watchOS.

Compact layouts use a labelled dock. Larger iPad windows use sidebar navigation. Dashboard content uses two columns from 780 available content points and three from 1220; Activity adds a side inspector from 980; Spending shows chart, categories and records together from 1250. Layouts respond to actual available window width.
