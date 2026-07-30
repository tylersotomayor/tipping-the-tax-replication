#!/usr/bin/env python3
"""Monthly fare-stack component totals on card trips -- the input for the
base-rule counterfactual menu (what each line of the tip base contributes).

Windows: calendar 2019 (the NYS congestion-surcharge year), October 2023 --
September 2024 (the last full year inside the estimation sample), and
January--June 2025 (the CBD-toll half-year). Sums are card-trip only, split
by standard rate (RatecodeID 1) versus other rate codes, since the
pass-through estimates come from rate codes 1 and 2.

Output: data/cells/component_totals.csv
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells", "component_totals.csv")
CACHE = os.path.join(ROOT, "data", "raw")
os.makedirs(CACHE, exist_ok=True)
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"

MONTHS = ([f"2019-{i:02d}" for i in range(1, 13)]
          + ["2023-10", "2023-11", "2023-12"]
          + [f"2024-{i:02d}" for i in range(1, 10)]
          + [f"2025-{i:02d}" for i in range(1, 7)])


def done():
    if not os.path.exists(OUT): return set()
    with open(OUT) as f:
        next(f, None)
        return {l.split(",")[0] for l in f}


def fetch(m):
    dst = os.path.join(CACHE, f"cmp_{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000: return dst
    for a in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "600", "-A", "Mozilla/5.0",
                            "-o", dst, URL.format(m=m)])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000: return dst
        if os.path.exists(dst): os.remove(dst)
        print(f"{m}: retry {a+1}", flush=True); time.sleep(30*(a+1))
    raise RuntimeError(m)


HEADER = ("ym,rc1,n_all,n_card,s_fare,s_extra,s_mta,s_imp,s_cs,s_cbd,"
          "s_air,s_tolls,s_ptt,s_tip\n")

con = duckdb.connect()
_d = done()
new = not os.path.exists(OUT)
if new:
    with open(OUT, "w") as f:
        f.write(HEADER)

for m in MONTHS:
    if m in _d:
        print(f"{m}: skip", flush=True); continue
    u = fetch(m)
    cols = {r[0].lower(): r[0] for r in con.execute(
        f"DESCRIBE SELECT * FROM read_parquet('{u}')").fetchall()}
    # TLC files flip between airport_fee and Airport_fee across months
    cbd = (f"COALESCE(\"{cols['cbd_congestion_fee']}\",0)"
           if "cbd_congestion_fee" in cols else "0")
    air = (f"COALESCE(\"{cols['airport_fee']}\",0)"
           if "airport_fee" in cols else "0")
    q = f"""
    WITH t AS (
      SELECT (RatecodeID = 1)::INT AS rc1, payment_type AS pay,
             fare_amount AS fare, COALESCE(extra,0) AS extra,
             COALESCE(mta_tax,0) AS mta,
             COALESCE(improvement_surcharge,0) AS imp,
             COALESCE(congestion_surcharge,0) AS cs,
             {cbd} AS cbd, {air} AS air,
             COALESCE(tolls_amount,0) AS tolls,
             (total_amount - tip_amount) AS ptt, tip_amount AS tip
      FROM read_parquet('{u}')
      WHERE fare_amount > 3 AND fare_amount < 200 AND tip_amount >= 0
    )
    SELECT '{m}' AS ym, rc1, COUNT(*) AS n_all,
           SUM((pay=1)::INT) AS n_card,
           SUM(CASE WHEN pay=1 THEN fare END),
           SUM(CASE WHEN pay=1 THEN extra END),
           SUM(CASE WHEN pay=1 THEN mta END),
           SUM(CASE WHEN pay=1 THEN imp END),
           SUM(CASE WHEN pay=1 THEN cs END),
           SUM(CASE WHEN pay=1 THEN cbd END),
           SUM(CASE WHEN pay=1 THEN air END),
           SUM(CASE WHEN pay=1 THEN tolls END),
           SUM(CASE WHEN pay=1 THEN ptt END),
           SUM(CASE WHEN pay=1 THEN tip END)
    FROM t GROUP BY 1, 2 ORDER BY 1, 2
    """
    rows = con.execute(q).fetchall()
    with open(OUT, "a") as f:
        for r in rows:
            f.write(",".join("" if x is None else str(x) for x in r) + "\n")
    print(f"{m}: done", flush=True)
    try: os.remove(u)
    except OSError: pass
print("CMPDONE", flush=True)
