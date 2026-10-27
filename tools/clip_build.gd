extends SceneTree
## Bangun Animation Godot dari klip JSON.
##
##   godot --headless --path . -s tools/clip_build.gd                      # semua klip di clipkit/clips/
##   godot --headless --path . -s tools/clip_build.gd -- --only=dodge      # satu klip
##   godot --headless --path . -s tools/clip_build.gd -- --dir=res://x/    # direktori lain
##
## Keluaran: res://clipkit/out/<nama>.res (bisa dimuat langsung ke AnimationLibrary).
## Exit code 1 jika ada klip yang gagal dibangun.

const ClipLib := preload("res://clipkit/clip_lib.gd")
const OUT_DIR := "res://clipkit/out/"

func _initialize() -> void:
	var only := ""
	var dir := "res://clipkit/clips/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--dir="):
			dir = a.substr(6)
	var rig := ClipLib.load_rig()
	var sk := ClipLib.load_skeleton(rig)
	var ctx := ClipLib.make_ctx(sk, rig)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var failed := 0
	var built := 0
	for path in ClipLib.load_clips(dir):
		var clip = ClipLib.read_json(path)
		if not (clip is Dictionary) or not clip.has("name") or not clip.has("duration"):
			printerr("GAGAL  %s: JSON tidak valid (butuh name, duration)" % path)
			failed += 1
			continue
		if only != "" and clip["name"] != only:
			continue
		if int(clip.get("format_version", 1)) > ClipLib.FORMAT_VERSION:
			printerr("GAGAL  %s: format_version %d lebih baru dari yang didukung (%d); perbarui clip_lib.gd" % [clip["name"], int(clip["format_version"]), ClipLib.FORMAT_VERSION])
			failed += 1
			continue
		var warns := ClipLib.check_channel_ranges(rig, clip)
		if not clip.has("format_version"):
			warns.append("format_version belum ada, dianggap %d" % ClipLib.FORMAT_VERSION)
		for vi in ClipLib.version_issues(clip.get("version", 1), clip.get("changelog", null), clip.get("format_version", 1)):
			if vi[0] != "PASS":
				warns.append(str(vi[1]))
		var anim := ClipLib.build_animation(sk, rig, ctx, clip)
		var save_path: String = OUT_DIR + str(clip["name"]) + ".res"
		if ResourceSaver.save(anim, save_path) != OK:
			printerr("GAGAL  simpan %s" % save_path)
			failed += 1
			continue
		built += 1
		print("OK     %-12s %.2fs  %d track  -> %s" % [clip["name"], anim.length, anim.get_track_count(), save_path])
		for w in warns:
			print("  PERINGATAN: ", w)
	print("Selesai: %d dibangun, %d gagal." % [built, failed])
	quit(1 if failed > 0 else 0)
