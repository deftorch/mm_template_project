# Design Doc: Pipeline Animasi Berbasis Teks untuk Godot

| | |
|---|---|
| **Status** | Draft / usulan (belum ada yang dibangun atau diuji utuh) |
| **Tanggal** | 27 Oktober 2026 |
| **Target engine** | Godot 4.x (cek versi untuk `SpringBoneSimulator3D`, `LookAtModifier3D`) |
| **Karakter awal** | MotusMan |
| **Sumber ide** | Analisis file stickman three.js (±2000 baris, 27 klip) dan diskusi retarget Motorica |

---

## 1. Latar Belakang

AI (LLM) kuat dalam menulis dan mengubah teks terstruktur, tetapi lemah pada animasi karena tiga hambatan:

1. **Data animasi sulit disentuh.** Ratusan key rotasi per bone tidak praktis disunting lewat teks.
2. **Tidak ada pengukur kualitas.** Tanpa metrik, kesalahan halus (lonjakan kecepatan, foot sliding) tidak terdeteksi.
3. **Tidak ada "mata".** Mesin tidak bisa menilai tampilan hasil tanpa render.

File stickman membuktikan sebagian solusinya: klip ditulis sebagai data JSON (channel, keyframe, easing, event, jendela gameplay), lalu engine-nya dijalankan di Node dan diukur secara numerik. Hasilnya, ditemukan lonjakan kecepatan putar `flip` di klip `roll` v2 (rata-rata ±8 rad/s, puncak ±33 rad/s, sekitar 31° per frame pada 60 fps).

## 2. Tujuan dan Non-Tujuan

### Tujuan
- Klip animasi menjadi **teks yang bisa ditulis, dijalankan, diukur, dan dilihat**.
- Perubahan animasi berupa edit beberapa angka, bukan menyunting ratusan key.
- Validasi otomatis sehingga perbaikan bisa diulang tanpa penilaian visual manual di tiap iterasi.
- Klip portabel antar karakter lewat rig abstrak.
- Semua langkah bisa dipanggil lewat perintah skrip dengan keluaran teks.

### Non-Tujuan
- Menggantikan mocap atau animator untuk karakter realistis.
- Menjamin gerakan "menarik". Metrik hanya menjamin gerakan **benar**. Penilaian estetika tetap oleh manusia.
- Meniru model AI terlatih milik Cascadeur (AutoPosing/AutoPhysics) dengan kualitas setara.

## 3. Prinsip Desain

1. **Teks sebagai sumber kebenaran.** Data klip di git, diff dan riwayat versi gratis.
2. **Skrip-first.** Tidak ada langkah yang hanya bisa dilakukan lewat GUI.
3. **Deterministik.** Input sama menghasilkan keluaran sama, agar tes regresi bisa dipercaya.
4. **Channel bermakna.** `lean`, `hip_height`, `arm_swing`, `flip`, bukan rotasi mentah per bone.
5. **Fisika sebagai pemeriksa.** Cek berbasis angka (pusat massa, kontak, penetrasi), bukan sekadar efek.
6. **Kontrol sedikit, hasil banyak.** Tentukan tujuan, biarkan solver mengisi detail.
7. **Lapisan aditif.** Pisahkan gerakan dasar dari penyesuaian agar iterasi aman.

## 4. Arsitektur

```
 clip.json ──► [build] ──► Animation (.tres)  ──► AnimationPlayer/Tree
    │                │
    │                └── memakai ──► rig_map (channel → bone, per skeleton)
    │
    ├──► [validate] ──► laporan metrik (teks/JSON)
    ├──► [preview]  ──► contact sheet (PNG)
    └──► [bake]     ──► library motion matching
```

| Komponen | Peran |
|---|---|
| **Clip Format** | Data klip: channel, keyframe, event, jendela, root motion, metadata |
| **Generator** | Mengubah klip menjadi `Animation` Godot |
| **Rig Abstrak / Bone Map** | Memetakan channel ke bone, divalidasi sekali per skeleton |
| **Validator** | Laporan metrik headless per klip |
| **Previewer** | Contact sheet dan overlay untuk penilaian visual |
| **CLI** | `build`, `validate`, `preview`, `bake` |

