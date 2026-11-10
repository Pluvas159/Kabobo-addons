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
    `Kabobo's addons`.
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
- **AH purchases are protected**: `C_AuctionHouse.StartCommoditiesPurchase` gives
  ADDON_ACTION_BLOCKED even when called from a click on an addon button (seen in game). Treat
  `ConfirmCommoditiesPurchase` and `PlaceBid` the same: only Blizzard's own buttons can buy.
  Addons can still search (`SendSearchQuery` works), fill the search box, and `hooksecurefunc`
  the purchase functions to see what was bought.
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
  Kabobo, 2026-11-07).
- **AH cut: 5%** of the sale (confirmed from AH sale invoices: 1s 50c on 30s, 25c on 5s). The
  neutral auction houses are not checked yet (15% in Classic).
- Item links: `item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:...`. Random-suffix items
  ("of the Bear") share an itemID, so key them by `itemID:suffixID`.

- **Auction house UI** (read from the `forever` branch of Gethe/wow-ui-source, November 2026; not
  yet checked in game): Forever uses the shared Mainline `AuctionHouseFrame`. Its `Camelot/`
  folder only overrides browse categories (`Blizzard_AuctionData.lua`). Your auctions are
  `AuctionHouseFrame.AuctionsFrame.AllAuctionsList`, a ScrollBox with a table builder (columns
  Name fill, Bid 120, Buyout 120, Time left 50), refreshed through `RefreshScrollFrame()`. Rows
  carry `rowData` from `C_AuctionHouse.GetOwnedAuctionInfo`.
- **An owned commodity's `buyoutAmount` is per unit** (confirmed from saved data, 2026-11-07:
  26 Coyote Meat listed at 95s each had `buyoutAmount` 9500, the same as its market value).
  `GetItemCommodityStatus` can return *Unknown* until the item's data has loaded, so do not divide
  by the quantity on *Unknown*; Kabobo's Auctions checks the reading against the market value.
- **Addons cannot buy at all (seen in game 2026-11-07):** `StartCommoditiesPurchase` called from
  an event handler got no answer; called from a click on an addon button it raised
  `ADDON_ACTION_BLOCKED KaboboAuctions StartCommoditiesPurchase()`. So the shopping list only fills
  `AuctionHouseFrame.SearchBar.SearchBox` (Browse tab) and leaves searching and buying to
  Blizzard's buttons. It hooks `ConfirmCommoditiesPurchase` and `PlaceBid` with `hooksecurefunc`
  to count purchases (`COMMODITY_PURCHASE_SUCCEEDED`, `AUCTION_HOUSE_PURCHASE_COMPLETED`). Not yet
  confirmed in game: that filling the search box taints nothing (watch for `ADDON_ACTION_BLOCKED`
  in `/ka log`), and `C_AuctionHouse.GetAuctionInfoByID` for item buyouts.
- **Filling in Blizzard's inputs** (from the `forever` branch source, Shared/; not yet checked in
  game): `AuctionHouseFrame.SearchBar:StartSearch()` runs a search (Search button and Enter call
  it). Clicking a commodity calls `CommoditiesBuyFrame:SetItemIDAndPrice(itemID, price)`, which
  sets the quantity to 1; `BuyDisplay:SetQuantitySelected(n)` sets it. Buy Now reads
  `BuyDisplay:GetItemID()`, `GetQuantitySelected()` and the unit/total price. In professions,
  `C_TradeSkillUI.OpenRecipe(recipeID)` makes Blizzard select the recipe (`OPEN_RECIPE_RESPONSE`),
  and `CraftingPage.CreateMultipleInputBox` holds the count Create reads. Whether values an addon
  writes there make the game block Buy Now / Create (taint) is not known yet: the shopping list
  turns its autofill off on `ADDON_ACTION_BLOCKED`.
- **Undercut labels** in the Auctions tab work (confirmed in game 2026-11-07); they show the result
  of the last scan or search of each item.
- **Sellers and time left in full scans**: the "Sold/day" estimate keys auctions by unit price,
  stack size and `ownerFullName`/`owner` from `GetReplicateItemInfo`, and reads
  `GetReplicateItemTimeLeft(i)` as `Enum.AuctionHouseTimeLeftBand` (Short < 30 min, Medium
  30 min-2 h, Long 2-12 h, Very long 12-48 h, as on Mainline). Not confirmed in game: whether
  commodity rows carry a seller (without one, identical stacks are matched by count), and the band
  boundaries. Without a time left, every auction is taken as 0-48 h.

## Professions

