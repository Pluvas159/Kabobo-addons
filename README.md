<img src="assets/icon.svg" width="64" height="64" alt="">

# Kabobo's addons

World of Warcraft addons for **World of Warcraft: Forever**, kept together in one repo.

| Addon | Description |
| --- | --- |
| [Kabobo's Auctions](addons/KaboboAuctions) | Auction house price scanning, price history in tooltips, crafts ranked by profit with a buy-and-craft shopping list, undercut alerts, and a sales, profit and gold ledger |
| [Kabobo's Professions](addons/KaboboProfessions) | Lists the recipes you have not learned yet and where to learn them (trainer, vendor, drop, quest), and with Kabobo's Auctions tells you whether an item is worth disenchanting |
| [Kabobo's QoL](addons/KaboboQoL) | Small quality-of-life touches: experience and reputation per hour, and the time to your next level, right on the experience and reputation bars |

## Download

Get the latest zip from [Releases](https://github.com/Pluvas159/pluvas-addons/releases):
`kabobo-addons-<version>.zip` has every addon, or pick a single `<Name>-<version>.zip`. Extract it
into `World of Warcraft\_forever_\Interface\AddOns`, so that you end up with
`Interface\AddOns\KaboboAuctions\KaboboAuctions.toc` (not a folder inside a folder), then restart
the game.

## Install from this repo (development)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

This symlinks every addon into `World of Warcraft\_forever_\Interface\AddOns`, so the game reads
straight from this repo. In game, they all appear under one **Kabobo's addons** header in the
AddOns list. The script looks for the game in the usual places (`D:\World of Warcraft\_forever_`
first). Use `-WowPath <folder>` or the `WOW_FOREVER_PATH` environment variable to point it
elsewhere.

Rerun it whenever addons are added, renamed or removed. It is safe to run any number of times,
and it never touches addons that are not from this repo. Other options:

- `-Status`: show what is installed, without changing anything.
- `-Addon KaboboAuctions`: install only that addon.
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

All addons are built on two small shared libraries:

- **KaboboCore** ([shared/KaboboCore](shared/KaboboCore)): the runtime. Events and addon messages,
  modules, saved variables with migrations, slash commands, error guards, and helpers for
  reading game windows safely.
- **KaboboUI** ([shared/KaboboUI](shared/KaboboUI)): one look. Style tokens, money formatting,
  windows, lists, grids, tabs, buttons and tooltips.

Each addon embeds its own copy in `Libs/`, so every addon still installs on its own. Edit the
libraries only in `shared/`, then run `npm run sync`.

Create a new addon with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/new-addon.ps1 -Name KaboboThing -Title "Kabobo's Thing"
```

- [AGENTS.md](AGENTS.md): repo layout, conventions and workflow, for people and coding agents.
- [docs/forever-client.md](docs/forever-client.md): what is known about the Forever client and its API.
