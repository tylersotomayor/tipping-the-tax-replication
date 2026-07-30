#!/usr/bin/env python3
"""Vendor-keyed 4pm-window cells for the vendor-split rho analysis.
Grain: date x minute x VendorID, standard-rate card-consistent moments."""
import duckdb, os, subprocess, time
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
PATH = os.path.join(OUT, "cells_minute_vendor.csv")
def months(a,b):
    ys,ms=int(a[:4]),int(a[5:7]); ye,me=int(b[:4]),int(b[5:7]); out=[]
    while (ys,ms)<=(ye,me):
        out.append(f"{ys:04d}-{ms:02d}"); ms+=1
        if ms==13: ys,ms=ys+1,1
    return out
MONTHS = months("2021-09","2024-09")
def done():
    if not os.path.exists(PATH): return set()
    with open(PATH) as f:
        next(f,None); return {l.split(",")[0][:7] for l in f}
def fetch(m):
    dst=os.path.join(CACHE,f"vd_{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst)>10_000_000: return dst
    for a in range(4):
        r=subprocess.run(["curl","-sf","--max-time","600","-A","Mozilla/5.0","-o",dst,URL.format(m=m)])
        if r.returncode==0 and os.path.getsize(dst)>10_000_000: return dst
        if os.path.exists(dst): os.remove(dst)
        time.sleep(60*(a+1))
    raise RuntimeError(m)
con=duckdb.connect()
_d=done()
for m in MONTHS:
    if m in _d:
        print(f"{m}: skip",flush=True); continue
    u=fetch(m)
    q=f"""
    SELECT strftime(tpep_pickup_datetime,'%Y-%m-%d') d,
      60*EXTRACT(hour FROM tpep_pickup_datetime)+EXTRACT(minute FROM tpep_pickup_datetime) mint,
      VendorID vid, COUNT(*) n_all, SUM((payment_type=1)::INT) n_card,
      SUM(CASE WHEN payment_type=1 THEN tip_amount END) s_tip,
      SUM(CASE WHEN payment_type=1 THEN COALESCE(extra,0) END) s_extra,
      SUM(CASE WHEN payment_type=1 THEN total_amount-tip_amount END) s_ptt,
      SUM((payment_type=1 AND (abs(tip_amount-0.20*(total_amount-tip_amount))<0.006
        OR abs(tip_amount-0.25*(total_amount-tip_amount))<0.006
        OR abs(tip_amount-0.30*(total_amount-tip_amount))<0.006))::INT) n_exact
    FROM read_parquet('{u}')
    WHERE fare_amount>3 AND fare_amount<200 AND tip_amount>=0 AND RatecodeID=1
      AND 60*EXTRACT(hour FROM tpep_pickup_datetime)+EXTRACT(minute FROM tpep_pickup_datetime) BETWEEN 870 AND 1050
    GROUP BY 1,2,3"""
    rows=con.execute(q).fetchall()
    new=not os.path.exists(PATH)
    with open(PATH,"a") as f:
        if new: f.write("d,mint,vid,n_all,n_card,s_tip,s_extra,s_ptt,n_exact\n")
        for r in rows: f.write(",".join("" if x is None else str(x) for x in r)+"\n")
    print(f"{m}: +{len(rows)}",flush=True)
    try: os.remove(u)
    except OSError: pass
print("VDDONE",flush=True)
