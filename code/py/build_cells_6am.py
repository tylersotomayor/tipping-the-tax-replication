#!/usr/bin/env python3
"""6:00am minute cells -- the locked outcome build_cells_v3.py never collected.

ANALYSIS_PLAN.md locks three clock windows (4pm, 8pm, 6am). build_cells_v3.py
collects only minutes 870-1050 (14:30-17:30) and 1110-1290 (18:30-21:30); the
05:00-07:00 window (minutes 300-420) was never built, so the 6am estimates
could not be produced even though 10_v3_analysis.do announced them.

This builder emits the IDENTICAL schema for the 6am window only, so the two
files can be appended. Overnight surcharge ends at 6:00am: $0.50 through
2022-12-18, $1.00 thereafter, so the step at 6am is DOWNWARD.

Output: data/cells/cells_minute_6am.csv
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
os.makedirs(CACHE, exist_ok=True)
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
PATH = os.path.join(OUT, "cells_minute_6am.csv")

HEADER = ("d,mint,n_all,n_card,s_tip,s_extra,s_fare,s_ptt,s_dist,"
          "s_dur,n_ex250,n_ex100,n_ex0,n_v2,n_zero,n_exact\n")


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
    dst = os.path.join(CACHE, f"am_{m}.parquet")
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
      SELECT tpep_pickup_datetime AS ts, tpep_dropoff_datetime AS te,
             payment_type AS pay, fare_amount AS fare, tip_amount AS tip,
             COALESCE(extra,0) AS extra, trip_distance AS dist,
             RatecodeID AS rc, VendorID AS vid,
             (total_amount - tip_amount) AS ptt
      FROM read_parquet('{u}')
      WHERE fare_amount > 3 AND fare_amount < 200 AND tip_amount >= 0
        AND RatecodeID = 1
    )
    SELECT strftime(ts,'%Y-%m-%d') AS d,
           60*EXTRACT(hour FROM ts)+EXTRACT(minute FROM ts) AS mint,
           COUNT(*) AS n_all,
           SUM((pay=1)::INT) AS n_card,
           SUM(CASE WHEN pay=1 THEN tip END) AS s_tip,
           SUM(CASE WHEN pay=1 THEN extra END) AS s_extra,
           SUM(CASE WHEN pay=1 THEN fare END) AS s_fare,
           SUM(CASE WHEN pay=1 THEN ptt END) AS s_ptt,
           SUM(CASE WHEN pay=1 THEN dist END) AS s_dist,
           SUM(CASE WHEN pay=1 THEN date_diff('second', ts, te)/60.0 END) AS s_dur,
           SUM((pay=1 AND abs(extra-2.5) < 0.005)::INT) AS n_ex250,
           SUM((pay=1 AND abs(extra-1.0) < 0.005)::INT) AS n_ex100,
           SUM((pay=1 AND extra = 0)::INT) AS n_ex0,
           SUM((pay=1 AND vid=2)::INT) AS n_v2,
           SUM((pay=1 AND tip=0)::INT) AS n_zero,
           SUM((pay=1 AND (abs(tip-0.20*ptt)<0.006 OR abs(tip-0.25*ptt)<0.006
                OR abs(tip-0.30*ptt)<0.006))::INT) AS n_exact
    FROM t
    WHERE (60*EXTRACT(hour FROM ts)+EXTRACT(minute FROM ts)) BETWEEN 300 AND 420
    GROUP BY 1,2 ORDER BY 1,2
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
print("AMDONE", flush=True)
