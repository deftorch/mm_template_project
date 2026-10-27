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
| `clipkit/rig_vrm.json` | Rig VRM (0.x dan 1.0) sebagai turunan rig MotusMan: `extends`, `bone_alias`, `%GeneralSkeleton`, `pos_scale: auto`, `optional_bones`, `out_dir: clipkit/out/vrm/` |
| `tests/test_clip_portability.gd` | Uji lintas skeleton (MotusMan, VRM 0.x, VRM 1.0): urutan bone, resolve path track lewat `AnimationPlayer` nyata, bone opsional, dan `out/` sinkron dengan JSON (sudah diuji sensitif: gagal jika JSON diubah tanpa rebuild) |
| `tests/fetch_vrm1_sample.sh` | Mengunduh model uji VRM 1.0 ke `testdata/vrm1/` (tidak di-commit; `.gitignore`) |
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
$G -s tests/test_clip_rig.gd                       # uji tanda channel (tambah -- --rig=vrm [--skeleton=res://...vrm])
$G -s tests/test_clip_portability.gd               # uji lintas skeleton + out/ sinkron
$G -s tools/clip_build.gd -- --rig=vrm             # rig lain -> clipkit/out/vrm/ (juga validate/export_pose/render_sheet.py --rig vrm)
sh tests/fetch_vrm1_sample.sh && $G --import       # model uji VRM 1.0 (sekali)
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

### Fakta terverifikasi tentang VRM (addon V-Sekai, Godot 4.6; jangan ditebak ulang)

- Repo hanya berisi VRM **0.x** (`animation/three-vrm-girl.vrm`, UniVRM 0.55). VRM **1.0** diuji dengan `VRM1_Constraint_Twist_Sample.vrm` (pixiv/three-vrm; `specVersion 1.0`, 54 humanoid bone, 14 node constraint).
- Keduanya diimpor addon sebagai `Root_/GeneralSkeleton` (161 / 167 bone), dengan bone `Root` di atas `Hips`; path track animasi `%GeneralSkeleton:<Bone>` (sama dengan animasi VRM bawaan repo).
- **Urutan bone BUKAN parent-dulu** pada kedua versi (parent bisa ber-index lebih besar). Loop `for i in n` untuk FK salah; pakai `ClipLib.bone_order()`.
- Nama bone: `Hips Spine Chest UpperChest Neck Head LeftShoulder LeftUpperArm LeftLowerArm LeftHand LeftUpperLeg LeftLowerLeg LeftFoot LeftToes`. Frame +X kiri, +Y atas, +Z depan; T-pose. Ukuran: paha 0.353, betis 0.415 m; tinggi panggul 0.894 (0.x) / 0.908 (1.0); tinggi toe rest 0.024 / 0.038 m; jangkauan lengan 0.433 / 0.435 m.
- 20 bone punya rest non-identity; desain "carry" tetap benar: 24/24 uji arah lulus di MotusMan, VRM 0.x, VRM 1.0 (ambang uji relatif terhadap ukuran tubuh, bukan meter MotusMan).

## 6. Temuan penting dan keputusan desain

- **Portabilitas VRM (sesi ini):** refaktor `clip_lib.gd` tidak mengubah keluaran MotusMan (ketiga `out/*.res` identik bit-per-bit, laporan validator identik). Validator foot sliding kini juga mensyaratkan kaki tidak sedang naik/turun cepat (`contact_max_vertical_ms` di `limits.json`); tanpa itu hasil dodge berbalik antara VRM 0.x dan 1.0 hanya karena toe berbeda ~1 cm di sekitar ambang kontak 0.03 m (frame lepas landas, root meluncur 6 m/s ikut terhitung). Angka MotusMan tidak berubah.

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
- Belum ada: `bake` motion matching otomatis dari pipeline klip (ada `tools/bake_motus_library_editor.gd` untuk MotusMan), key berbasis tujuan (IK), layer aditif, mirror, secondary motion, integrasi klip ke `AnimationLibrary`/`AnimationTree`, tes regresi/CI.
- Tidak ada klaim kualitas animasi. Jangan menulis bahwa gerakan "terlihat bagus" tanpa masukan visual manusia.

## 9. Langkah berikutnya yang disarankan (urutan)

1. Minta pemilik memutar `scenes/clipkit_demo.tscn` dan memberi masukan visual; terjemahkan ke perubahan angka, jalankan `build` → `validate` → `render_sheet.py`.
2. Perbaiki foot sliding (kaki bergeser saat tumpuan): key kaki berbasis IK dua-tulang atau tambah channel kompensasi `hip_x/z`.
3. Rapikan pose `parry` (lengan kiri) dan beri `slash` makna ayunan yang jelas.
4. Pasang klip ke `AnimationLibrary`/scene MotusMan agar bisa dipicu dari `player_controller.gd`; baca `metadata` jendela (`windows`, `events`) di gameplay.
5. (Rig VRM 0.x/1.0 sudah ada, lihat atas.) Berikutnya: CLI satu perintah, `bake` motion matching otomatis, tes regresi (Tahap 5).
6. Validator fisika/kontak lanjutan, key berbasis IK, layer aditif, mirror.

