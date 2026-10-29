-- Must Do: nudges in Blizzard's UI. Quest offer banner, quest giver chat notice, abandon
-- warning and quest log stars. Every hook is optional: if a frame or function this client
-- doesn't have is missing, that one nudge is skipped and the rest keep working.
local _, ns = ...
local MD = ns.MD

-- The raid-marker star exists in every client; desaturated, it takes the tier color cleanly.
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local STAR_COORDS = { 0, 1, 0, 1 }

local function Describe(id)
  local chain, tier = MD:ForQuest(id)
  if not chain then return nil end
  local done, total = MD:Progress(chain)
  local isFinal = chain.final == id
  local left = isFinal and 0 or (total - done - 1)
  -- Same wording as the list: "Must do · 5 more steps to Destruction in Deadmines (dungeon)".
  local name = MD:BestReward(chain)
  local target = name:match("^Dungeon quest: ") and MD:QuestName(chain.final) or name
  local why = MD:ShortWhy(chain, tier)
  local steps = left > 0 and string.format("%d more %s to ", left, left == 1 and "step" or "steps") or ""
  return chain, tier, string.format("%sMust do|r|cff909090  ·  %s|r%s%s|r|cff909090 (%s)|r",
    MD.Hex(tier), steps, MD.Hex(tier), target, why)
end

local function Say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffcc19Must Do:|r " .. msg)
end

-- Quest offer banner --------------------------------------------------------------------

local banner
local function ShowBanner(id)
  local chain, tier, text = Describe(id)
  if not chain then
    if banner then banner:Hide() end
    return
  end
  if not banner then
    banner = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    banner:SetSize(460, 50)
    banner:SetClampedToScreen(true)
    banner:SetFrameStrata("DIALOG")
    if banner.SetBackdrop then
      banner:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      banner:SetBackdropColor(0, 0, 0, 0.9)
    end
    banner.star = banner:CreateTexture(nil, "OVERLAY")
    banner.star:SetTexture(STAR)
    banner.star:SetTexCoord(unpack(STAR_COORDS))
    banner.star:SetDesaturated(true)
    banner.star:SetSize(26, 26)
    banner.star:SetPoint("LEFT", 8, 0)
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banner.text:SetPoint("LEFT", banner.star, "RIGHT", 6, 0)
    banner.text:SetJustifyH("LEFT")
  end
  -- One icon, like the list; its tooltip lists the other reward choices.
  local rewards = MD:RewardsOf({ chain })
  local best = select(4, MD:BestReward(chain))
  if best then
    for k, r in ipairs(rewards) do if r == best then table.remove(rewards, k) break end end
    table.insert(rewards, 1, best)
  end
  local leftIcon = MD:ShowRewardIcons(banner, { rewards[1] }, 30, "RIGHT", -10, 0)
  if leftIcon then
    leftIcon.others = {}
    for k = 2, #rewards do leftIcon.others[#leftIcon.others + 1] = rewards[k][2] end
  end
  banner.star:SetVertexColor(unpack(tier.color))
  if banner.SetBackdropBorderColor then banner:SetBackdropBorderColor(unpack(tier.color)) end
  -- Size the banner to the text: measure it unconstrained, then cap the width.
  banner.text:SetWidth(0)
  banner.text:SetText(text)
  local textWidth = math.min(banner.text:GetStringWidth() + 4, 520)
  banner.text:SetWidth(textWidth)
  banner:SetWidth(8 + 26 + 6 + textWidth + 8 + (leftIcon and 40 or 0) + 8)
  banner:ClearAllPoints()
  if QuestFrame and QuestFrame:IsShown() then
    banner:SetPoint("BOTTOMLEFT", QuestFrame, "TOPLEFT", 0, 2)
  else
    banner:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
  banner:Show()
end

-- Abandon warning ------------------------------------------------------------------------

local warning
local function ShowAbandonWarning(popup, id)
  local chain, tier, text = Describe(id)
  if not chain then return end
  if not warning then
    warning = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    warning:SetSize(520, 60)
    warning:SetClampedToScreen(true)
    warning:SetFrameStrata("FULLSCREEN_DIALOG")
    if warning.SetBackdrop then
      warning:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      warning:SetBackdropColor(0.25, 0, 0, 0.95)
      warning:SetBackdropBorderColor(1, 0.2, 0.2)
    end
    warning.text = warning:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    warning.text:SetPoint("TOPLEFT", 10, -8)
    warning.text:SetPoint("BOTTOM", 0, 8)
    warning.text:SetJustifyH("LEFT")
  end
  local leftIcon = MD:ShowRewardIcons(warning, MD:RewardsOf({ chain }), 32, "RIGHT", -10, 0)
  warning.text:SetPoint("RIGHT", leftIcon or warning, leftIcon and "LEFT" or "RIGHT", -8, 0)
  warning.text:SetText("|cffff4040Wait!|r This quest is part of a must-do chain. Its rewards are on the right.\n" .. text)
  warning:ClearAllPoints()
  if popup then
    warning:SetPoint("BOTTOM", popup, "TOP", 0, 4)
    warning:SetScript("OnUpdate", function(self) if not popup:IsShown() then self:Hide() self:SetScript("OnUpdate", nil) end end)
  else
    warning:SetPoint("TOP", UIParent, "TOP", 0, -160)
    C_Timer.After(8, function() warning:Hide() end)
  end
  warning:Show()
  Say("|cffff4040you're abandoning a must-do chain:|r " .. text)
