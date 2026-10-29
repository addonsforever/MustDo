-- Must Do: reward icons. A strip of icons for a chain's final rewards, used in the list, the
-- quest offer banner and the abandon warning.
--   hover        item tooltip
--   ctrl-click   preview on your character
--   shift-click  link in chat
--   right-click  copyable Wowhead link (addons can't open a browser, so you paste it yourself)
local _, ns = ...
local MD = ns.MD

local SPELL_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_ICONS = 6

local function ItemIcon(itemId)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemId) end
  if GetItemIcon then return GetItemIcon(itemId) end
end

local function ItemLink(itemId)
  local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemId)
  return link
end

-- Copy box for Wowhead links ------------------------------------------------------------
-- Addons can't open a browser, so the box holds each link selected, ready for Cmd+C.

local copyBox
local function CopyLine(index)
  local line = copyBox.lines[index]
  if line then return line end
  line = {}
  line.label = copyBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  line.label:SetPoint("TOPLEFT", 14, -30 - (index - 1) * 48)
  line.label:SetPoint("RIGHT", -14, 0)
  line.label:SetJustifyH("LEFT")
  line.edit = CreateFrame("EditBox", nil, copyBox, "InputBoxTemplate")
  line.edit:SetSize(440, 22)
  line.edit:SetPoint("TOPLEFT", 18, -46 - (index - 1) * 48)
  line.edit:SetAutoFocus(false)
  line.edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
  line.edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
  line.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  -- Keep the text from being edited away; always re-select it.
  line.edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(line.url) self:HighlightText() end
  end)
  copyBox.lines[index] = line
  return line
end

-- links = { { label, url }, ... }
local function ShowCopyBox(links)
  if not copyBox then
    copyBox = CreateFrame("Frame", "MustDoCopyBox", UIParent, "BasicFrameTemplateWithInset")
    copyBox:SetPoint("CENTER", 0, 120)
    copyBox:SetFrameStrata("FULLSCREEN_DIALOG")
    copyBox.lines = {}
    tinsert(UISpecialFrames, "MustDoCopyBox")
    copyBox.hint = copyBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyBox.hint:SetPoint("BOTTOMLEFT", 14, 10)
    copyBox.hint:SetText("Click a link, press Cmd+C (Ctrl+C on Windows), paste it in your browser.")
  end
  copyBox:SetSize(480, 40 + #links * 48)
  for i, link in ipairs(links) do
    local line = CopyLine(i)
    line.url = link[2]
    line.label:SetText(link[1])
    line.edit:SetText(link[2])
    line.edit:SetCursorPosition(0)
    line.label:Show()
    line.edit:Show()
  end
  for i = #links + 1, #copyBox.lines do
    copyBox.lines[i].label:Hide()
    copyBox.lines[i].edit:Hide()
  end
  copyBox:Show()
  copyBox.lines[1].edit:SetFocus()
  copyBox.lines[1].edit:HighlightText()
end

local function Announce(links)
  for _, link in ipairs(links) do
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc19Must Do:|r " .. link[1] .. ": " .. link[2])
  end
  MD.Safe(ShowCopyBox, links)
end

-- An item's Wowhead page (spell rewards, which have no item, get a search instead).
function MD:OpenWowhead(itemId, label)
  local url
  if itemId and itemId > 0 then
    url = "https://www.wowhead.com/forever/item=" .. itemId
  else
    url = "https://www.wowhead.com/forever/search?q=" .. (label or ""):gsub("^Learn ", ""):gsub(" ", "+")
  end
  Announce({ { "Item: " .. (label or "reward"), url } })
end

-- The quest to pick up next and the chain's final quest.
function MD:OpenQuestLinks(stepId, finalId)
  local links = { { "Next: " .. (MD:QuestName(stepId) or "quest"), "https://www.wowhead.com/forever/quest=" .. stepId } }
  if finalId and finalId ~= stepId then
    links[2] = { "Final: " .. (MD:QuestName(finalId) or "quest"), "https://www.wowhead.com/forever/quest=" .. finalId }
  end
  Announce(links)
end

-- Icons ------------------------------------------------------------------------------------

local function OnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.itemId and self.itemId > 0 then
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemId)
    else GameTooltip:SetHyperlink("item:" .. self.itemId) end
  else
    GameTooltip:AddLine(self.label or "Reward", 1, 1, 1)
  end
  if self.tags and self.tags ~= "" then GameTooltip:AddLine(self.tags, 0.7, 0.7, 0.7, true) end
  if self.others and #self.others > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Other rewards:", 1, 0.82, 0)
    for _, name in ipairs(self.others) do GameTooltip:AddLine("  " .. name, 1, 1, 1) end
  end
  GameTooltip:AddLine("Right-click: Wowhead link", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function OnClick(self, button)
  if button == "RightButton" then
    MD:OpenWowhead(self.itemId, self.label)
    return
  end
  local link = self.itemId and self.itemId > 0 and ItemLink(self.itemId)
  if not link then return end
  if IsControlKeyDown() and DressUpItemLink then DressUpItemLink(link)
  elseif IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

local function NewIcon(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b:RegisterForClicks("AnyUp")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.border:SetBlendMode("ADD")
  b.border:SetPoint("CENTER")
  b.border:SetSize(size * 1.8, size * 1.8)
  b:SetScript("OnEnter", function(self) MD.Safe(OnEnter, self) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, button) MD.Safe(OnClick, self, button) end)
  return b
end

-- Rewards of several chains, without repeats.
function MD:RewardsOf(chains)
  local out, seen = {}, {}
  for _, chain in ipairs(chains) do
    for _, r in ipairs(chain.rewards) do
      local key = r[1] > 0 and r[1] or r[2]
      if not seen[key] then seen[key] = true out[#out + 1] = r end
    end
  end
  return out
end

-- Fills parent.mustDoIcons with icons for these rewards, laid out right to left from anchor.
-- Returns the leftmost icon (or nil) so callers can keep text clear of it.
function MD:ShowRewardIcons(parent, rewards, size, anchorPoint, anchorX, anchorY)
  parent.mustDoIcons = parent.mustDoIcons or {}
  local icons = parent.mustDoIcons
  local count = math.min(#rewards, MAX_ICONS)
  local left
  for i = 1, count do
    local r = rewards[i]
    local b = icons[i] or NewIcon(parent, size)
    icons[i] = b
    b.itemId, b.label, b.tags = r[1], r[2], MD.RewardTags(r)
    b.icon:SetTexture(r[1] > 0 and (ItemIcon(r[1]) or UNKNOWN_ICON) or SPELL_ICON)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r[3]]
    if color and r[3] >= 2 then
      b.border:SetVertexColor(color.r, color.g, color.b)
      b.border:Show()
    else
      b.border:Hide()
    end
    b:ClearAllPoints()
    b:SetPoint(anchorPoint, parent, anchorPoint, anchorX - (i - 1) * (size + 4), anchorY)
    b:Show()
    left = b
  end
  for i = count + 1, #icons do icons[i]:Hide() end
  return left
end