- Kabobo's Auctions reads recipes with `C_TradeSkillUI.GetAllRecipeIDs()`, `GetRecipeInfo(id)`
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
- **Recipe list** (read from Mainline; not yet checked in game):
  `ProfessionsFrame.CraftingPage.RecipeList.ScrollBox` holds the rows; a recipe row's
  `GetElementData():GetData().recipeInfo` is its `TradeSkillRecipeInfo`. Kabobo's Auctions draws
  a profit label on each row (`ScrollUtil.AddAcquiredFrameCallback`, `OnScroll`,
  `OnDataRangeChanged`) and fills `RecipeList.SearchBox` for the shopping list's craft steps.
  Crafting (`C_TradeSkillUI.CraftRecipe`) is left to Blizzard's Create button, like buying.
- Crafts are counted with `UNIT_SPELLCAST_SUCCEEDED("player", castGUID, spellID)`, assuming a
  recipe ID equals its craft's spell ID as on Mainline (not yet confirmed on Forever). Recipes
  saved before recipe IDs were kept are counted from the crafted item's bag count instead.

### Read from Blizzard's Forever UI source

Blizzard's UI code for Forever is mirrored in the `forever` branch of
[Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever). Forever's internal
game type is **`camelot`**: files under `Camelot/` folders (and `[AllowLoadGameType camelot]` TOC
lines) override the Mainline UI. The facts below were read there in November 2026 and have not
yet been checked in game.

- **The profession window hides unlearned recipes on purpose.**
  `Blizzard_ProfessionsTemplates/Camelot/Blizzard_Professions.lua` removes the Learned/Unlearned
  and Sources entries from the filter menu, and wraps `Professions.GenerateCraftingDataProvider`
  to call `C_TradeSkillUI.SetShowUnlearned(false)` after *every* list build. Do not flip
  `SetShowUnlearned` to get them back: Blizzard resets it on each rebuild, and fighting that can
  cause a rebuild loop. Kabobo's Professions reads the recipe IDs itself and shows its own panel.
- Blizzard's recipe list uses `C_TradeSkillUI.GetFilteredRecipeIDs()`, which follows those filters.
  For unlearned recipes the schematic form calls `C_TradeSkillUI.GetRecipeSourceText(recipeID)`,
  which returns text like `|cFFFFD200Vendor: |rName|n|cFFFFD200Zone: |r...`.
- **The generated API docs are incomplete**: `GetFilteredRecipeIDs`, `GetRecipeSourceText` and
  `GetAllRecipeIDs` are missing from `TradeSkillUIDocumentation.lua`, but Blizzard's own code calls
  the first two. A function missing from the docs is not proof it is missing from the client.
- `TradeSkillRecipeInfo` fields include `name`, `learned`, `icon`, `categoryID`, `sourceType`,
  `hyperlink`, `isDummyRecipe`. It has no field for the skill needed to learn a recipe.
- **Confirmed in game (2026-11-07, build 70862, `/kprof dump` on Tailoring):**
  - `GetAllRecipeIDs()` exists and includes unlearned recipes: 429 unlearned for Tailoring.
  - `GetRecipeSourceText(id)` returns `nil` for unlearned recipes, and `GetRecipeInfo` has **no
    `sourceType` field** at all. Forever has no recipe source data, so sources must be learned
    from trainers and vendors the player visits.
  - `maxTrivialLevel` is filled (the skill where the recipe turns grey, e.g. Spinning Wheel 145).
  - The same recipe name can exist under several IDs (likely one per faction): Faction Banner was
    learned under one ID and unlearned under another (1263425). Match recipes by name.
  - Forever-only recipes have IDs around 1263000 (Loom 1263080, Spinning Wheel 1263032). The list
    also holds recipes that may not be obtainable yet.
- Merchant: `GetMerchantNumItems()`, `GetMerchantItemLink(i)` and `C_MerchantFrame.GetItemInfo(i)`
  (`name, price, hasExtendedCost, numAvailable, ...`), between `MERCHANT_SHOW` and `MERCHANT_CLOSED`.
  Recipe items are item class 9 (`Enum.ItemClass.Recipe`); subclass 0 is books. From the forever
  branch source, not yet checked in game.
- `NEW_RECIPE_LEARNED(recipeID, recipeLevel, baseRecipeID)` fires when a recipe is learned.
- `ProfessionsFrame` on Forever has a book (overview) page. Closing a trade skill while the book
  page is open does not hide the frame, so follow the frame's `OnShow`/`OnHide` rather than
  `TRADE_SKILL_SHOW`/`TRADE_SKILL_CLOSE`.

## Disenchanting

