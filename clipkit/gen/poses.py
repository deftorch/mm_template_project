import os
from solve import *
HERE = os.path.dirname(os.path.abspath(__file__))

# Kuda-kuda ortodoks: kaki kiri depan. Target telapak (x,z) tetap, kecuali heel-lift.
TOE_L = (0.16, 0.19)
TOE_R = (-0.16, -0.14)

S = dict(twist=-15, hip_twist=-12, lean=6, head_pitch=6, head_yaw=10, hip_y=-0.085, hip_z=0.0)
def body(**kw):
    d = dict(S); d.update(kw); return d

# tangan siaga (pergelangan relatif kepala; siku turun)
GL = dict(wrist=(0.14,-0.13,0.26), drop=0.16)     # lead hand (kiri)
GR = dict(wrist=(-0.08,-0.13,0.15), drop=0.18)    # rear hand (kanan), rapat di pipi

def mk(b, L, R, liftL=0.0, liftR=0.0, toeL=TOE_L, toeR=TOE_R):
    def arm(side, spec):
        spec = dict(spec); w = spec.pop("wrist")
        return arm_cost(side, w, **spec)
    return {"body": b, "cost": {"armL": arm("L", L), "armR": arm("R", R),
            "legL": leg_cost("L", toeL, liftL), "legR": leg_cost("R", toeR, liftR)}}

def G_(**kw): d = dict(GL); d.update(kw); return d
def GR_(**kw): d = dict(GR); d.update(kw); return d

SPECS = {
 "G":          mk(body(), GL, GR),
 "G_lo":       mk(body(hip_y=-0.105, lean=8, head_pitch=8), GL, GR),
 # jab (kiri)
 "jab_load":   mk(body(twist=-21, hip_twist=-17, lean=9, hip_y=-0.09, hip_z=-0.01),
                  dict(wrist=(0.13,-0.14,0.24), drop=0.16), GR),
 "jab_hit":    mk(body(twist=-4, hip_twist=-5, lean=12, hip_y=-0.09, hip_z=0.05, head_pitch=8),
                  dict(wrist=(0.10,-0.14,0.56), drop=0.04), GR_(wrist=(-0.08,-0.14,0.12))),
 # cross (kanan)
 "cross_load": mk(body(twist=-27, hip_twist=-26, lean=3, hip_y=-0.085, hip_z=-0.03, head_pitch=7),
                  GL, GR_(wrist=(-0.09,-0.15,0.11)), liftR=0.02),
 "cross_hit":  mk(body(twist=24, hip_twist=18, lean=14, hip_y=-0.09, hip_z=0.09, head_pitch=8, head_yaw=-18),
                  G_(wrist=(0.06,-0.13,0.16)), dict(wrist=(-0.04,-0.16,0.62), drop=0.04), liftR=0.07),
 # hook kiri
 "hook_load":  mk(body(twist=8, hip_twist=2, lean=5, side_lean=5, hip_y=-0.105, hip_x=0.03, head_pitch=7),
                  dict(wrist=(0.28,-0.12,0.18), drop=0.0, out=0.10), GR),
 "hook_hit":   mk(body(twist=-52, hip_twist=-38, lean=8, side_lean=-3, hip_y=-0.09, hip_z=0.03, head_pitch=7, head_yaw=40),
                  dict(wrist=(0.00,-0.10,0.46), drop=0.0, out=0.14), GR_(wrist=(-0.08,-0.14,0.12)), liftL=0.03, liftR=0.04),
 # uppercut kanan
 "upper_load": mk(body(twist=-24, hip_twist=-22, lean=4, side_lean=-6, hip_y=-0.14, head_pitch=7),
                  GL, dict(wrist=(-0.14,-0.46,0.12), drop=0.06, fwd=-0.08), liftR=0.015),
 "upper_hit":  mk(body(twist=14, hip_twist=10, lean=10, hip_y=-0.08, hip_z=0.04, head_pitch=6, head_yaw=-12),
                  G_(wrist=(0.07,-0.13,0.17)), dict(wrist=(-0.04,-0.14,0.46), drop=0.18), liftR=0.06),
}

def report(res):
    """Ukur ulang hasil akhir: galat pergelangan (murni), siku, dan kaki, dari posisi sendi Godot."""
    ids = list(res); F = fast([res[i][0] for i in ids]); out = {}
    for i, f in zip(ids, F):
        c = SPECS[i]["cost"]; r = {}
        for l in ("armL", "armR"):
            a, b = c[l].parts(f); r[l] = (round(a, 3), round(b, 3))
        for l in ("legL", "legR"): r[l] = round(c[l](f), 3)
        out[i] = r
    return out


PUNCHER = {  # lengan yang meninju per pose (tanpa prior ke G); lainnya diacu ke G
 "jab_hit": "armL", "cross_hit": "armR", "hook_hit": "armL", "upper_hit": "armR",
 "jab_load": "armL", "cross_load": "armR", "hook_load": "armL", "upper_load": "armR",
}
def run_all(prior_w=0.0012):
    import time; t = time.time()
    g = solve({"G": SPECS["G"]}, verbose=False)
    gch = g["G"][0]
    ref = {l: ({k: gch[k] for k in LIMBS[l][0]}, prior_w) for l in LIMBS}
    specs = {}
    for k, v in SPECS.items():
        if k == "G": continue
        v = dict(v); pr = {l: ref[l] for l in ("armL", "armR")}
        if k in PUNCHER: pr.pop(PUNCHER[k])
        v["prior"] = pr; specs[k] = v
    res = solve(specs)
    res["G"] = g["G"]
    return res, time.time() - t

if __name__ == "__main__":
    res, dt = run_all()
    json.dump({k: {"ch": v[0], "res": v[1]} for k, v in res.items()}, open(os.path.join(HERE, "solved.json"), "w"), indent=1)
    print("waktu %.0f s" % dt)
    rep = report(res)
    for k, r in rep.items():
        flag = "  <-- cek" if max(r["armL"][0], r["armR"][0], r["legL"], r["legR"]) > 0.025 else ""
        print(f"{k:11s} pergelangan L={r['armL'][0]:.3f} R={r['armR'][0]:.3f} | siku-hint L={r['armL'][1]:.3f} R={r['armR'][1]:.3f} | kaki L={r['legL']:.3f} R={r['legR']:.3f}{flag}")
    for k, (c, _) in res.items():
        print(f"{k:11s}", " ".join(f"{n}={c[n]:6.1f}" for n in ["armL_elev","armL_azim","elbowL","armL_roll"]), "|", " ".join(f"{n}={c[n]:6.1f}" for n in ["armR_elev","armR_azim","elbowR","armR_roll"]))
