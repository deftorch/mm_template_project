#!/usr/bin/env python3
"""Periksa, rilis, dan daftar versi klip clipkit. Tidak butuh Godot.

  python3 clipkit/clip_release.py check [nama ...]     # periksa format_version, changelog, kesesuaian snapshot
  python3 clipkit/clip_release.py release nama [...]   # simpan snapshot history/<nama>/v<N>.json (tidak menimpa)
  python3 clipkit/clip_release.py release --dry-run nama
  python3 clipkit/clip_release.py list [nama ...]      # versi, changelog, dan snapshot yang tersimpan

Exit code 1 jika ada FAIL. Aturan penomoran ada di clipver.py dan clipkit/README.md.
"""
import argparse
import sys

import clipver as cv


def _names(given):
    names = given or cv.list_clip_names()
    if not names:
        print("Tidak ada klip di %s" % cv.clips_dir())
    return names


def cmd_check(args):
    fails = warns = 0
    for name in _names(args.names):
        res = cv.check_clip(name)
        nf = sum(1 for s, _ in res if s == "FAIL")
        nw = sum(1 for s, _ in res if s == "WARN")
        fails += nf
        warns += nw
        print("\n== %s  %s" % (name, "FAIL" if nf else ("WARN" if nw else "OK")))
        for s, t in res:
            if args.quiet and s == "PASS":
                continue
            print("  [%s] %s" % (s, t))
    print("\nTotal: %d FAIL, %d WARN" % (fails, warns))
    return 1 if fails else 0


def cmd_release(args):
    rc = 0
    for name in args.names:
        ok, msg = cv.release(name, dry_run=args.dry_run)
        print("%s  %-10s %s" % ("OK    " if ok else "GAGAL ", name, msg))
        if not ok:
            rc = 1
    return rc


def cmd_list(args):
    for name in _names(args.names):
        try:
            clip = cv.load_json(cv.clip_path(name))
        except (OSError, ValueError) as e:
            print("%s: tidak terbaca (%s)" % (name, e))
            continue
        snaps = set(cv.list_snapshots(name))
        print("%s  (format %s, versi kerja v%s)" % (name, clip.get("format_version", "?"), clip.get("version", "?")))
        for e in clip.get("changelog") or []:
            v = e.get("v")
            mark = "tersimpan" if v in snaps else "tidak tersimpan"
            print("  v%-2s [%s] %s" % (v, mark, e.get("catatan", "")))
        if not clip.get("changelog"):
            print("  (tanpa changelog)")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("names", nargs="*")
    c.add_argument("--quiet", action="store_true", help="sembunyikan baris PASS")
    c.set_defaults(fn=cmd_check)
    r = sub.add_parser("release")
    r.add_argument("names", nargs="+")
    r.add_argument("--dry-run", action="store_true")
    r.set_defaults(fn=cmd_release)
    l = sub.add_parser("list")
    l.add_argument("names", nargs="*")
    l.set_defaults(fn=cmd_list)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
