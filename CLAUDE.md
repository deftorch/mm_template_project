# CLAUDE.md — konteks proyek (serah-terima antar sesi)

Dokumen ini merangkum apa yang sudah dibuat, apa yang terbukti, apa yang belum, dan cara menjalankannya.
Baca ini dulu sebelum mengubah apa pun. Bahasa kerja dengan pemilik proyek: **Bahasa Indonesia**.

## 1. Tujuan

Membuat animasi karakter game (Godot 4.6) yang bisa dikerjakan AI lewat **teks, kode, dan angka**:
klip ditulis sebagai JSON, dibangun jadi `Animation` Godot, diukur otomatis, dan dilihat lewat contact sheet.
Penilaian "enak dilihat" tetap oleh manusia. Rancangan lengkap: `docs/design-doc-pipeline-animasi-godot.md`.

## 2. Repo

- Asal: `https://github.com/deftorch/mm_template_project` (demo Motion Matching, ekstensi `godot-motion-matching` oleh GuilhermeGSousa, Godot 4.6).
- Karakter: **MotusMan** (`characters/motus_man/`, 252 klip `.res` di `animations/`) dan VRM (`animation/three-vrm-girl`).
- `tools/retarget_motorica_to_motus.gd`: retarget Motorica FBX ke MotusMan (rumus world-space delta; header skripnya menjelaskan bug rest-frame yang diperbaiki).
- `tests/`: ±28 skrip uji kecil lama (retarget, kecepatan klip, dll.).
- Status git: pekerjaan clipkit tahap 1-3 + demo masuk sebagai **satu commit** `a6d2c0d` (27 Okt 2026). Repo hanya punya 3 commit, jadi riwayat v1/v2 klip sebelum itu tidak ada di git. Pekerjaan versioning (bagian 3, baris `clipver.py` dst.) ada di commit sesudahnya. Tidak ada akses push dari sandbox.
- Catatan: `clipkit/out/` dan `clipkit/preview/` ikut ter-commit di `a6d2c0d` walau di bagian 10 dianggap artefak. Setelah mengubah klip, `out/*.res` perlu dibangun ulang agar sinkron dengan JSON.

## 3. Yang sudah dibangun (Tahap 1 + 2 + Tahap 3 + demo editor)

| File | Fungsi |
|---|---|
| `clipkit/clip_lib.gd` | Inti: easing, sampling keyframe, evaluasi channel → pose (FK), `build_animation`, `anim_pose` (pose dunia dari Animation apa pun), cek range channel |
| `clipkit/rig_motus_man.json` | Rig abstrak: 21 channel axis/pos + 2 aim lengan (`armL/armR` × `elev/azim/roll`), daftar 22 bone yang dianimasikan |
| `clipkit/limits.json` | Batas validator, 3 preset gaya: `realistic`, `stylized` (default), `exaggerated` |
| `clipkit/clips/*.json` | 3 klip contoh: `dodge`, `slash`, `parry` (**pose placeholder**) |
| `clipkit/out/*.res` | Hasil build (artefak, boleh di-regenerate) |
| `clipkit/preview.py` | Contact sheet (matplotlib) dari `*.pose.json` |
| `tools/clip_build.gd` | JSON → `Animation` `.res` |
| `tools/clip_validate.gd` | Validator numerik (exit 1 jika ada FAIL) |
| `tools/clip_export_pose.gd` | Ekspor posisi sendi per frame untuk preview |
| `tests/test_clip_rig.gd` | 24 uji arah/tanda channel rig (semua lolos) |
| `clipkit/README.md` | Format klip, daftar channel, metrik, batasan |
| `scenes/clipkit_demo.tscn` + `scripts/clipkit_demo.gd` | **Demo di editor**: memuat MotusMan asli, memutar klip `clipkit/out/*.res`, HUD jendela gameplay, jeda/langkah per frame, kamera orbit. Juga mode tangkapan layar (`--shot`) |
| `clipkit/render_sheet.py` | Contact sheet dengan **mesh asli** (Xvfb + Mesa llvmpipe, tanpa GPU) → `clipkit/preview/<klip>.mesh.png` |
| `tests/test_clipkit_demo.gd` | 12 uji jalur input demo (pilih klip, jeda, langkah, kecepatan, pose berubah) |
| `clipkit/clipver.py` | Pustaka versioning (Python murni): aturan versi/changelog/snapshot, `check_clip`, `release`, `resolve` |
| `clipkit/clip_release.py` | CLI `check` / `release` / `list` |
| `clipkit/clip_diff.py` | Diff numerik dua versi klip (jendela, event, move, klaim, selisih kurva per channel) |
| `clipkit/history/<klip>/v<N>.json` | Snapshot tidak berubah per versi yang dirilis (dodge v2, slash v2, parry v3) |
| `tests/test_clip_history.py` | 28 uji bagian Python versioning (`python3 tests/test_clip_history.py`) |

