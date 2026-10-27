"""Bake kaki menapak: tiap frame klip, cari sudut kaki agar ujung telapak tepat di titik lantai target (tumit boleh naik)."""
import math, os, random, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import clip_diff as cd
from kin import fast
from solve import LIMBS, leg_cost, TOE_Y, ANKLE_Y

FPS = 30.0
LEGBONES = ["LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"]
HIPCH = ["hip_x", "hip_y", "hip_z", "hip_twist", "hip_pitch", "hip_roll"]

def frame_times(dur):
    n = math.ceil(dur * FPS - 1e-9)
    return [min(f / FPS, dur) for f in range(n + 1)]

def eval_channels(clip, lifts, t):
    v = {c: cd.sample_keys(k, t) for c, k in clip["channels"].items()}
    v["_liftL"] = cd.sample_keys(lifts["L"], t); v["_liftR"] = cd.sample_keys(lifts["R"], t)
    return v

def bake(clip, lifts, toeL, toeR, n=700, rounds=3, w_prior=0.0004, seed=3, smooth=True):
    rnd = random.Random(seed)
    times = frame_times(clip["duration"])
    vals = [eval_channels(clip, lifts, t) for t in times]
    sides = {"L": ("legL", toeL), "R": ("legR", toeR)}
    sig0 = [8.0, 4.0, 10.0, 8.0]
    ref = {s: [[vals[i].get(ch, 0.0) for ch in LIMBS[l][0]] for i in range(len(times))] for s, (l, _) in sides.items()}
    pop = {s: [[[min(max(rnd.gauss(ref[s][i][m], sig0[m]), LIMBS[l][1][m][0]), LIMBS[l][1][m][1]) for m in range(4)]
                for _ in range(n)] for i in range(len(times))] for s, (l, _) in sides.items()}
    for s in pop:  # sertakan referensi sendiri sebagai kandidat
        for i in range(len(times)): pop[s][i][0] = list(ref[s][i])
    best = {s: [(9e9, None)] * len(times) for s in sides}
    sig = sig0
    for rd in range(rounds):
        poses = []
        for i in range(len(times)):
            base = {h: vals[i].get(h, 0.0) for h in HIPCH}
            for j in range(n):
                p = dict(base)
                for s, (l, _) in sides.items():
                    p.update({ch: round(pop[s][i][j][m], 2) for m, ch in enumerate(LIMBS[l][0])})
                poses.append(p)
        F = fast(poses, bones=LEGBONES, tag="plant")
        k = 0
        for i in range(len(times)):
            sc = {s: [] for s in sides}
            for j in range(n):
                f = F[k]; k += 1
                for s, (l, toe) in sides.items():
                    c = leg_cost(s, toe, vals[i]["_lift" + s])(f)
                    c += w_prior * sum(abs(pop[s][i][j][m] - ref[s][i][m]) for m in range(4))
                    sc[s].append((c, j))
            for s, (l, toe) in sides.items():
                sc[s].sort(key=lambda x: x[0])
                if sc[s][0][0] < best[s][i][0]:
                    best[s][i] = (sc[s][0][0], list(pop[s][i][sc[s][0][1]]))
                top = [pop[s][i][j] for _, j in sc[s][:8]] + [best[s][i][1]]
                pop[s][i] = [[min(max(rnd.gauss(c[m], sig[m]), LIMBS[l][1][m][0]), LIMBS[l][1][m][1]) for m in range(4)]
                             for c in (rnd.choice(top) for _ in range(n))]
        sig = [x * 0.4 for x in sig]
    sol = {s: [b[1] for b in best[s]] for s in sides}
    if smooth:  # penghalus 3-titik ringan (ujung tetap)
        for s in sides:
            a = sol[s]; sm = [list(x) for x in a]
            for i in range(1, len(a) - 1):
                for m in range(4): sm[i][m] = 0.25 * a[i-1][m] + 0.5 * a[i][m] + 0.25 * a[i+1][m]
            sol[s] = sm
    # galat kaki setelah penghalusan (ukur ulang di Godot)
    poses = []
    for i in range(len(times)):
        p = {h: vals[i].get(h, 0.0) for h in HIPCH}
        for s, (l, _) in sides.items():
            p.update({ch: sol[s][i][m] for m, ch in enumerate(LIMBS[l][0])})
        poses.append(p)
    F = fast(poses, bones=LEGBONES, tag="plant")
    errs = {s: [leg_cost(s, toe, vals[i]["_lift" + s])(F[i]) for i in range(len(times))] for s, (l, toe) in sides.items()}
    # tulis kunci per frame ke klip
    for s, (l, _) in sides.items():
        for m, ch in enumerate(LIMBS[l][0]):
            keys = [[0, round(sol[s][0][m], 2)]]
            for i in range(1, len(times)):
                keys.append([round(times[i], 5), round(sol[s][i][m], 2), "linear"])
            clip["channels"][ch] = keys
    return errs
