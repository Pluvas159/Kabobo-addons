# The WoW: Forever client: notes for addon authors

World of Warcraft: Forever is Blizzard's Classic+ branch. It launched on 2026-11-04 and is set in
vanilla-era Azeroth (level cap 60). The game feels like Classic, but **the client is the modern
one**. Addons therefore use the Retail (Mainline) API, not the Classic Era API.

> Sources: community addon pages and source (auxForever, Hammerprice, Grimlight Auctions,
> kami-labs addon guide), read in November 2026. They were written during the beta. Blizzard has
> not published Forever-specific API docs. If something here turns out wrong in game, fix this file.

## Client facts

| | |
| --- | --- |
| Game build | `1.60.1` (seen locally as `1.60.1.70862`) |
| TOC interface | `## Interface: 16001` |
| Client base | Modern Mainline 12.x (Midnight) client |
| Lua | 5.1 (as on every WoW client) |
| Install folder | `World of Warcraft\_forever_\` (here: `D:\World of Warcraft\_forever_`) |
| Product code | `wowf` |

- No Forever-specific TOC filename suffix has been confirmed. Use a plain `<Name>.toc`.
- `## Interface` takes comma-separated values (e.g. `16001, 120105`) when one addon supports
  several clients.
- AddOns list grouping, as documented on [warcraft.wiki.gg/wiki/TOC_format](https://warcraft.wiki.gg/wiki/TOC_format):
  - `## Category: <name>` puts the addon under a collapsible header. Every addon in this repo uses
    `Pluvas' addons`.
  - `## Group: <main addon>` nests an addon under a main addon as a sub-list that cannot be
    collapsed. Nested groups are not supported.
  - `## IconTexture` or `## IconAtlas` sets the icon in the list.
  - `## AddonCompartmentFunc` adds an entry to the addon compartment (minimap) menu.
- Several globals that Classic Era addons rely on live in `C_*` namespaces here
  (`C_AddOns.GetAddOnMetadata`, `C_Item.*`, `C_Container.*`, ...).
- Tooltips: use `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`.
  `GameTooltip:HookScript("OnTooltipSetItem")` does not exist on the modern client.

## Restrictions inherited from the Midnight client

- **The combat log is closed to addons**, and some values become "secret" in combat (health,
  threat, auras, enemy spells). Do not build features that read them in combat.
- **Hardware events**: posting, bidding, buying out and cancelling auctions each need a real key
  or mouse press. Never chain or automate them.
- Taint: never replace Blizzard secure functions or frames. Use `hooksecurefunc` and `HookScript`.

## Auction house

Forever uses the **modern auction house** (`C_AuctionHouse`), with item and commodity listings.

- **Full scan**: `C_AuctionHouse.ReplicateItems()`. Wait for `REPLICATE_ITEM_LIST_UPDATE` and
  until `GetNumReplicateItems()` stops changing, then read rows `0 .. n-1`. **The server allows one
  per account every 15 minutes.**
  - `GetReplicateItemInfo(i)` returns: `name, texture, count, quality, usable, level, levelType,
    minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
    ownerFullName, saleStatus, itemID, hasAllInfo`. `buyoutPrice` is for the **whole stack**.
  - `GetReplicateItemLink(i)` and `GetReplicateItemTimeLeft(i)` are also available.
- **Browse**: `SendBrowseQuery(query)`, then `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED` /
  `..._ADDED`, read with `GetBrowseResults()`. Each result has `itemKey`, `minPrice` and
  `totalQuantity`. Page with `RequestMoreBrowseResults()`.
- **Item search**: `SendSearchQuery(itemKey, sorts, true)`, then `ITEM_SEARCH_RESULTS_UPDATED`,
  read with `GetItemSearchResultInfo(itemKey, i)`. Check `HasFullItemSearchResults`.
- **Commodity search**: `COMMODITY_SEARCH_RESULTS_UPDATED(itemID)`, read with
  `GetCommoditySearchResultInfo(itemID, i)`, which gives `unitPrice` and `quantity`. Buying takes
  two steps: a server price quote, then a confirmation.
- Throttling: check `C_AuctionHouse.IsThrottledMessageSystemReady()`. Resend after
  `AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED`.
- **Deposits: `C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity)` crashes the
  client** (ACCESS_VIOLATION in Wow.exe, which `pcall` cannot catch). Confirmed 2026-11-07, build
  70862: it was called from an item tooltip with the AH closed, after `GetItemCommodityStatus`
  returned `1` (Item). Do not call it, or `CalculateCommodityDeposit`, outside the AH's own sell
  flow.
- **Deposit: a flat 1 silver per auction**, whatever the item or stack size (confirmed in game by
  Pluvas, 2026-11-07).
- **AH cut: 5%** of the sale (confirmed from AH sale invoices: 1s 50c on 30s, 25c on 5s). The
  neutral auction houses are not checked yet (15% in Classic).
- Item links: `item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:...`. Random-suffix items
  ("of the Bear") share an itemID, so key them by `itemID:suffixID`.

## Professions

- Pluvas' Auctions reads recipes with `C_TradeSkillUI.GetAllRecipeIDs()`, `GetRecipeInfo(id)`
  (`.learned`), `GetRecipeSchematic(id, false)` (`outputItemID`, `quantityMin/Max`,
  `reagentSlotSchematics[].reagents[1].itemID`, `.quantityRequired`, `.reagentType`) and
  `GetBaseProfessionInfo()`. Confirmed working in game (2026-11-07): the recipe panel showed the
  right mats. It only calls them while the profession window is open (between `TRADE_SKILL_SHOW`
  and `TRADE_SKILL_CLOSE`).
- Profession window panel: assumes the modern `ProfessionsFrame` (load-on-demand addon
  `Blizzard_Professions`) with `ProfessionsFrame.CraftingPage.SchematicForm` and its
  `Init(recipeInfo)` method. Confirmed in game (2026-11-07). The Track Recipe checkbox sits along
  the bottom edge of the schematic form, so anything drawn there must stay above it.
- Not confirmed: whether `GetBaseProfessionInfo().professionID` equals the skill line from
  `GetProfessionInfo`, so profession pruning matches on name as well.

## Mail

- The server loads 50 mails at a time.
- AH invoices: `GetInboxInvoiceInfo(i)` returns `invoiceType` (`"seller"`, `"buyer"`,
  `"seller_temp_invoice"`), `itemName`, `playerName`, `bid`, `buyout`, `deposit`, `consignment`,
  `moneyDelay`, `etaHour`, `etaMin`, `count`. `daysLeft` comes from `GetInboxHeaderInfo(i)`.
- Cancelled auctions come back by mail.
- Characters have first and last names, which matters for anything that parses names.
