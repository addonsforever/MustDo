"""Generate MustDo/Data.lua: quest chains that end in a notable reward.

Inputs (all in this folder):
  questie.json          merged QuestieDB Forever quests/NPCs (export.lua)
  cmangos.json          cmangos classic-db quest_template + item_template (parse_cmangos.py)
  gq_quest_rewards.json GearQuest Forever quest-reward items, from Wowhead's Forever data
  ../QDB/support/Forever/Zones/areaIdToUiMapId.lua
"""
import json, re, sys
from collections import defaultdict

Q = json.load(open("questie.json"))
CM = json.load(open("cmangos.json"))
GQ = json.load(open("gq_quest_rewards.json"))  # itemId -> [name, quality, ilvl, reqLevel, zone, questName]
quests, npcs, zones = Q["quests"], Q["npcs"], Q["zones"]
SPELLS = {int(k): v for k, v in json.load(open("spell_names.json")).items()}  # Wowhead Classic spell names
cq, citems = CM["quests"], CM["items"]

area_to_map = {}
for m in re.finditer(r"\[(\d+)\] = (\d+)", open("../QDB/support/Forever/Zones/areaIdToUiMapId.lua").read()):
    area_to_map.setdefault(int(m.group(1)), int(m.group(2)))

ALLIANCE = 77 | 4294967296
HORDE = 178 | 8589934592

def faction(races):
    if not races:
        return None
    a, h = bool(races & ALLIANCE), bool(races & HORDE)
    return None if a == h else ("A" if a else "H")

def ids(v):
    return [int(x) for x in (v or []) if x]

# --- Prerequisite graph -----------------------------------------------------------------
pre_any = {}   # quest -> [any one of these must be done]
pre_all = {}   # quest -> [all of these must be done]
inferred = set()
for qid, q in quests.items():
    qid = int(qid)
    pre_any[qid] = ids(q.get("pre"))
    pre_all[qid] = ids(q.get("preGroup"))
    c = cq.get(str(qid))
    if c and not pre_any[qid] and not pre_all[qid] and c["PrevQuestId"] > 0 and str(c["PrevQuestId"]) in quests:
        pre_any[qid] = [c["PrevQuestId"]]

# New Forever quests have no prerequisite links. Infer A -> B when A is turned in to the NPC who
# starts B, B comes shortly after A by ID, and the factions agree. The closest such A wins.
ended_by = defaultdict(list)
for qid, q in quests.items():
    for n in ids(q.get("endNpc")):
        ended_by[n].append(int(qid))
for qid, q in quests.items():
    qid = int(qid)
    if qid < 90000 or pre_any[qid] or pre_all[qid]:
        continue
    best = None
    for n in ids(q.get("startNpc")):
        for a in ended_by[n]:
            if a < qid <= a + 20 and a >= 90000:
                fa, fb = faction(quests[str(a)].get("races")), faction(q.get("races"))
                if fa and fb and fa != fb:
                    continue
                if best is None or a > best:
                    best = a
    if best:
        pre_any[qid] = [best]
        inferred.add(qid)

# Links the inference can't see (IDs too far apart), confirmed by hand.
MANUAL_PRE = {92819: 92753}  # Destruction in Deadmines part 2 follows part 1
for b, a in MANUAL_PRE.items():
    pre_any[b] = [a]
    inferred.discard(b)

# Breadcrumbs: quests that only send you to another quest, which doesn't require them. The game
# stops offering one once you have or finish the quest it leads to.
breadcrumb_for = {}
for qid, q in quests.items():
    qid = int(qid)
    if q.get("breadcrumbFor"):
        breadcrumb_for[qid] = q["breadcrumbFor"]
        continue
    c = cq.get(str(qid))
    nxt = q.get("next") or (c["NextQuestId"] if c and c.get("NextQuestId", 0) > 0 else None)
    if nxt and str(nxt) in quests and qid not in pre_any.get(nxt, []) + pre_all.get(nxt, []):
        breadcrumb_for[qid] = nxt

