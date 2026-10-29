-- Must Do: the list window. Sections: your current zone, then every other place. Quests in your
-- log are listed where their next step happens; abandoning one pops a warning (Hooks.lua). Each row leads with the quest to do, then what to do and where,
-- then what it leads to. Click a row to set a waypoint on the quest giver.
local _, ns = ...
local MD = ns.MD

local QUEST_SIZE, ACTION_SIZE, LEADS_SIZE, HEADER_SIZE = 16, 13, 12, 17
local HEADER_HEIGHT, ICON_SIZE, MAX_ICONS = 36, 26, 6
local WIDTH = 700
local ROW_WIDTH = WIDTH - 50
local TEXT_LEFT = 34

local frame, rows = nil, {}

local function Sized(fs, size)
  local font, _, flags = fs:GetFont()
  fs:SetFont(font, size, flags)
  return fs
end

local function SetWaypoint(g, title)
  if not (g and g[2]) then return false end
  local x, y = g[3] / 100, g[4] / 100
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(g[2], x, y, { title = title })
    return true
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(g[2], x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true
  end
  return false
end

local function GetRow(i)
  if rows[i] then return rows[i] end
  local row = CreateFrame("Button", nil, frame.content)
  row:SetWidth(ROW_WIDTH)
  row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(1, 1, 1, 0.06)
  -- Thin line under section headers.
  row.rule = row:CreateTexture(nil, "ARTWORK")
  row.rule:SetColorTexture(1, 0.8, 0.1, 0.35)
  row.rule:SetHeight(1)
  row.rule:SetPoint("BOTTOMLEFT", 8, 4)
  row.rule:SetPoint("BOTTOMRIGHT", -8, 4)
  -- "x" hides the row's chains; on a hidden row (shown via "Show hidden") it reads "unhide".
  row.hide = CreateFrame("Button", nil, row)
  row.hide:SetSize(22, 22)
  row.hide:SetPoint("TOPRIGHT", 0, -6)
  row.hide.label = Sized(row.hide:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), QUEST_SIZE)
  row.hide.label:SetPoint("RIGHT", -4, 0)
  row.hide:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  row.hide:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.isHidden and "Unhide this" or "Not interested - hide this", 1, 1, 1)
    GameTooltip:Show()
  end)
  row.hide:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if not row.isHidden and not row:IsMouseOver() then self:SetAlpha(0) end
  end)
  row.hide:SetScript("OnClick", function()
    if row.openerId then MD:SetOpenerHidden(row.openerId, not row.isHidden)
    elseif row.chains then MD:SetHidden(row.chains, not row.isHidden) end
  end)
  -- The x only shows while you hover the row (or always, on a hidden row, as "unhide").
  row:SetScript("OnEnter", function(self) self.hide:SetAlpha(1) end)
  row:SetScript("OnLeave", function(self)
    if not self.isHidden and not self.hide:IsMouseOver() then self.hide:SetAlpha(0) end
  end)
  row.star = row:CreateTexture(nil, "OVERLAY")
  row.star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
  row.star:SetDesaturated(true)
  row.star:SetSize(18, 18)
  row.star:SetPoint("TOPLEFT", 8, -10)
  local function line(size, template)
    local fs = Sized(row:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight"), size)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
  end
  row.quest = line(QUEST_SIZE)
  row.action = line(ACTION_SIZE)
  row.leads = line(LEADS_SIZE)
  -- Left-click: waypoint to the quest giver. Right-click: the quests on Wowhead.
  row:RegisterForClicks("AnyUp")
  row:SetScript("OnClick", function(self, button)
    MD.Safe(function()
      if button == "RightButton" then
        if self.stepId then MD:OpenQuestLinks(self.stepId, self.finalId) end
      elseif self.giver and SetWaypoint(self.giver, self.stepName) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc19Must Do:|r waypoint set to " .. self.giver[1])
      end
    end)
  end)
  rows[i] = row
  return row
end

-- Stacks the row's text lines top to bottom at the given width; returns the row height.
local function Layout(row, left, width, lines)
  local y = 8
  for _, fs in ipairs(lines) do
    fs:ClearAllPoints()
    if fs:GetText() and fs:GetText() ~= "" then
      fs:SetWidth(width)
      fs:SetPoint("TOPLEFT", row, "TOPLEFT", left, -y)
      fs:Show()
      y = y + fs:GetStringHeight() + 3
    else
      fs:Hide()
    end
  end
  return y + 6
end

local DUNGEON, GRAY, GREEN, WHITE = "|cffff9933", "|cff909090", "|cff40ff40", "|cffffffff"
local SEP = GRAY .. "  ·  |r"

-- One word for why it's on the list (shared with the banner, see Core.lua).
local function ShortWhy(entry) return MD:ShortWhy(entry.chain, entry.tier) end

-- Line 2: what to do (and where, unless the section header already says so), then where it leads.
-- Returns the text and the NPC to send a waypoint to.
local function DetailLine(entry, sectionPlace)
  local stepId, status = entry.stepId, entry.status
  local q = MD:QuestRow(stepId)
  local parts, spotOut = {}, nil
  local place, spot, state = MD:Where(stepId, status)
  local function where(name)
    if name and not MD.SamePlace(name, sectionPlace) then
      parts[#parts + 1] = (q[MD.Q_DUNGEON] == name and DUNGEON or GRAY) .. name .. "|r"
    end
  end
  if state == "turnin" and spot then
    parts[#parts + 1] = GREEN .. "Ready|r" .. GRAY .. " - turn in to|r " .. WHITE .. spot[1] .. "|r"
    where(spot[5])
    spotOut = spot
  elseif state == "doing" then
    parts[#parts + 1] = GRAY .. "In your log|r"
    where(place)
  else
    local g = q[MD.Q_GIVER]
    local item = g and g[1]:match("^(.-) %(item%)$")
    if item then
      parts[#parts + 1] = GRAY .. "Loot|r " .. WHITE .. item .. "|r"
    elseif g and g[2] then
      parts[#parts + 1] = GRAY .. "Pick up from|r " .. WHITE .. g[1] .. "|r"
    elseif g then
      parts[#parts + 1] = GRAY .. "Starts from|r " .. WHITE .. g[1] .. "|r"
    else
      parts[#parts + 1] = GRAY .. "Starts from a looted item|r"
    end
    where(place)
    if q[MD.Q_DUNGEON] and not MD.SamePlace(q[MD.Q_DUNGEON], sectionPlace) and not MD.SamePlace(q[MD.Q_DUNGEON], place) then
      parts[#parts + 1] = DUNGEON .. q[MD.Q_DUNGEON] .. "|r"
    end
    spotOut = g
  end
  -- Where it leads: the reward (or the dungeon), and how far off it is.
  local done, total = MD:Progress(entry.chain)
  local left = total - done - 1
  local name = MD:BestReward(entry.chain)
  local dungeonOnly = name:match("^Dungeon quest: (.+)")
  if dungeonOnly and left <= 0 then
    -- This is the last step and it has no item reward on record: nothing to point at.
    parts[#parts + 1] = MD.Hex(entry.tier) .. "dungeon quest|r"
  else
    local target = dungeonOnly and MD:QuestName(entry.chain.final) or name
    local steps = left > 0 and (GRAY .. left .. " more " .. (left == 1 and "step" or "steps") .. " to|r ") or ""
    parts[#parts + 1] = steps .. MD.Hex(entry.tier) .. target .. "|r" .. GRAY .. " (" .. ShortWhy(entry) .. ")|r"
  end
  return table.concat(parts, SEP), spotOut
end

-- One row per quest to do: several chains that start with the same quest are merged.
local function Collect(allLevels)
  local byStep, list = {}, {}
  for _, chain in ipairs(MD.chains) do
    local status, stepId = MD:Status(chain, allLevels, MustDoDB.showHidden)
    if status then
      local entry = byStep[stepId]
      if not entry then
        entry = { status = status, stepId = stepId, chains = {}, level = MD:QuestRow(stepId)[2] }
        byStep[stepId] = entry
        list[#list + 1] = entry
      end
      local tier = MD:Tier(chain)
      table.insert(entry.chains, chain)
      if not entry.tier or MD.Rank(tier) < MD.Rank(entry.tier) then entry.tier, entry.chain = tier, chain end
    end
  end
  return list
end

local function Refresh()
  local map, mapName = MD:PlayerMap()
  -- Each quest is listed under every place it belongs (MD:Places): where its next step is,
  -- its zone, and its dungeon. "Here in" gets everything that belongs where you are.
  local here, byPlace, placeNames, labels = {}, {}, {}, {}
  for _, entry in ipairs(Collect(MustDoDB.allLevels)) do
    entry.place = MD:Where(entry.stepId, entry.status)
    for _, p in ipairs(MD:Places(entry.stepId, entry.status, entry.chain.final)) do
      if MD.SamePlace(p, mapName) then
        here[#here + 1] = entry
      else
        -- Group by a loose key so spellings of one place share a section.
        local key = MD.PlaceKey(p)
        if not byPlace[key] then byPlace[key] = {} placeNames[#placeNames + 1] = key labels[key] = MD.PlaceLabel(p) end
        table.insert(byPlace[key], entry)
      end
    end
  end
  local function order(a, b)
    if MD.Rank(a.tier) ~= MD.Rank(b.tier) then return MD.Rank(a.tier) < MD.Rank(b.tier) end
    if a.level ~= b.level then return a.level < b.level end
    return MD:QuestName(a.stepId) < MD:QuestName(b.stepId)
  end
  -- Within a section, alternative quests (the same quest line from another starting zone) and
  -- repeats only show once.
  local function dedupe(list)
    table.sort(list, order)
    local out, shown = {}, {}
    for _, e in ipairs(list) do
      local key = MD:AltKey(e.stepId)
      if not shown[key] then shown[key] = true out[#out + 1] = e end
    end
    return out
  end
  here = dedupe(here)
  for _, p in ipairs(placeNames) do byPlace[p] = dedupe(byPlace[p]) end

  local y, i = 0, 0
  local function place(row, height)
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row:Show()
    y = y + height
  end
  local sectionPlace
  local function header(text, count, placeName)
    sectionPlace = placeName
    i = i + 1
    local row = GetRow(i)
    row.star:Hide()
    MD:ShowRewardIcons(row, {}, ICON_SIZE, "TOPRIGHT", -30, -8)
    row.hide:Hide()
    row.rule:Show()
    row:SetAlpha(1)
    row.chains, row.isHidden, row.giver, row.stepId, row.finalId, row.openerId = nil, nil, nil, nil, nil, nil
    Sized(row.quest, HEADER_SIZE)
    row.quest:SetText(string.format("|cffffcc19%s|r  |cff808080%d|r", text, count))
    row.action:SetText(count == 0 and (GRAY .. "Nothing to do here right now.|r") or "")
    row.leads:SetText("")
    local h = Layout(row, 8, ROW_WIDTH - 16, { row.quest, row.action, row.leads })
    place(row, math.max(h + 6, HEADER_HEIGHT))
  end
  local drawRow
  -- A row that fails to draw says so, instead of vanishing and taking the rest with it.
  local function chainRow(entry)
    i = i + 1
    local row = GetRow(i)
    local ok, err = MD.Safe(drawRow, row, entry)
    if not ok then
      row.star:Hide()
      Sized(row.quest, QUEST_SIZE)
      row.quest:SetText("|cffff4040(couldn't draw this row)|r " .. (MD:QuestName(entry.stepId) or "?"))
      row.action:SetText(GRAY .. tostring(err) .. "|r")
      row.leads:SetText("")
      place(row, Layout(row, TEXT_LEFT, ROW_WIDTH - TEXT_LEFT - 30, { row.quest, row.action, row.leads }))
    end
  end
  function drawRow(row, entry)
    row.rule:Hide()
    row.star:SetVertexColor(unpack(entry.tier.color))
    row.star:Show()
    -- Every reward gets an icon, the one the text names first (rightmost).
    local rewards = MD:RewardsOf(entry.chains)
    local best = select(4, MD:BestReward(entry.chain))
    if best then
      for k, r in ipairs(rewards) do
        if r == best then table.remove(rewards, k) break end
      end
      table.insert(rewards, 1, best)
    end
    local shownIcons = math.min(#rewards, MAX_ICONS)
    local trimmed = {}
    for k = 1, shownIcons do trimmed[k] = rewards[k] end
    MD:ShowRewardIcons(row, trimmed, ICON_SIZE, "TOPRIGHT", -30, -8)
    -- Rewards past the icon limit are listed in the first icon's tooltip.
    local first = row.mustDoIcons and row.mustDoIcons[1]
    if first then
      first.others = {}
      for k = shownIcons + 1, #rewards do first.others[#first.others + 1] = rewards[k][2] end
    end
    row.chains, row.isHidden, row.openerId = entry.chains, MD:IsHidden(entry.chain), nil
    row.hide.label:SetText(row.isHidden and "|cff40ff40unhide|r" or "|cff707070x|r")
    row.hide:SetWidth(row.isHidden and 56 or 22)
    row.hide:Show()
    row.hide:SetAlpha(row.isHidden and 1 or 0)
    row:SetAlpha(row.isHidden and 0.5 or 1)
    Sized(row.quest, QUEST_SIZE)
    row.quest:SetText(WHITE .. (MD:QuestName(entry.stepId) or "?") .. "|r")
    local detail, giver = DetailLine(entry, sectionPlace)
    row.action:SetText(detail)
    row.leads:SetText("")
    row.giver, row.stepName = giver, MD:QuestName(entry.stepId)
    row.stepId, row.finalId = entry.stepId, entry.chain.final
    local iconsWidth = shownIcons > 0 and (shownIcons * (ICON_SIZE + 4) + 8) or 0
    local h = Layout(row, TEXT_LEFT, ROW_WIDTH - TEXT_LEFT - 30 - iconsWidth, { row.quest, row.action, row.leads })
    place(row, math.max(h, ICON_SIZE + 18))
  end

  local function finish()
    for j = i + 1, #rows do rows[j]:Hide() end
    frame.content:SetHeight(math.max(y, 1))
    local label = frame.showHidden and (frame.showHidden.Text or frame.showHidden.text or frame.showHidden.label)
    if label then label:SetText(string.format("Show hidden (%d)", MD:HiddenCount())) end
  end

  -- Openers: quests that are strictly required for 3+ quests you haven't done.
  local list = {}
  for id in pairs(ns.openers or {}) do
    local info = MD:OpenerStatus(id, MustDoDB.allLevels, MustDoDB.showHidden)
    if info then
      info.id = id
      info.place = MD:Where(id, info.status)
      list[#list + 1] = info
    end
  end
  local function openerRow(info)
    i = i + 1
    local row = GetRow(i)
    row.rule:Hide()
    row.star:SetVertexColor(0.55, 0.8, 1)
    row.star:Show()
    MD:ShowRewardIcons(row, {}, ICON_SIZE, "TOPRIGHT", -30, -8)
    row.isHidden = MD:IsOpenerHidden(info.id)
    row.chains = nil
    row.openerId = info.id
    row.hide.label:SetText(row.isHidden and "|cff40ff40unhide|r" or "|cff707070x|r")
    row.hide:SetWidth(row.isHidden and 56 or 22)
    row.hide:Show()
    row.hide:SetAlpha(row.isHidden and 1 or 0)
    row:SetAlpha(row.isHidden and 0.5 or 1)
    Sized(row.quest, QUEST_SIZE)
    row.quest:SetText(WHITE .. MD:QuestName(info.id) .. "|r")
    -- Reuse the Must Do detail wording for "what to do", then say what it opens.
    local q = MD:QuestRow(info.id)
    local parts = {}
    local _, spot, state = MD:Where(info.id, info.status)
    if info.status == "active" then
      parts[1] = state == "turnin" and (GREEN .. "Ready|r" .. GRAY .. " - turn in to|r " .. WHITE .. spot[1] .. "|r")
        or (GRAY .. "In your log|r")
    else
      local g = q[MD.Q_GIVER]
      local item = g and g[1]:match("^(.-) %(item%)$")
      parts[1] = item and (GRAY .. "Loot|r " .. WHITE .. item .. "|r")
        or (g and (GRAY .. "Pick up from|r " .. WHITE .. g[1] .. "|r") or (GRAY .. "Starts from a looted item|r"))
    end
    if info.place and not MD.SamePlace(info.place, sectionPlace) then parts[#parts + 1] = GRAY .. info.place .. "|r" end
    local opens = string.format("|cff8ccfffopens %d quests|r", info.remaining)
    if info.mustDo > 0 then opens = opens .. GRAY .. string.format(" (%d must-do)", info.mustDo) .. "|r" end
    parts[#parts + 1] = opens
    if info.guessed then parts[#parts + 1] = GRAY .. "order guessed|r" end
    row.action:SetText(table.concat(parts, SEP))
    row.leads:SetText("")
    row.giver = (info.status ~= "active" or state == "turnin") and spot or nil
    row.stepName, row.stepId, row.finalId = MD:QuestName(info.id), info.id, nil
    place(row, math.max(Layout(row, TEXT_LEFT, ROW_WIDTH - TEXT_LEFT - 30, { row.quest, row.action, row.leads }), 44))
  end

  -- Openers also belong in "what to do here": they go under the must-dos in each section,
  -- skipping any quest that's already listed as a must-do there.
  local function openerKey(info) return info.id end
  local hereOpeners, placeOpeners = {}, {}
  local listedHere, listedAt = {}, {}
  for _, e in ipairs(here) do listedHere[e.stepId] = true end
  for key, entries in pairs(byPlace) do
    listedAt[key] = {}
    for _, e in ipairs(entries) do listedAt[key][e.stepId] = true end
  end
  for _, info in ipairs(list) do
    if info.status == "active" or info.status == "available" then
      local seen = {}
      for _, p in ipairs(MD:Places(info.id, info.status)) do
        local key = MD.PlaceKey(p)
        if not seen[key] then
          seen[key] = true
          if MD.SamePlace(p, mapName) then
            if not listedHere[info.id] then hereOpeners[#hereOpeners + 1] = info end
          elseif not (listedAt[key] and listedAt[key][info.id]) then
            if not byPlace[key] then byPlace[key] = {} placeNames[#placeNames + 1] = key labels[key] = MD.PlaceLabel(p) end
            placeOpeners[key] = placeOpeners[key] or {}
            table.insert(placeOpeners[key], info)
          end
        end
      end
    end
  end
  local function byOpensDesc(a, b)
    if a.remaining ~= b.remaining then return a.remaining > b.remaining end
    return MD:QuestName(openerKey(a)) < MD:QuestName(openerKey(b))
  end
  table.sort(hereOpeners, byOpensDesc)

  header("Here in " .. (mapName or "this zone"), #here + #hereOpeners, mapName)
  for _, e in ipairs(here) do chainRow(e) end
  for _, info in ipairs(hereOpeners) do openerRow(info) end
  -- Every other place: the ones next to where you are first (best stuff first), then the rest by
  -- how well their level suits you, closer first among equals (see Zones.lua).
  local function count(p) return #byPlace[p] + #(placeOpeners[p] or {}) end
  local sortKey = {}
  for _, p in ipairs(placeNames) do
    local best = 99 -- sections with only openers come after any with a must-do
    for _, e in ipairs(byPlace[p]) do best = math.min(best, MD.Rank(e.tier)) end
    local hops = mapName and MD.Hops(labels[p], mapName) or 99
    sortKey[p] = { near = hops <= 1 and 0 or 1, hops = hops, gap = MD.LevelGap(labels[p]) or 99, best = best }
  end
  table.sort(placeNames, function(a, b)
    local ka, kb = sortKey[a], sortKey[b]
    if ka.near ~= kb.near then return ka.near < kb.near end
    if ka.near == 1 and ka.gap ~= kb.gap then return ka.gap < kb.gap end
    if ka.near == 1 and ka.hops ~= kb.hops then return ka.hops < kb.hops end -- same level: closer first
    if ka.best ~= kb.best then return ka.best < kb.best end
    if count(a) ~= count(b) then return count(a) > count(b) end
    return labels[a] < labels[b]
  end)
  for _, p in ipairs(placeNames) do
    header(labels[p], count(p), labels[p])
    for _, e in ipairs(byPlace[p]) do chainRow(e) end
    table.sort(placeOpeners[p] or {}, byOpensDesc)
    for _, info in ipairs(placeOpeners[p] or {}) do openerRow(info) end
  end
  finish()
end

local function Checkbox(label, key, x, onChange)
  local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("BOTTOMLEFT", x, 8)
  local text = cb.Text or cb.text
  if not text then
    text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  text:SetText(label)
  cb.label = text
  cb:SetScript("OnShow", function(self) self:SetChecked(MustDoDB[key] and true or false) end)
  cb:SetScript("OnClick", function(self) MustDoDB[key] = self:GetChecked() and true or nil onChange() end)
  return cb
end

local function CreateWindow()
  frame = CreateFrame("Frame", "MustDoFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, 680)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("DIALOG")
  tinsert(UISpecialFrames, "MustDoFrame")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("Must Do")

  -- Legend and controls live in a "?" tooltip instead of crowding the top.
  local help = CreateFrame("Button", nil, frame)
  help:SetSize(22, 22)
  help:SetPoint("TOPLEFT", 10, -2)
  help.label = Sized(help:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 15)
  help.label:SetPoint("CENTER")
  help.label:SetText("?")
  help:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Must Do", 1, 0.8, 0.1)
    GameTooltip:AddLine("Quests worth doing (for the reward, a dungeon, or because they open", 1, 1, 1, true)
    GameTooltip:AddLine("lots of other quests), grouped by where you do them.", 1, 1, 1, true)
    GameTooltip:AddLine("The colored words at the top hide or show each kind.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Profession quests and rewards only show for professions you have.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click a row: waypoint to the quest giver", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click a row: Wowhead links", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Hover the icon: the rewards", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("x (on hover): hide it", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  help:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Category filters: click a chip to hide that kind of quest everywhere; dimmed means hidden.
  local chips = {}
  local function PaintChips()
    for _, c in ipairs(chips) do
      local off = MD:CategoryHidden(c.key)
      c.label:SetTextColor(c.color[1], c.color[2], c.color[3])
      c:SetAlpha(off and 0.35 or 1)
      c.strike:SetShown(off)
    end
  end
  local defs = {}
  for _, t in ipairs(MD.TIERS) do defs[#defs + 1] = { t.key, t.chip or t.label, t.color, t.label } end
  defs[#defs + 1] = { "openers", "openers", { 0.55, 0.8, 1 }, "quests that open up others" }
  local x = 14
  for k, def in ipairs(defs) do
    local c = CreateFrame("Button", nil, frame)
    c.key, c.color, c.full = def[1], def[3], def[4]
    c.label = Sized(c:CreateFontString(nil, "OVERLAY", "GameFontNormal"), LEADS_SIZE + 1)
    c.label:SetPoint("CENTER")
    c.label:SetText(def[2])
    c:SetSize(c.label:GetStringWidth() + 16, 22)
    c:SetPoint("TOPLEFT", x, -30)
    x = x + c:GetWidth() + 6
    c.strike = c:CreateTexture(nil, "OVERLAY")
    c.strike:SetColorTexture(1, 1, 1, 0.8)
    c.strike:SetHeight(1)
    c.strike:SetPoint("LEFT", 6, 0)
    c.strike:SetPoint("RIGHT", -6, 0)
    c:SetScript("OnClick", function(self) MD:SetCategoryHidden(self.key, not MD:CategoryHidden(self.key)) PaintChips() end)
    c:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(self.full, self.color[1], self.color[2], self.color[3])
      GameTooltip:AddLine(MD:CategoryHidden(self.key) and "Click to show these again" or "Click to hide these everywhere", 1, 1, 1)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chips[k] = c
  end
  frame.paintChips = PaintChips

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -58)
  scroll:SetPoint("BOTTOMRIGHT", -30, 40)
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetSize(ROW_WIDTH, 1)
  scroll:SetScrollChild(frame.content)

  Checkbox("Show all levels", "allLevels", 12, Refresh)
  Checkbox("Hide map markers", "hidePins", 160, function() if MD.RefreshPins then MD.RefreshPins() end end)
  frame.showHidden = Checkbox("Show hidden", "showHidden", 320, Refresh)
  Checkbox("Green upgrades", "greenPicks", 490, function() MD:Changed() end)

  frame:SetScript("OnShow", function() PaintChips() MD.Safe(Refresh) end)
end

local function Toggle()
  if not MD.ready then return end
  if not frame then CreateWindow() frame:Hide() end
  frame:SetShown(not frame:IsShown())
end

MD:OnChange(function() if frame and frame:IsShown() then MD.Safe(Refresh) end end)

local zoneEvents = CreateFrame("Frame")
zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneEvents:SetScript("OnEvent", function() if frame and frame:IsShown() then MD.Safe(Refresh) end end)

-- /mustdo why <quest name or id>: the addon's reasoning, for when something is missing.
local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffffcc19Must Do:|r " .. msg) end

local function Why(arg)
  local map, mapName = MD:PlayerMap()
  local race, raceFile, raceId = UnitRace("player")
  local _, classFile, classId = UnitClass("player")
  Say(string.format("you: level %d, %s (race %s), %s (class %s), %s; map %s (%s)", UnitLevel("player"), tostring(race),
    tostring(raceId), tostring(classFile), tostring(classId), tostring(UnitFactionGroup("player")), tostring(map), tostring(mapName)))
  if not arg or arg == "" then return end
  local ids = {}
  local n = tonumber(arg)
  if n then ids[1] = n else
    for id, q in pairs(ns.Q) do if q[1]:lower():find(arg:lower(), 1, true) then ids[#ids + 1] = id end end
  end
  if #ids == 0 then Say("no quest in Must Do's data matches '" .. arg .. "'") return end
  for _, id in ipairs(ids) do
    local q = ns.Q[id]
    local g = q[MD.Q_GIVER]
    Say(string.format("[%d] %s: level %d, req %d, eligible %s, completed %s, in log %s, giver %s on map %s",
      id, q[1], q[2], q[3], tostring(MD.Eligible(id)), tostring(MD.IsCompleted(id)), tostring(MD.InLog(id)),
      g and g[1] or "?", g and tostring(g[2]) or "?"))
    if ns.openers and ns.openers[id] then
      local info = MD:OpenerStatus(id, false, true)
      local unlocks = ns.openers[id]
      local open, done, other = {}, 0, 0
      for _, d in ipairs(unlocks) do
        if MD.IsCompleted(d) then done = done + 1
        elseif MD.Eligible(d) then open[#open + 1] = MD:QuestName(d)
        else other = other + 1 end
      end
      Say(string.format("   opener: unlocks %d (%d done, %d not for you); still open: %s; shown: %s%s",
        #unlocks, done, other, #open > 0 and table.concat(open, ", ") or "none",
        info and ("yes, " .. info.status .. ", " .. info.remaining .. " quests") or "no",
        info and "" or string.format(" (needs level %d+, opener level %d)", math.max(q[3], q[2] - 3), q[2])))
    end
    for _, chain in ipairs(MD.byQuest[id] or {}) do
      local tier = MD:Tier(chain)
      local status, step = MD:Status(chain)
      local done, total, nextSteps = MD:Progress(chain)
      Say(string.format("   chain to [%d] %s: tier %s, hidden %s, status %s%s, %d/%d done, next %s",
        chain.final, MD:QuestName(chain.final), tier and tier.key or "none", tostring(MD:IsHidden(chain)),
        tostring(status), step and (" (" .. MD:QuestName(step) .. ")") or "", done, total,
        #nextSteps > 0 and table.concat(nextSteps, ",") or "none"))
    end
  end
end

SLASH_MUSTDO1 = "/mustdo"
SLASH_MUSTDO2 = "/md"
SlashCmdList.MUSTDO = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  if cmd == "why" then MD.Safe(Why, rest) else Toggle() end
end
