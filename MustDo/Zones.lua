-- Must Do: a hand-made map of which places are next to each other, used to order the list:
-- where you are, then the places next to it, then everything else by how well its level suits you.
-- Names are matched loosely (MD.PlaceKey), so "Un'Goro Crater" and "Un Goro Crater" are the same.
local _, ns = ...
local MD = ns.MD

-- { place, lowLevel, highLevel }
local LEVELS = {
  -- Eastern Kingdoms
  { "Elwynn Forest", 1, 10 }, { "Dun Morogh", 1, 10 }, { "Tirisfal Glades", 1, 10 },
  { "Westfall", 10, 20 }, { "Loch Modan", 10, 20 }, { "Silverpine Forest", 10, 20 },
  { "Redridge Mountains", 15, 25 }, { "Duskwood", 18, 30 }, { "Wetlands", 20, 30 },
  { "Hillsbrad Foothills", 20, 30 }, { "Alterac Mountains", 30, 40 }, { "Arathi Highlands", 30, 40 },
  { "Stranglethorn Vale", 30, 45 }, { "Badlands", 35, 45 }, { "Swamp of Sorrows", 35, 45 },
  { "The Hinterlands", 40, 50 }, { "Searing Gorge", 43, 50 }, { "Blasted Lands", 45, 55 },
  { "Burning Steppes", 50, 58 }, { "Western Plaguelands", 51, 58 }, { "Eastern Plaguelands", 53, 60 },
  -- Kalimdor
  { "Teldrassil", 1, 10 }, { "Durotar", 1, 10 }, { "Mulgore", 1, 10 },
  { "Darkshore", 10, 20 }, { "The Barrens", 10, 25 }, { "Stonetalon Mountains", 15, 27 },
  { "Ashenvale", 18, 30 }, { "Thousand Needles", 25, 35 }, { "Desolace", 30, 40 },
  { "Dustwallow Marsh", 35, 45 }, { "Feralas", 40, 50 }, { "Tanaris", 40, 50 },
  { "Azshara", 45, 55 }, { "Un'Goro Crater", 48, 55 }, { "Felwood", 48, 55 },
  { "Winterspring", 55, 60 }, { "Silithus", 55, 60 }, { "Moonglade", 1, 60 },
  -- Cities: always worth a look.
  { "Stormwind City", 1, 60 }, { "Ironforge", 1, 60 }, { "Darnassus", 1, 60 },
  { "Orgrimmar", 1, 60 }, { "Thunder Bluff", 1, 60 }, { "Undercity", 1, 60 },
  -- New in Forever
  { "Zephras Isle", 1, 10 },
  -- Dungeons and raids
  { "Ragefire Chasm", 13, 18 }, { "The Hall of Thanes", 13, 18 }, { "Ruins of Lordaeron", 15, 20 },
  { "The Deadmines", 17, 26 }, { "Wailing Caverns", 17, 24 }, { "Shadowfang Keep", 22, 30 },
  { "Blackfathom Deeps", 24, 32 }, { "The Stockade", 24, 32 }, { "Gnomeregan", 29, 38 },
  { "Razorfen Kraul", 29, 38 }, { "Scarlet Monastery", 34, 45 }, { "Razorfen Downs", 37, 46 },
  { "Uldaman", 41, 51 }, { "Zul'Farrak", 44, 54 }, { "Maraudon", 46, 55 },
  { "The Temple of Atal'Hakkar", 50, 56 }, { "Blackrock Depths", 52, 60 }, { "Dire Maul", 55, 60 },
  { "Blackrock Spire", 55, 60 }, { "Scholomance", 58, 60 }, { "Stratholme", 58, 60 },
  { "Molten Core", 60, 60 }, { "Onyxia's Lair", 60, 60 }, { "Blackwing Lair", 60, 60 },
  { "Zul'Gurub", 60, 60 }, { "Ruins of Ahn'Qiraj", 60, 60 }, { "Temple of Ahn'Qiraj", 60, 60 },
  { "Naxxramas", 60, 60 },
  -- Battlegrounds
  { "Arathi Basin", 20, 60 }, { "Alterac Valley", 51, 60 },
}