## 10. Konvensi kerja

- Skrip Godot dijalankan dengan `--headless -s <skrip>`; argumen setelah `--`. Skrip alat memakai `extends SceneTree` + `_initialize()` + `quit(kode)`.
- Pakai `preload("res://clipkit/clip_lib.gd")` (bukan `class_name`) agar tidak bergantung pada cache kelas global.
- GDScript: nilai dari `Dictionary`/JSON bertipe Variant; jangan memakai `var x := <ekspresi Variant>` (error "cannot infer type"), beri tipe eksplisit.
- Komentar dan pesan dalam Bahasa Indonesia, sesuai gaya repo.
- Setiap perubahan klip: naikkan `version` + tambah entri `changelog` (jika isi berubah) → `clip_release.py check` → build → validate (exit 0, tanpa FAIL) → export → preview → lihat gambar → `clip_release.py release <nama>` jika diterima.
- `FORMAT_VERSION` ada di dua tempat (`clip_lib.gd` dan `clipver.py`); ubah keduanya bersamaan. Port easing di `clip_diff.py` harus tetap sama dengan `ClipLib.ease_fn`.
- Jangan commit artefak sementara; `clipkit/out/` dan `clipkit/preview/` adalah hasil regenerasi.

## 11. Pembaruan: dukungan VRM 0.x / 1.0 (Tahap 4)

Selesai dan diuji: rig VRM turunan (`extends`), alias bone kanonik, urutan bone topologis, `pos_scale: auto`, bone opsional,
`--rig`/`--skeleton` di build/validate/export/demo/render_sheet, tes portabilitas. Render mesh (Xvfb) dilihat untuk `dodge`
di VRM 0.x dan `parry` di VRM 1.0: pose terbaca wajar. **Belum dinilai manusia di editor.**
Masalah terbuka: pada model VRM 1.0 sample, lengan baju (bone constraint) tampak melebar saat render software, juga dengan
animasi VRM bawaan repo; penyebab belum dibuktikan (lihat `clipkit/README.md`, Batasan). Demo di editor (Forward+) belum diuji
untuk VRM; jalankan `scenes/clipkit_demo.tscn` dengan argumen `--rig=vrm` (mis. lewat `Project > Run Arguments` atau CLI `-- --rig=vrm`).

## 12. Klip pukulan (MotusMan)

Ditambah 6 klip: `jab`, `cross`, `hook`, `uppercut`, `combo_jab_cross_hook`, `guard_idle` (kuda-kuda tinju ortodoks). Semua v1, **belum dirilis** (`clip_release.py release` menunggu penilaian manusia) dan belum dinilai manusia.
Dibuat lewat `clipkit/gen/` (lihat README di sana): pose dicari numerik terhadap target pergelangan/telapak, kaki di-bake menapak per frame.
Validator: 9 klip, 0 FAIL, 10 WARN (foot sliding rata-rata 0.09-0.13 m/s pada klip baru; kecepatan siku `jab` 1457 dan kombo 1550 °/s; penetrasi lantai klip baru <=1 cm).
Temuan: kuda-kuda terlalu panjang membuat kaki belakang lurus penuh dan tak terjangkau saat pinggul naik/berputar (uppercut menembus lantai 7 cm) -> kuda-kuda dipersingkat, lutut ditekuk lebih dalam.
Interpolasi sudut sendi antar dua pose menapak tidak menjaga telapak di lantai; solusinya bake kaki per frame. Penghalus 3-titik pada hasil bake memperburuk galat di titik balik gerakan (dimatikan).
Tanda `roll` lengan **berlawanan** antara kiri dan kanan (guard rapat: kiri roll negatif, kanan positif). Tangan masih terbuka (tanpa kepalan).
Setelah rebase ke Tahap 4 (VRM): `gen/` tetap menghasilkan klip identik dengan `clip_lib.gd` baru; enam klip ikut di-build untuk rig VRM (`clipkit/out/vrm/`, wajib oleh `test_clip_portability.gd`). Validator VRM: 0 FAIL; uji rig VRM 24/24. Pose pukulan **belum dirender dengan mesh VRM** dan VRM 1.0 belum diuji (sampel butuh `tests/fetch_vrm1_sample.sh`). Setelah mengubah klip, bangun ulang kedua rig: `clip_build.gd` dan `clip_build.gd -- --rig=vrm`.
