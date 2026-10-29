-- Must Do: chain logic. Which chains matter for this character, how good their reward is
-- (the tier), and where the player is in each one.
local addonName, ns = ...
local MD = {}
ns.MD = MD
_G.MustDo = MD

-- Tiers, best first. Colors are used for the star, map markers and list rows; chip is the
-- shorter name on the list's filter buttons.
MD.TIERS = {
  { key = "pick",  label = "top pick for you", chip = "top picks", color = { 1.00, 0.80, 0.10 }, hex = "ffffcc19" },
  { key = "profession", label = "your professions", chip = "professions", color = { 0.45, 0.90, 0.30 }, hex = "ff73e64d" },
  { key = "epic",  label = "epic / unlock", chip = "epic",    color = { 0.70, 0.35, 1.00 }, hex = "ffb259ff" },
  { key = "rare",  label = "rare / special", chip = "rare", color = { 0.25, 0.60, 1.00 }, hex = "ff4099ff" },
  { key = "dungeon", label = "dungeon quest", chip = "dungeon",  color = { 1.00, 0.55, 0.15 }, hex = "ffff8c26" },
  { key = "elite", label = "elite / group quest at the end of a chain", chip = "elite", color = { 1.00, 0.35, 0.35 }, hex = "ffff5959" },
  { key = "fun",   label = "fun / recipe", chip = "fun", color = { 0.20, 0.90, 0.80 }, hex = "ff33e6cc" },
  { key = "cooking", label = "cooking recipe", chip = "cooking", color = { 0.95, 0.75, 0.55 }, hex = "fff2bf8c" },
}
-- Categories that start hidden until you click their chip to show them.
local HIDDEN_BY_DEFAULT = { cooking = true }
local TIER_INDEX = {}
for i, t in ipairs(MD.TIERS) do TIER_INDEX[t.key] = i end

local EPIC_TAGS = { ["epic"] = true, ["Onyxia attunement"] = true, ["UBRS key"] = true, ["Scholomance key"] = true,
  ["BRD key"] = true, ["Dire Maul key"] = true, ["Scarlet key"] = true, ["Workshop key"] = true, ["Sunken Temple"] = true,
  ["key"] = true, ["attunement"] = true, ["teaches spell"] = true, ["class quest"] = true }
local RARE_TAGS = { ["rare"] = true, ["use effect"] = true, ["proc"] = true }
local FUN_TAGS = { ["fun"] = true, ["cosmetic"] = true, ["recipe"] = true }

