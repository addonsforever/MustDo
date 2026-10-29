-- Must Do: colored quest-giver markers on the world map and minimap for the next step of
-- every relevant chain. Drawn with the Questie build of HereBeDragons (it knows Forever's maps),
-- bundled in Libs/ so Questie doesn't need to be installed.
local _, ns = ...
local MD = ns.MD

local HBDPins = LibStub and LibStub("HereBeDragonsQuestie-Pins-2.0", true)
if not HBDPins then return end

local ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local WORLD_SIZE, MINI_SIZE = 22, 16
local SHOW_IN_PARENT = 1 -- HBD_PINS_WORLDMAP_SHOW_PARENT

local pool, used = {}, {}

local function OnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Must Do", MD.TIERS[1].color[1], MD.TIERS[1].color[2], MD.TIERS[1].color[3])
  for _, entry in ipairs(self.entries) do
    local tier = entry.tier
    GameTooltip:AddLine(string.format("%s: |cffffffff%s|r", entry.giver, entry.quest), 1, 0.82, 0)
    GameTooltip:AddLine(string.format("leads to %s%s|r", MD.Hex(tier), MD:RewardText(entry.chain)), 1, 1, 1, true)
  end
  GameTooltip:Show()
end

local function Acquire(size)
  local f = table.remove(pool)
  if not f then
    f = CreateFrame("Button", nil, UIParent)
    f.texture = f:CreateTexture(nil, "OVERLAY")
    f.texture:SetAllPoints()
    f.texture:SetTexture(ICON)
    f.texture:SetDesaturated(true)
    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  f:SetSize(size, size)
  used[#used + 1] = f
  return f
end

local function Clear()
  HBDPins:RemoveAllWorldMapIcons(MD)
  HBDPins:RemoveAllMinimapIcons(MD)
  for _, f in ipairs(used) do f:Hide() pool[#pool + 1] = f end
  wipe(used)
end

local function Refresh()
  Clear()
  if MustDoDB and MustDoDB.hidePins then return end
  -- One marker per quest giver; it lists every must-do quest they offer.
  local byGiver = {}
  -- Alternative quests (the same quest line from several starting zones) get one marker:
  -- the one on your current map if there is one, otherwise the first.
  local map = MD:PlayerMap()
  local chosen = {}
  for _, chain in ipairs(MD.chains) do
    local status, stepId = MD:Status(chain)
    if status == "available" then
      local key = MD:AltKey(stepId)
      local g = MD:QuestRow(stepId)[MD.Q_GIVER]
      local here = g and g[2] == map
      if not chosen[key] or (here and not chosen[key].here) then
        chosen[key] = { chain = chain, stepId = stepId, here = here }
      end
    end
  end
  for _, pick in pairs(chosen) do
    local tier = MD:Tier(pick.chain)
    local g = MD:QuestRow(pick.stepId)[MD.Q_GIVER]
    if g and g[2] then
      local key = g[1] .. g[2]
      local spot = byGiver[key]
      if not spot then
        spot = { map = g[2], x = g[3] / 100, y = g[4] / 100, entries = {}, best = tier }
        byGiver[key] = spot
      end
      table.insert(spot.entries, { giver = g[1], quest = MD:QuestName(pick.stepId), chain = pick.chain, tier = tier })
      if MD.Rank(tier) < MD.Rank(spot.best) then spot.best = tier end
    end
  end
  for _, spot in pairs(byGiver) do
    for _, mini in ipairs({ false, true }) do
      local f = Acquire(mini and MINI_SIZE or WORLD_SIZE)
      f.entries = spot.entries
      f.texture:SetVertexColor(unpack(spot.best.color))
      if mini then
        HBDPins:AddMinimapIconMap(MD, f, spot.map, spot.x, spot.y, true, false)
      else
        HBDPins:AddWorldMapIconMap(MD, f, spot.map, spot.x, spot.y, SHOW_IN_PARENT, 3000)
      end
    end
  end
end

MD.RefreshPins = function() MD.Safe(Refresh) end
MD:OnChange(MD.RefreshPins)

local zoneEvents = CreateFrame("Frame")
zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneEvents:SetScript("OnEvent", function() if MD.ready then MD.RefreshPins() end end)
