# Record Transactions — Current companion

- **Install from iCloud:** [Record Transactions](https://www.icloud.com/shortcuts/d7f179ec8fc3412b949ffe5897091d70)
- **Import file:** [Record Transactions.shortcut](Record%20Transactions.shortcut)
- **Inspectable source:** [Record Transactions.plist](Record%20Transactions.plist)

The `.shortcut` file is the original Apple-signed download from the supplied iCloud share; its signed bytes have not been edited. The XML plist is an inspection copy of the workflow source. Prefer the iCloud link for installation if your browser does not import the repository file directly.

## Included workflow

The inspected file contains exactly one Current action:

```text
Notification trigger → Current: Record transaction from alert
Notification text: trigger output
App: Auto detect
Show when run: false
```

Its selected apps are **DANA, BRImo, GoPay, Gojek, Grab, SeaBank, Flip, myBCA, Shopee, wondr by BNI, LinkAja, and Yup**. Jenius and Honest are not selected in this supplied version; add them on your device if your OS exposes the necessary trigger and the apps are installed.

The workflow calls bundle `com.dony.currentledger`, intent `RecordTransactionFromAlertIntent`. If you build Current under another bundle ID or signing team, reselect your installed Current action in Shortcuts. The original signed file carries its author's App Intent identity; this is not a credential.

## Setup on iPhone/iPad

1. Install and open Current at least once so its App Intent is registered.
2. Import the Shortcut through the iCloud link or the signed file.
3. Open its editor and verify that the Current action resolves to the app on that device.
4. Review the notification trigger, selected apps, permissions and automatic-run setting **on each device**. OS support and terminology can differ. Importing or iCloud-syncing a workflow does not prove its trigger is active.
5. Sign in to Current if you want financial records synchronized across devices.
6. Test with one clear transaction and verify it appears only once in Activity. If a trigger is unavailable, use Current's paste/screenshot capture instead.

## Limits and privacy

The file includes a serialized `WFNotificationTrigger`; that confirms the shared workflow's configuration, not universal OS support or successful delivery of future notifications. It does not read notification history, other apps' databases, Notes, email or SMS stores. It contains no embedded API token, bank login or external upload action. Current itself syncs records to the Firebase project configured by its builder.

Current accepts one clear rupiah amount and completed movement wording. Promotions, failures, future charges, multiple amounts and ambiguous messages can be skipped. Booking references are used to deduplicate matching charges; unrelated messages about the same purchase may still require review. Check statements for completeness.

The native Mac app receives records through Firebase. This iOS Shortcut's App Intent binding is not a separate Mac notification listener. The Watch receives summaries through the paired iPhone.
