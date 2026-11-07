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

This links every addon into `World of Warcraft\_forever_\Interface\AddOns` with a directory
junction, so the game reads straight from this repo. It looks for the game in the usual places
(`D:\World of Warcraft\_forever_` first). Use `-WowPath <folder>` or the `WOW_FOREVER_PATH`
environment variable to point it elsewhere. Other options:

- `-Addon PluvasAuctions`: install only that addon.
- `-Copy`: copy the files instead of linking them.
- `-Uninstall`: remove the installed addons.

Restart WoW after installing a new addon. After that, `/reload` picks up code changes.

## Develop

```sh
npm install     # once
npm test        # syntax-check every addon as Lua 5.1 and run its tests outside the game
```

Create a new addon with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/new-addon.ps1 -Name PluvasThing -Title "Pluvas' Thing"
```

- [AGENTS.md](AGENTS.md): repo layout, conventions and workflow, for people and coding agents.
- [docs/forever-client.md](docs/forever-client.md): what is known about the Forever client and its API.
