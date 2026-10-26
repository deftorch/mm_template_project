extends SceneTree

func _initialize():
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")
	var ap: AnimationPlayer = inst.get_node("MotusMan_v55/AnimationPlayer")
	var at: AnimationTree = inst.get_node("MotusMan_v55/AnimationTree")
	at.active = false

	var r_foot_idx = sk.find_bone("RightFoot")
	var l_foot_idx = sk.find_bone("LeftFoot")
	var head_idx = sk.find_bone("Head")

	var anim = load("res://characters/motus_man/animations/Transitions_Sprint_to_Run_Straight.res").duplicate(true) as Animation

	# Check RightFoot position in Test 1
	var hips_track = -1
	for i in range(anim.get_track_count()):
		if str(anim.track_get_path(i)) == "Skeleton3D:Hips" and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			hips_track = i
			break

	var rest_quat = sk.get_bone_rest(sk.find_bone("Hips")).basis.get_rotation_quaternion()
	var anim1 = anim.duplicate(true)
	for k in range(anim1.track_get_key_count(hips_track)):
		var q = anim1.track_get_key_value(hips_track, k)
		anim1.track_set_key_value(hips_track, k, q * rest_quat)

	var lib1 = AnimationLibrary.new()
	lib1.add_animation("test1", anim1)
	ap.add_animation_library("t1", lib1)
	ap.play("t1/test1")
	ap.seek(11.0, true)

	print("LeftFoot global pose: ", sk.get_bone_global_pose(l_foot_idx).origin)
	print("RightFoot global pose: ", sk.get_bone_global_pose(r_foot_idx).origin)
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)

	quit(0)
