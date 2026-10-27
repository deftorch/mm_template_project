"""Jembatan ke Godot: evaluasi banyak pose konstan -> posisi sendi (lewat sample.gd, kinematika sama dengan pipeline)."""
import json, os, shutil, subprocess, tempfile, math

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GODOT = os.environ.get("GODOT") or shutil.which("godot") or os.path.expanduser("~/bin/godot")
NOISE = ("leaked", "RID ", "ObjectDB", "  at: ", "PagedAlloc", "resources still", "Godot Engine")
BONES = ["Hips", "Spine2", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]

def dist(a, b): return math.dist(a, b)

def run(args):
    r = subprocess.run([GODOT, "--headless", "--path", ROOT] + args, capture_output=True, text=True)
    return "\n".join(l for l in (r.stdout + r.stderr).splitlines() if not any(n in l for n in NOISE))

def fast(poses, bones=BONES, tag="fs"):
    """poses: list {channel: nilai}. Hasil: list {bone: (x,y,z)} (frame model: +X kiri, +Y atas, +Z depan)."""
    tmp = tempfile.gettempdir()
    pin, pout = os.path.join(tmp, f"clipgen_{tag}_in.json"), os.path.join(tmp, f"clipgen_{tag}_out.json")
    json.dump({"bones": bones, "poses": poses}, open(pin, "w"))
    if os.path.exists(pout): os.remove(pout)
    out = run(["-s", os.path.join(HERE, "sample.gd"), "--", pin, pout])
    if not os.path.exists(pout): raise RuntimeError(out)
    d = json.load(open(pout))
    return [{b: tuple(row[3*i:3*i+3]) for i, b in enumerate(bones)} for row in d["pos"]]