# --- Rewards and tags ------------------------------------------------------------------
def item_info(item_id):
    it = citems.get(str(item_id))
    if it:
        return {"name": it["name"], "q": it["Quality"], "cls": it["class"], "sub": it["subclass"], "inv": it["InventoryType"],
                "slots": it["ContainerSlots"], "req": it["RequiredLevel"],
                "skill": it["RequiredSkill"] if it.get("RequiredSkill") in PROFESSIONS else 0,
                "use": any(it["spellid_%d" % i] and it["spelltrigger_%d" % i] == 0 for i in range(1, 6)),
                "proc": any(it["spellid_%d" % i] and it["spelltrigger_%d" % i] == 2 for i in range(1, 6)),
                "learn": any(it["spellid_%d" % i] and it["spelltrigger_%d" % i] == 6 for i in range(1, 6))}
    g = GQ.get(str(item_id))
    if g:
        return {"name": g[0], "q": g[1], "cls": None, "sub": None, "inv": None, "slots": 0, "req": g[3], "skill": 0,
                "use": False, "proc": False, "learn": False}
    return None

# Professions by skill line. Rewards and quests that need one only matter if you have it.
PROFESSIONS = {129: "First Aid", 164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 182: "Herbalism",
               185: "Cooking", 186: "Mining", 197: "Tailoring", 202: "Engineering", 333: "Enchanting",
               356: "Fishing", 393: "Skinning"}
PROFESSION_BY_NAME = {v.lower(): k for k, v in PROFESSIONS.items()}
# Forever's own profession quests often leave the skill blank; their names say which one.
NAME_SKILL = {"The Quarry's Smith": 164, "An Enchanting Lesson": 333}

def quest_skill(qid):
    q = quests[str(qid)]
    s = q.get("skill")
    if s and isinstance(s[0], int) and s[0] in PROFESSIONS:
        return s[0]
    c = cq.get(str(qid))
    if c and c.get("RequiredSkill") in PROFESSIONS:
        return c["RequiredSkill"]
    if s:
        if q["name"] in NAME_SKILL:
            return NAME_SKILL[q["name"]]
        tail = q["name"].split(": ")[-1].lower()
        if tail in PROFESSION_BY_NAME:
            return PROFESSION_BY_NAME[tail]
    return 0

# Attunement and key rewards that cmangos doesn't mark as keys.
ATTUNEMENT_ITEMS = {16309: "Onyxia attunement", 12344: "UBRS key", 13704: "Scholomance key", 11000: "BRD key",
                    18249: "Dire Maul key", 7146: "Scarlet key", 6893: "Workshop key", 11078: "Sunken Temple"}
INFO_ONLY = {"Forever item"}

def item_tags(item_id, info):
    t = []
    if item_id in ATTUNEMENT_ITEMS: t.append(ATTUNEMENT_ITEMS[item_id])
    if info["q"] >= 4: t.append("epic")
    elif info["q"] == 3: t.append("rare")
    if info["cls"] == 1 and info["slots"] >= 8: t.append("%d-slot bag" % info["slots"])
    if info["cls"] in (2, 4) and info["use"]: t.append("use effect")
    if info["cls"] in (2, 4) and info["proc"]: t.append("proc")
    if info["cls"] == 15 and (info["use"] or info["learn"]): t.append("fun")
    if info["inv"] in (4, 19): t.append("cosmetic")
    if info["cls"] == 9: t.append("recipe")
    if info["cls"] == 13: t.append("key")
    if info.get("skill"): t.append(PROFESSIONS[info["skill"]])
    if item_id >= 200000: t.append("Forever item")
    return t

rewards = defaultdict(set)
for qid in quests:
    c = cq.get(qid)
    if c:
        for k in ["RewChoiceItemId%d" % i for i in range(1, 7)] + ["RewItemId%d" % i for i in range(1, 5)]:
            if c.get(k):
                rewards[int(qid)].add(c[k])

