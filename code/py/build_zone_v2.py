#!/usr/bin/env python3
"""Amendment-3 zone cells: PU x dropoff-in-zone x fare-bin, standard-rate,
card-consistent. Treatment eligibility = pickup OR dropoff in the fee zone."""
import duckdb, os, subprocess, time
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "cells")
CACHE = os.path.join(ROOT, "data", "raw")
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{m}.parquet"
PATH = os.path.join(OUT, "cells_zone_v2.csv")
def months(a,b):
    ys,ms=int(a[:4]),int(a[5:7]); ye,me=int(b[:4]),int(b[5:7]); out=[]
    while (ys,ms)<=(ye,me):
        out.append(f"{ys:04d}-{ms:02d}"); ms+=1
        if ms==13: ys,ms=ys+1,1
    return out
MONTHS = months("2018-07","2019-12")+months("2023-01","2025-06")
def done():
    if not os.path.exists(PATH): return set()
    with open(PATH) as f:
        next(f,None); return {l.split(",")[0] for l in f}
def fetch(m):
    dst=os.path.join(CACHE,f"z2_{m}.parquet")
    if os.path.exists(dst) and os.path.getsize(dst)>10_000_000: return dst
    for a in range(4):
        r=subprocess.run(["curl","-sf","--max-time","600","-A","Mozilla/5.0","-o",dst,URL.format(m=m)])
        if r.returncode==0 and os.path.getsize(dst)>10_000_000: return dst
        if os.path.exists(dst): os.remove(dst)
        time.sleep(60*(a+1))
    raise RuntimeError(m)
# CBD zone list learned once from 2025-03 (pickup fee incidence > 0.30)
con=duckdb.connect()
zf=os.path.join(OUT,"cbd_zones.csv")
if not os.path.exists(zf):
    u=fetch("2025-03")
    rows=con.execute(f"""SELECT PULocationID pu FROM read_parquet('{u}')
      WHERE fare_amount>3 GROUP BY 1
      HAVING AVG(COALESCE(cbd_congestion_fee,0))>0.30""").fetchall()
    with open(zf,"w") as f:
        f.write("pu\n")
        for r in rows: f.write(f"{r[0]}\n")
CBD=set(int(l) for l in open(zf).read().split()[1:])
cbdlist=",".join(str(x) for x in sorted(CBD))
_d=done()
for m in MONTHS:
    if m in _d:
        print(f"{m}: skip",flush=True); continue
    u=fetch(m)
    cols=[r[0] for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{u}')").fetchall()]
    cbd="COALESCE(cbd_congestion_fee,0)" if "cbd_congestion_fee" in cols else "0"
    cs="COALESCE(congestion_surcharge,0)" if "congestion_surcharge" in cols else "0"
    q=f"""
    SELECT '{m}' ym, PULocationID pu,
      (DOLocationID IN ({cbdlist}))::INT doin,
      LEAST(GREATEST(floor(fare_amount/5)*5,5),40) fbin,
      COUNT(*) n_all, SUM((payment_type=1)::INT) n_card,
      SUM(CASE WHEN payment_type=1 THEN tip_amount END) s_tip,
      SUM(CASE WHEN payment_type=1 THEN total_amount-tip_amount END) s_ptt,
      SUM(CASE WHEN payment_type=1 THEN {cbd} END) s_cbd,
      SUM(CASE WHEN payment_type=1 THEN {cs} END) s_cs
    FROM read_parquet('{u}')
    WHERE fare_amount>3 AND fare_amount<200 AND tip_amount>=0 AND RatecodeID=1
    GROUP BY 1,2,3,4"""
    rows=con.execute(q).fetchall()
    new=not os.path.exists(PATH)
    with open(PATH,"a") as f:
        if new: f.write("ym,pu,doin,fbin,n_all,n_card,s_tip,s_ptt,s_cbd,s_cs\n")
        for r in rows: f.write(",".join("" if x is None else str(x) for x in r)+"\n")
    print(f"{m}: +{len(rows)}",flush=True)
    try: os.remove(u)
    except OSError: pass
print("Z2DONE",flush=True)
