# Pluvas' Auctions

Auction house price tracking and auction profit tracking for **World of Warcraft: Forever**.

## Features

**Price scanning and history**
- **Full scan** with the button under the auction house window, or `/pa scan`. It reads every
  auction at once. The server allows one full scan per account every 15 minutes, and the button
  counts that down.
- **Passive capture**: anything you browse or search in the normal AH window also updates prices.
- For each item it stores the **market value**, the **lowest buyout**, the **quantity listed**, and
  **60 days of daily history**. The market value is the average of the cheapest 30% of listed units,
  skipping listings far from their median, so one misprice cannot skew it.
- **Tooltips**: AH market, AH lowest, the 14-day average, and the average price you sold the item at,
  shown with gold, silver and copper coin icons. For a stack in your bags it also shows the
  market value of the whole stack and what is left after the 5% AH cut and the 1 silver deposit.
- **Craft cost**: for items this character can craft, the tooltip shows what the mats cost on the
  AH (for the whole stack). Mats you can craft yourself are priced from *their* mats, all the
  way down to the base mats (bag -> bolts -> cloth). Below it, a list of those base mats with
  how many you need and what each costs. Open each profession window once so the
  addon can read your recipes; it rereads them every time you open it.
- **Profession window**: the selected recipe shows its mats cost, what the item sells for on the
  AH, what is left after the AH cut and deposit, the profit, and the list of base mats.
- **Bugs stay contained**: if part of the addon keeps erroring, it turns itself off until `/reload`
  instead of throwing an error on every hover.
- Random-suffix items ("of the Bear") are priced separately.

**Sales and profit tracking**
- Reads auction invoice mail ("Auction successful" and "Auction won") whenever your mailbox is open.
  The same mail is never counted twice.
- **Ledger window** (`/pa`, or right-click the scan button): sales, AH cut, purchases and profit
  for today, 7 days, 30 days and all time, plus recent transactions and top items (30 days).
- **Gold tracking**: total gold across your characters on the realm/faction, and how much it has
  changed since yesterday.

Data is kept per realm (ruleset) and faction in the `PluvasAuctionsDB` saved variable.

## Commands

| Command | What it does |
| --- | --- |
| `/pa` | Open or close the ledger window |
| `/pa scan` | Full AH scan (AH must be open) |
| `/pa price <item link>` | Print stored prices for an item |
| `/pa tooltip` | Turn the tooltip lines on or off |
| `/pa resetprices` | Delete price data for this realm/faction |
| `/pa resetledger` | Delete the sales history for this realm/faction |

## Files

| File | Role |
| --- | --- |
| `Core.lua` | Namespace, events, saved variables, slash commands |
| `Crafting.lua` | Reads your recipes from the profession window, works out mats cost |
| `ProfessionsUI.lua` | Mats cost and profit panel in the profession window |
| `Util.lua` | Money, time and string formatting |
| `Pricing.lua` | Item keys, market value statistics, price database and history |
| `Scanner.lua` | Full scan (`ReplicateItems`) and passive capture from browse and search results |
| `Ledger.lua` | Reading auction mail, merging transactions, summaries, gold tracking |
| `Tooltip.lua` | Tooltip lines and `/pa price` |
| `UI.lua` | Ledger window and the scan button on the auction house frame |

## Known limits

- Deposits lost on expired or cancelled auctions are not counted yet.
- A sale appears in the ledger only once its mail reaches your mailbox.

## Changelog

- **0.1.1**: tooltip prices use gold, silver and copper coin icons. Tooltips show the stack's
  total market value and the amount left after the AH cut and deposit. Tooltips show the AH cost of
  mats for items you can craft, pricing craftable mats from their own mats. The profession
  window shows mats cost, sale value and profit for the selected recipe. Both list the base
  mats. The deposit is a flat 1 silver per auction. Repeated errors turn the failing feature off instead of
  spamming errors.
- **0.1.0**: first version. Full scan, passive capture, price history and tooltips, mail ledger,
  gold tracking.
