extends SceneTree

func _initialize():
	print("Building motus_motion_library.tres ...")
	var lib = MMAnimationLibrary.new()

	# 1. Setup Features
	var traj_feat = MMTrajectoryFeature.new()
	traj_feat.set("past_frames", 0)
	traj_feat.set("future_delta_time", 0.5)
	traj_feat.set("future_frames", 4)
	traj_feat.set("facing_weight", 10.0)

	var bone_feat = MMBoneDataFeature.new()
	bone_feat.set("bone_names", PackedStringArray([
		"LeftUpLeg", "LeftLeg", "LeftFoot",
		"RightUpLeg", "RightLeg", "RightFoot"
	]))

	var feats: Array[MMFeature] = [traj_feat, bone_feat]
	lib.set("features", feats)
	lib.set("sampling_rate", 4.0)
	lib.set("include_cost_results", true)

	# 2. Add all animations from res://characters/motus_man/animations/
	var anim_dir = "res://characters/motus_man/animations/"
	var d = DirAccess.open(anim_dir)
	if d == null:
		printerr("Cannot open: ", anim_dir)
		quit(1)
		return

	var files: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".res"):
			files.append(f)
	files.sort()

	print("Found %d animation .res files." % files.size())
	for f in files:
		var anim_name = f.get_basename()
		var anim = load(anim_dir + f) as Animation
		if anim != null:
			lib.add_animation(anim_name, anim)
		else:
			printerr("Failed to load: ", anim_dir + f)

	var out_path = "res://characters/motus_man/motus_motion_library.tres"
	var err = ResourceSaver.save(lib, out_path)
	print("Saved %s with %d animations! Result: %d" % [out_path, files.size(), err])
	quit(0)
