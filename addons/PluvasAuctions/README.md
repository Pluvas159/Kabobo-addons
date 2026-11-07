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
- **Craft cost**: for items this character can craft, the tooltip shows what the mats cost
  (for the whole stack). Each mat is priced at the cheaper of its AH price and its vendor price. Mats you can craft yourself are priced from *their* mats, all the
  way down to the base mats (bag -> bolts -> cloth). Below it, a list of those base mats with
  how many you need and what each costs. Open each profession window once so the
  addon can read your recipes; it rereads them every time you open it.
- **Vendor prices**: open any vendor window and the addon remembers what it charges for every
  item it sells for gold in unlimited supply (thread, dyes, vials, flux, ...), for all your
  characters. Mats priced from a vendor are marked "vendor" in the mats list, and item tooltips
  show a "Buy from vendor" line.
- **Profession window**: the selected recipe shows its mats cost, what the item sells for on the
  AH, what is left after the AH cut and deposit, the profit, and the list of base mats. With
  Pluvas' Professions installed, items that can be disenchanted also show what disenchanting them
  brings in and the profit that way.
- **Old prices are flagged**: a price shows when it was last seen ("3h ago"). Once that is more
  than 3 days ago, it is marked in orange, e.g. "(5d old)", in tooltips, mats lists and the
  profession window, so you know to scan again. Change the limit with `/pa stale <days>`.
- **Bugs stay contained**: if part of the addon keeps erroring, it turns itself off until `/reload`
  instead of throwing an error on every hover.
- Random-suffix items ("of the Bear") are priced separately.
- **Works with Pluvas' Professions**: with both installed, Pluvas' Professions uses these prices to
  tell you in tooltips whether an item is worth disenchanting, and the profession window shows
  what a crafted item would disenchant for.

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
| `/pa tooltip` | Turn all tooltip lines on or off |
| `/pa history` | The 14-day average in tooltips (on/off) |
| `/pa sold` | Your average sale price in tooltips (on/off) |
| `/pa craft` | Mats cost in tooltips of items you can craft (on/off) |
| `/pa mats` | The list of base mats under the mats cost (on/off) |
| `/pa panel` | Mats cost and profit in the profession window (on/off) |
| `/pa stale <days>` | Prices not seen for longer are flagged as old (default 3; no number prints the setting) |
| `/pa resetprices` | Delete price data for this realm/faction |
| `/pa resetledger` | Delete the sales history for this realm/faction |
| `/pa help` | List the commands and the state of each setting |

## Files

Data modules read, store and compute. UI modules only draw, and they refresh when a data module
sends an addon message (`PricesChanged`, `VendorPricesChanged`, `ScanStateChanged`, `LedgerChanged`). The runtime comes from
`Libs/PluvasCore`, the look from `Libs/PluvasUI`.

| File | Role |
| --- | --- |
| `Core.lua` | Saved variables and slash commands |
| `Pricing.lua` | Item keys, market value statistics, price database and history |
| `Scanner.lua` | Full scan (`ReplicateItems`) and passive capture from browse and search results |
| `Ledger.lua` | Reading auction mail, merging transactions, summaries, gold tracking |
| `Vendor.lua` | Learns vendor buy prices while a vendor window is open |
| `Crafting.lua` | Reads your recipes from the profession window, works out mats cost |
| `Lines.lua` | The label/value lines shown in tooltips and the profession window |
| `Tooltip.lua` | Tooltip hook and `/pa price` |
| `Api.lua` | Prices other Pluvas addons may read (`ns:Peer("PluvasAuctions")`) |
| `CraftPanel.lua` | Mats cost and profit panel in the profession window |
| `LedgerWindow.lua` | The ledger window |
| `ScanButton.lua` | The full scan button on the auction house frame |

## Known limits

- Deposits lost on expired or cancelled auctions are not counted yet.
- A sale appears in the ledger only once its mail reaches your mailbox.

## Changelog

- **Unreleased**: shares its prices with other Pluvas addons (used by Pluvas' Professions for
  disenchanting); with Pluvas' Professions, the profession window shows disenchant value and
  profit. Prices not seen for more than 3 days are flagged as old (`/pa stale <days>`).
- **0.1.0**: first public release. Full and passive AH scans with price history; tooltips with
  market value, lowest price, 14-day average, stack value and what is left after the AH cut and
  deposit; mats cost for items you can craft, priced at the cheaper of AH and vendor and broken
  down to base mats; mats cost, sale value and profit in the profession window; a ledger of sales,
  purchases, profit and gold across your characters, read from auction mail.
