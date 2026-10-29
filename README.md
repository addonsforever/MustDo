# Must Do

Flags quest chains that end in a great reward, so you don't abandon them. Made for WoW: Forever.

`/mustdo` (or `/md`) opens the list: chains worth doing near you and across the world, grouped into tabs — top picks for your class, your professions, epic/unlocks, rare/special, dungeon quests, elite group quests, fun/recipes, cooking recipes (hidden by default; click the chip to show) and "openers" (quests that unlock lots of others). Click a category chip to hide or show it everywhere.

Quest givers on the map and NPC names are marked, and you're warned before abandoning a quest that's part of a must-do chain.

**Optional:** with **GearQuestForever** (and its class pack) installed, gear upgrades for your class and spec show as *top picks*.

### Data

Quest chains come from [QuestieDB](https://github.com/Questie/QuestieDB)'s Forever data and rewards from the [cMaNGOS classic-db](https://github.com/cmangos/classic-db) (both GPL), plus Forever quest rewards from GearQuestForever. `MustDo/tools/` has the generator; see its README to rebuild `Data.lua` from newer QuestieDB data.

## Install

**WowUp:** Get Addons → *Install from URL* → paste `https://github.com/addonsforever/MustDo`. WowUp will offer updates when a new release comes out.

**By hand:** download `MustDo-vX.Y.Z.zip` from [Releases](https://github.com/addonsforever/MustDo/releases/latest), unzip it, and put the `MustDo` folder in `World of Warcraft/_classic_beta_/Interface/AddOns/` (the Forever client folder). Then `/reload` or restart the game.

## License

GPL-3.0 (it ships data derived from GPL-licensed QuestieDB and cMaNGOS). Bundled libraries keep their own licenses: see `THIRD_PARTY.md`.
