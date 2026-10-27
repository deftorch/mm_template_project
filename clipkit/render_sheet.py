#!/usr/bin/env python3
"""Contact sheet dengan MESH asli (render software, tanpa GPU/monitor).

Memakai scenes/clipkit_demo.tscn dalam mode tangkapan layar di bawah Xvfb + Mesa llvmpipe.
Prasyarat (Linux): godot 4.6, xvfb-run, libGL/mesa (llvmpipe), python3 + pillow.

  python3 clipkit/render_sheet.py slash                    # 8 frame, dua sudut -> clipkit/preview/slash.mesh.png
  python3 clipkit/render_sheet.py parry --yaw 35 -60 --n 8
  GODOT=/path/ke/godot python3 clipkit/render_sheet.py dodge
  python3 clipkit/render_sheet.py dodge --rig vrm          # karakter VRM -> dodge.vrm.mesh.png
  python3 clipkit/render_sheet.py dodge --rig vrm --skeleton res://testdata/vrm1/X.vrm --tag vrm1

Catatan: render ini hanya untuk menilai pose/timing secara visual; bukan pengganti memutar klip di editor.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def shoot(godot, clip, yaw, times, prefix, extra=()):
    cmd = ["xvfb-run", "-a", "-s", "-screen 0 800x600x24", godot, "--path", ROOT,
           "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--resolution", "640x560", "res://scenes/clipkit_demo.tscn", "--",
           f"--shot={prefix}", f"--clip={clip}", f"--yaw={yaw}",
           "--times=" + ",".join(f"{t:.3f}" for t in times), "--follow", "--nohud", "--dist=4.2", *extra]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    return out.count("SHOT ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("clip")
    ap.add_argument("--yaw", type=float, nargs="+", default=[90, 35])
    ap.add_argument("--n", type=int, default=8, help="jumlah frame (min 2)")
    ap.add_argument("--rig", default="", help="rig/karakter: motus (default) atau vrm")
    ap.add_argument("--skeleton", default="", help="scene karakter lain, mis. res://testdata/vrm1/model.vrm")
    ap.add_argument("--tag", default="", help="akhiran nama berkas keluaran")
    args = ap.parse_args()
    godot = os.environ.get("GODOT") or shutil.which("godot") or os.path.expanduser("~/bin/godot")
    if not shutil.which("xvfb-run"):
        sys.exit("xvfb-run tidak ditemukan (apt install xvfb).")
    cj = os.path.join(ROOT, "clipkit", "clips", args.clip + ".json")
    dur = json.load(open(cj))["duration"]
    n = max(args.n, 2)
    times = [dur * i / (n - 1) for i in range(n)]
    cw, ch = 380, 520
    cols = 4
    rows_per_yaw = (n + cols - 1) // cols
    sheet = Image.new("RGB", (cw * cols, ch * rows_per_yaw * len(args.yaw)))
    with tempfile.TemporaryDirectory() as tmp:
        for yi, yaw in enumerate(args.yaw):
            prefix = os.path.join(tmp, f"s{yi}")
            extra = ([f"--rig={args.rig}"] if args.rig else []) + ([f"--skeleton={args.skeleton}"] if args.skeleton else [])
            got = shoot(godot, args.clip, yaw, times, prefix, extra)
            if got != n:
                sys.exit(f"hanya {got}/{n} tangkapan berhasil (cek godot/xvfb).")
            for i, t in enumerate(times):
                im = Image.open(f"{prefix}_{i}.png").convert("RGB")
                w, h = im.size
                x0, y0 = (w - cw) // 2, (h - ch) // 2 + 10
                cell = im.crop((x0, y0, x0 + cw, y0 + ch))
                d = ImageDraw.Draw(cell)
                d.rectangle((0, 0, 190, 22), fill=(0, 0, 0))
                d.text((6, 5), f"{args.clip} t={t:.2f}s yaw={yaw:g}", fill=(255, 255, 255))
                sheet.paste(cell, ((i % cols) * cw, (yi * rows_per_yaw + i // cols) * ch))
    outdir = os.path.join(ROOT, "clipkit", "preview")
    os.makedirs(outdir, exist_ok=True)
    tag = args.tag or (args.rig if args.rig and args.rig != "motus" else "")
    out = os.path.join(outdir, f"{args.clip}.{tag + '.' if tag else ''}mesh.png")
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