## 5. Format Klip

Elemen yang didukung:

- **Channel** bermakna dengan keyframe `[waktu, nilai, easing]`.
- **Event** (suara, efek) dan **jendela gameplay**: `inv`, `guard`, `parry`, `cancel`, `hitbox_on`, `holdAt`.
- **`move`**: root motion per klip (mode `script` atau `free`).
- **Metadata**: nama, grup, tag, versi.
- **(Lanjutan)** key berbasis tujuan (`goal`) yang diselesaikan IK.

### Contoh draf: `dodge`

> Ilustrasi struktur. Nilai angka belum divalidasi dan hanya contoh.

```json
{
  "name": "dodge",
  "version": 1,
  "group": "locomotion",
  "tags": ["defense", "i-frame"],
  "duration": 0.6,
  "channels": {
    "lean":       [[0.00, 0.0, "linear"], [0.10, -0.35, "outQuad"], [0.45, -0.10, "inOutSine"], [0.60, 0.0, "outBack"]],
    "hip_height": [[0.00, 1.00, "linear"], [0.15, 0.70, "outQuad"], [0.60, 1.00, "inOutSine"]]
  },
  "goals": [
    { "t": 0.40, "foot_L": "plant(x,z)", "hips": "height(0.55)" }
  ],
  "windows": {
    "inv":    [0.10, 0.23],
    "cancel": [0.45, 0.60]
  },
  "events": [
    { "t": 0.05, "type": "sfx", "id": "whoosh" },
    { "t": 0.25, "type": "vfx", "id": "dust" }
  ],
  "move": { "mode": "free", "distance": 2.5 }
}
```

Catatan: `inv` pada contoh adalah detik untuk keterbacaan. Dokumen asli menyebut i-frame sebagai frame 6–14; tentukan satuan tunggal (detik atau frame) sebelum implementasi.

## 6. Rig Abstrak

- Satu **bone map** per skeleton: channel → bone beserta sumbu dan faktor skala.
- **Rest-alignment** divalidasi sekali per skeleton. Ini mencegah kelas bug retarget yang menimpa klip Motorica (frame rest berbeda).
- Konvensi karakter (arah hadap, satuan, nama bone) dicatat di README per karakter.
- Pembuktian portabilitas: klip yang sama dipasang ke karakter kedua (mis. VRM).

## 7. Validator

Laporan per klip, dijalankan headless:

| Kategori | Yang diperiksa |
|---|---|
| **Kontinuitas** | Pose awal dan akhir cocok; loncatan per frame |
| **Kinematika** | Kecepatan dan percepatan sudut maksimum per channel (deteksi gerakan menyentak) |
| **Batas anatomi** | Lutut tidak terbalik; bahu dan leher dalam rentang wajar |
| **Kontak** | Foot sliding; kaki menembus lantai |
| **Klaim data** | Jarak dan durasi sesuai metadata (mis. dodge 2.5 m) |
| **Event/jendela** | Tidak tumpang tindih salah; `cancel` setelah `active` |
| **(Lanjutan) Fisika** | Lintasan pusat massa saat melayang (parabola); penetrasi kolisi |

Toleransi per metrik ditentukan oleh keputusan gaya (bagian 10).

## 8. Preview ("Mata" untuk AI)

- **Contact sheet:** render pose tiap N frame dalam satu gambar dari beberapa sudut.
- **Overlay:** lintasan kaki/tangan, kurva channel, penanda event dan jendela.
- **Perbandingan versi:** dua versi klip berdampingan.

**Risiko:** Godot `--headless` tidak merender gambar. Opsi: Xvfb dengan render software, atau mesin render sederhana yang mengekspor frame. **Belum dicoba**, verifikasi di lingkungan Anda lebih dulu.

## 9. Fitur Lanjutan (setelah dasar terbukti)

