"""Extract quest_template and item_template from the cmangos classic-db dump into JSON."""
import json, re

SQL = open("classicdb.sql", encoding="utf-8", errors="replace").read()

def columns(table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\) " % table, SQL, re.S)
    return re.findall(r"^\s*`(\w+)`", m.group(1), re.M)

def rows(table):
    """Yield value tuples from every INSERT INTO `table` VALUES (...),(...); statement."""
    for m in re.finditer(r"INSERT INTO `%s` (?:\([^)]*\) )?VALUES\s*" % table, SQL):
        i, n = m.end(), len(SQL)
        while i < n:
            if SQL[i] != "(":
                break
            i += 1
            vals, cur, inq = [], [], False
            while True:
                c = SQL[i]
                if inq:
                    if c == "\\":
                        cur.append(SQL[i + 1]); i += 2; continue
                    if c == "'":
                        if SQL[i + 1] == "'":
                            cur.append("'"); i += 2; continue
                        inq = False; i += 1; continue
                    cur.append(c); i += 1; continue
                if c == "'":
                    inq = True; cur.append("\0"); i += 1; continue
                if c in ",)":
                    tok = "".join(cur).strip()
                    if tok.startswith("\0"):
                        vals.append(tok[1:])
                    elif tok.upper() == "NULL":
                        vals.append(None)
                    else:
                        try:
                            vals.append(int(tok))
                        except ValueError:
                            vals.append(float(tok))
                    cur = []
                    i += 1
                    if c == ")":
                        break
                    continue
                cur.append(c); i += 1
            yield vals
            while i < n and SQL[i] in ", \n\r\t":
                i += 1
            if i < n and SQL[i] == ";":
                break

def table(name, keep):
    cols = columns(name)
    idx = {c: cols.index(c) for c in keep if c in cols}
    missing = [c for c in keep if c not in cols]
    if missing:
        print(name, "missing columns:", missing)
    out = {}
    for r in rows(name):
        rec = {c: r[i] for c, i in idx.items()}
        out[str(r[0])] = rec
    return out

QUEST_KEEP = ["entry", "Title", "QuestLevel", "MinLevel", "ZoneOrSort", "Type", "RequiredClasses", "RequiredRaces",
              "PrevQuestId", "NextQuestId", "ExclusiveGroup", "NextQuestInChain", "SrcItemId", "RewSpell", "RewSpellCast",
              "RewOrReqMoney", "RewXP" ] + ["RewChoiceItemId%d" % i for i in range(1, 7)] + \
             ["RewChoiceItemCount%d" % i for i in range(1, 7)] + ["RewItemId%d" % i for i in range(1, 5)] + \
             ["RewItemCount%d" % i for i in range(1, 5)] + ["RewRepFaction1", "RewRepValue1", "SpecialFlags", "QuestFlags", "RequiredSkill", "RequiredSkillValue"]
ITEM_KEEP = ["entry", "name", "Quality", "class", "subclass", "InventoryType", "ItemLevel", "RequiredLevel", "AllowableClass",
             "ContainerSlots", "bonding", "description", "RequiredSkill", "RequiredSkillRank"] + ["spellid_%d" % i for i in range(1, 6)] + \
            ["spelltrigger_%d" % i for i in range(1, 6)]
SPELL_KEEP = ["Id", "SpellName", "Effect1", "Effect2", "Effect3", "EffectTriggerSpell1", "EffectMiscValue1", "Description"]

quests = table("quest_template", QUEST_KEEP)
items = table("item_template", ITEM_KEEP)
print(len(quests), "quests", len(items), "items")
json.dump({"quests": quests, "items": items}, open("cmangos.json", "w"))
print(quests["166"]["Title"], {k: v for k, v in quests["166"].items() if k.startswith("Rew") and v})
print(items["2042"])
