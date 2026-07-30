#!/usr/bin/env python3
"""Build choropleth-ready zone geometry (Manhattan + inner boroughs) for Stata.

Reads the TLC taxi-zone shapefile, reprojects to lon/lat, simplifies, and
writes a flat polygon file Stata can plot with twoway area. Geometry only.
"""
import glob, os, csv
import shapefile
from pyproj import Transformer
from shapely.geometry import shape
from shapely.ops import transform as shp_transform

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHP = glob.glob(os.path.join(ROOT, "data/raw/taxi_zones/**/*.shp"), recursive=True)[0]
OUT = os.path.join(ROOT, "data", "cells", "zone_geometry.csv")

sf = shapefile.Reader(SHP)
flds = [f[0] for f in sf.fields[1:]]
i_loc, i_bor = flds.index("LocationID"), flds.index("borough")
tr = Transformer.from_crs("EPSG:2263", "EPSG:4326", always_xy=True)

KEEP = {"Manhattan", "Brooklyn", "Queens", "Bronx"}
rows = []
for srec in sf.shapeRecords():
    rec = srec.record
    if rec[i_bor] not in KEEP:
        continue
    geom = shape(srec.shape.__geo_interface__)
    geom = shp_transform(lambda x, y, z=None: tr.transform(x, y), geom)
    geom = geom.simplify(0.0004, preserve_topology=True)
    polys = [geom] if geom.geom_type == "Polygon" else list(geom.geoms)
    # keep only the largest ring per zone to keep the file small
    polys.sort(key=lambda p: p.area, reverse=True)
    for pi, poly in enumerate(polys[:1]):
        for x, y in poly.exterior.coords:
            rows.append((rec[i_loc], rec[i_bor], pi, round(x, 5), round(y, 5)))

with open(OUT, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["pu", "borough", "part", "lon", "lat"])
    w.writerows(rows)
print(f"zones written: {len(set(r[0] for r in rows))}, vertices: {len(rows)}")
