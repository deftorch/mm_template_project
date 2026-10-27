"""Pencari pose: tiap pose punya badan (tetap) + 4 anggota gerak (lengan L/R, kaki L/R) yang dicari acak->halus.
Biaya tiap anggota gerak dihitung dari posisi sendi hasil Godot (sample.gd), bukan model matematika sendiri."""
import json, math, random, sys
from kin import fast, dist

def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def lerp(a, b, u): return tuple(a[i] + (b[i]-a[i])*u for i in range(3))

LIMBS = {
 "armL": (["armL_elev","armL_azim","elbowL","armL_roll"], [(-90,70),(-100,135),(5,150),(-100,100)]),
 "armR": (["armR_elev","armR_azim","elbowR","armR_roll"], [(-90,70),(-100,135),(5,150),(-100,100)]),
 "legL": (["legL_swing","legL_abd","kneeL","footL_pitch"], [(-35,75),(-10,40),(0,115),(-50,60)]),
 "legR": (["legR_swing","legR_abd","kneeR","footR_pitch"], [(-35,75),(-10,40),(0,115),(-50,60)]),
}
TOE_Y, ANKLE_Y = 0.030, 0.135   # kaki datar pada rest (terukur)

class ArmCost:
    """Pergelangan harus mencapai `wrist` (relatif kepala); siku diarahkan lunak ke titik tengah bahu-pergelangan
    + (keluar, turun, maju). Panjang lengan atas/bawah ditentukan rig, jadi siku tidak diberi target mutlak."""
    def __init__(self, side, wrist, drop=0.10, out=0.0, fwd=0.0, w_el=0.4):
        self.S = "Left" if side == "L" else "Right"
        self.sx = 1 if side == "L" else -1
        self.wrist, self.drop, self.out, self.fwd, self.w_el = wrist, drop, out, fwd, w_el
    def parts(self, F):
        h = F["Head"]; S = self.S
        w = sub(F[S+"Hand"], h); e = sub(F[S+"ForeArm"], h); sh = sub(F[S+"Arm"], h)
        mid = lerp(sh, self.wrist, 0.5)
        te = (mid[0] + self.out*self.sx, mid[1] - self.drop, mid[2] + self.fwd)
        return dist(w, self.wrist), dist(e, te)
    def __call__(self, F):
        a, b = self.parts(F)
        return a + self.w_el * b

def arm_cost(side, wrist, **kw):
    return ArmCost(side, wrist, **kw)

def leg_cost(side, toe_xz, lift=0.0):
    S = "Left" if side == "L" else "Right"
    def f(F):
        t = F[S+"ToeBase"]; a = F[S+"Foot"]
        return dist(t, (toe_xz[0], TOE_Y, toe_xz[1])) + 0.7 * abs(a[1] - (ANKLE_Y + lift))
    return f

def prior(spec, l, p):
    c = 0.0
    if l.startswith("arm"):
        az = [v for k, v in p.items() if k.endswith("_azim")][0] if False else p[LIMBS[l][0][1]]
        c += 0.003 * max(0.0, az - 115.0)           # hindari lengan menyilang ekstrem
    ref = spec.get("prior", {}).get(l)
    if ref:
        r, w = ref
        c += w * sum(abs(p[k] - r[k]) for k in LIMBS[l][0])
    return c

def solve(specs, n=1300, rounds=4, seed=7, verbose=True):
    """specs: {id: {'body': {...}, 'cost': {'armL': fn, 'armR': fn, 'legL': fn, 'legR': fn}}} -> {id: (canal dict, residual dict)}"""
    rnd = random.Random(seed)
    ids = list(specs)
    pop = {i: {l: [{k: rnd.uniform(*r) for k, r in zip(*LIMBS[l])} for _ in range(n)] for l in LIMBS} for i in ids}
    best = {i: {l: (9e9, None) for l in LIMBS} for i in ids}
    sig = {l: [(r[1]-r[0]) / 6 for r in LIMBS[l][1]] for l in LIMBS}
    for rd in range(rounds):
        poses = []
        for i in ids:
            for j in range(n):
                p = dict(specs[i]["body"])
                for l in LIMBS: p.update({k: round(v, 2) for k, v in pop[i][l][j].items()})
                poses.append(p)
        frames = fast(poses)
        k = 0
        for i in ids:
            sc = {l: [] for l in LIMBS}
            for j in range(n):
                F = frames[k]; k += 1
                for l in LIMBS:
                    sc[l].append((specs[i]["cost"][l](F) + prior(specs[i], l, pop[i][l][j]), j))
            for l in LIMBS:
                sc[l].sort(key=lambda x: x[0])
                if sc[l][0][0] < best[i][l][0]:
                    best[i][l] = (sc[l][0][0], dict(pop[i][l][sc[l][0][1]]))
                top = [pop[i][l][j] for _, j in sc[l][:10]] + [best[i][l][1]]
                new = []
                for _ in range(n):
                    c = rnd.choice(top)
                    new.append({kk: min(max(rnd.gauss(c[kk], sig[l][m]), LIMBS[l][1][m][0]), LIMBS[l][1][m][1])
                                for m, kk in enumerate(LIMBS[l][0])})
                pop[i][l] = new
        sig = {l: [s * 0.42 for s in v] for l, v in sig.items()}
        if verbose:
            worst = max(b[0] for i in ids for b in best[i].values())
            print(f"  putaran {rd+1}/{rounds}: biaya terburuk {worst:.3f}", flush=True)
    out = {}
    for i in ids:
        ch = dict(specs[i]["body"]); res = {}
        for l in LIMBS:
            c, p = best[i][l]; res[l] = round(c, 3)
            ch.update({k: round(v, 1) for k, v in p.items()})
        out[i] = (ch, res)
    return out
