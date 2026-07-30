#!/usr/bin/env python3
"""Build committed estimation cells from the public TLC CDN (ANALYSIS_PLAN.md).
Streams monthly parquet via duckdb; stores no raw data. Deterministic.
Outputs (data/cells/): cells_minute.csv (D1-D3), cells_did.csv (D4),
cells_vendor.csv (D0). Grain and columns documented in each query.
"""
import duckdb, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
os.makedirs(OUT, exist_ok=True)
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
CACHE = os.path.join(ROOT, "data", "raw")
os.makedirs(CACHE, exist_ok=True)

def fetch(m):
    """Download the month's parquet with one plain GET; return local path."""
    import subprocess, time
    dst = os.path.join(CACHE, f"yellow_{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000:
        return dst
    for attempt in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "300", "-A",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            "-o", dst, URL.format(m=m)])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000:
            return dst
        if os.path.exists(dst): os.remove(dst)
        print(f"{m}: download retry {attempt+1}", flush=True)
        time.sleep(60*(attempt+1))
    raise RuntimeError(f"download failed for {m}")

def cleanup(path):
    try: os.remove(path)
    except OSError: pass

def months(a, b):
    ys, ms = int(a[:4]), int(a[5:7]); ye, me = int(b[:4]), int(b[5:7])
    out = []
    while (ys, ms) <= (ye, me):
        out.append(f"{ys:04d}-{ms:02d}")
        ms += 1
        if ms == 13: ys, ms = ys + 1, 1
    return out

MIN_M = months("2021-10", "2022-11") + months("2023-01", "2024-12") + months("2025-01", "2025-06")
DID25 = months("2024-01", "2025-06")
DID19 = months("2018-07", "2019-12")
VEND  = months("2024-07", "2025-06")

con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs;")

def base_for(u):
    import time
    for attempt in range(4):
        try:
            cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{u}')").fetchall()]
            break
        except Exception as e:
            if attempt == 3: raise
            print(f"schema probe retry {attempt+1} for {u.split('/')[-1]}: {e}", flush=True)
            time.sleep(10*(attempt+1))
    cbd = "COALESCE(cbd_congestion_fee, 0)" if "cbd_congestion_fee" in cols else "0"
    cs = "COALESCE(congestion_surcharge, 0)" if "congestion_surcharge" in cols else "0"
    return BASE.format(u=u, cbd=cbd, cs=cs)

BASE = """
  SELECT tpep_pickup_datetime AS ts, VendorID AS vid,
         payment_type AS pay, fare_amount AS fare, tip_amount AS tip,
         COALESCE(extra, 0) AS extra,
         {cs} AS cs,
         {cbd} AS cbd,
         (total_amount - tip_amount) AS ptt, tolls_amount AS tolls
  FROM read_parquet('{u}')
  WHERE fare_amount > 3 AND fare_amount < 200 AND tip_amount >= 0
"""

def done_months(path, col0prefix=7):
    if not os.path.exists(path): return set()
    seen = set()
    with open(path) as f:
        next(f, None)
        for line in f:
            seen.add(line.split(",")[0][:col0prefix])
    return seen

def run(sql, path, header, month):
    import time
    for attempt in range(4):
        try:
            rows = con.execute(sql).fetchall()
            break
        except Exception as e:
            if attempt == 3: raise
            print(f"{month}: retry {attempt+1} after {e}", flush=True)
            time.sleep(10*(attempt+1))
    new = not os.path.exists(path)
    with open(path, "a") as f:
        if new: f.write(header + "\n")
        for r in rows:
            f.write(",".join("" if x is None else str(x) for x in r) + "\n")
    print(f"{month}: {os.path.basename(path)} +{len(rows)}", flush=True)

