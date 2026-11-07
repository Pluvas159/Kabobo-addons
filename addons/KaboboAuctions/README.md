# Kabobo's Auctions

Auction house price tracking and auction profit tracking for **World of Warcraft: Forever**.

## Features

**Price scanning and history**
- **Full scan** with the button under the auction house window, or `/ka scan`. It reads every
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
  (for the whole stack). Each mat is priced at the cheaper of its AH price and its vendor price.
  Mats you can craft yourself are priced from *their* mats, all the way down to the base mats
  (bag -> bolts -> cloth), unless buying the mat on the AH is cheaper than crafting it. Below it, a list of those base mats with
  how many you need and what each costs. Open each profession window once so the
  addon can read your recipes; it rereads them every time you open it.
- **Vendor prices**: open any vendor window and the addon remembers what it charges for every
  item it sells for gold in unlimited supply (thread, dyes, vials, flux, ...), for all your
  characters. Mats priced from a vendor are marked "vendor" in the mats list, and item tooltips
  show a "Buy from vendor" line.
- **Profession window**: the selected recipe shows its mats cost, what the item sells for on the
  AH, what is left after the AH cut and deposit, the profit, and the list of base mats (cut short
  with "+N more" when it would run into the reagents; the item's tooltip has the full list). With
  Kabobo's Professions installed, items that can be disenchanted also show what disenchanting them
  brings in and the profit that way. The recipe list shows the profit per craft beside every
  recipe (`*` when some mats have no price yet), and how many leave the AH per day when that is
  known (`~4/d`). A **Profit ranking** button under the window opens the crafts window on that
  profession.
- **Old prices are flagged**: a price shows when it was last seen ("3h ago"). Once that is more
  than 3 days ago, it is marked in orange, e.g. "(5d old)", in tooltips, mats lists and the
  profession window, so you know to scan again. Change the limit with `/ka stale <days>`.
- **Bugs stay contained**: if part of the addon keeps erroring, it turns itself off until `/reload`
  instead of throwing an error on every hover.
- Random-suffix items ("of the Bear") are priced separately.
- **Works with Kabobo's Professions**: with both installed, Kabobo's Professions uses these prices to
  tell you in tooltips whether an item is worth disenchanting, and the profession window shows
  what a crafted item would disenchant for.

**Sales and profit tracking**
- Reads auction invoice mail ("Auction successful" and "Auction won") whenever your mailbox is open.
  The same mail is never counted twice.
- **Ledger window** (`/ka`, or right-click the scan button): sales, AH cut, purchases and profit
  for today, 7 days, 30 days and all time, plus recent transactions and top items (30 days).
  Click any row to put that item in the auction house search box.
- **Gold tracking**: total gold across your characters on the realm/faction, and how much it has
  changed since yesterday.

Data is kept per realm (ruleset) and faction in the `KaboboAuctionsDB` saved variable.

**Crafts ranked by profit**
- **Crafts window** (`/ka crafts`, the "Crafts by profit" button in the ledger, or "Profit
  ranking" under the profession window): every recipe this character has learned, one tab per
  profession. Columns: mats cost, what the items sell for after the 5% AH cut and the deposit, the
  profit, **Gone/day**, **You sold** (30 days) and how many are listed on the AH.
- **Sort** button: by profit per craft, or by **profit per day** (profit x Gone/day), so a big
  profit on something nobody buys drops down. Recipes without a Gone/day yet come after those with
  one.
- **Gone/day** is an estimate. The game does not tell addons what other players buy, so after
  each full scan the listings of every item you can craft are compared with the previous full
  scan: auctions that were there and are gone now are counted. That includes auctions that expired
  or were cancelled, so it reads high. It needs two full scans 1 to 36 hours apart, and it averages
  the last 14 days. **You sold** is exact: it comes from your auction mail.
- Recipes with some mats unpriced (marked `*`) come after the fully priced ones, since their profit
  is too high; recipes whose item has no AH price yet come last. Hover a row for the item's full
  tooltip with the mats list.
- Recipes are the ones saved when you last opened each profession window, so open each one once.

**Shopping list**
- Click a recipe in the crafts window to open its shopping list for a number of crafts (`-`/`+`).
  It lists what to **buy** and, below it, what to **craft**: mats you can craft yourself (Copper
  Bar, Rough Grinding Stone, ...) when crafting them is cheaper than buying them, and the recipe
  itself last. Your bags are used first, for every level (3 Copper Bars in your bags mean less
  Copper Ore to buy). Mats a vendor sells cheaper are marked "vendor" and not bought on the AH.
- Each row shows what it is worth, crafted mats included, and the totals show what all the mats
  are worth **including what you already have** (so the profit matches the crafts window), what
  is still to buy, what the crafted items sell for after the AH cut, the profit, and how many
  leave the AH per day.
- The main button walks the steps. **Find** puts the next mat's name in the auction house search
  box: press Enter, click the item, and the list says how many to buy and what that costs. You buy
  with the auction house's own **Buy Now**: on this client only Blizzard's buttons may buy, so no
  addon can. **Craft** puts the next recipe in the profession window's search box: click it and
  the window's own **Create**. Each purchase and craft is counted, then the next step comes up.
  Click a row to pick that step, **Skip** to leave one for later.
- **Price cap**: it advises buying only listings up to 120% of an item's average price of the 14
  days before today (its market value while it has no history; `/ka buycap <percent>` to change),
  and warns with a sound when the auction house's price quote is above the cap, before you
  confirm. Today is left out because searching an item records today's listings.
- Purchases arrive by mail. Bags are counted only when the list is made, so collecting the mail
  does not count anything twice. The bank is not counted.

**Undercut alerts**
- Your auctions are read whenever the auction house opens and after you post or cancel one. Each
  one not checked in the last 5 minutes is then searched automatically, one every 2 seconds while
  the auction house is open.
- Every listing the addon sees is compared with yours too: full scans, searches (the Sell tab
  searches the item you post, so a fresh post is checked right away) and the browse list. When
  someone lists below your price, or at your price after you, you get a chat line with both
  prices and a sound. A full scan ends with one summary.
- **Same price**: at the same price the auction listed later sells first, so only someone who
  lists at your price *after* you counts as an undercut. The AH does not say when an auction was
  listed, so the addon remembers how many units others had at your price when it first compared
  it; more units later means someone listed after you. Auctions the addon first sees long after
  you posted them count everything already at your price as listed before you.
- The Auctions tab shows the status beside each of your auctions: **Undercut** with the cheaper
  price, **Undercut, same price**, **Same price, before you**, or **Lowest**.
- The ledger's **My auctions** list shows all of them, undercut first.

## Commands

| Command | What it does |
| --- | --- |
| `/ka` | Open or close the ledger window |
| `/ka scan` | Full AH scan (AH must be open) |
| `/ka crafts` | Open or close the crafts window: learned recipes ranked by profit |
| `/ka listprofit` | Profit beside each recipe in the profession window's list (on/off) |
| `/ka undercut` | Chat alert when someone undercuts or matches your auction (on/off) |
| `/ka labels` | Undercut status beside your auctions in the Auctions tab (on/off) |
| `/ka buycap <percent>` | Most the shopping list pays per unit, as % of market value (default 120) |
| `/ka price <item link>` | Print stored prices for an item |
| `/ka tooltip` | Turn all tooltip lines on or off |
| `/ka history` | The 14-day average in tooltips (on/off) |
| `/ka sold` | Your average sale price in tooltips (on/off) |
| `/ka craft` | Mats cost in tooltips of items you can craft (on/off) |
| `/ka mats` | The list of base mats under the mats cost (on/off) |
| `/ka panel` | Mats cost and profit in the profession window (on/off) |
| `/ka stale <days>` | Prices not seen for longer are flagged as old (default 3; no number prints the setting) |
| `/ka resetprices` | Delete price data for this realm/faction |
| `/ka resetledger` | Delete the sales history for this realm/faction |
| `/ka log [clear]` | Show the last lines of the diagnostic log (all of it is saved on `/reload`) |
| `/ka help` | List the commands and the state of each setting |

## Files

Data modules read, store and compute. UI modules only draw, and they refresh when a data module
sends an addon message (`PricesChanged`, `VendorPricesChanged`, `ScanStateChanged`, `LedgerChanged`). The runtime comes from
`Libs/KaboboCore`, the look from `Libs/KaboboUI`.

| File | Role |
| --- | --- |
| `Core.lua` | Saved variables and slash commands |
| `Pricing.lua` | Item keys, market value statistics, price database and history |
| `Scanner.lua` | Full scan (`ReplicateItems`) and passive capture from browse and search results |
| `Ledger.lua` | Reading auction mail, merging transactions, summaries, gold tracking |
| `Sales.lua` | How fast craftable items leave the AH (between full scans) and how many you sold |
| `Vendor.lua` | Learns vendor buy prices while a vendor window is open |
| `Crafting.lua` | Reads your recipes from the profession window, works out mats cost |
| `Lines.lua` | The label/value lines shown in tooltips and the profession window |
| `Tooltip.lua` | Tooltip hook and `/ka price` |
| `Api.lua` | Prices other Kabobo addons may read (`ns:Peer("KaboboAuctions")`) |
| `CraftPanel.lua` | Mats cost and profit panel in the profession window |
| `LedgerWindow.lua` | The ledger window |
| `CraftsWindow.lua` | The crafts window: learned recipes per profession, ranked by profit |
| `RecipeProfit.lua` | Profit beside each recipe in the profession window, and its Profit ranking button |
| `Undercut.lua` | Your auctions, compared with every listing seen; undercut alerts |
| `AuctionLabels.lua` | Undercut status beside your auctions in the Auctions tab |
| `Shopping.lua` | Shopping list for a recipe: what to buy and craft, advice under the price cap, counting |
| `ShopWindow.lua` | The shopping list window: its steps, totals, and Find/Craft and Skip buttons |
| `ScanButton.lua` | The full scan button on the auction house frame |

## Known limits

- Deposits lost on expired or cancelled auctions are not counted yet.
- A sale appears in the ledger only once its mail reaches your mailbox.

## Changelog

- **Unreleased**: shares its prices with other Kabobo addons (used by Kabobo's Professions for
  disenchanting); with Kabobo's Professions, the profession window shows disenchant value and
  profit. Prices not seen for more than 3 days are flagged as old (`/ka stale <days>`).
  Crafts window (`/ka crafts`) ranking this character's learned recipes per
  profession by profit or profit per day, with mats cost, net sale value, an estimate of how many
  leave the AH per day, your own sales and quantity listed. Profit beside each recipe in the
  profession window. Shopping list per recipe with what to buy and what to craft, cost and profit
  totals, that finds each mat in the AH and each recipe in the profession window, and advises how
  many to buy under a price cap (`/ka buycap`). Undercut alerts for your auctions, checked
  automatically when the AH opens (someone listing at your price after you counts too), with the
  status shown in the Auctions tab and the ledger. Ledger rows
  search their item in the AH. Crafted mats that are cheaper on the AH are priced (and bought) at
  the AH price. Mail read before its buyer name loaded is no longer recorded twice; duplicates
  saved before are removed. A diagnostic log (`/ka log`).
- **0.1.0**: first public release. Full and passive AH scans with price history; tooltips with
  market value, lowest price, 14-day average, stack value and what is left after the AH cut and
  deposit; mats cost for items you can craft, priced at the cheaper of AH and vendor and broken
  down to base mats; mats cost, sale value and profit in the profession window; a ledger of sales,
  purchases, profit and gold across your characters, read from auction mail.
