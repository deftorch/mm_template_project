#!/usr/bin/env python3
"""Bandingkan dua versi klip secara numerik. Tidak butuh Godot.

  python3 clipkit/clip_diff.py parry@2 parry@3     # dua snapshot
  python3 clipkit/clip_diff.py parry@2 parry       # snapshot vs klip kerja ('parry' = 'parry@cur')
  python3 clipkit/clip_diff.py a.json b.json       # dua file JSON

Yang dibandingkan: durasi/loop/tag, changelog di antara kedua versi, move, jendela, event, klaim,
dan tiap channel (jumlah key, rentang nilai, selisih maksimum pada kurva yang disampel 30 fps
dengan easing yang sama seperti ClipLib.sample_keys di clip_lib.gd).
Baris berawalan '!' mengubah perilaku gameplay (durasi, loop, move, jendela, event).
"""
import argparse
import json
import math
import sys

import clipver as cv

FPS = 30.0
EPS = 1e-9


# ----- port ClipLib.ease_fn / sample_keys (clip_lib.gd) ---------------------------------

def ease_fn(name, u):
    u = min(max(u, 0.0), 1.0)
    if name == "linear":
        return u
    if name == "hold":
        return 0.0 if u < 1.0 else 1.0
    if name == "inQuad":
        return u * u
    if name == "outQuad":
        return 1.0 - (1.0 - u) * (1.0 - u)
    if name == "inOutQuad":
        return 2.0 * u * u if u < 0.5 else 1.0 - (-2.0 * u + 2.0) ** 2 / 2.0
    if name == "inCubic":
        return u ** 3
    if name == "outCubic":
        return 1.0 - (1.0 - u) ** 3
    if name == "inOutCubic":
        return 4.0 * u ** 3 if u < 0.5 else 1.0 - (-2.0 * u + 2.0) ** 3 / 2.0
    if name == "inSine":
        return 1.0 - math.cos(u * math.pi / 2.0)
    if name == "outSine":
        return math.sin(u * math.pi / 2.0)
    if name == "inOutSine":
        return -(math.cos(math.pi * u) - 1.0) / 2.0
    if name == "outBack":
        c1 = 1.70158
        c3 = c1 + 1.0
        return 1.0 + c3 * (u - 1.0) ** 3 + c1 * (u - 1.0) ** 2
    return u  # easing tidak dikenal = linear, sama seperti GDScript


def sample_keys(keys, t):
    if not keys:
        return 0.0
    if t <= float(keys[0][0]):
        return float(keys[0][1])
    if t >= float(keys[-1][0]):
        return float(keys[-1][1])
    for i in range(1, len(keys)):
        if t <= float(keys[i][0]):
            a, b = keys[i - 1], keys[i]
            span = max(float(b[0]) - float(a[0]), 1e-6)
            u = (t - float(a[0])) / span
            e = str(b[2]) if len(b) > 2 else "linear"
            return float(a[1]) + (float(b[1]) - float(a[1])) * ease_fn(e, u)
    return float(keys[-1][1])


# ----- bagian-bagian diff ---------------------------------------------------------------

def _fmt(x):
    if isinstance(x, float):
        return "%g" % x
    return json.dumps(x, ensure_ascii=False)


def _compact(x):
    return json.dumps(x, ensure_ascii=False, separators=(",", ":"))


def diff_scalars(a, b, out):
    for k in ("name", "group", "duration", "loop"):
        if a.get(k) != b.get(k):
            gp = "!" if k in cv.GAMEPLAY_KEYS else " "
            out.append("%s %s: %s -> %s" % (gp, k, _fmt(a.get(k)), _fmt(b.get(k))))
    ta, tb = set(a.get("tags", [])), set(b.get("tags", []))
    if ta != tb:
        parts = []
        if tb - ta:
            parts.append("+" + ",".join(sorted(tb - ta)))
        if ta - tb:
            parts.append("-" + ",".join(sorted(ta - tb)))
        out.append("  tags: " + " ".join(parts))


def diff_move(a, b, out):
    if a.get("move") != b.get("move"):
        out.append("! move: %s -> %s" % (_compact(a["move"]) if "move" in a else "(tidak ada)",
                                          _compact(b["move"]) if "move" in b else "(tidak ada)"))


def diff_windows(a, b, out):
    wa, wb = a.get("windows", {}), b.get("windows", {})
    for n in sorted(set(wa) | set(wb)):
        if n not in wa:
            out.append("! jendela %s: baru %s" % (n, _compact(wb[n])))
        elif n not in wb:
            out.append("! jendela %s: dihapus (dulu %s)" % (n, _compact(wa[n])))
        elif wa[n] != wb[n]:
            dur_a = float(wa[n][1]) - float(wa[n][0])
            dur_b = float(wb[n][1]) - float(wb[n][0])
            out.append("! jendela %s: %s -> %s (lebar %.2fs -> %.2fs)" % (n, _compact(wa[n]), _compact(wb[n]), dur_a, dur_b))