# GearQuest's Forever rewards, matched to quests by name (and zone when the name repeats).
def norm(s):
    return re.sub(r"[^a-z]", "", (s or "").lower())
by_name = defaultdict(list)
for qid, q in quests.items():
    by_name[norm(q["name"])].append(int(qid))
gq_items = set()
for item_id, g in GQ.items():
    cands = by_name.get(norm(g[5]), [])
    if len(cands) > 1:
        z = [c for c in cands if norm(zones.get(str(quests[str(c)].get("zone")), "")) == norm(g[4])]
        cands = z or cands
    if len(cands) > 1:  # several parts with one name: the reward sits on the last one
        has_next = {p for c in cands for p in pre_any.get(c, []) + pre_all.get(c, [])}
        cands = [c for c in cands if c not in has_next] or cands
    for c in cands:
        rewards[c].add(int(item_id))
        gq_items.add(int(item_id))

def quest_tags(qid):
    t = []
    c = cq.get(str(qid))
    # RewSpell is a spell you learn. RewSpellCast alone is usually a buff, except on class quests.
    if c and (c.get("RewSpell") or (c.get("RewSpellCast") and c.get("RequiredClasses"))):
        t.append("teaches spell")
    if quests[str(qid)].get("classes"):
        t.append("class quest")
    if "attunement" in quests[str(qid)]["name"].lower():
        t.append("attunement")
    if qid >= 90000:
        t.append("new in Forever")
    if dungeon(qid):
        t.append("dungeon: " + dungeon(qid))
    # Elite (group) quests you reach through a chain. cmangos quest Type 1 = Elite; Forever's new
    # quests aren't in cmangos, so they aren't tagged. Elites you can just pick up aren't flagged.
    elif c and c.get("Type") == 1 and depth(qid) >= 2:
        t.append("elite")
    if quest_skill(qid):
        t.append(PROFESSIONS[quest_skill(qid)])
    return t

# Dungeon quests: Questie files them under the dungeon's area; the DungeonQuests addon's lists
# (siz_Data.lua) and Forever's new dungeons fill in the rest.
DUNGEONS = {}
for m in re.finditer(r'\{ "([^"]+)", (\d+), "[^"]*", (true|false), \{([\d,]*)\} \}', open("siz_Data.lua").read()):
    DUNGEONS[int(m.group(2))] = m.group(1)
    for qid in m.group(4).split(","):
        if qid:
            DUNGEON_OF_QUEST = globals().setdefault("DUNGEON_OF_QUEST", {})
            DUNGEON_OF_QUEST[int(qid)] = m.group(1)
DUNGEONS.update({16919: "The Hall of Thanes", 16611: "Ruins of Lordaeron"})
DUNGEON_OF_QUEST = globals().get("DUNGEON_OF_QUEST", {})
DUNGEON_OF_QUEST.update({92753: "The Deadmines", 92819: "The Deadmines"})

def dungeon(qid):
    z = quests[str(qid)].get("zone")
    return DUNGEONS.get(z) or DUNGEON_OF_QUEST.get(qid)

# --- Chains ----------------------------------------------------------------------------
def ancestors(qid, seen=None):
    seen = seen if seen is not None else set()
    for p in pre_any.get(qid, []) + pre_all.get(qid, []):
        if str(p) in quests and p not in seen:
            seen.add(p)
            ancestors(p, seen)
    return seen

depth_cache = {}
def depth(qid, stack=()):
    if qid in depth_cache:
        return depth_cache[qid]
    if qid in stack:
        return 1
    ps = [p for p in pre_any.get(qid, []) + pre_all.get(qid, []) if str(p) in quests]
    d = 1 + max((depth(p, stack + (qid,)) for p in ps), default=0)
    depth_cache[qid] = d
    return d

