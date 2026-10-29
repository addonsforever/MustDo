"""Extract GearQuest Forever quest-reward items from the class packs into gq_quest_rewards.json.
itemId -> [name, quality, ilvl, reqLevel, zone, questName]"""
import glob, json, re, sys
ADDONS = sys.argv[1] if len(sys.argv) > 1 else "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
out = {}
FIELD = lambda f, s: (re.search(r'\b%s=("((?:[^"\\]|\\.)*)"|[-\d.]+)' % f, s) or [None, None, None])
for path in glob.glob(ADDONS + "/GearQuestForever_*/Data.*.generated.lua"):
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r'\s*\[(\d+)\]=\{(.*)\},?\s*$', line)
        if not m or 'sourceType="quest_reward"' not in m.group(2):
            continue
        body = m.group(2)
        def get(f, num=False):
            mm = re.search(r'\b%s=("((?:[^"\\]|\\.)*)"|[-\d.]+)' % f, body)
            if not mm: return 0 if num else ""
            return (float(mm.group(1)) if "." in mm.group(1) else int(mm.group(1))) if num else (mm.group(2) or "").replace('\\"', '"')
        out.setdefault(m.group(1), [get("name"), get("quality", True), get("ilvl", True), get("reqLevel", True), get("zone"), get("questName")])
json.dump(out, open("mustdo/gq_quest_rewards.json", "w"))
print(len(out), "items")
