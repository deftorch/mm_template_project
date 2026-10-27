extends SceneTree
## Bangun animation/vrm_motorica_library.tres dari semua klip di animation/animations/motorica_vrm/.
## Fitur sama persis dengan vrm_motion_library.tres (O3DE) supaya perbandingan dataset adil:
## trajectory 4 x 0.5 dtk + 6 tulang kaki, sampling 4 Hz.
## Database MM (motion_data dst.) baru terisi setelah "Bake": tools/bake_vrm_motorica.sh
## Opsi: -- --out=res://animation/x.tres --filter=Walk,Idle (hanya klip yang namanya mengandung salah satu kata)
const IN_DIR := "res://animation/animations/motorica_vrm/"

func _initialize() -> void:
	var out_path := "res://animation/vrm_motorica_library.tres"
	var filters: PackedStringArray = PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--filter="):
			filters = a.substr(9).split(",")
	var lib := MMAnimationLibrary.new()
	var traj := MMTrajectoryFeature.new()
	traj.set("past_frames", 0)
	traj.set("future_delta_time", 0.5)
	traj.set("future_frames", 4)
	traj.set("facing_weight", 10.0)
	var bone := MMBoneDataFeature.new()
	bone.set("bone_names", PackedStringArray(["LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot"]))
	var feats: Array[MMFeature] = [traj, bone]
	lib.set("features", feats)
	lib.set("sampling_rate", 4.0)
	lib.set("include_cost_results", true)
	var d := DirAccess.open(IN_DIR)
	if d == null:
		printerr("Tidak bisa membuka ", IN_DIR)
		quit(1)
		return
	var files: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".res"):
			var keep := filters.is_empty()
			for w in filters:
				if f.contains(w):
					keep = true
			if keep:
				files.append(f)
	files.sort()
	for f in files:
		var anim := load(IN_DIR + f) as Animation
		if anim == null:
			printerr("Gagal memuat ", f)
			continue
		lib.add_animation(f.get_basename(), anim)
	var err := ResourceSaver.save(lib, out_path)
	print("Library tersimpan: %s (%d klip) hasil=%d" % [out_path, files.size(), err])
	quit(0 if err == OK else 1)
