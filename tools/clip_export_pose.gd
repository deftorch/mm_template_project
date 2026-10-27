extends SceneTree
## Ekspor posisi sendi per frame (frame model, termasuk root motion) ke JSON untuk preview.
##
##   godot --headless --path . -s tools/clip_export_pose.gd -- [<file.res|dir> ...]
## Default: semua di res://clipkit/out/. Keluaran: clipkit/preview/<nama>.pose.json
## Lalu render dengan:  python3 clipkit/preview.py clipkit/preview/<nama>.pose.json

const ClipLib := preload("res://clipkit/clip_lib.gd")
const OUT_DIR := "res://clipkit/preview/"

func _initialize() -> void:
	var targets: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			targets.append(a)
	if targets.is_empty():
		targets.append("res://clipkit/out/")
	var rig := ClipLib.load_rig()
	var sk := ClipLib.load_skeleton(rig)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var names: Array = rig["animated_bones"]
	var idx: Array = []
	var parents: Array = []
	for n in names:
		idx.append(sk.find_bone(n))
	for i in idx:
		var p := sk.get_bone_parent(i)
		parents.append(idx.find(p))  # -1 jika parent tidak ikut digambar

	var files: Array = []
	for t in targets:
		if t.ends_with(".res"):
			files.append(t)
		else:
			var d := DirAccess.open(t)
			if d != null:
				for f in d.get_files():
					if f.ends_with(".res"):
						files.append(str(t).path_join(f))
	files.sort()
	for f in files:
		var anim := load(f) as Animation
		if anim == null:
			continue
		var tracks := ClipLib.index_tracks(sk, anim)
		var frames: Array = []
		var nf := int(ceil(anim.length * ClipLib.FPS))
		for k in range(nf + 1):
			var g := ClipLib.anim_pose(sk, anim, tracks, minf(k / ClipLib.FPS, anim.length))
			var row: Array = []
			for i in idx:
				var o: Vector3 = (g[i] as Transform3D).origin
				row.append([snappedf(o.x, 0.0001), snappedf(o.y, 0.0001), snappedf(o.z, 0.0001)])
			frames.append(row)
		var name := str(anim.get_meta("clip_name", f.get_file().get_basename()))
		var out := {"name": name, "fps": ClipLib.FPS, "duration": anim.length, "bones": names, "parents": parents,
			"frames": frames, "windows": anim.get_meta("windows", {}), "events": anim.get_meta("events", [])}
		var fa := FileAccess.open(OUT_DIR + name + ".pose.json", FileAccess.WRITE)
		fa.store_string(JSON.stringify(out))
		fa.close()
		print("OK  %s  %d frame -> %s%s.pose.json" % [name, frames.size(), OUT_DIR, name])
	quit(0)
