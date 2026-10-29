-- Must Do: colors must-do quest givers' names in the mouseover tooltip and on the target frame,
-- and adds a line saying what they have for you. The name over their head is drawn by the game
-- and can't be changed.
local _, ns = ...
local MD = ns.MD

-- NPC name -> { tier, text } for everyone with a must-do quest for you right now: the giver of
-- your next step, or the NPC to hand a finished quest to. Rebuilt whenever Must Do refreshes.
local marks = {}

local function Rebuild()
  wipe(marks)
  for _, chain in ipairs(MD.chains) do
    local status, stepId = MD:Status(chain)
    if status then
      local _, spot, state = MD:Where(stepId, status)
      local npc
      if status == "available" then
        local g = MD:QuestRow(stepId)[MD.Q_GIVER]
        npc = g and g[2] and g[1]
      elseif state == "turnin" then
        npc = spot and spot[1]
      end
      if npc then
        local tier = MD:Tier(chain)
        local mark = marks[npc]
        if not mark or MD.Rank(tier) < MD.Rank(mark.tier) then
          local name = MD:BestReward(chain)
          local target = name:match("^Dungeon quest: ") and MD:QuestName(chain.final) or name
          local verb = state == "turnin" and "turn in " or ""
          marks[npc] = { tier = tier, text = string.format("Must Do: %s%s - %s (%s)", verb, MD:QuestName(stepId),
            target, MD:ShortWhy(chain, tier)) }
        end
      end
    end
  end
end
MD:OnChange(function() MD.Safe(Rebuild) end)

-- Forever restricts reading unit details inside instances (Questie skips there too), and quest
-- givers are outside anyway. Any read the game refuses just means "no mark".
local isForever = (select(4, GetBuildInfo()) or 0) >= 16000
local function MarkFor(unit)
  if isForever and IsInInstance() then return nil end
  local ok, mark = pcall(function()
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
    return marks[UnitName(unit)]
  end)
  return ok and mark or nil
end

-- Tooltip -------------------------------------------------------------------------------------

local function OnUnitTooltip(tooltip)
  if tooltip ~= GameTooltip or (isForever and IsInInstance()) then return end
  local _, unit = tooltip:GetUnit()
  local mark = MarkFor(unit or "mouseover")
  if not mark then return end
  local nameLine = _G["GameTooltipTextLeft1"]
  if nameLine then nameLine:SetTextColor(unpack(mark.tier.color)) end
  tooltip:AddLine(mark.text, mark.tier.color[1], mark.tier.color[2], mark.tier.color[3], true)
  tooltip:Show()
end

-- Same detection as Questie: modern tooltips use the data processor, Classic ones the old script.
local usesTooltipData = type(GameTooltip.GetPrimaryTooltipData) == "function"
  and TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
  and Enum and Enum.TooltipDataType
if usesTooltipData then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip) MD.Safe(OnUnitTooltip, tooltip) end)
elseif GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) MD.Safe(OnUnitTooltip, tooltip) end)
end

-- Target frame ---------------------------------------------------------------------------------

local function TargetName()
  local content = TargetFrame and TargetFrame.TargetFrameContent
  return (content and content.TargetFrameContentMain and content.TargetFrameContentMain.Name)
    or (TargetFrame and TargetFrame.name) or _G["TargetFrameTextureFrameName"]
end

local defaultColor
local function ColorTargetName()
  local fs = TargetName()
  if not fs then return end
  if not defaultColor then defaultColor = { fs:GetTextColor() } end
  local mark = MarkFor("target")
  if mark then fs:SetTextColor(unpack(mark.tier.color)) else fs:SetTextColor(unpack(defaultColor)) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function()
  -- Let Blizzard's own update finish first, then color.
  C_Timer.After(0, function() MD.Safe(ColorTargetName) end)
end)
