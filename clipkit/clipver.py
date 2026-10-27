"""clipver: pustaka versioning klip clipkit (Python murni, tanpa Godot).

Model:
  - clips/<nama>.json          klip kerja (sumber kebenaran, di-commit).
  - history/<nama>/v<N>.json   snapshot tidak berubah dari klip saat versi N dirilis.
  - Setiap klip membawa `format_version` (skema JSON) dan `changelog` (catatan per versi).

Aturan penomoran: `version` naik setiap kali isi yang memengaruhi hasil berubah
(BEHAVIOR_KEYS: durasi, loop, channel, move, windows, events, claims, validate).
Perubahan `tags`, `group`, `name`, atau changelog saja tidak perlu menaikkan versi.
"""
import json
import os

FORMAT_VERSION = 1  # harus sama dengan ClipLib.FORMAT_VERSION di clip_lib.gd

BEHAVIOR_KEYS = ("duration", "loop", "channels", "move", "windows", "events", "claims", "validate")
GAMEPLAY_KEYS = ("duration", "loop", "move", "windows", "events")  # berdampak ke gameplay, bukan hanya tampilan

HERE = os.path.dirname(os.path.abspath(__file__))


def clips_dir(base=HERE):
    return os.path.join(base, "clips")


def history_dir(base=HERE):
    return os.path.join(base, "history")


def clip_path(name, base=HERE):
    return os.path.join(clips_dir(base), name + ".json")


def snapshot_path(name, v, base=HERE):
    return os.path.join(history_dir(base), name, "v%d.json" % v)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def list_clip_names(base=HERE):
    d = clips_dir(base)
    if not os.path.isdir(d):
        return []
    return sorted(f[:-5] for f in os.listdir(d) if f.endswith(".json"))


def list_snapshots(name, base=HERE):
    """Nomor versi yang tersimpan di history/<nama>/, terurut naik."""
    d = os.path.join(history_dir(base), name)
    if not os.path.isdir(d):
        return []
    out = []
    for f in os.listdir(d):
        if f.startswith("v") and f.endswith(".json") and f[1:-5].isdigit():
            out.append(int(f[1:-5]))
    return sorted(out)


def behavior(clip):
    """Bagian klip yang memengaruhi hasil animasi/gameplay (untuk perbandingan isi)."""
    return {k: clip[k] for k in BEHAVIOR_KEYS if k in clip}


def behavior_diff_keys(a, b):
    """Daftar kunci BEHAVIOR_KEYS yang isinya beda antara klip a dan b."""
    ba, bb = behavior(a), behavior(b)
    return [k for k in BEHAVIOR_KEYS if ba.get(k) != bb.get(k)]


def _is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def check_changelog(clip):
    """Periksa changelog terhadap `version`. Return list [(sev, teks)]."""
    out = []
    ver = clip.get("version")
    cl = clip.get("changelog")
    if cl is None:
        return [("FAIL", "changelog belum ada (tambahkan daftar {v, catatan} per versi)")]
    if not isinstance(cl, list) or not cl:
        return [("FAIL", "changelog harus berupa daftar tidak kosong")]
    bad = False
    for i, e in enumerate(cl):
        if not isinstance(e, dict) or not _is_int(e.get("v")):
            out.append(("FAIL", "changelog[%d]: butuh objek dengan 'v' bilangan bulat" % i))
            bad = True
            continue
        if not isinstance(e.get("catatan"), str) or not e["catatan"].strip():
            out.append(("FAIL", "changelog v%s: 'catatan' kosong" % e["v"]))
            bad = True
    if bad:
        return out
    vs = [e["v"] for e in cl]
    if vs != list(range(1, len(vs) + 1)):
        out.append(("FAIL", "nomor changelog harus berurutan 1..N tanpa lompat, ditemukan %s" % vs))
        return out
    if vs[-1] != ver:
        out.append(("FAIL", "version=%s tetapi changelog berakhir di v%d" % (ver, vs[-1])))
        return out
    out.append(("PASS", "changelog %d entri, konsisten dengan version %d" % (len(cl), ver)))
    return out


