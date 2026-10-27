#!/usr/bin/env python3
"""Contact sheet dari *.pose.json (hasil tools/clip_export_pose.gd).

Pakai: python3 clipkit/preview.py clipkit/preview/dodge.pose.json [--frames 10] [--out file.png]
Baris 1: tampak samping (kanan = depan karakter). Baris 2: tampak depan (kanan = kiri karakter).
Panel dipusatkan pada Root sehingga pose bisa dibandingkan; jarak root motion ditulis di judul.
Bawah: lintasan semua frame (dunia), kecepatan tangan/kaki, dan jendela gameplay.
Warna: biru = sisi kiri, merah = sisi kanan, abu = badan/kepala. Bingkai panel: hijau = inv,
oranye = hitbox/parry/active, ungu putus-putus = cancel.
"""
import json, sys, argparse
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

ap = argparse.ArgumentParser()
ap.add_argument("pose"); ap.add_argument("--frames", type=int, default=10); ap.add_argument("--out", default=None)
args = ap.parse_args()

d = json.load(open(args.pose))
names, parents = d["bones"], d["parents"]
P = np.array(d["frames"])            # [frame, bone, xyz]
fps, dur = d["fps"], d["duration"]
nF = P.shape[0]
bi = {n: i for i, n in enumerate(names)}
win = d.get("windows", {})

def color(n):
    if n.startswith("Left"): return "#1f77b4"
    if n.startswith("Right"): return "#d62728"
    return "#444444"

# posisi relatif: pusat = Hips(x,z) pada frame itu dikurangi root displacement? gunakan posisi toe-rata2 awal
# pusatkan pada proyeksi Hips di frame 0 + geser root (Hips pada frame f - offset hips lokal) -> sederhana:
# kita pakai pusat per frame = rata-rata (x,z) dari kedua ToeBase di frame 0 + (Root disp) yang tersirat pada posisi.
root_disp = P[:, bi["Hips"], :] - P[0, bi["Hips"], :]   # termasuk offset hips lokal
def centered(f):
    c = np.array([P[f, bi["Hips"], 0] - 0.0, 0, P[f, bi["Hips"], 2]])
    return P[f] - c * np.array([1, 0, 1])               # tengahkan pada Hips (x,z), y tetap = tinggi nyata

def draw(ax, pts, view, lw=2.2, alpha=1.0):
    h = 2 if view == "side" else 0
    for i, p in enumerate(parents):
        if p < 0: continue
        ax.plot([pts[p, h], pts[i, h]], [pts[p, 1], pts[i, 1]], color=color(names[i]), lw=lw, alpha=alpha, solid_capstyle="round")
    hd = pts[bi["Head"]]
    ax.scatter([hd[h]], [hd[1]], s=60, color="#444444", alpha=alpha, zorder=3)

def window_color(t):
    c = None
    for n, (a, b) in win.items():
        if a <= t <= b:
            if n == "inv": c = c or "#2ca02c"
            elif n == "cancel": c = c or "#9467bd"
            else: c = "#ff7f0e"
    return c

N = min(args.frames, nF)
sel = np.unique(np.linspace(0, nF - 1, N).round().astype(int))
N = len(sel)
fig = plt.figure(figsize=(2.0 * N + 1, 11))
gs = fig.add_gridspec(4, N, height_ratios=[1.35, 1.35, 1.5, 0.75], hspace=0.38, wspace=0.08)

ymax = float(P[:, :, 1].max()) + 0.15
for r, view in enumerate(("side", "front")):
    for c, f in enumerate(sel):
        ax = fig.add_subplot(gs[r, c])
        pts = centered(f)
        draw(ax, pts, view)
        ax.axhline(0, color="#999999", lw=1)
        ax.set_xlim(-1.0, 1.0); ax.set_ylim(-0.1, ymax)
        ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
        t = f / fps
        wc = window_color(t)
        for s in ax.spines.values():
            s.set_edgecolor(wc or "#cccccc"); s.set_linewidth(3 if wc else 0.8)
        if r == 0:
            rd = root_disp[f]
            ax.set_title("t=%.2fs\nHips y=%.2f" % (t, P[f, bi["Hips"], 1]), fontsize=8)
        if c == 0:
            ax.set_ylabel("samping" if view == "side" else "depan", fontsize=9)

# lintasan dunia (samping)
ax = fig.add_subplot(gs[2, :int(np.ceil(N / 2))])
for f in range(0, nF, max(1, nF // 14)):
    draw(ax, P[f], "side", lw=1.0, alpha=0.18 + 0.6 * f / nF)
for bn, col in (("LeftHand", "#1f77b4"), ("RightHand", "#d62728"), ("LeftToeBase", "#6baed6"), ("RightToeBase", "#fc9272"), ("Head", "#222222")):
    ax.plot(P[:, bi[bn], 2], P[:, bi[bn], 1], color=col, lw=1.3, ls="-" if "Hand" in bn or bn == "Head" else "--", label=bn)
ax.axhline(0, color="#999999", lw=1)
ax.set_aspect("equal"); ax.set_title("lintasan dunia (samping; kanan = depan) — garis: tangan/kepala, putus-putus: ujung kaki", fontsize=9)
ax.legend(fontsize=7, ncol=5, loc="upper left")

# kecepatan titik ujung
ax = fig.add_subplot(gs[2, int(np.ceil(N / 2)):])
tt = np.arange(nF) / fps
for bn, col in (("LeftHand", "#1f77b4"), ("RightHand", "#d62728"), ("LeftToeBase", "#6baed6"), ("RightToeBase", "#fc9272"), ("Hips", "#444444")):
    v = np.linalg.norm(np.diff(P[:, bi[bn], :], axis=0), axis=1) * fps
    ax.plot(tt[1:], v, color=col, lw=1.3, label=bn)
ax.set_xlabel("detik", fontsize=8); ax.set_ylabel("kecepatan (m/s)", fontsize=8)
ax.set_title("kecepatan titik: puncak tajam = gerakan menyentak, datar = lamban", fontsize=9)
ax.legend(fontsize=7, ncol=3); ax.grid(alpha=0.3)

# jendela gameplay + event
ax = fig.add_subplot(gs[3, :])
ycol = {"inv": "#2ca02c", "cancel": "#9467bd"}
for i, (n, (a, b)) in enumerate(win.items()):
    ax.add_patch(Rectangle((a, i), b - a, 0.8, color=ycol.get(n, "#ff7f0e"), alpha=0.8))
    ax.text(a + 0.005, i + 0.4, "%s [%.2f–%.2f]" % (n, a, b), va="center", fontsize=8, color="white")
for ev in d.get("events", []):
    ax.axvline(ev["t"], color="#555555", lw=1, ls=":")
    ax.text(ev["t"], len(win) + 0.15, ev.get("id", ""), rotation=45, fontsize=7, ha="left")
ax.set_xlim(0, dur); ax.set_ylim(0, len(win) + 1.2); ax.set_yticks([])
ax.set_xlabel("detik — jendela gameplay dan event (garis titik)", fontsize=8)

fig.suptitle("%s  (%.2fs, root motion %.2f m)" % (d["name"], dur, float(np.hypot(*(P[-1, bi["Hips"], [0, 2]] - P[0, bi["Hips"], [0, 2]])))), fontsize=12)
out = args.out or args.pose.replace(".pose.json", ".contact.png")
fig.savefig(out, dpi=80, bbox_inches="tight")
print(out)