-- Places next to each other: shared borders, plus boats, trams and zeppelins ("A"/"H" = one faction
-- only). A dungeon sits next to the zone its entrance is in.
local LINKS = {
  -- Eastern Kingdoms
  { "Elwynn Forest", "Stormwind City" }, { "Elwynn Forest", "Westfall" }, { "Elwynn Forest", "Redridge Mountains" },
  { "Elwynn Forest", "Duskwood" }, { "Westfall", "Duskwood" }, { "Duskwood", "Redridge Mountains" },
  { "Duskwood", "Stranglethorn Vale" }, { "Redridge Mountains", "Burning Steppes" },
  { "Burning Steppes", "Searing Gorge" }, { "Swamp of Sorrows", "Blasted Lands" },
  { "Dun Morogh", "Ironforge" }, { "Dun Morogh", "Loch Modan" }, { "Loch Modan", "Wetlands" },
  { "Loch Modan", "Badlands" }, { "Wetlands", "Arathi Highlands" }, { "Arathi Highlands", "Hillsbrad Foothills" },
  { "Hillsbrad Foothills", "Alterac Mountains" }, { "Hillsbrad Foothills", "Silverpine Forest" },
  { "Hillsbrad Foothills", "The Hinterlands" }, { "Alterac Mountains", "Silverpine Forest" },
  { "Silverpine Forest", "Tirisfal Glades" }, { "Tirisfal Glades", "Undercity" },
  { "Tirisfal Glades", "Western Plaguelands" }, { "Western Plaguelands", "Eastern Plaguelands" },
  { "Stormwind City", "Ironforge", "A" }, -- Deeprun Tram
  -- Kalimdor
  { "Teldrassil", "Darnassus" }, { "Darkshore", "Ashenvale" }, { "Ashenvale", "Felwood" },
  { "Ashenvale", "Azshara" }, { "Ashenvale", "Stonetalon Mountains" }, { "Ashenvale", "The Barrens" },
  { "Felwood", "Winterspring" }, { "Felwood", "Moonglade" }, { "Winterspring", "Moonglade" },
  { "Stonetalon Mountains", "The Barrens" }, { "Stonetalon Mountains", "Desolace" }, { "Desolace", "Feralas" },
  { "The Barrens", "Durotar" }, { "The Barrens", "Mulgore" }, { "The Barrens", "Dustwallow Marsh" },
  { "The Barrens", "Thousand Needles" }, { "Durotar", "Orgrimmar" }, { "Mulgore", "Thunder Bluff" },
  { "Thousand Needles", "Feralas" }, { "Thousand Needles", "Tanaris" }, { "Tanaris", "Un'Goro Crater" },
  { "Un'Goro Crater", "Silithus" },
  -- Boats and zeppelins
  { "Teldrassil", "Darkshore", "A" }, { "Darkshore", "Wetlands", "A" }, { "Wetlands", "Dustwallow Marsh", "A" },
  { "The Barrens", "Stranglethorn Vale" }, -- Ratchet to Booty Bay
  { "Durotar", "Tirisfal Glades", "H" }, { "Durotar", "Stranglethorn Vale", "H" },
  { "Tirisfal Glades", "Stranglethorn Vale", "H" },
  -- Dungeon entrances
  { "The Deadmines", "Westfall" }, { "The Stockade", "Stormwind City" }, { "Gnomeregan", "Dun Morogh" },
  { "The Hall of Thanes", "Dun Morogh" }, { "The Hall of Thanes", "Ironforge" },
  { "Ruins of Lordaeron", "Tirisfal Glades" }, { "Ruins of Lordaeron", "Undercity" },
  { "Shadowfang Keep", "Silverpine Forest" }, { "Scarlet Monastery", "Tirisfal Glades" },
  { "Uldaman", "Badlands" }, { "The Temple of Atal'Hakkar", "Swamp of Sorrows" },
  { "Blackrock Depths", "Burning Steppes" }, { "Blackrock Depths", "Searing Gorge" },
  { "Blackrock Spire", "Burning Steppes" }, { "Blackrock Spire", "Searing Gorge" },
  { "Molten Core", "Burning Steppes" }, { "Molten Core", "Searing Gorge" },
  { "Blackwing Lair", "Burning Steppes" }, { "Blackwing Lair", "Searing Gorge" },
  { "Scholomance", "Western Plaguelands" }, { "Stratholme", "Eastern Plaguelands" },
  { "Naxxramas", "Eastern Plaguelands" }, { "Zul'Gurub", "Stranglethorn Vale" },
  { "Ragefire Chasm", "Orgrimmar" }, { "Wailing Caverns", "The Barrens" }, { "Razorfen Kraul", "The Barrens" },
  { "Razorfen Downs", "The Barrens" }, { "Razorfen Downs", "Thousand Needles" },
  { "Blackfathom Deeps", "Ashenvale" }, { "Maraudon", "Desolace" }, { "Dire Maul", "Feralas" },
  { "Zul'Farrak", "Tanaris" }, { "Onyxia's Lair", "Dustwallow Marsh" },
  { "Ruins of Ahn'Qiraj", "Silithus" }, { "Temple of Ahn'Qiraj", "Silithus" },
  { "Arathi Basin", "Arathi Highlands" }, { "Alterac Valley", "Alterac Mountains" },
  { "Alterac Valley", "Hillsbrad Foothills" },
}

-- Other names the quest data uses for these places.
local ALIASES = {
  ["New Tinkertown Old"] = "Dun Morogh", ["Sunken Temple"] = "The Temple of Atal'Hakkar",
  ["Ahn Qiraj"] = "Temple of Ahn'Qiraj", ["Blackrock Depths Shadowforge City"] = "Blackrock Depths",
  ["Alcaz Island"] = "Dustwallow Marsh",
}
for alias, name in pairs(ALIASES) do MD.placeAliases[MD.PlaceKey(alias)] = name end

local levels, links = {}, {}
for _, z in ipairs(LEVELS) do levels[MD.PlaceKey(z[1])] = { z[2], z[3] } end

local function Build()
  local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
  wipe(links)
  for _, l in ipairs(LINKS) do
    if not l[3] or l[3] == faction then
      local a, b = MD.PlaceKey(l[1]), MD.PlaceKey(l[2])
      links[a] = links[a] or {}
      links[b] = links[b] or {}
      links[a][b], links[b][a] = true, true
    end
  end
end

-- How many steps apart two places are (1 = next to each other), or nil if they don't connect.
local hopsFrom = {}
function MD.Hops(place, here)
  if not next(links) then Build() end
  local start, goal = MD.PlaceKey(here), MD.PlaceKey(place)
  local dist = hopsFrom[start]
  if not dist then
    dist = { [start] = 0 }
    local queue, i = { start }, 1
    while queue[i] do
      local cur = queue[i]
      i = i + 1
      for nb in pairs(links[cur] or {}) do
        if not dist[nb] then dist[nb] = dist[cur] + 1 queue[#queue + 1] = nb end
      end
    end
    hopsFrom[start] = dist
  end
  return dist[goal]
end

-- How far the place's level range is from your level: 0 inside it, nil when unknown.
function MD.LevelGap(place)
  local r = levels[MD.PlaceKey(place)]
  if not r then return nil end
  local level = UnitLevel("player") or 1
  if level < r[1] then return r[1] - level end
  if level > r[2] then return level - r[2] end
  return 0
end
