# clipkit/gen: pembuat klip pukulan (pose dicari numerik)

Klip `jab`, `cross`, `hook`, `uppercut`, `combo_jab_cross_hook`, `guard_idle` dibuat dengan alat ini. Angka di `clips/*.json` hasil pencarian,
jadi ubah koreografi di sini lalu hasilkan ulang, jangan menyunting angka satu per satu.

```bash
python3 clipkit/gen/poses.py        # ~20 s: cari pose kunci -> gen/solved.json (lengan: pergelangan ke target relatif kepala; kaki: ujung telapak ke titik lantai)
python3 clipkit/gen/make_clips.py   # ~1 mnt: rakit timeline, bake kaki menapak per frame -> clips/*.json   (argumen: nama klip tertentu)
godot --headless --path . -s tools/clip_build.gd && godot --headless --path . -s tools/clip_validate.gd
```
Env `GODOT` menunjuk binary Godot bila tidak ada di PATH/`~/bin/godot`. Hasil deterministik (seed tetap): dijalankan ulang menghasilkan JSON identik.

- `sample.gd`: evaluasi ribuan pose konstan di Godot (memakai `ClipLib.eval_pose` + `anim_pose`), keluaran posisi sendi. `kin.py` jembatan Python.
- `solve.py`: pencarian acak -> halus per anggota gerak. Biaya dihitung dari posisi sendi hasil Godot, bukan model matematika terpisah.
- `poses.py`: kuda-kuda, 10 pose kunci, target tangan/kaki. `make_clips.py`: timing, easing, jendela, event. `plant.py`: bake kaki per frame.

Batasan: tangan terbuka (tanpa kepalan); jab/cross mentok jangkauan lengan (3-6 cm di bawah target); `hip_twist` memutar kaki sehingga pivot hanya didekati lewat posisi telapak (tanpa channel yaw kaki);
kaki di-bake per frame (kunci rapat, kurang enak disunting tangan). Belum dinilai manusia.