def check_clip(name, base=HERE):
    """Periksa satu klip. Return list [(sev, teks)] dengan sev PASS/WARN/FAIL."""
    path = clip_path(name, base)
    if not os.path.isfile(path):
        return [("FAIL", "file klip tidak ditemukan: %s" % path)]
    try:
        clip = load_json(path)
    except ValueError as e:
        return [("FAIL", "JSON tidak terbaca: %s" % e)]
    out = []

    if clip.get("name") != name:
        out.append(("FAIL", "field name=%r tidak sama dengan nama file %r" % (clip.get("name"), name)))

    fv = clip.get("format_version")
    if fv is None:
        out.append(("FAIL", 'format_version belum ada (tambahkan "format_version": %d)' % FORMAT_VERSION))
    elif not _is_int(fv) or fv < 1:
        out.append(("FAIL", "format_version tidak valid: %r" % (fv,)))
    elif fv > FORMAT_VERSION:
        out.append(("FAIL", "format_version %d lebih baru dari yang didukung (%d)" % (fv, FORMAT_VERSION)))
    else:
        out.append(("PASS", "format_version %d" % fv))

    ver = clip.get("version")
    if not _is_int(ver) or ver < 1:
        out.append(("FAIL", "version harus bilangan bulat >= 1, ditemukan %r" % (ver,)))
        return out

    out += check_changelog(clip)

    snaps = list_snapshots(name, base)
    for v in snaps:
        if v > ver:
            out.append(("FAIL", "snapshot v%d ada tetapi version klip hanya %d" % (v, ver)))
    for v in snaps:
        try:
            s = load_json(snapshot_path(name, v, base))
        except ValueError as e:
            out.append(("FAIL", "snapshot v%d rusak: %s" % (v, e)))
            continue
        if s.get("version") != v or s.get("name") != name:
            out.append(("FAIL", "snapshot v%d isinya name=%r version=%r (tidak cocok dengan nama file)" % (v, s.get("name"), s.get("version"))))
            continue
        # catatan lama tidak boleh ditulis ulang diam-diam
        old = s.get("changelog") or []
        cur = (clip.get("changelog") or [])[: len(old)]
        if old != cur:
            out.append(("WARN", "changelog v1..v%d berbeda dari yang tersimpan di snapshot v%d (riwayat ditulis ulang?)" % (len(old), v)))

    if ver in snaps:
        try:
            s = load_json(snapshot_path(name, ver, base))
            diff = behavior_diff_keys(clip, s)
        except ValueError:
            diff = None
        if diff is None:
            pass
        elif diff:
            out.append(("FAIL", "isi berubah dari snapshot v%d tanpa menaikkan version (beda: %s)" % (ver, ", ".join(diff))))
        else:
            out.append(("PASS", "isi sama dengan snapshot v%d" % ver))
    else:
        out.append(("WARN", "v%d belum dirilis (jalankan: clip_release.py release %s)" % (ver, name)))
    return out


def has_fail(results):
    return any(s == "FAIL" for s, _ in results)


def release(name, base=HERE, dry_run=False):
    """Simpan snapshot versi saat ini. Return (ok, pesan). Tidak pernah menimpa snapshot."""
    res = check_clip(name, base)
    blocking = [(s, t) for s, t in res if s == "FAIL"]
    if blocking:
        return False, "tidak dirilis, ada FAIL: " + "; ".join(t for _, t in blocking)
    clip = load_json(clip_path(name, base))
    ver = clip["version"]
    dst = snapshot_path(name, ver, base)
    if os.path.exists(dst):
        return True, "v%d sudah dirilis dan isinya sama, tidak ada yang dilakukan" % ver
    if dry_run:
        return True, "(dry-run) akan menyimpan %s" % os.path.relpath(dst, base)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(clip_path(name, base), "rb") as f:
        data = f.read()
    with open(dst, "xb") as f:  # 'x': gagal jika file sudah ada
        f.write(data)
    return True, "v%d disimpan -> %s" % (ver, os.path.relpath(dst, base))


def resolve(spec, base=HERE):
    """'nama@N' -> snapshot, 'nama' atau 'nama@cur' -> klip kerja, '*.json' -> file.
    Return (label, dict). Raise ValueError jika tidak ditemukan."""
    if spec.endswith(".json") and os.path.isfile(spec):
        c = load_json(spec)
        return "%s (%s)" % (c.get("name", "?"), spec), c
    name, _, ver = spec.partition("@")
    if ver in ("", "cur", "current"):
        p = clip_path(name, base)
        if not os.path.isfile(p):
            raise ValueError("klip tidak ditemukan: %s" % p)
        c = load_json(p)
        return "%s v%s (kerja)" % (name, c.get("version", "?")), c
    if not ver.isdigit():
        raise ValueError("versi harus angka, 'cur', atau kosong: %r" % spec)
    p = snapshot_path(name, int(ver), base)
    if not os.path.isfile(p):
        have = list_snapshots(name, base)
        raise ValueError("snapshot %s@%s tidak ada (tersimpan: %s). Pakai '%s' untuk klip kerja." % (name, ver, have or "tidak ada", name))
    return "%s v%s" % (name, ver), load_json(p)
