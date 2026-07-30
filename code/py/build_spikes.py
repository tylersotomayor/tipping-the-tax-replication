#!/usr/bin/env python3
"""Tip-rate histogram cells against two candidate bases, June 2025.

The paper's first empirical fact drawn rather than argued: credit-card tips
spike at exactly 20/25/30 percent of the ALL-IN pre-tip total (the base the
buttons multiply), and the same tips scatter when expressed against the
metered fare alone. Half-percentage-point bins.

Sample matches the pipeline: standard rate (RatecodeID=1), credit card,
fare $3-200, positive tip, no tolls (so the all-in total is fare + statutory
surcharges and fees exactly).

Output: data/cells/spikes.csv  (base, bin, n)
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells", "spikes.csv")
CACHE = os.path.join(ROOT, "data", "raw")
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2025-06.parquet"
MONTH = "2025-06"


def fetch():
    dst = os.path.join(CACHE, f"sp_{MONTH}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000:
        return dst
    for a in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "600", "-A", "Mozilla/5.0",
                            "-o", dst, URL])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000:
            return dst
        if os.path.exists(dst): os.remove(dst)
        time.sleep(30 * (a + 1))
    raise RuntimeError(MONTH)


u = fetch()
con = duckdb.connect()
src = f"""
  SELECT tip_amount AS tip, fare_amount AS fare,
         (total_amount - tip_amount) AS allin
  FROM read_parquet('{u}')
  WHERE CAST(payment_type AS VARCHAR) = '1' AND RatecodeID = 1
    AND fare_amount BETWEEN 3 AND 200 AND tip_amount > 0
    AND COALESCE(tolls_amount, 0) = 0 AND (total_amount - tip_amount) > 0
"""
q = f"""
WITH t AS ({src})
SELECT 'allin' AS base, round(200.0*tip/allin)/2 AS bin, COUNT(*) AS n
FROM t WHERE 100.0*tip/allin BETWEEN 5 AND 40 GROUP BY 2
UNION ALL
SELECT 'fare' AS base, round(200.0*tip/fare)/2 AS bin, COUNT(*) AS n
FROM t WHERE 100.0*tip/fare BETWEEN 5 AND 40 GROUP BY 2
ORDER BY 1, 2
"""
rows = con.execute(q).fetchall()
ntot = con.execute(f"WITH t AS ({src}) SELECT COUNT(*) FROM t").fetchone()[0]
exact = con.execute(f"""
WITH t AS ({src})
SELECT AVG((abs(tip-0.20*allin)<0.005 OR abs(tip-0.25*allin)<0.005
         OR abs(tip-0.30*allin)<0.005)::INT) FROM t""").fetchone()[0]
with open(OUT, "w") as f:
    f.write("base,bin,n\n")
    for r in rows:
        f.write(",".join(str(x) for x in r) + "\n")
print(f"trips {ntot:,}  exact-button share on all-in base {exact:.3f}", flush=True)
try: os.remove(u)
except OSError: pass
print("SPIKESDONE", flush=True)