| Fitur | Pendekatan di Godot | Kelayakan |
|---|---|---|
| Key berbasis tujuan (AutoPosing-lite) | IK diselesaikan di generator | Sedang |
| Arah pandang | `LookAtModifier3D` | Mudah |
| Secondary motion | `SpringBoneSimulator3D` (Godot 4.4+, cek versi) | Mudah |
| Rotation smoothing | Filter pada kurva channel | Mudah |
| Layer aditif | `Add2`/`Blend2` berfilter di `AnimationTree` | Mudah–sedang |
| Mirror | Daftar channel yang dibalik | Mudah |
| Penetration cleaning | Raycast/cek bentuk per frame lalu dorong keluar | Mudah–sedang |
| Parameter prinsip animasi | Anticipation, overshoot (`outBack`), squash/stretch, eksagerasi global | Mudah |
| AI inbetweening/AutoPhysics | Tidak ditiru. Alternatif: pakai Cascadeur lalu ekspor GLB/FBX | Sulit |

## 10. Keputusan Terbuka

1. **Gaya:** realistis, stilisasi, atau eksagerasi? Menentukan default parameter dan toleransi metrik.
2. **Format:** JSON atau `.tres` teks?
3. **Satuan waktu:** detik atau frame untuk jendela gameplay?
4. **Cascadeur:** tiru fiturnya atau masukkan ke pipeline? Perlu cek lisensi/biaya (Pro $49/bulan atau $396/tahun menurut sumber) dan apakah Python API bisa dipanggil headless.
5. **Lisensi data:** untuk model/data AI pihak ketiga pada game komersial.

## 11. Rencana Bertahap

| Tahap | Isi | Kriteria selesai |
|---|---|---|
| **1** | Format klip + generator, 1 karakter, ~3 klip (`attack`, `dodge` dengan `inv`, `parry`) | Klip terbentuk jadi `Animation` dan bisa diputar |
| **2** | Skrip validasi + laporan metrik | Laporan terbaca mesin; bug sengaja (mis. lonjakan) terdeteksi |
| **3** | Contact sheet | Gambar dihasilkan di lingkungan target |
| **4** | Rig abstrak ke karakter kedua | Klip sama tampil benar di dua skeleton |
| **5** | CLI lengkap, bake motion matching otomatis, tes regresi di CI | Satu perintah membangun dan memvalidasi semua klip |

**Langkah pertama paling murah (pilih salah satu):**
- (a) Format JSON + generator + validator untuk satu klip `dodge` pada MotusMan.
- (b) Validator kontak kaki dan penetrasi untuk klip Motorica hasil retarget (data sudah ada, hasil langsung terukur).

## 12. Kebutuhan

- Akses ke project dan Godot yang bisa dijalankan.
- Karakter target beserta konvensinya di README.
- Keputusan gaya.
- Masukan visual dari manusia setelah tiap iterasi.

## 13. Risiko dan Batasan

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Preview tidak bisa dirender headless | AI tidak bisa menilai visual | Uji Xvfb/render software sejak Tahap 3 |
| Pose benar tetapi tidak menarik | Animasi terasa kaku | Penilaian visual manusia tiap iterasi; parameter prinsip animasi |
| Validator menyembunyikan kesalahan | Pose lolos tetapi salah | Gabungkan beberapa metrik; tinjau visual |
| Bug rest-frame saat retarget | Pose salah di karakter lain | Validasi bone map sekali per skeleton |
| Kualitas IK di bawah model AI | Pose kurang natural | Terima batasan, atau pakai Cascadeur |
| Lisensi data/alat | Masalah pada rilis komersial | Cek sebelum dipakai |

## 14. Kriteria Keberhasilan

- Satu perintah membangun dan memvalidasi seluruh klip.
- Memperbaiki satu masalah (mis. lonjakan kecepatan) cukup dengan mengubah beberapa angka lalu mengukur ulang.
- Klip yang sama berjalan di minimal dua skeleton tanpa bug rest-frame.
- Perubahan klip bisa ditinjau lewat diff git.
