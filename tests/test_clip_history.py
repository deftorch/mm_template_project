#!/usr/bin/env python3
"""Uji versioning klip (clipkit/clipver.py, clip_release.py, clip_diff.py). Tidak butuh Godot.

  python3 tests/test_clip_history.py
"""
import copy
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "clipkit"))
import clip_diff as cd  # noqa: E402
import clip_release as cr  # noqa: E402
import clipver as cv  # noqa: E402

REAL_CLIPKIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "clipkit")


def base_clip():
    return {
        "name": "demo",
        "format_version": 1,
        "version": 2,
        "changelog": [{"v": 1, "catatan": "awal"}, {"v": 2, "catatan": "perbaikan siku"}],
        "group": "combat",
        "tags": ["a"],
        "duration": 1.0,
        "loop": False,
        "channels": {"lean": [[0, 0], [0.5, 10, "outQuad"], [1.0, 0, "inOutSine"]]},
        "windows": {"hitbox": [0.2, 0.4], "cancel": [0.6, 1.0]},
        "events": [{"t": 0.1, "type": "sfx", "id": "whoosh"}],
        "claims": {"duration": 1.0, "tolerance": 0.1},
    }


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.makedirs(cv.clips_dir(self.tmp))
        self.write(base_clip())

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, clip, fname="demo"):
        with open(cv.clip_path(fname, self.tmp), "w", encoding="utf-8") as f:
            f.write(json.dumps(clip, indent=1, ensure_ascii=False))

    def load(self, name="demo"):
        return cv.load_json(cv.clip_path(name, self.tmp))

    def sev(self, name="demo"):
        return [s for s, _ in cv.check_clip(name, self.tmp)]

    def texts(self, name="demo"):
        return " | ".join(t for _, t in cv.check_clip(name, self.tmp))


class TestCheck(Base):
    def test_valid_but_unreleased_is_warn_only(self):
        self.assertEqual(self.sev().count("FAIL"), 0)
        self.assertIn("belum dirilis", self.texts())

    def test_missing_format_version_fails(self):
        c = self.load()
        del c["format_version"]
        self.write(c)
        self.assertIn("format_version belum ada", self.texts())

    def test_newer_format_version_fails(self):
        c = self.load()
        c["format_version"] = cv.FORMAT_VERSION + 1
        self.write(c)
        self.assertIn("lebih baru", self.texts())

    def test_changelog_gap_fails(self):
        c = self.load()
        c["changelog"][1]["v"] = 3
        self.write(c)
        self.assertIn("berurutan", self.texts())

    def test_changelog_last_must_match_version(self):
        c = self.load()
        c["version"] = 3
        self.write(c)
        self.assertIn("changelog berakhir di v2", self.texts())

    def test_changelog_missing_or_empty_note_fails(self):
        c = self.load()
        c["changelog"][0]["catatan"] = "  "
        self.write(c)
        self.assertIn("catatan' kosong", self.texts())
        c = self.load()
        del c["changelog"]
        self.write(c)
        self.assertIn("changelog belum ada", self.texts())

    def test_name_must_match_filename(self):
        c = self.load()
        c["name"] = "lain"
        self.write(c)
        self.assertIn("tidak sama dengan nama file", self.texts())

    def test_bool_is_not_a_version(self):
        c = self.load()
        c["version"] = True
        self.write(c)
        self.assertIn("version harus bilangan bulat", self.texts())


class TestRelease(Base):
    def test_release_writes_exact_copy(self):
        ok, _ = cv.release("demo", self.tmp)
        self.assertTrue(ok)
        with open(cv.clip_path("demo", self.tmp), "rb") as a, open(cv.snapshot_path("demo", 2, self.tmp), "rb") as b:
            self.assertEqual(a.read(), b.read())
        self.assertEqual(cv.list_snapshots("demo", self.tmp), [2])
        self.assertEqual(self.sev().count("FAIL") + self.sev().count("WARN"), 0)

    def test_release_is_idempotent(self):
        cv.release("demo", self.tmp)
        ok, msg = cv.release("demo", self.tmp)
        self.assertTrue(ok)
        self.assertIn("sudah dirilis", msg)

    def test_dry_run_writes_nothing(self):
        ok, _ = cv.release("demo", self.tmp, dry_run=True)
        self.assertTrue(ok)
        self.assertEqual(cv.list_snapshots("demo", self.tmp), [])

    def test_change_without_bump_fails_and_cannot_overwrite(self):
        cv.release("demo", self.tmp)
        c = self.load()
        c["windows"]["hitbox"] = [0.25, 0.45]
        self.write(c)
        self.assertIn("tanpa menaikkan version (beda: windows)", self.texts())
        ok, msg = cv.release("demo", self.tmp)
        self.assertFalse(ok)
        with open(cv.snapshot_path("demo", 2, self.tmp), encoding="utf-8") as f:
            self.assertEqual(json.load(f)["windows"]["hitbox"], [0.2, 0.4])  # snapshot utuh

    def test_tags_and_group_change_need_no_bump(self):
        cv.release("demo", self.tmp)
        c = self.load()
        c["tags"] = ["b", "c"]
        c["group"] = "lain"
        self.write(c)
        self.assertNotIn("FAIL", self.sev())

    def test_bump_then_release_second_snapshot(self):
        cv.release("demo", self.tmp)
        c = self.load()
        c["channels"]["lean"][1][1] = 12
        c["version"] = 3
        c["changelog"].append({"v": 3, "catatan": "lean 12"})
        self.write(c)
        self.assertNotIn("FAIL", self.sev())
        ok, _ = cv.release("demo", self.tmp)
        self.assertTrue(ok)
        self.assertEqual(cv.list_snapshots("demo", self.tmp), [2, 3])

    def test_snapshot_newer_than_clip_fails(self):
        cv.release("demo", self.tmp)
        c = self.load()
        c["version"] = 1
        c["changelog"] = c["changelog"][:1]
        self.write(c)
        self.assertIn("snapshot v2 ada tetapi version klip hanya 1", self.texts())

    def test_rewritten_history_is_warned(self):
        cv.release("demo", self.tmp)
        c = self.load()
        c["changelog"][0]["catatan"] = "ditulis ulang"
        self.write(c)
        self.assertIn("riwayat ditulis ulang", self.texts())
        self.assertNotIn("FAIL", self.sev())

    def test_cli_exit_codes(self):
        # cli memakai base default (clipkit/ asli); di sini hanya uji fungsi inti lewat exit semantics
        self.assertFalse(cv.has_fail(cv.check_clip("demo", self.tmp)))
        c = self.load()
        c["version"] = 9
        self.write(c)
        self.assertTrue(cv.has_fail(cv.check_clip("demo", self.tmp)))


