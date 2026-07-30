#!/usr/bin/env python3
"""Build zone-level cells for the congestion-fee event studies.

The fee columns only exist post-treatment, so treated status must be defined
GEOGRAPHICALLY (pickup taxi zone) to have a pre-period treated group. This
script aggregates by (month, PULocationID, fare bin) and records fee
incidence, so Stata can learn the treated zone set from post-period fee
incidence and apply it to the pre-period.

Outputs: data/cells/cells_zone.csv
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
os.makedirs(OUT, exist_ok=True); os.makedirs(CACHE, exist_ok=True)
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"

def months(a, b):
    ys, ms = int(a[:4]), int(a[5:7]); ye, me = int(b[:4]), int(b[5:7])
    out = []
    while (ys, ms) <= (ye, me):
        out.append(f"{ys:04d}-{ms:02d}")
        ms += 1
        if ms == 13: ys, ms = ys + 1, 1
    return out

MONTHS = months("2018-07", "2019-12") + months("2024-01", "2025-06")
PATH = os.path.join(OUT, "cells_zone.csv")

def done():
    if not os.path.exists(PATH): return set()
    with open(PATH) as f:
        next(f, None)
        return {l.split(",")[0] for l in f}

def fetch(m):
    dst = os.path.join(CACHE, f"yellow_{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000: return dst
    for a in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "300", "-A",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", "-o", dst, URL.format(m=m)])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000: return dst
        if os.path.exists(dst): os.remove(dst)
        print(f"{m}: retry {a+1}", flush=True); time.sleep(60*(a+1))
    raise RuntimeError(m)

con = duckdb.connect(); con.execute("INSTALL httpfs; LOAD httpfs;")
_d = done()
for m in MONTHS:
    if m in _d:
        print(f"{m}: skip", flush=True); continue
    u = fetch(m)
    cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{u}')").fetchall()]
    cbd = "COALESCE(cbd_congestion_fee, 0)" if "cbd_congestion_fee" in cols else "0"
    cs = "COALESCE(congestion_surcharge, 0)" if "congestion_surcharge" in cols else "0"
    q = f"""
    SELECT '{m}' AS ym, PULocationID AS pu,
      LEAST(GREATEST(floor(fare_amount/5)*5, 5), 40) AS fbin,
      COUNT(*) AS n_all,
      SUM((payment_type = 1)::INT) AS n_card,
      SUM(CASE WHEN payment_type = 1 THEN tip_amount END) AS sum_tip,
      SUM(CASE WHEN payment_type = 1 THEN total_amount - tip_amount END) AS sum_ptt,
      AVG({cbd}) AS mean_cbd, AVG({cs}) AS mean_cs
    FROM read_parquet('{u}')
    WHERE fare_amount > 3 AND fare_amount < 200 AND tip_amount >= 0
    GROUP BY 1,2,3
    """
    rows = con.execute(q).fetchall()
    new = not os.path.exists(PATH)
    with open(PATH, "a") as f:
        if new: f.write("ym,pu,fbin,n_all,n_card,sum_tip,sum_ptt,mean_cbd,mean_cs\n")
        for r in rows:
            f.write(",".join("" if x is None else str(x) for x in r) + "\n")
    print(f"{m}: +{len(rows)}", flush=True)
    try: os.remove(u)
    except OSError: pass
print("ZONEDONE", flush=True)