_done = done_months(os.path.join(OUT, "cells_minute.csv"))
for m in sorted(set(MIN_M)):
    if m in _done:
        print(f"{m}: minute cells already built, skip", flush=True)
        continue
    u = fetch(m)
    q = f"""
    WITH t AS ({base_for(u)})
    SELECT strftime(ts, '%Y-%m-%d') AS d,
           60*EXTRACT(hour FROM ts) + EXTRACT(minute FROM ts) AS mint,
           COUNT(*) AS n_all,
           AVG(extra) AS mean_extra,
           SUM((pay = 1)::INT) AS n_card,
           SUM(CASE WHEN pay = 1 THEN tip END) AS sum_tip_card,
           SUM((pay = 1 AND (abs(tip - 0.20*ptt) < 0.006 OR abs(tip - 0.25*ptt) < 0.006
                OR abs(tip - 0.30*ptt) < 0.006))::INT) AS n_exact,
           SUM((pay = 1 AND tip = 0)::INT) AS n_zero,
           AVG(CASE WHEN pay = 1 THEN ptt END) AS mean_ptt_card
    FROM t
    WHERE (mint BETWEEN 870 AND 1050) OR (mint BETWEEN 1110 AND 1290)
       OR (mint BETWEEN 300 AND 420)
    GROUP BY 1, 2 ORDER BY 1, 2
    """
    q = q.replace("WHERE (mint", "WHERE ((60*EXTRACT(hour FROM ts) + EXTRACT(minute FROM ts))")
    q = q.replace("OR (mint BETWEEN 1110 AND 1290)",
                  "OR ((60*EXTRACT(hour FROM ts) + EXTRACT(minute FROM ts)) BETWEEN 1110 AND 1290)")
    q = q.replace("OR (mint BETWEEN 300 AND 420)",
                  "OR ((60*EXTRACT(hour FROM ts) + EXTRACT(minute FROM ts)) BETWEEN 300 AND 420)")
    run(q, os.path.join(OUT, "cells_minute.csv"),
        "d,mint,n_all,mean_extra,n_card,sum_tip_card,n_exact,n_zero,mean_ptt_card", m)

_done = done_months(os.path.join(OUT, "cells_did.csv"))
for m in sorted(set(DID25 + DID19)):
    if m in _done:
        print(f"{m}: did cells already built, skip", flush=True)
        continue
    u = fetch(m)
    flag = "cbd > 0" if m >= "2024-01" else "cs > 0"
    q = f"""
    WITH t AS ({base_for(u)})
    SELECT '{m}' AS ym, ({flag})::INT AS zone,
           LEAST(GREATEST(floor(fare/2)*2, 4), 40) AS fbin,
           COUNT(*) AS n_all,
           SUM((pay = 1)::INT) AS n_card,
           SUM(CASE WHEN pay = 1 THEN tip END) AS sum_tip_card,
           SUM((pay = 1 AND tip = 0)::INT) AS n_zero,
           AVG(CASE WHEN pay = 1 THEN ptt END) AS mean_ptt_card
    FROM t GROUP BY 1, 2, 3 ORDER BY 2, 3
    """
    run(q, os.path.join(OUT, "cells_did.csv"),
        "ym,zone,fbin,n_all,n_card,sum_tip_card,n_zero,mean_ptt_card", m)

_done = done_months(os.path.join(OUT, "cells_vendor.csv"))
for m in VEND:
    if m in _done:
        print(f"{m}: vendor cells already built, skip", flush=True)
        continue
    u = fetch(m)
    q = f"""
    WITH t AS ({base_for(u)})
    SELECT '{m}' AS ym, vid, COUNT(*) AS n_cardtip,
      AVG((abs(tip - 0.20*ptt) < 0.006 OR abs(tip - 0.25*ptt) < 0.006 OR abs(tip - 0.30*ptt) < 0.006)::INT) AS m_allin,
      AVG((abs(tip - 0.20*(ptt - cbd)) < 0.006 OR abs(tip - 0.25*(ptt - cbd)) < 0.006 OR abs(tip - 0.30*(ptt - cbd)) < 0.006)::INT) AS m_nocbd,
      AVG((abs(tip - 0.20*fare) < 0.006 OR abs(tip - 0.25*fare) < 0.006 OR abs(tip - 0.30*fare) < 0.006)::INT) AS m_fare
    FROM t WHERE pay = 1 AND tip > 0 AND tolls = 0
    GROUP BY 1, 2 ORDER BY 2
    """
    run(q, os.path.join(OUT, "cells_vendor.csv"),
        "ym,vid,n_cardtip,m_allin,m_nocbd,m_fare", m)
    cleanup(u)

import glob as _g
for f in _g.glob(os.path.join(CACHE, "yellow_*.parquet")):
    cleanup(f)
print("DONE", flush=True)
