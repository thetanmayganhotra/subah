#!/usr/bin/env python3
"""Checks every candidate song against the Deezer catalog (title, artist, length) and writes verified.jsonl."""
import json, re, os, glob, time, urllib.request, urllib.parse, unicodedata, threading
from concurrent.futures import ThreadPoolExecutor
D = os.path.dirname(os.path.abspath(__file__))
GENRES = {"desi", "classic", "indie", "jazz", "film", "instrumental", "sacred"}
BAD = ["live", "remix", "karaoke", "tribute", "lullaby", "made famous", "originally performed", "instrumental version", "cover", "8d", "slowed", "sped up", "nightcore", "reprise", "demo"]

def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\s*[\(\[].*?[\)\]]", "", s); s = re.sub(r"\s+-\s+.*$", "", s)
    return " ".join(re.sub(r"[^a-z0-9 ]", " ", s).split())
def words(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return {w for w in re.sub(r"[^a-z0-9 ]", " ", s).split() if len(w) > 2 and w not in ("the", "and", "feat")}
def clean_title(t):
    t = re.sub(r"\s*[\(\[]\s*(remaster|from|feat|with|live|mono|stereo|single|album|original|version|\d{4}).*?[\)\]]", "", t, flags=re.I)
    t = re.sub(r"\s+-\s+(remaster|single|live|from|mono|stereo|\d{4}).*$", "", t, flags=re.I)
    return t.strip()

lock = threading.Lock(); stamps = []
def dz(q):
    for attempt in range(6):
        with lock:  # gentle global rate limit
            now = time.time(); stamps[:] = [t for t in stamps if now - t < 5]
            if len(stamps) >= 35: time.sleep(5 - (now - stamps[0]) + 0.05)
            stamps.append(time.time())
        try:
            with urllib.request.urlopen("https://api.deezer.com/search?" + urllib.parse.urlencode({"q": q, "limit": 25}), timeout=20) as r:
                j = json.load(r)
            if "error" in j: time.sleep(8); continue
            return j.get("data", [])
        except Exception: time.sleep(4)
    return None

def pick(results, title, aliases, instr):
    want = norm(title); aw = set().union(*[words(a) for a in aliases]); best = None
    for rank, r in enumerate(results or []):
        tn, an, al = r.get("title", ""), r["artist"]["name"], (r.get("album") or {}).get("title", "")
        low = (tn + " " + al).lower()
        if any(b in low for b in BAD) and not any(b in title.lower() for b in BAD): continue
        d = r.get("duration", 0)
        if not (60 <= d <= 540): continue
        nt = norm(tn); exact = nt == want
        if not (exact or nt.startswith(want) or want.startswith(nt)): continue
        art = aw & words(an)
        if not (instr or art): continue
        score = (10 if exact else 4) + (3 if art else 0) - rank * 0.15 + min(r.get("rank", 0), 900000) / 300000
        if best is None or score > best[0]: best = (score, r)
    return best[1] if best else None

def parse():
    out = []
    for f in sorted(glob.glob(D + "/p?.txt")):
        for line in open(f, encoding="utf-8"):
            line = line.strip()
            if not line or line.count("|") < 2: continue
            artist, gtags, items = [x.strip() for x in line.split("|", 2)]
            gt = gtags.split()
            for it in items.split(";"):
                it = it.strip()
                if not it: continue
                itags = None
                if "~" in it: it, t = it.rsplit("~", 1); itags = t.split()
                art = artist
                if "@" in it: it, art = it.rsplit("@", 1)
                title = it.strip(); art = art.strip()
                if art == "*": continue
                tags = set(g for g in gt if g in GENRES)
                tags |= set(itags) if itags is not None else set(gt)
                out.append((title, art, sorted(tags)))
    return out

def work(c):
    title, artist, tags = c
    aliases = [a.strip() for a in artist.split("/")]; instr = "instrumental" in tags
    hit = None
    for q in (f'track:"{clean_title(title)}" artist:"{aliases[0]}"', f"{clean_title(title)} {aliases[0]}", f'track:"{clean_title(title)}"' if instr else None):
        if not q: continue
        hit = pick(dz(q), title, aliases, instr)
        if hit: break
    rec = {"want": f"{title} — {artist}", "tags": tags, "ok": bool(hit)}
    if hit: rec.update(title=clean_title(hit["title"]), artist=hit["artist"]["name"], ms=hit["duration"] * 1000)
    return rec

if __name__ == "__main__":
    cands = parse(); print(len(cands), "candidates", flush=True)
    with ThreadPoolExecutor(4) as ex, open(D + "/verified.jsonl", "w", encoding="utf-8") as out:
        for i, rec in enumerate(ex.map(work, cands), 1):
            out.write(json.dumps(rec, ensure_ascii=False) + "\n"); out.flush()
            if i % 100 == 0: print(i, flush=True)
    print("DONE", flush=True)
