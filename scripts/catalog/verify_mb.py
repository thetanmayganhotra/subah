#!/usr/bin/env python3
"""Checks each candidate against MusicBrainz (1 req/s, as their rules ask). Writes verified.jsonl."""
import json, re, time, urllib.request, urllib.parse, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify import parse, norm, words, clean_title, BAD
D = os.path.dirname(os.path.abspath(__file__))
UA = "SubahAlarm/2.0 (personal project; local verification script)"
last = [0.0]
def mb(query):
    for attempt in range(5):
        w = 1.1 - (time.time() - last[0])
        if w > 0: time.sleep(w)
        last[0] = time.time()
        try:
            req = urllib.request.Request("https://musicbrainz.org/ws/2/recording/?" + urllib.parse.urlencode({"query": query, "fmt": "json", "limit": 12}), headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=25) as r: return json.load(r).get("recordings", [])
        except urllib.error.HTTPError as e: time.sleep(10 if e.code in (429, 503) else 4)
        except Exception: time.sleep(4)
    return None
def pick(recs, title, aliases, instr):
    want = norm(title); aw = set().union(*[words(a) for a in aliases]); best = None
    for rank, r in enumerate(recs or []):
        if r.get("score", 0) < 80: continue
        tn = r.get("title", ""); dis = (r.get("disambiguation") or "").lower()
        if any(b in (tn.lower() + " " + dis) for b in BAD) and not any(b in title.lower() for b in BAD): continue
        credit = " ".join((c.get("name", "") + " " + c.get("artist", {}).get("name", "")) for c in r.get("artist-credit", []))
        nt = norm(tn)
        if not (nt == want or nt.startswith(want) or want.startswith(nt)): continue
        art = aw & words(credit)
        if not (instr or art): continue
        ln = r.get("length")
        if ln and not (60_000 <= ln <= 540_000): continue
        official = any(rel.get("status") == "Official" for rel in r.get("releases", []) or [])
        score = r.get("score", 0) + (8 if nt == want else 0) + (6 if art else 0) + (5 if official else 0) + (3 if ln else 0) - rank * 0.3
        if best is None or score > best[0]: best = (score, r, credit)
    return best
def name_of(r):
    ac = r.get("artist-credit", [])
    return "".join((c.get("name") or c["artist"]["name"]) + (c.get("joinphrase") or "") for c in ac) or ""
cands = parse(); print(len(cands), "candidates", flush=True)
with open(D + "/verified.jsonl", "w", encoding="utf-8") as out:
    for i, (title, artist, tags) in enumerate(cands, 1):
        aliases = [a.strip() for a in artist.split("/")]; instr = "instrumental" in tags
        hit = None
        for q in (f'recording:"{clean_title(title)}" AND artist:"{aliases[0]}"', f'recording:"{clean_title(title)}" AND {aliases[0]}'):
            hit = pick(mb(q), title, aliases, instr)
            if hit: break
        rec = {"want": f"{title} — {artist}", "tags": tags, "ok": bool(hit), "src": "mb"}
        if hit:
            r = hit[1]
            rec.update(title=clean_title(r["title"]), artist=aliases[0] if aliases[0].lower() in name_of(r).lower() else name_of(r), ms=r.get("length") or 0)
        out.write(json.dumps(rec, ensure_ascii=False) + "\n"); out.flush()
        if i % 50 == 0: print(i, flush=True)
print("DONE", flush=True)