The client has no API for disenchant results, so Kabobo's Professions carries its own tables in
`addons/KaboboProfessions/Disenchant.lua`. They are Classic's rules by item level, quality and
weapon or armor (uncommon armor 75% dust, 20% essence, ~5% shard; weapons swap dust and essence;
rares give a shard; epics give shards or Nexus Crystals). Rules, not item lists, so new Forever
items are covered as long as they have a normal item level and quality.

From a Forever guide (wow-professions.com/forever/disenchanting-guide, read November 2026; it does
not say whether its data comes from beta or live). **Not checked in game:**
- Same mats and chances as Classic. The guide keys its table by required level (1-10, 11-15, ...),
  which lines up with Classic's item-level bands shifted by 5.
- **No Enchanting skill requirement**: any Enchanter can disenchant any item.
- Disenchant is not in the spellbook; it is cast from the profession window.

Still to confirm: that `C_Item.GetItemInfo` returns Classic item levels for vanilla items, that
real disenchants match the tables, and whether Forever adds mats of its own.

## Trainers

Read from `Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua` on the `forever` branch (see
above). Not yet checked in game.

- Events: `TRAINER_SHOW`, `TRAINER_UPDATE`, `TRAINER_CLOSED`, `TRAINER_DESCRIPTION_UPDATE`,
  `TRAINER_SERVICE_INFO_NAME_UPDATE`. The frame is `ClassTrainerFrame` (load-on-demand
  `Blizzard_TrainerUI`) and is used for profession trainers too. `IsTradeskillTrainer()` tells
  them apart.
- **`GetTrainerServiceInfo(i)` returns `name, serviceType, texture, reqLevel, subText, category`.**
  This differs from the wiki (`name, rank, category, expanded`). `serviceType` is `"available"`,
  `"unavailable"` or `"used"`, and `category` groups services when "Categorize" is on
  (`C_Trainer.GetCategorizeTrainerUI()`).
- `GetTrainerServiceSkillReq(i)` returns `skillName, skillRank, hasReq`, and **`hasReq` is true
  when the requirement is met** (Blizzard colors it red otherwise). The wiki says the opposite.
- `GetTrainerServiceCost(i)` returns `moneyCost, isProfession`. `GetTrainerServiceSkillLine(i)`
  gives the profession name.
- The client only lists services that the filter lets through:
  `GetTrainerServiceTypeFilter(type)` / `SetTrainerServiceTypeFilter(type, bool)` with `type`
  `"available"`, `"unavailable"`, `"used"`. Blizzard saves these filters only for the `classic`
  game type (`TRAINER_FILTER_*_BOOL` in the TOC), so on Forever they probably reset every session.
- `BuyTrainerService(i)` is what the Train button calls. Never automate it.

## Experience and reputation bars

Read from `Blizzard_StatusTrackingBar` on the `forever` branch (see above), November 2026. Not
yet checked in game.

- Forever uses the Mainline bars: `StatusTrackingBarManager` with two containers
  (`MainStatusTrackingBarContainer`, `SecondaryStatusTrackingBarContainer`, also in
  `StatusTrackingBarManager.barContainers`). Each container creates one bar of every kind in
  `container.bars[StatusTrackingBarInfo.BarsEnum.X]` (Reputation 1, Experience 4) and shows one
  at a time. Experience has priority 0, Reputation 2 (`Camelot/StatusTrackingBarConstants.lua`).
- A bar has `StatusBar` and `OverlayFrame.Text` (Blizzard's own text, centered at y = 1, shown on
  hover or with the `xpBarText` CVar). The container is 1192 x 17.
- The reputation bar reads `C_Reputation.GetWatchedFactionData()`: `factionID`, `name`,
  `reaction`, `currentStanding`, `currentReactionThreshold`, `nextReactionThreshold`.
  `currentStanding` counts from the bottom of Hated, so it only grows across standings.
- The paragon tooltip on the reputation bar uses `EmbeddedItemTooltip`, not `GameTooltip`.
- Kabobo's QoL adds a font string to each experience and reputation bar's `OverlayFrame` and
  hooks `OnEnter`/`OnLeave`.

## Mail

- The server loads 50 mails at a time.
- AH invoices: `GetInboxInvoiceInfo(i)` returns `invoiceType` (`"seller"`, `"buyer"`,
  `"seller_temp_invoice"`), `itemName`, `playerName`, `bid`, `buyout`, `deposit`, `consignment`,
  `moneyDelay`, `etaHour`, `etaMin`, `count`. `daysLeft` comes from `GetInboxHeaderInfo(i)`.
- Cancelled auctions come back by mail.
- Characters have first and last names, which matters for anything that parses names.