def diff_events(a, b, out):
    def group(c):
        g = {}
        for e in c.get("events", []):
            g.setdefault((e.get("type"), e.get("id")), []).append(float(e.get("t", -1)))
        return {k: sorted(v) for k, v in g.items()}
    ga, gb = group(a), group(b)
    for k in sorted(set(ga) | set(gb), key=str):
        ta, tb = ga.get(k, []), gb.get(k, [])
        if ta == tb:
            continue
        label = "%s/%s" % k
        if not ta:
            out.append("! event %s: baru di %s" % (label, ", ".join("%.2fs" % t for t in tb)))
        elif not tb:
            out.append("! event %s: dihapus (dulu %s)" % (label, ", ".join("%.2fs" % t for t in ta)))
        else:
            out.append("! event %s: %s -> %s" % (label, ", ".join("%.2fs" % t for t in ta), ", ".join("%.2fs" % t for t in tb)))


def diff_claims(a, b, out):
    ca, cb = a.get("claims", {}), b.get("claims", {})
    for k in sorted(set(ca) | set(cb)):
        if ca.get(k) != cb.get(k):
            out.append("  klaim %s: %s -> %s" % (k, _fmt(ca.get(k, "-")), _fmt(cb.get(k, "-"))))


def diff_channels(a, b):
    """Return (daftar_baris, jumlah_sama). Tiap baris: (maks_selisih_atau_None, teks)."""
    ca, cb = a.get("channels", {}), b.get("channels", {})
    dur = max(float(a.get("duration", 0)), float(b.get("duration", 0)))
    grid = [i / FPS for i in range(int(math.ceil(dur * FPS)) + 1)]
    rows, same = [], 0
    for n in sorted(set(ca) | set(cb)):
        if n not in ca:
            rows.append((float("inf"), "  + %s  baru (%d key, %g..%g)" % (n, len(cb[n]), *_range(cb[n]))))
            continue
        if n not in cb:
            rows.append((float("inf"), "  - %s  dihapus (dulu %d key); kembali ke default rig" % (n, len(ca[n]))))
            continue
        times = sorted(set(grid) | {float(k[0]) for k in ca[n]} | {float(k[0]) for k in cb[n]})
        best, best_t = 0.0, 0.0
        for t in times:
            d = abs(sample_keys(ca[n], t) - sample_keys(cb[n], t))
            if d > best:
                best, best_t = d, t
        if best < EPS and ca[n] == cb[n]:
            same += 1
            continue
        if best < EPS:
            same += 1  # key beda penulisan tetapi kurvanya sama
            continue
        ra, rb = _range(ca[n]), _range(cb[n])
        rows.append((best, "  ~ %s  maks selisih %.2f @%.2fs | key %d -> %d | rentang %g..%g -> %g..%g"
                     % (n, best, best_t, len(ca[n]), len(cb[n]), ra[0], ra[1], rb[0], rb[1])))
    rows.sort(key=lambda r: -r[0])
    return rows, same


def _range(keys):
    vals = [float(k[1]) for k in keys]
    return (min(vals), max(vals)) if vals else (0.0, 0.0)


def changelog_between(a, b):
    va, vb = a.get("version"), b.get("version")
    if not (isinstance(va, int) and isinstance(vb, int)) or va == vb:
        return []
    lo, hi = sorted((va, vb))
    return [e for e in (b if vb > va else a).get("changelog", []) if lo < e.get("v", 0) <= hi]


def diff_report(label_a, a, label_b, b, top=0):
    out = ["== %s  ->  %s ==" % (label_a, label_b)]
    cl = changelog_between(a, b)
    if cl:
        out.append("changelog:")
        for e in cl:
            out.append("  v%s: %s" % (e.get("v"), e.get("catatan", "")))
    body = []
    diff_scalars(a, b, body)
    diff_move(a, b, body)
    diff_windows(a, b, body)
    diff_events(a, b, body)
    diff_claims(a, b, body)
    rows, same = diff_channels(a, b)
    shown = rows[:top] if top else rows
    if body:
        out += body
    out.append("channel: %d berubah, %d sama" % (len(rows), same))
    out += [t for _, t in shown]
    if top and len(rows) > top:
        out.append("  ... %d channel lain disembunyikan (--top)" % (len(rows) - top))
    gameplay = [k for k in cv.GAMEPLAY_KEYS if a.get(k) != b.get(k)]
    out.append("perilaku gameplay: " + ("BERUBAH (%s)" % ", ".join(gameplay) if gameplay else "tidak berubah (hanya pose/kurva)"))
    return "\n".join(out)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("a", help="nama@N | nama | file.json")
    p.add_argument("b", help="nama@N | nama | file.json")
    p.add_argument("--top", type=int, default=0, help="tampilkan hanya N channel dengan selisih terbesar")
    args = p.parse_args(argv)
    try:
        la, a = cv.resolve(args.a)
        lb, b = cv.resolve(args.b)
    except (ValueError, OSError) as e:
        print("GAGAL: %s" % e, file=sys.stderr)
        return 1
    print(diff_report(la, a, lb, b, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
