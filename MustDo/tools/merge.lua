-- Merge QuestieDB Forever data (base + generated delta + authored fixes) and dump chosen quests.
-- Usage: lua merge.lua <questId,...|zone:NAME,...>
local QDB = "QDB/"

-- Permissive mock: any field/call returns another mock.
local mock
mock = setmetatable({}, {
  __index = function() return mock end,
  __call = function() return mock end,
  __newindex = function() end,
})

local modules = {}
local function module(name)
  modules[name] = modules[name] or setmetatable({}, { __index = function() return mock end })
  return modules[name]
end
QuestieLoader = { ImportModule = function(_, n) return module(n) end, CreateModule = function(_, n) return module(n) end }
Questie = { db = { profile = {}, global = {}, char = {} }, IsClassic = true }
l10n = mock
modules.l10n = setmetatable({}, { __index = function() return mock end, __call = function(_, s) return s end })

-- Enums
local Enum = {}
loadfile(QDB .. "src/corrections/enum/zones.lua")(nil, { Enum = Enum })
local zoneIDs = Enum.zoneIDs
module("ZoneDB").zoneIDs = zoneIDs
local raceKeys = {
  ALL_ALLIANCE = 4294967373, ALL_HORDE = 8589934770, NONE = 0,
  HUMAN = 1, ORC = 2, DWARF = 4, NIGHT_ELF = 8, UNDEAD = 16, TAUREN = 32, GNOME = 64, TROLL = 128,
  SKYBORNE_ALLIANCE = 4294967296, SKYBORNE_HORDE = 8589934592,
}
local QuestieDB = module("QuestieDB")
QuestieDB.raceKeys = raceKeys
QuestieDB.classKeys = setmetatable({}, { __index = function() return 0 end })
QuestieDB.sortKeys = setmetatable({}, { __index = function() return 0 end })
QuestieDB.specialFlags = setmetatable({}, { __index = function() return 0 end })

-- Base compiled data (defines key enums and data strings)
local function patchKeys(keys)
  return setmetatable(keys, { __index = function(_, name)
    local base, op = name:match("^(.-)_(add)$")
    if not base then base, op = name:match("^(.-)_(remove)$") end
    if base and rawget(keys, base) then return op .. ":" .. rawget(keys, base) end
    return "unknown:" .. name
  end })
end
local function loadBase(path, dataField)
  dofile(path)
  return load(QuestieDB[dataField])()
end
local quests = loadBase(QDB .. "data/Forever/foreverQuestDB.lua", "questData")
local qk = patchKeys(QuestieDB.questKeys)
local npcs = loadBase(QDB .. "data/Forever/foreverNpcDB.lua", "npcData")
local nk = patchKeys(QuestieDB.npcKeys)
local items = loadBase(QDB .. "data/Forever/foreverItemDB.lua", "itemData")
local ik = patchKeys(QuestieDB.itemKeys)
local objects = loadBase(QDB .. "data/Forever/foreverObjectDB.lua", "objectData")
local ok = patchKeys(QuestieDB.objectKeys)

