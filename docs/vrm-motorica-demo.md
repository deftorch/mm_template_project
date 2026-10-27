# Motorica pada karakter VRM + demo perbandingan dataset

Dokumen ini menjelaskan cara 252 klip Motorica dipakai pada `three-vrm-girl`, cara menjalankan
demo perbandingan (animasi O3DE sebelumnya vs Motorica), dan apa saja yang bisa dikonfigurasi.

## Menjalankan demo
Buka `scenes/vrm_dataset_demo.tscn` lalu F6 (atau `godot --path . scenes/vrm_dataset_demo.tscn`).
Default: 2 karakter, A = O3DE, B = Motorica, input sama untuk keduanya.

| Kontrol | Fungsi |
|---|---|
| WASD / Shift / Ctrl | jalan-lari / sprint / jalan pelan |
| klik kanan (tahan) | strafe (menghadap kamera) |
| Spasi, R | lompat, reset posisi |
| F2 | skenario otomatis identik untuk semua karakter (diam, jalan, lari, sprint, belok, strafe) |
| F3 | eksplorasi acak (seed tetap) - menjangkau lebih banyak klip |
| 1 / 2 / 3 | pilih slot aktif |
| F1, Esc | sembunyikan panel, lepas mouse |

Tab panel: **Konfigurasi** (dataset + parameter per slot), **Klip** (putar langsung klip apa pun,
tur otomatis semua klip), **Cakupan** (klip Motorica yang pernah dipilih MM), **Bantuan**.

## Yang perlu dikonfigurasi sendiri untuk membandingkan
Per slot (A/B/C) di tab Konfigurasi:
- **Dataset**: O3DE (22 klip) atau Motorica (252 klip). Membandingkan KONFIGURASI: pilih dataset yang sama di
  dua slot lalu beri preset/nilai berbeda.
- `MMAnimationNode`: `query_frequency`, `transition_halflife`, `blending_enabled`.
- `MMCharacter`: `halflife`, `history_delta_time`, `trajectory_delta_time`, `check_environment`.
- Synchronizer: Mix (`root_motion_amount`), Clamp (`clamp_distance`), RootMotion.
- Kecepatan input jalan/lari/sprint. Default O3DE 1.5/3.0/3.8 m/s; Motorica-VRM 1.05/3.1/4.6 m/s
  (median `path_speed` klip forward pada `animation/motorica_vrm_catalog.json`).
- Tombol "Salin config (JSON)" mengekspor semua pengaturan untuk dicatat.

Catatan: tiap karakter harus punya `MMAnimationNode` sendiri. `tree_root.duplicate(true)` TIDAK
menggandakan node di dalamnya, sehingga dua karakter saling menimpa properti `library`.
Demo membangun ulang blend tree per slot.

## Membuat ulang aset (urutan)
```
godot --headless --path . --import
godot --headless --path . -s tools/retarget_motorica_to_vrm.gd        # 252 .res + katalog JSON (~50 dtk)
godot --headless --path . -s tools/build_vrm_motorica_library.gd      # library tanpa data bake
GODOT=godot tools/bake_vrm_motorica.sh                                # bake lewat editor di Xvfb (~2 dtk)
git checkout project.godot animation/vrm_motion_library.tres          # editor menyentuh file ini
```
Bake: tombol "Bake" MMEditor membake library yang DIPILIH di dropdown di sebelahnya (default library pertama
di AnimationPlayer, yaitu O3DE). `tools/bake_library_editor.gd` memilih library lewat nama file.
Library harus terpasang di AnimationPlayer karakter (sudah, di `three_vrm_girl.tscn`).
Opsi retarget: `--spine=low|mid_top|mid_top3`, `--root-scale=auto|<angka>`, `--only=<NamaKlip>`, `--out=<dir>`.

## Keputusan retarget
- Rumus rotasi sama dengan retarget Motus (world-space delta + koreksi arah rest), tetapi FK memakai urutan
  topologis karena urutan bone VRM tidak parent-dulu.
- Spine: Motorica 5 tulang -> VRM 3. `mid_top` (Chest<-Spine2, UpperChest<-Spine4) terbaik: selisih arah
  segmen rata-rata 0,21 derajat (`low` 0,69; lengan dan kaki 0,00).
- Pinggul dan root motion diskalakan 0,9176 (rasio tinggi pinggul-ke-pergelangan). Uji skala 0,80-1,0 dengan
  `tools/clip_validate.gd` tidak menemukan nilai yang jelas lebih baik.
- Rotasi Root (yaw saat berbelok, ada di 140 klip) disalin apa adanya.

## Tes
```
godot --headless --fixed-fps 60 --path . -s tests/test_vrm_dataset_demo.gd            # ~1 menit
godot --headless --path . -s tests/eval_vrm_retarget.gd -- --clips=Idle_Loop --modes=low,mid_top
godot --headless --path . -s tools/clip_validate.gd -- --rig=vrm --style=realistic <klip.res|folder>
xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --fixed-fps 30 \
   -s tests/render_vrm_demo.gd -- --out=/tmp/shot                                      # tangkapan layar
```

## Hasil terukur dan batasannya
- Retarget: 252/252 klip. Database: 252/252 klip ada (22.222 sampel).
- `test_vrm_dataset_demo.gd`: lulus. Sapuan 274 klip lewat browser: pose valid, tinggi pinggul 0,45-1,35 m, klip
  benar-benar diputar. Ini BUKAN penilaian kualitas visual.
- Cakupan MM: skenario tetap menjangkau 105/252 klip (~4 menit), eksplorasi acak 184/252 (10 menit simulasi). MM hanya
  memilih klip yang paling cocok; sisanya dapat diputar lewat tab Klip. `Idle_Loop` tidak pernah dipilih MM saat diam
  (klip turn_in_place yang terpilih).
- `clip_validate.gd`: peringatan kecepatan sudut kaki sama dengan versi MotusMan (sifat data mocap), foot sliding VRM
  30-75% lebih tinggi dari Motus (kemungkinan karena proporsi tubuh; belum dibuktikan). Penetrasi lantai sampai 2-3 cm
  pada klip belok.
- Belum diperiksa manusia: kualitas gerak terlihat (kaki, lengan, kepala) pada proporsi VRM.
- Model VRM 1.0 tanpa `UpperChest` belum didukung oleh tool retarget.