-- Professions --------------------------------------------------------------------------
-- Rewards and quests that need a profession only count if you have it. Your main professions
-- make the "your professions" tier; first aid and fishing count as fun; cooking recipes get
-- their own tier (hidden by default).
local PROFESSIONS = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
  [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
  [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
local COOKING = 185
local SECONDARY = { [129] = true, [356] = true }
local PROFESSION_BY_NAME = {}
for id, name in pairs(PROFESSIONS) do PROFESSION_BY_NAME[name] = id end
MD.PROFESSIONS = PROFESSIONS

local known -- skill line id -> true, read on demand
local function KnownProfessions()
  if known then return known end
  known = {}
  pcall(function()
    if GetNumSkillLines and GetSkillLineInfo then
      for i = 1, GetNumSkillLines() do
        local name, isHeader = GetSkillLineInfo(i)
        if not isHeader and PROFESSION_BY_NAME[name] then known[PROFESSION_BY_NAME[name]] = true end
      end
    elseif GetProfessions then
      for _, index in pairs({ GetProfessions() }) do
        local id = select(7, GetProfessionInfo(index))
        if id then known[id] = true end
      end
    end
  end)
  return known
end
function MD:ResetProfessions() known = nil end
function MD.HasProfession(id) return not id or id == 0 or KnownProfessions()[id] == true end

-- A reward you can't use because it needs a profession you don't have.
local function Unusable(r) return not MD.HasProfession(r[6]) end
MD.Unusable = Unusable

-- Field positions in ns.Q rows and ns.chains rows (see Data.lua).
local NAME, LEVEL, REQ, FACTION, CLASSES, PRE_ANY, PRE_ALL, GIVER, INFERRED, RACES, EXCLUSIVE = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
MD.Q_GIVER, MD.Q_INFERRED, MD.Q_DUNGEON, MD.Q_ZONE, MD.Q_TURNIN = GIVER, INFERRED, 12, 13, 14

local playerFaction, playerClassBit, playerRaceBit

local function IsCompleted(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
  if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
  return false
end
MD.IsCompleted = IsCompleted

local function InLog(id)
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
  if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) end
  return false
end
MD.InLog = InLog

-- Classic quest data lists only the original races (Alliance 77, Horde 178, both 255), so Forever's
-- new races (bit 33 and up, e.g. Skyborne) are missing from those masks. A mask that covers every
-- original race of your faction means "anyone in this faction", so it includes the new races too.
local CLASSIC_FACTION_RACES = { A = 77, H = 178 }
local NEW_RACE_BITS = 4294967296 -- 2^32

local function RaceAllowed(mask)
  -- Race masks go past 32 bits (Skyborne), so test the bit with arithmetic, not the bit library.
  if math.floor(mask / playerRaceBit) % 2 == 1 then return true end
  if playerRaceBit < NEW_RACE_BITS then return false end
  local classic = CLASSIC_FACTION_RACES[playerFaction]
  return classic ~= nil and bit.band(mask % NEW_RACE_BITS, classic) == classic
end

local function Eligible(id)
  local q = ns.Q[id]
  if not q then return false end
  if q[FACTION] and q[FACTION] ~= playerFaction then return false end
  if q[CLASSES] and bit.band(q[CLASSES], playerClassBit) == 0 then return false end
  if q[RACES] and playerRaceBit and not RaceAllowed(q[RACES]) then return false end
  return true
end
MD.Eligible = Eligible

-- Done, or ruled out because you did (or are doing) one of its alternatives.
local BREADCRUMB_FOR = 15
local function Settled(id)
  if IsCompleted(id) then return true end
  local q = ns.Q[id]
  -- A breadcrumb is gone once you have or finish the quest it sends you to.
  local target = q and q[BREADCRUMB_FOR]
  if target and (IsCompleted(target) or InLog(target)) then return true end
  for _, other in ipairs(q and q[EXCLUSIVE] or {}) do
    if IsCompleted(other) or InLog(other) then return true end
  end
  return false
end

-- Prerequisites the player can actually do (other-faction or other-class links are ignored).
local function Prereqs(id)
  local q = ns.Q[id]
  local any, all = {}, {}
  for _, p in ipairs(q[PRE_ANY] or {}) do if Eligible(p) then any[#any + 1] = p end end
  for _, p in ipairs(q[PRE_ALL] or {}) do if Eligible(p) then all[#all + 1] = p end end
  return any, all
end

local function PrereqsDone(id)
  local any, all = Prereqs(id)
  for _, p in ipairs(all) do if not IsCompleted(p) then return false end end
  if #any == 0 then return true end
  for _, p in ipairs(any) do if IsCompleted(p) then return true end end
  return false
end

-- Chain index ------------------------------------------------------------------------

-- chain = { final, steps, rewards, questTags, members = { questIds } }
MD.chains = {}
MD.byQuest = {} -- questId -> { chain, ... } for every chain the quest leads to

local function CollectMembers(id, members, seen)
  if seen[id] or not ns.Q[id] then return end
  seen[id] = true
  members[#members + 1] = id
  local q = ns.Q[id]
  for _, p in ipairs(q[PRE_ANY] or {}) do CollectMembers(p, members, seen) end
  for _, p in ipairs(q[PRE_ALL] or {}) do CollectMembers(p, members, seen) end
end

local function BuildIndex()
  for _, row in ipairs(ns.chains) do
    local chain = { final = row[1], steps = row[2], rewards = row[3], questTags = row[4], skill = row[5] or 0, members = {} }
    CollectMembers(chain.final, chain.members, {})
    MD.chains[#MD.chains + 1] = chain
    MD.rewardItems = MD.rewardItems or {}
    for _, r in ipairs(chain.rewards) do if r[1] > 0 then MD.rewardItems[r[1]] = true end end
    for _, id in ipairs(chain.members) do
      MD.byQuest[id] = MD.byQuest[id] or {}
      table.insert(MD.byQuest[id], chain)
    end
  end
end

-- GearQuest top picks ----------------------------------------------------------------

-- itemId -> level ranges where GearQuest ranks it top 3 for your class and spec.
local topPicks
local function TopPicks()
  if topPicks then return topPicks end
  local GQ = _G.GearQuest
  if not (GQ and GQ.Data and GQ.Data.entries) then return {} end
  topPicks = {}
  local ok = pcall(function()
    for _, entry in ipairs(GQ.Data.entries) do
      if entry.sourceType == "quest_reward" and entry.itemId and (entry.curatedRank or 99) <= 3
        and (not GQ.Data.EntryMatchesPlayer or GQ.Data:EntryMatchesPlayer(entry))
        and (not (GQ.Equip and GQ.Equip.EntryMatchesSpec) or GQ.Equip:EntryMatchesSpec(entry)) then
        topPicks[entry.itemId] = topPicks[entry.itemId] or {}
        table.insert(topPicks[entry.itemId], { entry.minLevel or 1, entry.maxLevel or 60 })
      end
    end
  end)
  if not ok then topPicks = {} end
  return topPicks
end

-- A reward is an upgrade for you if GearQuest ranks it top 3 at the level you'd get it:
-- your level now, or the item's required level if that's higher. (A rank 1 at level 14
-- doesn't make it an upgrade at 19.)
local function IsPick(reward)
  if Unusable(reward) then return false end
  -- Green upgrades are off unless you turn them on ("Green upgrades" in the list).
  if not MustDoDB.greenPicks and ((MD.GameQuality and MD.GameQuality(reward[1])) or reward[3]) <= 2 then return false end
  local ranges = TopPicks()[reward[1]]
  if not ranges then return false end
  local level = math.max(UnitLevel("player") or 1, reward[4] or 0)
  for _, r in ipairs(ranges) do
    if level >= r[1] and level <= r[2] then return true end
  end
  return false
end
MD.IsPick = IsPick

function MD:ResetTopPicks() topPicks = nil end

-- Gear check ----------------------------------------------------------------------------
-- The data's item quality can be wrong (Forever changed some items), so the game's own quality
-- wins whenever it knows the item. And gear only counts as rare/epic/special if it beats what
-- you're wearing in that slot (by item level).

local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function ItemLevel(item)
  local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  if fn then
    local ok, level = pcall(fn, item)
    if ok and level then return level end
  end
  local _, _, _, level = (C_Item and C_Item.GetItemInfo or GetItemInfo)(item)
  return level
end

local function GameQuality(itemId)
  if C_Item and C_Item.GetItemQualityByID then
    local q = C_Item.GetItemQualityByID(itemId)
    if q then return q end
  end
  local _, _, q = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemId)
  return q
end
MD.GameQuality = GameQuality

-- True when you already wear something at least as good in every slot this item could go in.
local function Outclassed(itemId)
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not getInstant then return false end
  local equipLoc = select(4, getInstant(itemId))
  local slots = equipLoc and SLOTS[equipLoc]
  if not slots then return false end
  local mine = ItemLevel(itemId)
  if not mine then return false end
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink("player", slot)
    if not link then return false end -- empty slot: anything helps
    local worn = ItemLevel(link)
    if not worn or mine > worn then return false end
  end
  return true
end

-- A reward's tags after the live checks above. Cached until your gear or level changes.
local tagCache = {}
function MD:ResetRewardTags() wipe(tagCache) end
function MD.RewardTags(r)
  local id = r[1]
  if id == 0 then return r[5] end -- spell rewards
  if Unusable(r) then return "" end
  if tagCache[id] then return tagCache[id] end
  local quality = GameQuality(id) or r[3]
  local outclassed = Outclassed(id)
  local kept = {}
  for raw in r[5]:gmatch("[^,]+") do
    local tag = raw:gsub("^%s+", "")
    local gearTag = tag == "rare" or tag == "epic" or tag == "use effect" or tag == "proc"
    local wrongQuality = (tag == "rare" and quality ~= 3) or (tag == "epic" and quality < 4)
    if not wrongQuality and not (gearTag and outclassed) then kept[#kept + 1] = tag end
  end
  -- The game says it's blue or purple when the data didn't: add the tag.
  local has = table.concat(kept, ",")
  if quality == 3 and not outclassed and not has:find("rare") then table.insert(kept, 1, "rare") end
  if quality >= 4 and not outclassed and not has:find("epic") then table.insert(kept, 1, "epic") end
  local tags = table.concat(kept, ", ")
  -- The game hasn't loaded the item yet: use the data for now, don't cache.
  if not GameQuality(id) then return tags end
  tagCache[id] = tags
  return tags
end
local RewardTags = MD.RewardTags

-- Whether a chain's quest tags (comma-separated) include this exact tag.
function MD:HasQuestTag(chain, wanted)
  for raw in chain.questTags:gmatch("[^,]+") do
    if raw:gsub("^%s+", ""):gsub("%s+$", "") == wanted then return true end
  end
  return false
end

-- Tier for one chain, for this character, or nil when it isn't a must-do for them.
function MD:Tier(chain)
  local best
  if not MD.HasProfession(chain.skill) then return nil end
  local function consider(key)
    if not best or TIER_INDEX[key] < TIER_INDEX[best] then best = key end
  end
  local function profession(tag)
    local id = PROFESSION_BY_NAME[tag]
    if id == COOKING then
      if MD.HasProfession(id) then consider("cooking") end
      return true
    end
    if id and MD.HasProfession(id) then consider(SECONDARY[id] and "fun" or "profession") return true end
    return id ~= nil
  end
  for _, r in ipairs(chain.rewards) do
    if IsPick(r) then consider("pick") end
    -- A cooking recipe only counts as cooking: its "recipe" tag doesn't make it fun.
    if r[6] == COOKING then
      if MD.HasProfession(COOKING) then consider("cooking") end
    else
    for raw in RewardTags(r):gmatch("[^,]+") do
      local tag = raw:gsub("^%s+", "")
      if profession(tag) then -- handled
      elseif EPIC_TAGS[tag] then consider("epic")
      elseif RARE_TAGS[tag] or tag:find("slot bag") then consider("rare")
      elseif FUN_TAGS[tag] then consider("fun") end
    end
    end
  end
  for raw in chain.questTags:gmatch("[^,]+") do
    local tag = raw:gsub("^%s+", "")
    if profession(tag) then -- handled
    elseif EPIC_TAGS[tag] then consider("epic")
    elseif tag:find("^dungeon: ") then consider("dungeon")
    elseif tag == "elite" then consider("elite") end
  end
  return best and MD.TIERS[TIER_INDEX[best]] or nil
end

-- The best reward of a chain: its name, why it's flagged, and how many other rewards there are.
function MD:BestReward(chain)
  local best, bestScore = nil, -1
  -- Upgrade for you beats a tagged reward beats quality; ties keep the data's order.
  for _, r in ipairs(chain.rewards) do
    -- "Forever item" is just a note, not a reason; the game's quality beats the data's.
    local tagged = RewardTags(r):gsub(",?%s*Forever item", "") ~= ""
    local quality = (r[1] > 0 and GameQuality(r[1])) or r[3]
    local score = (IsPick(r) and 100 or 0) + (tagged and 10 or 0) + quality - (Unusable(r) and 1000 or 0)
    if score > bestScore then best, bestScore = r, score end
  end
  if not best then
    -- No item reward recorded: name what it is instead.
    local d = chain.questTags:match("dungeon: ([^,]+)")
    if d then return "Dungeon quest: " .. d, "", 0 end
    if MD:HasQuestTag(chain, "elite") then return "Elite quest", "", 0 end
    return chain.questTags, "", 0
  end
  local why = RewardTags(best):gsub("Forever item", "new in Forever")
  if IsPick(best) then why = why ~= "" and ("upgrade for you, " .. why) or "upgrade for you" end
  if why == "" and chain.questTags ~= "" then why = (chain.questTags:gsub("dungeon: ", "")) end
  return best[2], why, #chain.rewards - 1, best
end

-- One word for why a chain is on the list: upgrade, spell, bag, dungeon, recipe...
function MD:ShortWhy(chain, tier)
  if tier.key == "pick" then return "upgrade" end
  if tier.key == "dungeon" then return "dungeon" end
  if tier.key == "elite" then return "elite" end
  local _, why = MD:BestReward(chain)
  why = (why or ""):lower()
  if tier.key == "profession" then
    for raw in ((select(2, MD:BestReward(chain)) or "") .. "," .. chain.questTags):gmatch("[^,]+") do
      local tag = raw:gsub("^%s+", "")
      if PROFESSION_BY_NAME[tag] then return tag:lower() end
    end
  end
  for _, word in ipairs({ "teaches spell", "attunement", "key", "slot bag", "epic", "class quest", "recipe",
                          "use effect", "proc", "rare", "cosmetic", "fun" }) do
    if why:find(word, 1, true) then
      return ({ ["teaches spell"] = "spell", ["slot bag"] = "bag", ["use effect"] = "special",
                ["proc"] = "special" })[word] or word
    end
  end
  return tier.label
end

-- One line: "Chausses of Westfall - upgrade for you, rare (+2 more)".
function MD:RewardText(chain)
  local name, why, more = MD:BestReward(chain)
  return string.format("%s%s%s", name, why ~= "" and (" - " .. why) or "", more > 0 and string.format(" (+%d more)", more) or "")
end

-- Progress ---------------------------------------------------------------------------

-- Returns done, total, nextSteps (quests ready to pick up now), active (quests in your log).
function MD:Progress(chain)
  local done, total, nextSteps, active = 0, 0, {}, {}
  for _, id in ipairs(chain.members) do
    if Eligible(id) and (IsCompleted(id) or not Settled(id)) then
      total = total + 1
      if IsCompleted(id) then
        done = done + 1
      elseif InLog(id) then
        active[#active + 1] = id
      elseif PrereqsDone(id) then
        nextSteps[#nextSteps + 1] = id
      end
    end
  end
  return done, total, nextSteps, active
end

-- Classic's gray level: quests at or below it give no XP.
local function GrayLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - math.floor(level / 10) - 5 end
  if level <= 59 then return level - math.floor(level / 5) - 1 end
  return level - 9
end

-- Category filters (per account): MustDoDB.hideCategory[tierKey or "openers"] = true hides that
-- whole kind of quest everywhere (list, map, NPC names, banner, abandon warning).
-- A category you've never toggled uses its default (HIDDEN_BY_DEFAULT); once you click it,
-- your choice is saved as true or false.
function MD:CategoryHidden(key)
  local choice = MustDoDB.hideCategory and MustDoDB.hideCategory[key]
  if choice == nil then return HIDDEN_BY_DEFAULT[key] == true end
  return choice == true
end
function MD:SetCategoryHidden(key, hidden)
  MustDoDB.hideCategory = MustDoDB.hideCategory or {}
  if hidden then
    MustDoDB.hideCategory[key] = true
  else
    MustDoDB.hideCategory[key] = HIDDEN_BY_DEFAULT[key] and false or nil
  end
  MD:Changed()
end

-- Hidden chains (per character): chains you've said you're not interested in.
function MD:IsHidden(chain) return MustDoCharDB.hidden[chain.final] == true end
function MD:SetHidden(chains, hidden)
  for _, chain in ipairs(chains) do MustDoCharDB.hidden[chain.final] = hidden or nil end
  MD:Changed()
end
function MD:HiddenCount()
  local n = 0
  for _ in pairs(MustDoCharDB.hidden) do n = n + 1 end
  return n
end

-- Rewards that stay worth it after the chain turns gray: spells, keys, attunements, upgrades.
-- Gear (class quest weapons included) goes stale like anything else.
local TIMELESS = { ["teaches spell"] = true, ["key"] = true, ["attunement"] = true, ["Onyxia attunement"] = true,
  ["UBRS key"] = true, ["Scholomance key"] = true, ["BRD key"] = true, ["Dire Maul key"] = true, ["Scarlet key"] = true,
  ["Workshop key"] = true, ["Sunken Temple"] = true }
function MD:Timeless(chain)
  -- Profession quests and rewards stay worth it at any level.
  if MD:Tier(chain) and MD:Tier(chain).key == "profession" then return true end
  for _, r in ipairs(chain.rewards) do
    if IsPick(r) then return true end
    for raw in RewardTags(r):gmatch("[^,]+") do if TIMELESS[(raw:gsub("^%s+", ""))] then return true end end
  end
  for raw in chain.questTags:gmatch("[^,]+") do if TIMELESS[(raw:gsub("^%s+", ""))] then return true end end
  return false
end

-- Where a chain stands for you right now:
--   "active"    one of its quests is in your log (show at any level: that's when you'd abandon it)
--   "available" its next step can be picked up at your level (wherever the chain ends)
--   nil         nothing to do about it right now
function MD:Status(chain, allLevels, includeHidden)
  if not includeHidden and MD:IsHidden(chain) then return nil end
  if not Eligible(chain.final) or Settled(chain.final) or not MD:Tier(chain) then return nil end
  if MD:CategoryHidden(MD:Tier(chain).key) then return nil end
  local _, _, nextSteps, active = MD:Progress(chain)
  if #active > 0 then return "active", active[1] end
  -- A chain shows when its next step is at your level now, however high it ends: long chains
  -- that pay off later are the point. Gray or green starting steps count. A chain that ends
  -- entirely below you (gray) only shows for a spell, key or upgrade, which stay worth it.
  local level = UnitLevel("player")
  local final = ns.Q[chain.final]
  if not allLevels and final[LEVEL] <= GrayLevel(level) and not MD:Timeless(chain) then return nil end
  -- Dungeon and elite chains show as soon as you can pick them up: you collect them (and find
  -- a group) before you go.
  local group = chain.questTags:find("dungeon: ", 1, true) ~= nil or MD:HasQuestTag(chain, "elite")
  for _, id in ipairs(nextSteps) do
    local q = ns.Q[id]
    if allLevels or (q[REQ] <= level and (group or q[LEVEL] <= level + 3)) then return "available", id end
  end
  return nil
end

function MD:Relevant(chain, allLevels)
  return MD:Status(chain, allLevels) ~= nil
end

-- Openers ---------------------------------------------------------------------------------
-- Quests that are strictly required for 3+ quests you haven't done. Returns nil, or
-- { status = "available"|"active", remaining = n, mustDo = n, guessed = bool }.
function MD:IsOpenerHidden(id) return MustDoCharDB.hiddenOpeners[id] == true end
function MD:SetOpenerHidden(id, hidden)
  MustDoCharDB.hiddenOpeners[id] = hidden or nil
  MD:Changed()
end

function MD:OpenerStatus(id, allLevels, includeHidden)
  local unlocks = ns.openers and ns.openers[id]
  if not unlocks or not Eligible(id) or Settled(id) then return nil end
  if not includeHidden and MD:IsOpenerHidden(id) then return nil end
  if MD:CategoryHidden("openers") then return nil end
  local q = ns.Q[id]
  local level = UnitLevel("player")
  local status
  if InLog(id) then
    status = "active"
  elseif PrereqsDone(id) and (allLevels or (q[REQ] <= level and q[LEVEL] <= level + 3)) then
    status = "available"
  else
    return nil
  end
  local remaining, mustDo, highest, guessed = 0, 0, 0, q[INFERRED] and true or false
  for _, d in ipairs(unlocks) do
    if Eligible(d) and not Settled(d) then
      remaining = remaining + 1
      highest = math.max(highest, ns.Q[d][LEVEL])
      if ns.Q[d][INFERRED] then guessed = true end
      for _, chain in ipairs(MD.byQuest[d] or {}) do
        if chain.final == d and MD:Tier(chain) and not MD:IsHidden(chain) then mustDo = mustDo + 1 break end
      end
    end
  end
  if remaining < 3 then return nil end
  -- Everything it opens is gray for you: not worth it.
  if not allLevels and highest <= GrayLevel(level) then return nil end
  return { status = status, remaining = remaining, mustDo = mustDo, guessed = guessed }
end

-- Best relevant chain a quest leads to, with its tier and the quest's step number.
function MD:ForQuest(id)
  local best, bestTier
  for _, chain in ipairs(MD.byQuest[id] or {}) do
    if Eligible(chain.final) and not Settled(chain.final) and not MD:IsHidden(chain)
      and not (MD:Tier(chain) and MD:CategoryHidden(MD:Tier(chain).key)) then
      local tier = MD:Tier(chain)
      if tier and (not bestTier or TIER_INDEX[tier.key] < TIER_INDEX[bestTier.key]) then
        best, bestTier = chain, tier
      end
    end
  end
  return best, bestTier
end

-- Quests that are alternatives of each other (one per starting zone, say) share this key:
-- the lowest quest ID among them.
function MD:AltKey(id)
  local key = id
  for _, other in ipairs(ns.Q[id] and ns.Q[id][EXCLUSIVE] or {}) do
    if other < key then key = other end
  end
  return key
end

-- In your log with every objective done.
function MD.IsReady(id)
  if C_QuestLog and C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(id) end
  if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) end
  return false
end

-- Where you need to be for this step right now, and the NPC to go to (for a waypoint):
--   not picked up yet   where the quest giver is
--   in your log         the dungeon it's done in, or the zone it takes place in
--   ready to hand in    where you turn it in
-- Returns locationName, npcSpot, state ("pickup", "doing" or "turnin").
function MD:Where(stepId, status)
  local q = ns.Q[stepId]
  local giver, turnIn = q[GIVER], q[14]
  if status ~= "active" then
    -- Quests that start from a looted item (no NPC location) belong where the item drops:
    -- the dungeon, or the zone the quest is in.
    if not (giver and giver[2]) then return q[12] or q[13] or (giver and giver[5]), giver, "pickup" end
    return giver[5], giver, "pickup"
  end
  if MD.IsReady(stepId) then
    return turnIn and turnIn[5] or (giver and giver[5]), turnIn or giver, "turnin"
  end
  return q[12] or q[13] or (giver and giver[5]), nil, "doing"
end

-- Every place a quest belongs in the list, most important first:
--   where its next step happens (see MD:Where), the zone the quest belongs to, its dungeon,
--   and the dungeon the whole chain leads to.
function MD:Places(stepId, status, finalId)
  local q = ns.Q[stepId]
  local out = {}
  local function add(name)
    if not name or name == "" then return end
    for _, existing in ipairs(out) do if MD.SamePlace(existing, name) then return end end
    out[#out + 1] = name
  end
  add((MD:Where(stepId, status)))
  add(q[13])
  add(q[12])
  if finalId and ns.Q[finalId] then add(ns.Q[finalId][12]) end
  return out
end

-- Location names compare loosely ("The Stockade" vs "Stockade", "Hall Of" vs "Hall of").
local function RawKey(name)
  return ((name or ""):lower():gsub("^the ", ""):gsub("[^%a]", ""))
end
-- Other names for one place (Zones.lua fills this): raw key -> the name to use.
MD.placeAliases = {}
function MD.PlaceLabel(name)
  return MD.placeAliases[RawKey(name)] or name
end
function MD.PlaceKey(name)
  return RawKey(MD.PlaceLabel(name))
end
function MD.SamePlace(a, b)
  if not a or not b then return false end
  return MD.PlaceKey(a) == MD.PlaceKey(b)
end

-- The map you're on, and its name.
function MD:PlayerMap()
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return map, info and info.name
end

function MD:QuestName(id) return ns.Q[id] and ns.Q[id][NAME] end
function MD:QuestRow(id) return ns.Q[id] end
function MD.Hex(tier) return "|c" .. tier.hex end
function MD.Rank(tier) return TIER_INDEX[tier.key] end

-- Events -----------------------------------------------------------------------------

-- Runs fn; each distinct error is shown in chat once instead of vanishing. Returns ok, err.
local errorsShown = {}
function MD.Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    MD.errorShown = true
    local msg = tostring(err)
    if not errorsShown[msg] then
      errorsShown[msg] = true
      DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Must Do error:|r " .. msg)
    end
  end
  return ok, err
end

MD.listeners = {}
function MD:OnChange(fn) self.listeners[#self.listeners + 1] = fn end
function MD:Changed()
  for _, fn in ipairs(self.listeners) do MD.Safe(fn) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Talent changes can change your spec, and with it GearQuest's picks.
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")
-- Learning or dropping a profession.
events:RegisterEvent("SKILL_LINES_CHANGED")
-- The game loading an item's details (its real quality can change a reward's tags).
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local itemRefreshPending = false
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == addonName then
      MustDoDB = MustDoDB or {}
      MustDoCharDB = MustDoCharDB or {}
      MustDoCharDB.hidden = MustDoCharDB.hidden or {}
      MustDoCharDB.hiddenOpeners = MustDoCharDB.hiddenOpeners or {}
    elseif arg1 and arg1:find("^GearQuestForever") then
      MD:ResetTopPicks()
    end
    return
  end
  if event == "PLAYER_LOGIN" then
    playerFaction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    playerClassBit = bit.lshift(1, (select(3, UnitClass("player")) or 1) - 1)
    local raceId = select(3, UnitRace("player"))
    playerRaceBit = raceId and 2 ^ (raceId - 1) or nil
    BuildIndex()
    MD.ready = true
    -- GearQuest loads its class pack after login; check again once it has.
    C_Timer.After(5, function() MD:ResetTopPicks() MD:Changed() end)
  end
  if event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
    MD:ResetTopPicks()
  end
  if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" then
    MD:ResetRewardTags()
  end
  if event == "GET_ITEM_INFO_RECEIVED" then
    -- Many arrive at once when the list opens: refresh once, a moment later, and only for
    -- items Must Do knows about.
    if not MD.ready or itemRefreshPending or not (arg1 and MD.rewardItems and MD.rewardItems[arg1]) then return end
    itemRefreshPending = true
    C_Timer.After(1, function() itemRefreshPending = false MD:Changed() end)
    return
  end
  if event == "SKILL_LINES_CHANGED" then
    local before = known and table.concat((function() local t = {} for k in pairs(known) do t[#t + 1] = k end table.sort(t) return t end)(), ",")
    MD:ResetProfessions()
    local after = {}
    for k in pairs(KnownProfessions()) do after[#after + 1] = k end
    table.sort(after)
    -- Skill-ups fire this constantly; only refresh when the set of professions changed.
    if before == table.concat(after, ",") then return end
  end
  if MD.ready then
    -- Completion flags (and your level, on a level-up) update a moment after these events.
    C_Timer.After(0.5, function() MD:Changed() end)
  end
end)