chains, in_chain = [], set()
for qid in sorted(int(x) for x in quests):
    # A quest qualifies through a notable reward, but every reward choice is kept so the
    # addon can show them all.
    items, notable = [], False
    for item_id in sorted(rewards.get(qid, [])):
        info = item_info(item_id)
        if not info:
            continue
        tags = item_tags(item_id, info)
        flagged = bool([x for x in tags if x not in INFO_ONLY] or item_id in gq_items)
        notable = notable or flagged
        items.append((item_id, info, tags, flagged))
    # Notable rewards first, then by quality, so the addon leads with the interesting one.
    items = [(i, info, t) for i, info, t, _ in sorted(items, key=lambda x: (not x[3], -x[1]["q"], x[0]))]
    c = cq.get(str(qid))
    spell = c and (c.get("RewSpell") or (c.get("RequiredClasses") and c.get("RewSpellCast")))
    if spell and SPELLS.get(spell):
        name = re.sub(r"^Teach ", "", SPELLS[spell])
        items.append((0, {"name": "Learn " + name, "q": 3, "req": 0, "skill": 0}, ["teaches spell"]))
    # Being a class or Forever quest only adds context; it needs an item or a spell to count.
    qtags = [t for t in quest_tags(qid) if t not in ("new in Forever", "class quest")]
    if not notable and not qtags:
        continue
    steps = depth(qid)  # 1 for a single quest: a great reward counts even without a chain
    anc = ancestors(qid)
    # A chain needs a profession if any of its quests does.
    skill = next((quest_skill(x) for x in [qid] + sorted(anc) if quest_skill(x)), 0)
    chains.append((qid, steps, items, quest_tags(qid), anc, skill))
    in_chain.add(qid)
    in_chain.update(anc)

def races(qid):
    r = quests[str(qid)].get("races") or 0
    c = cq.get(str(qid))
    if c and c.get("RequiredRaces"):
        r = (r & c["RequiredRaces"]) if r else c["RequiredRaces"]
    return r

# --- Openers ---------------------------------------------------------------------------
# Quests that are strictly required for 3+ others: the only prerequisite, or one of several
# that are all required. "Any one of" alternatives and breadcrumbs (optional) don't count, and
# neither do straight chains (see branches()).
breadcrumb = {int(q) for q, v in quests.items() if v.get("breadcrumbFor")}
required_children = defaultdict(set)
for q, ps in pre_all.items():
    for p in ps or []:
        if str(p) in quests:
            required_children[p].add(q)
for q, ps in pre_any.items():
    ps = [p for p in (ps or []) if str(p) in quests]
    if len(ps) == 1:
        required_children[ps[0]].add(q)

opens_memo = {}
def opens(qid, stack=()):
    if qid in opens_memo:
        return opens_memo[qid]
    out = set()
    for c in required_children.get(qid, ()):
        if c not in stack:
            out.add(c)
            out |= opens(c, stack + (qid,))
    opens_memo[qid] = out
    return out

# An opener has to open things up: somewhere in what it unlocks (or itself) a quest leads to two or
# more quests. A straight chain (A -> B -> C, like the Messenger quests) is just a chain.
def branches(qid):
    return any(len(required_children.get(n, ())) >= 2 for n in [qid] + sorted(opens(qid)))

openers = {}
for q in quests:
    q = int(q)
    if q not in breadcrumb and len(opens(q)) >= 3 and branches(q):
        openers[q] = sorted(opens(q))
for q, d in openers.items():
    in_chain.add(q)
    in_chain.update(d)

# --- Write Lua -------------------------------------------------------------------------
def lua_str(s):
    return '"' + (s or "").replace("\\", "\\\\").replace('"', '\\"') + '"'

def lua_list(xs):
    return "{" + ",".join(str(x) for x in xs) + "}" if xs else "nil"