## 4. Cara menjalankan (lingkungan sandbox Linux)

Godot **tidak terpasang** di sandbox baru. Yang berhasil di sesi sebelumnya:

```bash
curl -sL -o /tmp/godot.zip https://github.com/godotengine/godot-builds/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip
unzip -oq /tmp/godot.zip -d /tmp && mkdir -p ~/bin && mv /tmp/Godot_v4.6-stable_linux.x86_64 ~/bin/godot && chmod +x ~/bin/godot
~/bin/godot --version     # 4.6.stable.official.89cea1439
```
Catatan jaringan: `github.com` dan `release-assets.githubusercontent.com` diizinkan; `api.github.com` kena rate-limit; paket PyPI `godot` **bukan** engine; conda-forge tidak punya Godot.

Pertama kali di salinan baru: `godot --headless --path . --import`. Ini mengubah `characters/motus_man/MotusMan_v55.fbx.import`; kembalikan dengan `git checkout characters/motus_man/MotusMan_v55.fbx.import`.

```bash
G="godot --headless --path ."
$G -s tools/clip_build.gd                          # clips/*.json -> clipkit/out/*.res  (-- --only=dodge)
$G -s tools/clip_validate.gd                       # validasi (-- --style=realistic --quiet, atau path .res lain)
$G -s tools/clip_export_pose.gd                    # out/*.res -> clipkit/preview/*.pose.json
python3 clipkit/preview.py clipkit/preview/slash.pose.json --frames 10   # -> .contact.png (butuh matplotlib, numpy)
$G -s tests/test_clip_rig.gd                       # uji tanda channel
python3 clipkit/clip_release.py check              # versi + changelog + snapshot (tanpa Godot)
python3 clipkit/clip_diff.py parry@3 parry         # diff snapshot vs klip kerja (tanpa Godot)
python3 tests/test_clip_history.py                 # uji Python versioning
```
Output Godot berisi banyak peringatan "leaked RID/ObjectDB" saat keluar; abaikan dengan
`2>&1 | grep -v -i 'leaked\|RID \|ObjectDB\|  at: \|PagedAlloc\|resources still\|Godot Engine'`.
Saat memakai pipe `| grep`, `$?` adalah exit code grep, bukan Godot. Simpan ke file dulu (`> /tmp/x.txt; echo $?`) untuk cek exit code asli.

### Demo di editor (cara paling cepat melihat hasil)

1. Buka proyek di Godot 4.6 (pertama kali biarkan import selesai).
2. Buka `scenes/clipkit_demo.tscn`, tekan **F6** (Run Current Scene). Jangan ubah `run/main_scene`.
3. Kontrol: `1..9`/`Tab` pilih klip, `Spasi` ulang, `P` jeda, `,` `.` langkah 1 frame, `[` `]` kecepatan, `A` auto-ulang, `F` kamera ikuti pinggul, mouse kiri orbit, roda zoom, `H` sembunyikan HUD.
4. Klip dimuat dari `clipkit/out/*.res`; setelah mengubah JSON jalankan `clip_build.gd` lalu jalankan ulang scene.

Render software di sandbox (terbukti berhasil di sesi ini): `xvfb-run` + `--rendering-method gl_compatibility --rendering-driver opengl3`
(Mesa llvmpipe). `python3 clipkit/render_sheet.py <klip> [--yaw 90 35] [--n 8]` memakainya. Forward+ **tidak** diuji (tidak ada Vulkan di sandbox).
Kamera: `+Z` = depan karakter; `--yaw=0` kamera di depan, `90` dari sisi +X (kiri karakter), `-90` dari sisi kanan karakter.