end

local function AbandonQuestID()
  if C_QuestLog and C_QuestLog.GetAbandonQuest then return C_QuestLog.GetAbandonQuest() end
  if GetAbandonQuestName then
    local name = GetAbandonQuestName()
    for id, q in pairs(ns.Q) do if q[1] == name and MD.InLog(id) then return id end end
  end
end

if type(StaticPopup_Show) == "function" then
  hooksecurefunc("StaticPopup_Show", function(which)
    if type(which) ~= "string" or not which:find("^ABANDON_QUEST") then return end
    local id = AbandonQuestID()
    if not id then return end
    local popup = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
    MD.Safe(ShowAbandonWarning, popup, id)
  end)
end

-- Quest givers ------------------------------------------------------------------------------

local function AnnounceAvailable(ids)
  for _, id in ipairs(ids) do
    local chain, _, text = Describe(id)
    if chain then Say(string.format("|cffffffff%s|r here. %s", MD:QuestName(id) or ("quest " .. id), text)) end
  end
end

local function GossipQuestIDs()
  local ids = {}
  if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
    for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      if info.questID then ids[#ids + 1] = info.questID end
    end
  end
  return ids
end

local function GreetingQuestIDs()
  local ids = {}
  if GetNumAvailableQuests and GetAvailableQuestInfo then
    for i = 1, GetNumAvailableQuests() do
      local id = select(5, GetAvailableQuestInfo(i))
      if id then ids[#ids + 1] = id end
    end
  end
  return ids
end

-- Quest log stars ---------------------------------------------------------------------------

local function StarFor(button)
  if not button.mustDoStar then
    local star = button:CreateTexture(nil, "OVERLAY")
    star:SetTexture(STAR)
    star:SetTexCoord(unpack(STAR_COORDS))
    star:SetDesaturated(true)
    star:SetSize(14, 14)
    star:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    button.mustDoStar = star
  end
  return button.mustDoStar
end

local function Decorate(button, id)
  if not button or not button.CreateTexture then return end
  local chain, tier = nil, nil
  if id then chain, tier = MD:ForQuest(id) end
  if chain then
    local star = StarFor(button)
    star:SetVertexColor(unpack(tier.color))
    star:Show()
    button.mustDoQuestID = id
    if not button.mustDoTooltip and button.HookScript then
      button.mustDoTooltip = true
      button:HookScript("OnEnter", function(self)
        local qid = self.mustDoQuestID
        if not (qid and self.mustDoStar and self.mustDoStar:IsShown()) then return end
        local _, _, text = Describe(qid)
        if text and GameTooltip:IsShown() then
          GameTooltip:AddLine(text, 1, 1, 1, true)
          GameTooltip:Show()
        end
      end)
    end
  elseif button.mustDoStar then
    button.mustDoStar:Hide()
  end
end

-- Modern quest log (inside the world map).
local function UpdateModernLog()
  local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
  if not (pool and pool.EnumerateActive) then return end
  for button in pool:EnumerateActive() do
    Decorate(button, button.questID)
  end
end

-- Classic quest log window.
local function UpdateClassicLog()
  if not (QuestLogListScrollFrame and GetQuestLogTitle) then return end
  local offset = FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
  for i = 1, QUESTS_DISPLAYED or 0 do
    local button = _G["QuestLogTitle" .. i]
    if button then
      local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i + offset)
      Decorate(button, (not isHeader) and id or nil)
    end
  end
end

local function HookIfPresent(name, fn)
  if type(_G[name]) == "function" then
    hooksecurefunc(name, function() MD.Safe(fn) end)
    return true
  end
end

-- Events -------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_FINISHED")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("QUEST_GREETING")
events:SetScript("OnEvent", function(_, event)
  if not MD.ready and event ~= "PLAYER_LOGIN" then return end
  if event == "PLAYER_LOGIN" then
    HookIfPresent("QuestLogQuests_Update", UpdateModernLog)
    HookIfPresent("QuestLog_Update", UpdateClassicLog)
    MD:OnChange(function() MD.Safe(UpdateModernLog) MD.Safe(UpdateClassicLog) end)
  elseif event == "QUEST_DETAIL" then
    local id = GetQuestID and GetQuestID()
    if id and id > 0 then MD.Safe(ShowBanner, id) end
  elseif event == "QUEST_FINISHED" then
    if banner then banner:Hide() end
  elseif event == "GOSSIP_SHOW" then
    MD.Safe(AnnounceAvailable, GossipQuestIDs())
  elseif event == "QUEST_GREETING" then
    MD.Safe(AnnounceAvailable, GreetingQuestIDs())
  end
end)
