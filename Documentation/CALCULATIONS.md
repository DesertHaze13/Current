# Calculations and data boundaries

- **Spent:** confirmed purchase records in the selected calendar month.
- **Income:** confirmed income records in the selected calendar month.
- **Bills paid:** cash used to settle existing debt; not a second purchase.
- **Moved:** recorded transfers between your own accounts; excluded from income and spending. Separate route legs can appear in this activity total.
- **Cash flow:** income − purchases − bills paid. This is not a bank balance.
- **Carryover:** the transaction trail from the earliest recorded confirmed income. Earlier funds and missing transactions are unknown.
- **Needs review:** visible in Activity but excluded from confirmed money summaries and category charts.
- **Own money:** sum of individually confirmed bank/wallet balance snapshots. Credit limits, paylater availability and reward points are excluded. Mixed snapshot dates are labelled explicitly.

New public builds contain no imported financial history. Account presets begin at zero with an unconfirmed timestamp; set actual balances yourself. No real bank balances or transactions are bundled in this repository.

The health view uses simple recorded-cash-flow thresholds (20% retention and 30% bill share). Incomplete data, one-off repayments and pre-existing savings can materially change the interpretation. Labels are informational and are not a personalized financial recommendation.

The app does not access bank APIs, third-party notification history or mailbox databases. Vision reads screenshots only when the user chooses/pastes an image. Review OCR output before saving. A Shortcut must actually supply alert text to the App Intent before it can be parsed.
