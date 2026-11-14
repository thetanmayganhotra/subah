#!/usr/bin/env python3
"""Second chance for candidates that missed: looser MusicBrainz query, then iTunes (slowly, to stay under its rate limit)."""
import json, time, urllib.request, urllib.parse, os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_mb_lib import mb, pick, name_of, norm, words, clean_title, BAD, D
last = [0.0]
def itunes(term):
    for country in ("US", "IN"):
        w = 4.5 - (time.time() - last[0])
        if w > 0: time.sleep(w)
        last[0] = time.time()
        try:
            with urllib.request.urlopen("https://itunes.apple.com/search?" + urllib.parse.urlencode({"term": term, "entity": "song", "limit": 15, "country": country}), timeout=20) as r:
                res = json.load(r)["results"]
        except Exception:
            time.sleep(30); continue
        if res: yield res
rows = [json.loads(l) for l in open(D + "/verified.jsonl", encoding="utf-8")]
fixed = 0
for i, r in enumerate(rows):
    if r["ok"]: continue
    title, artist = [x.strip() for x in r["want"].split(" — ", 1)]
    aliases = [a.strip() for a in artist.split("/")]; instr = "instrumental" in r["tags"]
    hit = None
    for q in (f'{clean_title(title).replace(chr(39), " ")} {aliases[0]}', f'recording:"{clean_title(title)}"' if instr else None):
        if not q: continue
        hit = pick(mb(q), title, aliases, instr)
        if hit: break
    if hit:
        rec = hit[1]
        r.update(ok=True, src="mb2", title=clean_title(rec["title"]), artist=aliases[0] if aliases[0].lower() in name_of(rec).lower() else name_of(rec), ms=rec.get("length") or 0)
        fixed += 1; continue
    want = norm(title); aw = set().union(*[words(a) for a in aliases])
    for res in itunes(f"{clean_title(title)} {aliases[0]}"):
        cand = None
        for x in res:
            low = (x.get("trackName", "") + " " + x.get("collectionName", "")).lower()
            if any(b in low for b in BAD) and not any(b in title.lower() for b in BAD): continue
            ms = x.get("trackTimeMillis") or 0
            if not 60_000 <= ms <= 540_000: continue
            nt = norm(x["trackName"])
            if not (nt == want or nt.startswith(want) or want.startswith(nt)): continue
            if not (instr or (aw & words(x["artistName"]))): continue
            cand = x; break
        if cand:
            r.update(ok=True, src="itunes", title=clean_title(cand["trackName"]), artist=cand["artistName"], ms=cand["trackTimeMillis"]); fixed += 1; break
with open(D + "/verified.jsonl", "w", encoding="utf-8") as f:
    for r in rows: f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("recovered", fixed, "| still missing", sum(not r["ok"] for r in rows))
