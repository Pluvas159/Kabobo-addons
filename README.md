<img src="assets/icon.svg" width="64" height="64" alt="">

# Pluvas' addons

World of Warcraft addons for **World of Warcraft: Forever**, kept together in one repo.

| Addon | Description |
| --- | --- |
| [Pluvas' Auctions](addons/PluvasAuctions) | Auction house price scanning, price history in tooltips, and a sales, profit and gold ledger |

## Install into the game

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

This symlinks every addon into `World of Warcraft\_forever_\Interface\AddOns`, so the game reads
straight from this repo. In game, they all appear under one **Pluvas' addons** header in the
AddOns list. The script looks for the game in the usual places (`D:\World of Warcraft\_forever_`
first). Use `-WowPath <folder>` or the `WOW_FOREVER_PATH` environment variable to point it
elsewhere.

Rerun it whenever addons are added, renamed or removed. It is safe to run any number of times,
and it never touches addons that are not from this repo. Other options:

- `-Status`: show what is installed, without changing anything.
- `-Addon PluvasAuctions`: install only that addon.
- `-Copy`: copy the files instead of linking them.
- `-Uninstall`: remove this repo's addons from the game.

Symlinks need Windows Developer Mode (or an admin shell). Without it, the script uses junctions,
which work the same for the game.

Restart WoW after installing a new addon. After that, `/reload` picks up code changes.

## Develop

```sh
npm install     # once
npm test        # syntax-check every addon as Lua 5.1 and run its tests outside the game
npm run sync    # after editing shared/: copy the shared libraries into the addons
```

All addons share one look through **PluvasUI**, a small UI library in
[shared/PluvasUI](shared/PluvasUI) (style tokens, windows, lists, tabs, buttons, tooltips). Each
addon embeds its own copy in `Libs/PluvasUI`, so every addon still installs on its own. Edit the
library only in `shared/`, then run `npm run sync`.

Create a new addon with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/new-addon.ps1 -Name PluvasThing -Title "Pluvas' Thing"
```

- [AGENTS.md](AGENTS.md): repo layout, conventions and workflow, for people and coding agents.
- [docs/forever-client.md](docs/forever-client.md): what is known about the Forever client and its API.