## 5. Fakta terverifikasi tentang MotusMan (jangan ditebak ulang)

- Frame model: **+X = kiri karakter, +Y = atas, +Z = depan**. Rest pose = **T-pose** (lengan di ±X). Jadi channel yang tidak diisi harus punya default (lengan tergantung, `elev` -75).
- 80 bone, urutan parent-dulu. Rotasi rest per-bone tidak identity (mis. Hips Euler (0,-90,90), tulang memanjang di sumbu X lokal). Itu sebabnya sumbu channel didefinisikan di frame model dan "dibawa" rotasi parent (`carry = G_parent_pose * G_parent_rest⁻¹`), bukan pada rotasi lokal bone.
- Struktur klip: 22 track rotasi (`Skeleton3D:Hips` … `RightToeBase`, tanpa jari), 1 track posisi `Hips` (lokal, rest y = 0.968), 1 track posisi `Root` (root motion). Path `Skeleton3D:<Bone>`. 30 FPS.
- Ukuran: paha 0.426 m, betis 0.402 m. Tinggi sendi `ToeBase` pada rest = 0.030 m (dipakai sebagai "lantai" validator).
- Tanda channel (diverifikasi): `lean`+ = membungkuk ke depan; `twist`+ = dada ke kiri (bahu kanan maju); `legX_swing`+ = paha ke depan; `kneeX`+ = menekuk; `footX_pitch`+ = ujung kaki turun; `elbowX`+ = siku menekuk (tangan maju saat lengan tergantung); arm `azim` 0 = ke samping, 90 = ke depan.
- Kaki menapak datar saat tumpuan: `footX_pitch = swing − knee`. Penurunan panggul untuk tumpuan konsisten: `d = L1(1−cos a) + L2(1−cos(k−a))`, posisi kaki di depan panggul `L1 sin a − L2 sin(k−a)`.

## 6. Temuan penting dan keputusan desain

- Channel lengan **tidak** memakai rotasi sumbu bertumpuk (gimbal: lengan tergantung tidak bisa diayun maju lewat sumbu Y). Dipakai parametrisasi arah (aim: elev/azim) + `roll`; siku memakai sumbu yang dibawa lengan.
- Validator menemukan masalah nyata pada klip sendiri (tangan `parry` 3107 °/s, `slash` menembus lantai 4.9 cm). Contact sheet menemukan hal yang **tidak** ditangkap angka: kecepatan root `dodge` 21 m/s (teleport) dan `slash` yang hanya gerakan lengan. Metrik kecepatan root lalu ditambahkan ke validator. Pola kerja yang terbukti: ukur → lihat → perbaiki → ukur ulang.
- Validator juga dijalankan pada klip Motorica hasil retarget (Idle bersih; Run memberi WARN foot sliding). Jangan anggap WARN itu vonis (lihat batasan).

## 7. Status klip contoh (placeholder; sudah dirender dengan mesh, belum dinilai manusia)

`dodge` v2: lompat mundur 2.5 m (root `linear` 0.18–0.50 s, `inv` 0.10–0.45); render mesh: jongkok → lompat (lutut ditekuk) → mendarat, terbaca wajar.
`slash` v2: lunge dengan tumpuan; render mesh: ancang-ancang ke belakang, ayunan, lalu kembali. Tidak ada senjata, jadi arti ayunan baru terbaca dari lengan.
`parry` **v3**: lengan kanan diperbaiki setelah render mesh menunjukkan v2 melipat siku ke samping kepala. Sekarang `elev` -10, `azim` 55, siku 95, `roll` 0 selama jendela parry (blok silang di depan dada). Pose masih kaku (lengan kiri juga lurus ke depan, kesan "zombie").
Hasil validator terakhir: **0 FAIL, 3 WARN** (foot sliding pada ketiga klip; peringatan kecepatan lengan `parry` hilang). Foot sliding `slash` rata-rata 0.78 m/s menurut validator; belum dipastikan secara visual (kaki bisa juga melangkah sungguhan saat lunge). Jika terkonfirmasi, perbaikan wajar: key kaki berbasis IK (belum ada).
Eksperimen `roll` lengan kanan (render mesh, t=0.24 s): roll 0 = lengan bawah menyilang horizontal di dada; roll 20–35 = tangan naik ke wajah, siku melebar; roll 60–90 = lengan bawah lurus ke atas; roll negatif = lengan bawah menggantung.