local function apply(target, fixes)
  for id, fields in pairs(fixes) do
    if type(fields) == "table" then
      target[id] = target[id] or {}
      for k, v in pairs(fields) do
        if type(k) == "number" then target[id][k] = v end
      end
      for k, v in pairs(fields) do
        local op, idx
        if type(k) == "string" then op, idx = k:match("^(%a+):(%d+)$") end
        if op == "add" or op == "remove" then
          idx = tonumber(idx)
          local cur = target[id][idx] or {}
          local grouped = false
          for _, x in pairs(v) do if type(x) == "table" then grouped = true end end
          local function merge(list, ops)
            local out = {}
            local function has(t, x) for _, y in ipairs(t) do if y == x then return true end end end
            for _, x in ipairs(list or {}) do if not (op == "remove" and has(ops, x)) then out[#out + 1] = x end end
            if op == "add" then for _, x in ipairs(ops) do if not has(out, x) then out[#out + 1] = x end end end
            return out
          end
          if grouped then
            for g, list in pairs(v) do cur[g] = merge(cur[g], list) end
          else
            cur = merge(cur, v)
          end
          target[id][idx] = cur
        end
      end
    end
  end
end

local function loadFix(path, moduleName, fn)
  local chunk, err = loadfile(path)
  if not chunk then io.stderr:write(err, "\n") return {} end
  local okRun, e = pcall(chunk)
  if not okRun then io.stderr:write("run ", path, ": ", tostring(e), "\n") return {} end
  local m = modules[moduleName]
  local f = m and rawget(m, fn)
  if not f then io.stderr:write("no ", moduleName, ".", fn, "\n") return {} end
  local okLoad, res = pcall(f, m)
  if not okLoad then io.stderr:write("load ", path, ": ", tostring(res), "\n") return {} end
  return res
end

local F = QDB .. "src/corrections/Forever/"
apply(quests, loadFix(F .. "generated/foreverBaseQuest.lua", "ForeverBaseQuest", "Load"))
apply(quests, loadFix(F .. "foreverQuestFixes.lua", "ForeverQuestFixes", "Load"))
apply(npcs, loadFix(F .. "generated/foreverBaseNpc.lua", "ForeverBaseNpc", "Load"))
apply(npcs, loadFix(F .. "foreverNPCFixes.lua", "ForeverNpcFixes", "Load"))
apply(items, loadFix(F .. "generated/foreverBaseItem.lua", "ForeverBaseItem", "Load"))
apply(items, loadFix(F .. "foreverItemFixes.lua", "ForeverItemFixes", "Load"))
apply(objects, loadFix(F .. "generated/foreverBaseObject.lua", "ForeverBaseObject", "Load"))
apply(objects, loadFix(F .. "foreverObjectFixes.lua", "ForeverObjectFixes", "Load"))

local zoneName = {}
for name, id in pairs(zoneIDs) do zoneName[id] = zoneName[id] or name end

local function list(t) if not t then return "-" end local o = {} for _, v in ipairs(t) do o[#o + 1] = tostring(v) end return table.concat(o, ",") end
local function faction(r)
  if not r or r == 0 then return "both" end
  local a = (r & 77) ~= 0 or (r & 4294967296) ~= 0
  local h = (r & 178) ~= 0 or (r & 8589934592) ~= 0
  return a and h and "both" or a and "A" or h and "H" or tostring(r)
end
local function spawnStr(sp)
  if not sp then return "" end
  for z, pts in pairs(sp) do
    if pts[1] then return string.format("%s %.1f,%.1f", zoneName[z] or z, pts[1][1], pts[1][2]) end
  end
  return ""
end
local function npcStr(id)
  local n = npcs[id]
  if not n then return "npc" .. id .. "?" end
  return string.format("%s[%d] @ %s", n[nk.name] or "?", id, spawnStr(n[nk.spawns]))
end
local function objStr(id)
  local o = objects[id]
  if not o then return "obj" .. id .. "?" end
  return string.format("OBJ %s[%d] @ %s", o[ok.name] or "?", id, spawnStr(o[ok.spawns]))
end
local function itemStr(id)
  local it = items[id]
  if not it then return "item" .. id .. "?" end
  local src = {}
  for _, d in ipairs(it[ik.npcDrops] or {}) do src[#src + 1] = "drop:" .. npcStr(d) end
  for _, d in ipairs(it[ik.objectDrops] or {}) do src[#src + 1] = "obj:" .. objStr(d) end
  return string.format("ITEM %s[%d] {%s}", it[ik.name] or "?", id, table.concat(src, "; "))
end
local function startStr(s)
  if not s then return "?" end
  local o = {}
  for _, id in ipairs(s[1] or {}) do o[#o + 1] = npcStr(id) end
  for _, id in ipairs(s[2] or {}) do o[#o + 1] = objStr(id) end
  for _, id in ipairs(s[3] or {}) do o[#o + 1] = itemStr(id) end
  return table.concat(o, " | ")
end

local function dump(id)
  local q = quests[id]
  if not q then print(id, "MISSING") return end
  print(string.format("[%d] %s  lvl %s req %s  %s  zone=%s", id, q[qk.name], q[qk.questLevel], q[qk.requiredLevel],
    faction(q[qk.requiredRaces]), zoneName[q[qk.zoneOrSort]] or tostring(q[qk.zoneOrSort])))
  print("   start: " .. startStr(q[qk.startedBy]))
  print("   end:   " .. startStr(q[qk.finishedBy]))
  print(string.format("   preSingle=%s preGroup=%s next=%s exclusive=%s breadcrumbFor=%s srcItem=%s",
    list(q[qk.preQuestSingle]), list(q[qk.preQuestGroup]), tostring(q[qk.nextQuestInChain]),
    list(q[qk.exclusiveTo]), tostring(q[qk.breadcrumbForQuestId]), tostring(q[qk.sourceItemId])))
end

-- Export for other scripts
_G.MERGED = { quests = quests, npcs = npcs, items = items, objects = objects, qk = qk, nk = nk, ik = ik, ok = ok,
  zoneIDs = zoneIDs, zoneName = zoneName, dump = dump, faction = faction }

for _, a in ipairs(arg) do
  for tok in a:gmatch("[^,]+") do
    local z = tok:match("^zone:(.+)")
    if z then
      local zid = zoneIDs[z]
      local ids = {}
      for id, q in pairs(quests) do if q[qk.zoneOrSort] == zid then ids[#ids + 1] = id end end
      table.sort(ids)
      print("== zone " .. z .. " (" .. #ids .. ")")
      for _, id in ipairs(ids) do dump(id) end
    else
      dump(tonumber(tok))
    end
  end
end
