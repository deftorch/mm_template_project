# clipkit: klip animasi berbasis teks untuk MotusMan

Tahap 1 + 2 dari design doc: format klip JSON, generator ke `Animation` Godot, dan validator numerik.
Diuji dengan Godot 4.6 headless. **Pose di `clips/` adalah placeholder** (angka diset untuk menguji pipeline,
belum ditinjau secara visual).

## Perintah

```bash
godot --headless --path . -s tools/clip_build.gd                    # clips/*.json -> out/*.res
godot --headless --path . -s tools/clip_build.gd -- --only=dodge
godot --headless --path . -s tools/clip_validate.gd                 # validasi out/*.res
godot --headless --path . -s tools/clip_validate.gd -- --style=realistic --quiet
godot --headless --path . -s tools/clip_validate.gd -- res://characters/motus_man/animations/Idle_Loop.res
godot --headless --path . -s tests/test_clip_rig.gd                 # uji arah/tanda channel rig
```
Validator juga bisa dipakai pada klip `.res` mana pun (mis. hasil retarget Motorica). Exit code 1 jika ada FAIL.
Pertama kali di mesin baru jalankan `godot --headless --path . --import`.

## Demo di editor Godot

Buka `scenes/clipkit_demo.tscn` lalu tekan **F6**. MotusMan memutar klip dari `clipkit/out/` dengan HUD jendela gameplay
(inv/hitbox/parry/cancel), jeda, langkah per frame (`,` `.`), kecepatan (`[` `]`), dan kamera orbit (mouse kiri + roda).
Daftar tombol lengkap ada di header `scripts/clipkit_demo.gd`. Uji otomatis: `godot --headless --path . -s tests/test_clipkit_demo.gd`.

## Preview visual (contact sheet)

Dengan mesh asli (render software, Linux + Xvfb, butuh pillow): `python3 clipkit/render_sheet.py slash` -> `clipkit/preview/slash.mesh.png`.
Boneka garis (di bawah) tetap berguna untuk lintasan dan grafik kecepatan.


Godot headless tidak merender, jadi pose diekspor lalu digambar dengan matplotlib (tanpa GPU):

```bash
godot --headless --path . -s tools/clip_export_pose.gd             # out/*.res -> preview/*.pose.json
python3 clipkit/preview.py clipkit/preview/slash.pose.json --frames 10   # -> slash.contact.png
```
Isi gambar: 10 pose (tampak samping dan depan, bingkai berwarna menandai jendela inv/hitbox/parry/cancel),
lintasan dunia tangan/kaki/kepala, grafik kecepatan titik, dan timeline jendela + event.
Ini boneka garis: cukup untuk menilai timing, keseimbangan, tumpuan kaki, kekakuan, dan lonjakan kecepatan,
tidak cukup untuk menilai bobot, gaya, atau kehalusan. Butuh matplotlib + numpy.

## Versi dan riwayat

Tiga hal berbeda, jangan dicampur:

- `format_version`: versi **skema** JSON. Naik hanya jika format berubah tidak kompatibel. Konstanta pasangannya: `FORMAT_VERSION` di `clip_lib.gd` dan di `clipver.py` (harus sama).
- `version` + `changelog`: versi **isi klip**. Naikkan `version` dan tambah satu entri `changelog` setiap kali `duration`, `loop`, `channels`, `move`, `windows`, `events`, `claims`, atau `validate` berubah. Perubahan `tags`, `group`, atau teks changelog saja tidak perlu menaikkan versi.
- `history/<nama>/v<N>.json`: snapshot klip saat versi N dirilis. Tidak pernah ditimpa. Riwayat sebelum snapshot pertama tidak tersedia (di changelog ditandai "tidak tersimpan").

```bash
python3 clipkit/clip_release.py check [nama...]        # format_version, changelog, kesesuaian dengan snapshot (exit 1 jika FAIL)
python3 clipkit/clip_release.py release nama [...]     # simpan snapshot versi saat ini (menolak jika ada FAIL; --dry-run tersedia)
python3 clipkit/clip_release.py list [nama...]         # versi, changelog, dan snapshot yang tersimpan
python3 clipkit/clip_diff.py parry@3 parry@4           # bandingkan dua snapshot; 'parry' = klip kerja; file .json juga boleh
python3 tests/test_clip_history.py                     # uji bagian Python
```

Alur mengubah klip: edit JSON -> naikkan `version` dan tambah entri `changelog` -> `clip_release.py check` (FAIL jika isi berubah
tanpa menaikkan versi) -> `clip_build.gd` -> `clip_validate.gd` -> `clip_release.py release <nama>` jika hasilnya diterima.
`clip_diff.py` menandai dengan `!` perubahan yang memengaruhi gameplay (durasi, loop, move, jendela, event) dan melaporkan selisih
maksimum tiap channel pada kurva 30 fps; easing-nya sama dengan `ClipLib.sample_keys` (dicocokkan dengan GDScript, lihat catatan di CLAUDE.md).

