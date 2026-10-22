# Calculations and data boundaries

- **Spent:** confirmed purchase records in the selected calendar month.
- **Income:** confirmed income records in the selected calendar month.
- **Bills paid:** cash used to settle existing debt; not a second purchase.
- **Moved:** recorded transfers between your own accounts; excluded from income and spending. Separate route legs can appear in this activity total.
- **Cash flow:** income − purchases − bills paid. This is not a bank balance.
- **Carryover:** the transaction trail from the earliest recorded confirmed income. Earlier funds and missing transactions are unknown.
- **Needs review:** visible in Activity but excluded from confirmed money summaries and category charts.
- **Own money:** separate confirmed snapshot and estimated totals. Estimates replay assigned, confirmed movements strictly after each account’s snapshot, using integer minor units. Income increases cash; purchases and debt settlement reduce it. Transfers require explicit source and destination accounts. Reconfirming a balance advances its cutoff, preventing double subtraction. Unknown funding stays visible for review. Credit limits, paylater availability and reward points are excluded. Mixed snapshot dates are labelled explicitly.

New public builds contain no imported financial history. Account presets begin at zero with an unconfirmed timestamp; set actual balances yourself. No real bank balances or transactions are bundled in this repository.

The health view uses simple recorded-cash-flow thresholds (20% retention and 30% bill share). Incomplete data, one-off repayments and pre-existing savings can materially change the interpretation. Labels are informational and are not a personalized financial recommendation.

The app does not access bank APIs, third-party notification history or mailbox databases. Vision reads screenshots only when the user chooses/pastes an image. Review OCR output before saving. A Shortcut must actually supply alert text to the App Intent before it can be parsed.

## Local category AI

Apple Intelligence can classify purchase descriptions and original alert context on eligible devices. Bulk changes require reviewing proposals; per-record and batch Undo preserve previous categories, and later manual edits win. New captures are saved before enrichment, so model unavailability does not discard a transaction. Temporary card holds are excluded until a completed charge is received. Raw notification context lives only in a device-local sidecar excluded from backups; Firebase receives category/result metadata with the existing financial record. Context captured on one device is not copied to another device.

Temporary authorizations are not completed purchases. Both alert capture and pasted/OCR input reject hold notices. Older hold records remain visible with a Hold label, but are excluded from confirmed totals even if an older client marked them reviewed. A separate completed-charge notification can be recorded; equal amounts alone do not establish that two messages describe the same booking.
