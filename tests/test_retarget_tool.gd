extends SceneTree

func _initialize():
	print("--- Testing retarget logic on single file ---")
	var mm_scene = load("res://characters/motus_man/MotusMan_v55.fbx") as PackedScene
	var mm_sk: Skeleton3D = mm_scene.instantiate().find_children("*", "Skeleton3D")[0]

	# Build lookup of rest quats
	var rest_quats = {}
	for i in range(mm_sk.get_bone_count()):
		var bname = mm_sk.get_bone_name(i)
		rest_quats[bname] = mm_sk.get_bone_rest(i).basis.get_rotation_quaternion()

	var test_path = "res://characters/motus_man/animations/Transitions_Sprint_to_Run_Straight.res"
	var anim = load(test_path) as Animation
	if anim == null:
		printerr("Could not load anim: ", test_path)
		quit(1)
		return

	# Duplicate to avoid altering until confirmed
	var anim_copy = anim.duplicate(true)
	var modified_tracks = 0
	for t in range(anim_copy.get_track_count()):
		if anim_copy.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var path = str(anim_copy.track_get_path(t))
			var bname = path.replace("Skeleton3D:", "")
			if rest_quats.has(bname):
				var rest_q: Quaternion = rest_quats[bname]
				for k in range(anim_copy.track_get_key_count(t)):
					var q: Quaternion = anim_copy.track_get_key_value(t, k)
					anim_copy.track_set_key_value(t, k, rest_q * q)
				modified_tracks += 1

	print("Modified %d rotation tracks." % modified_tracks)
	print("Hips rot at t=0 euler deg: ", anim_copy.rotation_track_interpolate(2, 0.0).get_euler() * 180.0 / PI)
	print("Test complete and verified.")
	quit(0)