## 8. Batasan dan hal yang belum terbukti

- **Belum dinilai manusia.** Klip sudah dirender dengan mesh MotusMan (render software, frame statis), tetapi tidak ada yang melihatnya bergerak di editor. Frame statis tidak menangkap bobot, kehalusan, dan irama. Minta pemilik memutar `scenes/clipkit_demo.tscn` dan memberi masukan.
- Demo diuji dengan renderer `gl_compatibility` dan headless; **Forward+ (renderer proyek) belum diuji**.
- Lantai didekati dari sendi `ToeBase`, bukan telapak. Foot sliding memakai ambang tinggi toe, jadi bisa terpengaruh ayunan kaki; perlakukan sebagai petunjuk.
- Lengan memakai arah tanpa roll otomatis: siku bisa menekuk ke bidang yang janggal (mis. `parry`, lengan kanan melipat ke arah kepala). Atur `roll`.
- Versioning: snapshot baru ada dari dodge v2, slash v2, parry v3 (v1 dan parry v2 hilang; changelog-nya hanya berisi apa yang tercatat di dokumen ini, ditandai "tidak tercatat"). Tanggal tidak dicatat di changelog karena tidak diketahui untuk versi lama. Easing di `clip_diff.py` dicocokkan dengan GDScript (13 easing x 101 titik, selisih maks 5e-16; 4459 sampel kurva klip nyata, selisih maks 5e-14), tetapi diff membandingkan data klip, bukan pose dunia hasil build.
- Belum ada: rig ke karakter kedua (VRM), `bake` motion matching otomatis, key berbasis tujuan (IK), layer aditif, mirror, secondary motion, integrasi klip ke `AnimationLibrary`/`AnimationTree`, tes regresi/CI.
- Tidak ada klaim kualitas animasi. Jangan menulis bahwa gerakan "terlihat bagus" tanpa masukan visual manusia.

## 9. Langkah berikutnya yang disarankan (urutan)

1. Minta pemilik memutar `scenes/clipkit_demo.tscn` dan memberi masukan visual; terjemahkan ke perubahan angka, jalankan `build` → `validate` → `render_sheet.py`.
2. Perbaiki foot sliding (kaki bergeser saat tumpuan): key kaki berbasis IK dua-tulang atau tambah channel kompensasi `hip_x/z`.
3. Rapikan pose `parry` (lengan kiri) dan beri `slash` makna ayunan yang jelas.
4. Pasang klip ke `AnimationLibrary`/scene MotusMan agar bisa dipicu dari `player_controller.gd`; baca `metadata` jendela (`windows`, `events`) di gameplay.
5. Rig ke karakter kedua (VRM) untuk menguji portabilitas (Tahap 4); lalu CLI satu perintah, `bake` motion matching otomatis, tes regresi (Tahap 5).
6. Validator fisika/kontak lanjutan, key berbasis IK, layer aditif, mirror.

## 10. Konvensi kerja

- Skrip Godot dijalankan dengan `--headless -s <skrip>`; argumen setelah `--`. Skrip alat memakai `extends SceneTree` + `_initialize()` + `quit(kode)`.
- Pakai `preload("res://clipkit/clip_lib.gd")` (bukan `class_name`) agar tidak bergantung pada cache kelas global.
- GDScript: nilai dari `Dictionary`/JSON bertipe Variant; jangan memakai `var x := <ekspresi Variant>` (error "cannot infer type"), beri tipe eksplisit.
- Komentar dan pesan dalam Bahasa Indonesia, sesuai gaya repo.
- Setiap perubahan klip: naikkan `version` + tambah entri `changelog` (jika isi berubah) → `clip_release.py check` → build → validate (exit 0, tanpa FAIL) → export → preview → lihat gambar → `clip_release.py release <nama>` jika diterima.
- `FORMAT_VERSION` ada di dua tempat (`clip_lib.gd` dan `clipver.py`); ubah keduanya bersamaan. Port easing di `clip_diff.py` harus tetap sama dengan `ClipLib.ease_fn`.
- Jangan commit artefak sementara; `clipkit/out/` dan `clipkit/preview/` adalah hasil regenerasi.