`clip_build.gd` menyalin `clip_version`, `format_version`, dan `changelog` ke metadata `Animation`; `clip_validate.gd` memeriksa
konsistensinya (FAIL jika changelog tidak cocok dengan versi, WARN jika tanpa changelog). Klip `.res` lain (mis. hasil retarget Motorica) tidak punya
metadata ini, jadi pemeriksaan itu dilewati.

## Format klip (`clips/*.json`)

| Field | Arti |
|---|---|
| `name`, `group`, `tags` | metadata |
| `format_version` | versi skema JSON (saat ini 1). Klip dengan format lebih baru dari yang dipahami `clip_lib.gd` ditolak saat build; tanpa field ini dianggap 1 |
| `version`, `changelog` | versi klip (bilangan bulat) dan catatan per versi `[{v, catatan}, ...]`, berurutan 1..N, entri terakhir = `version`. Lihat bagian Versi dan riwayat |
| `duration` (detik), `loop` | durasi, apakah loop |
| `channels` | `{nama: [[waktu, nilai, easing], ...]}`. Easing sebuah key dipakai untuk segmen yang MENUJU key itu |
| `move` | root motion: `{dir:[x,y,z], distance, t0, t1, ease}` (objek atau daftar segmen) |
| `windows` | jendela gameplay `{inv:[a,b], hitbox:[a,b], parry:[a,b], cancel:[a,b]}` |
| `events` | `[{t, type, id}]` |
| `claims` | `{distance, duration, tolerance}` dicek validator terhadap hasil ukur |
| `validate` | opsional: `{"foot_slide":false, "check_floor":false}` |

Channel yang tidak diisi memakai default rig (lengan tergantung, siku 10°, lainnya 0).
Easing: linear, hold, inQuad, outQuad, inOutQuad, inCubic, outCubic, inOutCubic, inSine, outSine, inOutSine, outBack.
Windows/events/claims disimpan sebagai metadata `Animation` (`get_meta("windows")` dst) agar bisa dibaca gameplay.

## Channel (`rig_motus_man.json`)

Frame model: **+X kiri karakter, +Y atas, +Z depan**. Sumbu didefinisikan di frame model pada pose rest
dan dibawa oleh rotasi parent, sehingga rotasi rest per-bone MotusMan yang tidak identity tidak berpengaruh
(kelas bug yang sama dengan retarget Motorica). Arah tiap channel diverifikasi oleh `tests/test_clip_rig.gd`.

- Badan: `lean`, `side_lean`, `twist` (dibagi ke Spine/Spine1/Spine2), `hip_pitch|twist|roll`, `hip_x|y|z` (meter)
- Kepala: `head_pitch`, `head_yaw`
- Lengan L/R (`armL_*`, `armR_*`): `elev` (0 = horizontal, -90 = tergantung), `azim` (0 = ke samping, 90 = ke depan), `roll`
- Siku: `elbowL|R`
- Kaki: `legL|R_swing`, `legL|R_abd`, `kneeL|R`, `footL|R_pitch`

Nilai di luar `range` rig menghasilkan peringatan saat build.

## Metrik validator (`limits.json`)

Kecepatan/percepatan sudut per tulang, kontinuitas loop, fleksi lutut (bertanda; negatif = terbalik), siku, leher,
kecepatan root motion (terlalu cepat = terasa teleport), penetrasi lantai (sendi toe terhadap tinggi toe pada rest), foot sliding, klaim jarak/durasi, validitas dan urutan
jendela. Tiga preset gaya: `realistic`, `stylized` (default), `exaggerated`.

## Batasan yang diketahui

- Lantai didekati dari tinggi sendi `ToeBase` pada pose rest, bukan telapak sebenarnya.
- Foot sliding memakai ambang tinggi toe; pada klip lari angkanya bisa terpengaruh ayunan kaki yang melewati ambang.
  Perlakukan sebagai petunjuk, bukan vonis.
- Lengan memakai arah (aim) tanpa roll otomatis: atur `roll` agar siku menekuk ke bidang yang diinginkan.
- Belum ada: key berbasis tujuan (IK), layer aditif, mirror, bake motion matching.
- Versioning: snapshot hanya mulai dari versi yang dirilis pertama kali (dodge v2, slash v2, parry v3); v1 dan parry v2 tidak tersimpan. Tidak ada migrasi otomatis antar `format_version` (baru ada format 1). Snapshot tidak dilindungi dari penyuntingan manual selain lewat Git; `check` hanya mendeteksi kalau isi klip kerja menyimpang dari snapshot versi yang sama. Diff membandingkan data klip, bukan hasil gerak (pose dunia) setelah build.
