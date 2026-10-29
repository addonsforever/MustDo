-- Export merged QuestieDB Forever quests and NPCs to JSON for the MustDo generator.
arg = {} dofile("merge.lua")
local M, qk, nk = MERGED, MERGED.qk, MERGED.nk
local function enc(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then return (v == math.floor(v)) and string.format("%d", v) or string.format("%.2f", v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  local n, isArr = 0, true
  for k in pairs(v) do n = n + 1 if type(k) ~= "number" then isArr = false end end
  if isArr and n == #v then local o = {} for i = 1, #v do o[i] = enc(v[i]) end return "[" .. table.concat(o, ",") .. "]" end
  local o = {} for k, x in pairs(v) do o[#o + 1] = enc(tostring(k)) .. ":" .. enc(x) end return "{" .. table.concat(o, ",") .. "}"
end
local quests = {}
for id, q in pairs(M.quests) do
  if q[qk.name] then
    local sb, fb = q[qk.startedBy] or {}, q[qk.finishedBy] or {}
    quests[tostring(id)] = { name = q[qk.name], level = q[qk.questLevel], req = q[qk.requiredLevel], races = q[qk.requiredRaces], classes = q[qk.requiredClasses],
      pre = q[qk.preQuestSingle], preGroup = q[qk.preQuestGroup], next = q[qk.nextQuestInChain], zone = q[qk.zoneOrSort],
      startNpc = sb[1], startObj = sb[2], startItem = sb[3], endNpc = fb[1], endObj = fb[2], exclusive = q[qk.exclusiveTo],
      breadcrumbFor = q[qk.breadcrumbForQuestId], specialFlags = q[qk.specialFlags], skill = q[qk.requiredSkill] }
  end
end
local npcs = {}
for id, n in pairs(M.npcs) do
  if n[nk.name] then
    local spawn
    for z, pts in pairs(n[nk.spawns] or {}) do if pts[1] then spawn = { z, pts[1][1], pts[1][2] } break end end
    npcs[tostring(id)] = { name = n[nk.name], spawn = spawn, friendly = n[nk.friendlyToFaction] }
  end
end
local objects = {}
for id, o in pairs(M.objects) do if o[M.ok.name] then objects[tostring(id)] = o[M.ok.name] end end
local zones = {}
for id, name in pairs(M.zoneName) do zones[tostring(id)] = name end
io.open("mustdo/questie.json", "w"):write(enc({ quests = quests, npcs = npcs, objects = objects, zones = zones }))
