import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from author import build, save
S = json.load(open(os.path.join(HERE, "solved.json")))
CH = sorted(set().union(*[set(v["ch"]) for v in S.values()]))
def pose(k): return {c: S[k]["ch"].get(c, 0) for c in CH}
OUT = os.path.join(HERE, "..", "clips") + os.sep
STRIKE, LOAD, BACK = "outSine", "inOutSine", "inOutSine"

LIFT = {"G":(0,0),"G_lo":(0,0),"jab_load":(0,0),"jab_hit":(0,0),"cross_load":(0,0.02),"cross_hit":(0,0.07),
        "hook_load":(0,0),"hook_hit":(0.03,0.04),"upper_load":(0,0.015),"upper_hit":(0,0.06)}
def timeline(name, dur, keys, windows, events, catatan, tags, claims_tol=0.1, loop=False):
    """keys: [(t, pose_id, easing)]. Easing untuk segmen yang MENUJU key."""
    poses = []
    for t, pid, e in keys:
        p = {c: (v, e) for c, v in pose(pid).items()}
        poses.append((t, p))
    c = build(name, dur, poses, easing=LOAD, catatan=catatan, tags=tags, loop=loop)
    c["_lifts"] = {"L": [[t, LIFT[pid][0]] if i == 0 else [t, LIFT[pid][0], e] for i, (t, pid, e) in enumerate(keys)],
                   "R": [[t, LIFT[pid][1]] if i == 0 else [t, LIFT[pid][1], e] for i, (t, pid, e) in enumerate(keys)]}
    c["windows"] = windows; c["events"] = events
    c["claims"] = {"duration": dur, "tolerance": claims_tol}
    return c

TAGS = ["attack", "punch", "boxing", "unreviewed"]
clips = {}

clips["jab"] = timeline("jab", 0.48, [
    (0.00, "G", LOAD), (0.07, "jab_load", LOAD), (0.19, "jab_hit", STRIKE), (0.24, "jab_hit", "linear"),
    (0.38, "G", BACK), (0.48, "G", LOAD)],
    {"hitbox": [0.17, 0.25], "cancel": [0.30, 0.48]},
    [{"t": 0.15, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.19, "type": "hit", "id": "jab"}],
    "Jab kiri dari kuda-kuda ortodoks (pose dicari numerik terhadap target pergelangan/kaki; kaki di-bake menapak; render mesh; belum dinilai manusia).", TAGS)

clips["cross"] = timeline("cross", 0.68, [
    (0.00, "G", LOAD), (0.10, "cross_load", LOAD), (0.24, "cross_hit", STRIKE), (0.30, "cross_hit", "linear"),
    (0.52, "G", BACK), (0.68, "G", LOAD)],
    {"hitbox": [0.22, 0.31], "cancel": [0.38, 0.68]},
    [{"t": 0.19, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.24, "type": "hit", "id": "cross"}],
    "Cross kanan: putar pinggul/dada, tumit belakang terangkat (pose dicari numerik; kaki di-bake menapak; belum dinilai manusia).", TAGS)

clips["hook"] = timeline("hook", 0.74, [
    (0.00, "G", LOAD), (0.12, "hook_load", LOAD), (0.24, "hook_hit", STRIKE), (0.30, "hook_hit", "linear"),
    (0.56, "G", BACK), (0.74, "G", LOAD)],
    {"hitbox": [0.22, 0.31], "cancel": [0.40, 0.74]},
    [{"t": 0.19, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.24, "type": "hit", "id": "hook"}],
    "Hook kiri: siku terangkat, badan berputar ke kanan (pose dicari numerik; belum dinilai manusia).", TAGS)

clips["uppercut"] = timeline("uppercut", 0.74, [
    (0.00, "G", LOAD), (0.14, "upper_load", LOAD), (0.26, "upper_hit", STRIKE), (0.32, "upper_hit", "linear"),
    (0.56, "G", BACK), (0.74, "G", LOAD)],
    {"hitbox": [0.24, 0.33], "cancel": [0.40, 0.74]},
    [{"t": 0.21, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.26, "type": "hit", "id": "uppercut"}],
    "Uppercut kanan: jongkok lalu bangkit, tinju naik dari bawah (pose dicari numerik; belum dinilai manusia).", TAGS)

clips["combo_jab_cross_hook"] = timeline("combo_jab_cross_hook", 1.42, [
    (0.00, "G", LOAD), (0.07, "jab_load", LOAD), (0.19, "jab_hit", STRIKE), (0.23, "jab_hit", "linear"),
    (0.36, "cross_load", LOAD), (0.50, "cross_hit", STRIKE), (0.54, "cross_hit", "linear"),
    (0.70, "hook_load", LOAD), (0.82, "hook_hit", STRIKE), (0.87, "hook_hit", "linear"),
    (1.14, "G", BACK), (1.42, "G", LOAD)],
    {"cancel": [0.95, 1.42]},
    [{"t": 0.15, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.19, "type": "hit", "id": "jab"},
     {"t": 0.45, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.50, "type": "hit", "id": "cross"},
     {"t": 0.77, "type": "sfx", "id": "punch_swoosh"}, {"t": 0.82, "type": "hit", "id": "hook"}],
    "Kombo jab - cross - hook; kembali ke guard di antara pukulan hanya sebagian (pose dicari numerik; kaki di-bake menapak; belum dinilai manusia). Event 'hit' menandai tiap pukulan; satu jendela hitbox tak cukup untuk tiga pukulan.",
    TAGS + ["combo"])

clips["guard_idle"] = timeline("guard_idle", 1.2, [
    (0.00, "G", LOAD), (0.60, "G_lo", LOAD), (1.20, "G", LOAD)], {}, [],
    "Kuda-kuda tinju diam (loop): bobbing pinggul 2 cm.", ["idle", "boxing", "unreviewed", "loop"], loop=True)
clips["guard_idle"]["group"] = "locomotion"
del clips["guard_idle"]["claims"]["tolerance"]; clips["guard_idle"]["claims"]["tolerance"] = 0.1

if __name__ == "__main__":
    import plant, poses
    only = sys.argv[1:] or list(clips)
    for k in only:
        c = clips[k]
        errs = plant.bake(c, c.pop("_lifts"), poses.TOE_L, poses.TOE_R, smooth=False)
        worst = {s: max(e) for s, e in errs.items()}
        print(f"{k:22s} {c['duration']:.2f}s  galat kaki maks (m): L={worst['L']:.3f} R={worst['R']:.3f}", flush=True)
        c["tags"] = c["tags"] + ["legs-baked"]
        save(c, OUT + k + ".json")
