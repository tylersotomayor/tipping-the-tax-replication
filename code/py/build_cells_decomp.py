#!/usr/bin/env python3
"""Category-by-minute cells for the mechanism decomposition ("who passes it
through"). For every date x minute in the 4pm window (14:30-17:30, ALL days
so weekends can serve as the DiDisc control), split card tips into four
mutually exclusive categories and record counts and tip sums per category:

  button : tip equals 20/25/30% of the pre-tip total to within half a cent
  whole  : tip is a whole-dollar amount (and not a button match)
  zero   : tip is zero
  other  : everything else (custom, non-round amounts)

The June-2025 first cut (logged 2026-07-28) showed pass-through lives with
the button and other categories while whole-dollar tippers are inert; this
builder produces the full-sample input for the locked-spec version.

Output: data/cells/cells_minute_decomp.csv (minute grain -> NOT versioned,
        same policy as cells_minute_v3.csv; rebuild deterministically).
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
os.makedirs(CACHE, exist_ok=True)
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
PATH = os.path.join(OUT, "cells_minute_decomp.csv")

HEADER = ("d,mint,n_card,s_allin,"
          "n_btn,s_btn,n_whole,s_whole,n_other,s_other,n_zero\n")


def months(a, b):
    ys, ms = int(a[:4]), int(a[5:7]); ye, me = int(b[:4]), int(b[5:7])
    out = []
    while (ys, ms) <= (ye, me):
        out.append(f"{ys:04d}-{ms:02d}")
        ms += 1
        if ms == 13: ys, ms = ys + 1, 1
    return out


MONTHS = months("2021-09", "2024-09")


def done():
    if not os.path.exists(PATH): return set()
    with open(PATH) as f:
        next(f, None)
        return {l.split(",")[0][:7] for l in f}


def fetch(m):
    dst = os.path.join(CACHE, f"dc_{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000: return dst
    for a in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "600", "-A", "Mozilla/5.0",
                            "-o", dst, URL.format(m=m)])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000: return dst
        if os.path.exists(dst): os.remove(dst)
        print(f"{m}: retry {a+1}", flush=True); time.sleep(30*(a+1))
    raise RuntimeError(m)


con = duckdb.connect()
_d = done()
for m in MONTHS:
    if m in _d:
        print(f"{m}: skip", flush=True); continue
    u = fetch(m)
    q = f"""
    WITH t AS (
      SELECT tpep_pickup_datetime AS ts, tip_amount AS tip,
             (total_amount - tip_amount) AS ptt
      FROM read_parquet('{u}')
      WHERE payment_type = 1 AND RatecodeID = 1
        AND fare_amount > 3 AND fare_amount < 200 AND tip_amount >= 0
    ), c AS (
      SELECT strftime(ts,'%Y-%m-%d') AS d,
             60*EXTRACT(hour FROM ts)+EXTRACT(minute FROM ts) AS mint,
             tip, ptt,
             CASE WHEN tip = 0 THEN 'zero'
                  WHEN abs(tip-0.20*ptt)<0.005 OR abs(tip-0.25*ptt)<0.005
                       OR abs(tip-0.30*ptt)<0.005 THEN 'btn'
                  WHEN abs(tip - round(tip)) < 0.005 THEN 'whole'
                  ELSE 'other' END AS cat
      FROM t
      WHERE 60*EXTRACT(hour FROM ts)+EXTRACT(minute FROM ts) BETWEEN 870 AND 1050
    )
    SELECT d, mint, COUNT(*) AS n_card, SUM(ptt) AS s_allin,
           SUM((cat='btn')::INT) AS n_btn,   SUM(CASE WHEN cat='btn' THEN tip END) AS s_btn,
           SUM((cat='whole')::INT) AS n_whole, SUM(CASE WHEN cat='whole' THEN tip END) AS s_whole,
           SUM((cat='other')::INT) AS n_other, SUM(CASE WHEN cat='other' THEN tip END) AS s_other,
           SUM((cat='zero')::INT) AS n_zero
    FROM c GROUP BY 1,2 ORDER BY 1,2
    """
    rows = con.execute(q).fetchall()
    new = not os.path.exists(PATH)
    with open(PATH, "a") as f:
        if new: f.write(HEADER)
        for r in rows:
            f.write(",".join("" if x is None else str(x) for x in r) + "\n")
    print(f"{m}: +{len(rows)}", flush=True)
    try: os.remove(u)
    except OSError: pass
print("DECOMPDONE", flush=True)
