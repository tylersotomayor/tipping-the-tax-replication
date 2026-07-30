#!/usr/bin/env python3
"""Haggag & Paci (2014) replication cells: vendor-specific default menus.

Archival TLC files (2012-2013) code VendorID as 1 (CMT) / 2 (VTS) and
payment_type as 1 (credit) / 2 (cash). We extract (a) the distribution of the
tip-to-fare ratio by vendor and fare band, which reveals each vendor's default
menu as spikes, and (b) mean tip rates by vendor and fare bin.

Outputs: data/cells/hp_ratio.csv, data/cells/hp_means.csv
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
MONTHS = ["2012-04", "2012-05", "2012-06", "2012-10", "2013-04", "2013-05"]

def fetch(m):
    dst = os.path.join(CACHE, f"y{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000: return dst
    for a in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "600", "-A", "Mozilla/5.0",
                            "-o", dst, URL.format(m=m)])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000: return dst
        if os.path.exists(dst): os.remove(dst)
        time.sleep(60*(a+1))
    raise RuntimeError(m)

con = duckdb.connect()
RATIO, MEANS = os.path.join(OUT, "hp_ratio.csv"), os.path.join(OUT, "hp_means.csv")
for path in (RATIO, MEANS):
    if os.path.exists(path): os.remove(path)

for m in MONTHS:
    u = fetch(m)
    base = f"""
      SELECT CAST(VendorID AS VARCHAR) AS v, fare_amount AS fare,
             tip_amount AS tip, total_amount AS tot
      FROM read_parquet('{u}')
      WHERE CAST(payment_type AS VARCHAR) IN ('1','CRD')
        AND fare_amount BETWEEN 4 AND 60 AND tip_amount >= 0 AND tip_amount < 40
    """
    # (a) tip-rate histogram in 0.5pp bins, by vendor and fare band
    q1 = f"""
    WITH t AS ({base})
    SELECT '{m}' AS ym, v,
      CASE WHEN fare < 15 THEN 'lo' ELSE 'hi' END AS band,
      round(200.0*tip/fare)/2 AS rate_bin,
      COUNT(*) AS n
    FROM t WHERE tip > 0 AND 100.0*tip/fare <= 45
    GROUP BY 1,2,3,4
    """
    rows = con.execute(q1).fetchall()
    new = not os.path.exists(RATIO)
    with open(RATIO, "a") as f:
        if new: f.write("ym,v,band,rate_bin,n\n")
        for r in rows: f.write(",".join(str(x) for x in r) + "\n")
    # (b) means by vendor and $2 fare bin
    q2 = f"""
    WITH t AS ({base})
    SELECT '{m}' AS ym, v, LEAST(floor(fare/2)*2, 40) AS fbin,
      COUNT(*) AS n, AVG(tip) AS mean_tip, AVG(tip/fare) AS mean_rate,
      AVG((tip = 0)::INT) AS zero_sh
    FROM t GROUP BY 1,2,3
    """
    rows = con.execute(q2).fetchall()
    new = not os.path.exists(MEANS)
    with open(MEANS, "a") as f:
        if new: f.write("ym,v,fbin,n,mean_tip,mean_rate,zero_sh\n")
        for r in rows: f.write(",".join(str(x) for x in r) + "\n")
    print(f"{m}: done", flush=True)
    try: os.remove(u)
    except OSError: pass
print("HPDONE", flush=True)
