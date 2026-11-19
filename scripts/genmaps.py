import json, math, sys
# Generates gamedata/maps/*.json (control points are hand-authored here; Neon is parametric).
# Usage: python3 scripts/genmaps.py gamedata/maps 1.17 1.12 1.08 '[{"s": 168, "length": 12, "vy": 8}, {"s": 705, "length": 12, "vy": 9}]'
#   args: outdir, sunny scale, frosty scale, neon scale, frosty ramps JSON. Then: make fixtures sync test
out = sys.argv[1]
def r(v): return round(v, 2)
def write(mid, name, theme, pts, ramps):
    with open(f"{out}/{mid}.json", "w") as f:
        f.write('{\n  "id": "%s",\n  "name": "%s",\n  "theme": "%s",\n  "points": [\n' % (mid, name, theme))
        f.write(",\n".join("    [%s]" % ", ".join(str(r(v)) for v in p) for p in pts))
        f.write('\n  ],\n  "ramps": %s\n}\n' % json.dumps(ramps))

S = float(sys.argv[2]); F = float(sys.argv[3]); N = float(sys.argv[4])
# Sunny Circuit: wide flat loop, 3 sweeping corners + chicane, CCW
sunny = [(0,0),(120,0),(240,0),(320,30),(350,100),(330,170),(270,200),(220,196),(170,214),(120,204),
         (50,212),(-30,200),(-85,150),(-100,80),(-70,20)]
write("sunny", "Sunny Circuit", "sunny", [(x*S, 0, z*S, 22, 0) for x, z in sunny], [])

# Neon Overpass: hand-made figure-8, two mirrored teardrop lobes with ~30 m hairpins;
# first pass over the crossing at y=10 (bridge), second at y=0.
R = [(0,0),(70,50),(150,72),(220,62),(265,38),(285,5),(275,-28),(245,-45),(180,-55),(100,-50),(40,-25)]
ry = [10,9,7,5,4,3,3,2,1.5,1,0.5]
L = [(-x, z) for x, z in R]
ly = [0,0.5,1,2,3,4,5,6,7,8,9]
pts = [(x*N, y, z*N, 20, 0) for (x, z), y in zip(R, ry)] + [(x*N, y, z*N, 20, 0) for (x, z), y in zip(L, ly)]
write("neon", "Neon Overpass", "neon", pts, [])

# Frosty Peaks: elevation, banked turns, narrow sections, 2 ramps (CCW: bank>0 raises the outside)
fro = [(0,0,0,20,0),(120,3,0,20,0),(240,8,0,18,0),(330,12,30,18,0.15),(360,14,110,18,0.18),
       (330,16,190,18,0.15),(250,20,220,20,0),(160,26,215,20,0),(70,30,240,18,0),(-60,26,260,18,0.15),
       (-90,20,180,18,0.18),(-80,12,100,18,0.15),(-50,5,40,20,0.1)]
write("frosty", "Frosty Peaks", "frosty", [(x*F, y, z*F, w, b) for x, y, z, w, b in fro],
      json.loads(sys.argv[5]) if len(sys.argv) > 5 else [])
