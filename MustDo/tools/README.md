# Regenerating Must Do's Data.lua

Not loaded by the game. Needs Lua 5.4 and Python 3. Last built in `~/.cache/mustdo-build/` (inputs are big; not kept here).

1. Clone QuestieDB next to these files as `QDB/` (github.com/Questie/QuestieDB) and run `lua export.lua`
   (expects `mustdo/` as the output folder; adjust paths if you move things).
2. Download cmangos classic-db `Full_DB/ClassicDB_1_12_1_z2815.sql.gz`, gunzip to `classicdb.sql`,
   run `python3 parse_cmangos.py`.
3. `python3 extract_gq.py` writes `mustdo/gq_quest_rewards.json` from the installed `GearQuestForever_*` class packs.
4. `spell_names.json` (spell id -> name, from nether.wowhead.com/classic/tooltip/spell/ID) must sit next to the generator.
5. `python3 gen_mustdo.py ../Data.lua`
