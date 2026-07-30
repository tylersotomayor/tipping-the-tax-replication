#!/usr/bin/env python3
"""2012 vendor tip-base cells: which base did each vendor's percentages use?

The draft tested only two candidate bases (metered fare, pre-tip total) and
concluded VTS computed on the fare alone. That is wrong: `extra` is zero on
most daytime trips, so "fare" and "fare + extra" coincide there and the
fare-only test matches partially by accident. Testing the full ladder of
candidate bases separates them.

Emits per-vendor, per-base match rates so a do-file can write the fragment
(house rule: StataBE writes every displayed table).

Output: data/cells/hp_base.csv
"""
import duckdb, os, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
MONTHS = ["2012-04", "2012-05", "2012-06", "2012-10", "2013-04", "2013-05"]
PATH = os.path.join(OUT, "hp_base.csv")

BASES = {
    1: ("fare only",                "fare"),
    2: ("fare + surcharge",         "fare+extra"),
    3: ("fare + surcharge + tax",   "fare+extra+mta_tax"),
    4: ("all-in (incl. tolls)",     "fare+extra+mta_tax+tolls"),
}


def fetch(m):
    dst = os.path.join(CACHE, f"y{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000_000:
        return dst, False
    for a in range(4):
        r = subprocess.run(["curl", "-sf", "--max-time", "600", "-A", "Mozilla/5.0",
                            "-o", dst, URL.format(m=m)])
        if r.returncode == 0 and os.path.getsize(dst) > 10_000_000:
            return dst, True
        if os.path.exists(dst): os.remove(dst)
        time.sleep(30 * (a + 1))
    raise RuntimeError(m)


con = duckdb.connect()
if os.path.exists(PATH): os.remove(PATH)
rows_out = []

for m in MONTHS:
    u, fetched = fetch(m)
    src = f"""
      SELECT CAST(VendorID AS VARCHAR) AS v, fare_amount AS fare,
             COALESCE(extra,0) AS extra, COALESCE(mta_tax,0) AS mta_tax,
             COALESCE(tolls_amount,0) AS tolls, tip_amount AS tip
      FROM read_parquet('{u}')
      WHERE CAST(payment_type AS VARCHAR) IN ('1','CRD')
        AND fare_amount BETWEEN 4 AND 60 AND tip_amount >= 0 AND tip_amount < 40
    """
    sel = ["COUNT(*) AS n",
           "AVG((tip>0)::INT) AS pos_sh",
           "AVG(tip/fare) AS mean_rate",
           "AVG(fare) AS mean_fare",
           "AVG(extra) AS mean_extra",
           "AVG(mta_tax+tolls) AS mean_taxtoll",
           "AVG((mta_tax+tolls)/fare) AS gapshare"]
    for k, (_lbl, expr) in BASES.items():
        cond = " OR ".join(f"abs(tip - {p/100:.2f}*({expr})) < 0.005" for p in (20, 25, 30))
        sel.append(f"AVG((tip>0 AND ({cond}))::INT) AS b{k}")
    q = f"WITH t AS ({src}) SELECT v, " + ", ".join(sel) + " FROM t GROUP BY 1 ORDER BY 1"
    for r in con.execute(q).fetchall():
        rows_out.append((m,) + r)
    print(f"{m}: done", flush=True)
    if fetched:
        try: os.remove(u)
        except OSError: pass

hdr = ("ym,v,n,pos_sh,mean_rate,mean_fare,mean_extra,mean_taxtoll,gapshare,"
       + ",".join(f"b{k}" for k in BASES) + "\n")
with open(PATH, "w") as f:
    f.write(hdr)
    for r in rows_out:
        f.write(",".join(str(x) for x in r) + "\n")
print("HPBASEDONE", flush=True)
