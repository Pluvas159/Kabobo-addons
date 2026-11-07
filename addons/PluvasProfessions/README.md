# Pluvas' Professions

Shows the profession recipes you have **not learned yet**, and where to learn them, for
**World of Warcraft: Forever**.

On Forever, the profession window only lists recipes you already know. Blizzard removed the
"Show unlearned" filter. This addon brings that list back as a separate panel. Open it only when
you want it.

## Features

- **Show unlearned** button under the profession window. It opens a panel next to the window
  with every recipe of that profession you have not learned, grouped by where it comes from:
  **Trainer**, **Vendor**, **Quest**, **Drop**, and so on. Hover a recipe to see the game's own
  source text (which vendor, which zone, ...).
- **Vendor recipes**: open any vendor window and the recipes it sells are remembered. Unlearned
  recipes then show up under **Vendor** with who sells them, where, and the price. Shared by all
  your characters.
- **Trainer details**: visit a trainer once, and trainer recipes show the skill and level they
  need, what they cost, and who teaches them. Recipes you can learn **right now** are green. The
  button shows how many there are (`+3`).
- **Trainers show everything**: profession trainers also list recipes you cannot learn yet, so you
  can see what comes next. Turn this off with `/pprof trainer`.
- **Opens the way you left it**: if the panel was open when you last used a profession window, it
  opens with the next one; if you closed it (button, close button or `/pprof`), it stays closed.
  Closing the profession window itself, or pressing Escape, does not count as closing the panel.
- It works with the profession window closed too: `/pprof` shows the saved list for each of your
  professions.
- Recipes drop off the list as soon as you learn them.
- Click a group header to fold it away. Forever gives no source for most recipes, and its list
  includes recipes that may not be in the game yet, so those start folded under **No source info**.
  Visiting a trainer moves the recipes it teaches out of that pile.

## Disenchanting

With **Pluvas' Auctions** installed too, the tooltip of every item you can disenchant (green, blue
and purple weapons and armor) says whether it is **worth disenchanting**:

- **worth it** (green) when the mats it should give are worth more than selling the item, or
  **not worth it** (red) when selling it on the AH or to a vendor brings in more.
- **expected mats**: what disenchanting is worth on average, from each possible result's chance,
  amount and AH price. **selling instead**: the better of the AH and the vendor. Both are after
  the 5% AH cut, and the AH sale also pays its deposit.
- The possible results, likeliest first, with what each would be worth (`/pprof demats` hides
  them), and a reminder when this character has no Enchanting. On Forever any Enchanting skill
  can disenchant any item.
- Mats without an AH price yet are left out. When that leaves it open, the tooltip says so: scan
  the AH with Pluvas' Auctions.
- Prices that Pluvas' Auctions counts as old (not seen for 3 days, `/pa stale <days>`) are
  marked in orange with their age, and the verdict says "(old prices)": it may no longer hold.

Pluvas' Auctions also shows in its profession window panel what a crafted item would disenchant
for, and the profit if you disenchant it instead of selling.

Without Pluvas' Auctions there are no prices, so these lines stay off. The results follow
Classic's disenchanting rules (by item level, quality and weapon or armor), which Forever guides
list unchanged. They are rules rather than a list of items, so gear new in Forever is covered too.
They have not been checked against real disenchants yet.

## Commands

| Command | What it does |
| --- | --- |
| `/pprof` | Open or close the unlearned list |
| `/pprof auto` | Open the list together with the profession window (on/off) |
| `/pprof trainer` | Make profession trainers list recipes you cannot learn yet (on/off, default on) |
| `/pprof unknown` | Hide recipes the game gives no source for (on/off) |
| `/pprof de` | "Worth disenchanting?" in item tooltips (on/off, default on, needs Pluvas' Auctions) |
| `/pprof demats` | List the possible disenchant results in those tooltips (on/off) |
| `/pprof reset` | Forget this character's recipe data |
| `/pprof help` | List the commands and the state of each setting |
| `/pprof dump` | With a profession window open: print what the game returns for a few unlearned recipes (for troubleshooting) |

## How it gets the data

- Open each profession window once. The addon reads every recipe of that profession, including
  unlearned ones.
- Forever's client has no data on where recipes come from, so the addon learns it as you play:
  from every trainer and vendor window you open. Recipes nobody has been seen with stay under
  **No source info**, sorted by the skill where they turn grey.
- Trainer requirements and costs are shared by all your characters. The list of what is still
  unlearned is kept per character.

## Files

| File | Role |
| --- | --- |
| `Core.lua` | Saved variables and slash commands |
| `Data.lua` | The saved recipe, trainer and vendor data |
| `Rows.lua` | Turns that data into the grouped, sorted rows of the list (pure, unit tested) |
| `Recipes.lua` | Reads the open profession window |
| `Trainer.lua` | Reads what profession trainers teach |
| `Vendor.lua` | Learns which vendors sell recipes |
| `Disenchant.lua` | What disenchanting gives and whether it beats selling (pure, unit tested) |
| `DisenchantTooltip.lua` | The disenchant lines in item tooltips, priced by Pluvas' Auctions |
| `Api.lua` | What other Pluvas addons may read (`ns:Peer("PluvasProfessions")`): disenchant value |
| `Panel.lua` | The unlearned-recipes panel and its button under the profession window |

The readers send `RecipesChanged` after each change, and the panel redraws. The runtime comes from
`Libs/PluvasCore`, the look from `Libs/PluvasUI`.

## Changelog

- **Unreleased**: tooltips say whether an item is worth disenchanting (needs Pluvas' Auctions),
  and flag verdicts that rest on old AH prices.
- **0.1.0**: first public release.