SMALL_WORDS = {"of", "the", "and", "in", "on", "at", "to", "a"}
def zone_title(area):
    words = zones.get(str(area), "").replace("_", " ").title().replace("'S", "'s").split(" ")
    return " ".join(w.lower() if i > 0 and w.lower() in SMALL_WORDS else w for i, w in enumerate(words))

def npc_spot(npc_ids):
    for n in ids(npc_ids):
        npc = npcs.get(str(n))
        if npc:
            sp = npc.get("spawn")
            if sp and area_to_map.get(sp[0]):
                return "{%s,%d,%.1f,%.1f,%s}" % (lua_str(npc["name"]), area_to_map[sp[0]], sp[1], sp[2], lua_str(zone_title(sp[0])))
            return "{%s}" % lua_str(npc["name"])
    return None

def giver(q):
    spot = npc_spot(q.get("startNpc"))
    if spot:
        return spot
    for o in ids(q.get("startObj")):
        if str(o) in Q["objects"]:
            return "{%s}" % lua_str(Q["objects"][str(o)])
    for i in ids(q.get("startItem")):
        info = item_info(i)
        if info:
            return "{%s}" % lua_str(info["name"] + " (item)")
    return "nil"

def turn_in(q):
    return npc_spot(q.get("endNpc")) or "nil"

def quest_zone(q):
    z = q.get("zone")
    return lua_str(zone_title(z)) if z and z > 0 and zones.get(str(z)) else "nil"

out = ["-- GENERATED by gen_mustdo.py. Do not edit by hand.",
       "-- Chains: QuestieDB Forever data (github.com/Questie/QuestieDB); order of new Forever quests is",
       "-- inferred from quest-giver handoffs. Rewards: cmangos classic-db, plus GearQuest Forever's",
       "-- Wowhead-sourced Forever quest rewards.",
       "local _, ns = ...", "",
       "-- [questId] = { name, level, reqLevel, faction, classMask, preAny, preAll, giver, inferred, raceMask, exclusiveTo, dungeon,",
       "--               questZone, turnIn, breadcrumbFor }   giver/turnIn = { name, uiMapId, x, y, zoneName } or { name }",
       "ns.Q = {"]
for qid in sorted(in_chain):
    q = quests[str(qid)]
    out.append("  [%d]={%s,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s}," % (
        qid, lua_str(q["name"]), q.get("level") or 0, q.get("req") or 0,
        lua_str(faction(q.get("races"))) if faction(q.get("races")) else "nil",
        q.get("classes") or "nil", lua_list(pre_any.get(qid)), lua_list(pre_all.get(qid)), giver(q),
        "true" if qid in inferred else "nil", races(qid) or "nil", lua_list(ids(q.get("exclusive"))),
        lua_str(dungeon(qid)) if dungeon(qid) else "nil", quest_zone(q), turn_in(q),
        breadcrumb_for.get(qid) or "nil"))
out += ["}", "",
        "-- { finalQuestId, steps, { { itemId, name, quality, reqLevel, tags, skill }, ... }, questTags, skill }",
        "-- skill = profession skill line the reward or chain needs (0 = none)",
        "ns.chains = {"]
for qid, steps, items, qtags, _, skill in chains:
    its = ",".join("{%d,%s,%d,%d,%s,%d}" % (i, lua_str(info["name"]), info["q"], info["req"] or 0,
                                            lua_str(", ".join(t)), info.get("skill") or 0) for i, info, t in items)
    out.append("  {%d,%d,{%s},%s,%d}," % (qid, steps, its, lua_str(", ".join(qtags)), skill))
out.append("}")
out += ["", "-- [questId] = { quests it's strictly required for (directly or further down the line) }",
        "ns.openers = {"]
for q in sorted(openers):
    out.append("  [%d]=%s," % (q, lua_list(openers[q])))
out.append("}")
open(sys.argv[1] if len(sys.argv) > 1 else "Data.lua", "w").write("\n".join(out) + "\n")
print("chains:", len(chains), "quests in chains:", len(in_chain), "inferred links:", len(inferred))