class TestResolve(Base):
    def test_specs(self):
        cv.release("demo", self.tmp)
        lbl, c = cv.resolve("demo@2", self.tmp)
        self.assertEqual(c["version"], 2)
        lbl, c = cv.resolve("demo", self.tmp)
        self.assertIn("kerja", lbl)
        _, c = cv.resolve("demo@cur", self.tmp)
        self.assertEqual(c["name"], "demo")
        with self.assertRaises(ValueError):
            cv.resolve("demo@1", self.tmp)
        with self.assertRaises(ValueError):
            cv.resolve("tidakada", self.tmp)
        with self.assertRaises(ValueError):
            cv.resolve("demo@x", self.tmp)


class TestEase(unittest.TestCase):
    NAMES = ["linear", "hold", "inQuad", "outQuad", "inOutQuad", "inCubic", "outCubic",
             "inOutCubic", "inSine", "outSine", "inOutSine", "outBack"]

    def test_endpoints(self):
        for n in self.NAMES:
            self.assertAlmostEqual(cd.ease_fn(n, 0.0), 0.0, places=9, msg=n)
            self.assertAlmostEqual(cd.ease_fn(n, 1.0), 1.0, places=9, msg=n)

    def test_known_values_match_gdscript(self):
        self.assertAlmostEqual(cd.ease_fn("outQuad", 0.5), 0.75)
        self.assertAlmostEqual(cd.ease_fn("inOutSine", 0.5), 0.5)
        self.assertEqual(cd.ease_fn("hold", 0.999), 0.0)
        self.assertEqual(cd.ease_fn("tidak_dikenal", 0.3), 0.3)  # fallback linear, sama dengan GDScript

    def test_sample_keys_uses_easing_of_target_key(self):
        keys = [[0, 0], [1, 10, "inQuad"]]
        self.assertAlmostEqual(cd.sample_keys(keys, 0.5), 2.5)
        self.assertEqual(cd.sample_keys(keys, -1), 0)
        self.assertEqual(cd.sample_keys(keys, 5), 10)
        self.assertEqual(cd.sample_keys([], 0.3), 0.0)


class TestDiff(unittest.TestCase):
    def test_identical_has_no_changes(self):
        a = base_clip()
        txt = cd.diff_report("a", a, "b", copy.deepcopy(a))
        self.assertIn("channel: 0 berubah, 1 sama", txt)
        self.assertIn("tidak berubah", txt)

    def test_window_and_event_marked_gameplay(self):
        a, b = base_clip(), base_clip()
        b["windows"]["hitbox"] = [0.2, 0.5]
        b["events"][0]["t"] = 0.15
        txt = cd.diff_report("a", a, "b", b)
        self.assertIn("! jendela hitbox", txt)
        self.assertIn("! event sfx/whoosh: 0.10s -> 0.15s", txt)
        self.assertIn("BERUBAH (windows, events)", txt)

    def test_channel_delta_and_added_removed(self):
        a, b = base_clip(), base_clip()
        b["channels"]["lean"][1][1] = 14
        b["channels"]["twist"] = [[0, 0], [1, 5]]
        a["channels"]["old"] = [[0, 1]]
        txt = cd.diff_report("a", a, "b", b)
        self.assertIn("~ lean  maks selisih 4.00 @0.50s", txt)
        self.assertIn("+ twist", txt)
        self.assertIn("- old", txt)

    def test_same_curve_different_keys_counts_as_same(self):
        a, b = base_clip(), base_clip()
        a["channels"] = {"x": [[0, 0], [1.0, 10]]}
        b["channels"] = {"x": [[0, 0], [0.5, 5], [1.0, 10]]}  # key tambahan tepat di garis lurus yang sama
        rows, same = cd.diff_channels(a, b)
        self.assertEqual((len(rows), same), (0, 1))

    def test_changelog_between_versions(self):
        a = base_clip()
        b = copy.deepcopy(a)
        b["version"] = 3
        b["changelog"].append({"v": 3, "catatan": "baru"})
        txt = cd.diff_report("a", a, "b", b)
        self.assertIn("v3: baru", txt)
        self.assertNotIn("v2: perbaikan", txt)  # hanya entri di antara kedua versi


class TestRealClips(unittest.TestCase):
    """Klip yang benar-benar ada di repo harus lolos check (FAIL = 0)."""

    def test_repo_clips_have_no_fail(self):
        names = cv.list_clip_names(REAL_CLIPKIT)
        self.assertTrue(names)
        for n in names:
            res = cv.check_clip(n, REAL_CLIPKIT)
            self.assertFalse(cv.has_fail(res), "%s: %s" % (n, res))

    def test_cli_main_runs(self):
        self.assertEqual(cr.main(["check", "--quiet"]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=1)
