extends SceneTree

func _initialize():
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")
	var ap: AnimationPlayer = inst.get_node("MotusMan_v55/AnimationPlayer")
	var at: AnimationTree = inst.get_node("MotusMan_v55/AnimationTree")
	at.active = false

	var hips_idx = sk.find_bone("Hips")
	var head_idx = sk.find_bone("Head")
	var foot_idx = sk.find_bone("LeftFoot")
	var rest_quat = sk.get_bone_rest(hips_idx).basis.get_rotation_quaternion()

	var anim = load("res://characters/motus_man/animations/Transitions_Sprint_to_Run_Straight.res").duplicate(true) as Animation

	# Find Hips rotation track
	var hips_track = -1
	for i in range(anim.get_track_count()):
		if str(anim.track_get_path(i)) == "Skeleton3D:Hips" and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			hips_track = i
			break

	print("Hips track found: ", hips_track)

	# Test 1: key_rot * rest_quat
	var anim1 = anim.duplicate(true)
	for k in range(anim1.track_get_key_count(hips_track)):
		var q = anim1.track_get_key_value(hips_track, k)
		anim1.track_set_key_value(hips_track, k, q * rest_quat)

	var lib1 = AnimationLibrary.new()
	lib1.add_animation("test1", anim1)
	ap.add_animation_library("t1", lib1)
	ap.play("t1/test1")
	ap.seek(11.0, true)

	print("\n--- Test 1 (key_rot * rest_quat) at t=11.0 ---")
	print("Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)

	# Test 2: rest_quat * key_rot
	var anim2 = anim.duplicate(true)
	for k in range(anim2.track_get_key_count(hips_track)):
		var q = anim2.track_get_key_value(hips_track, k)
		anim2.track_set_key_value(hips_track, k, rest_quat * q)

	var lib2 = AnimationLibrary.new()
	lib2.add_animation("test2", anim2)
	ap.add_animation_library("t2", lib2)
	ap.play("t2/test2")
	ap.seek(11.0, true)

	print("\n--- Test 2 (rest_quat * key_rot) at t=11.0 ---")
	print("Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)

	quit(0)
