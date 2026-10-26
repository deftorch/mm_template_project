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

	# Adjust all rotation tracks: new_rot = rest_quat * anim_rot (or anim_rot * rest_quat)
	var anim_retargeted = anim.duplicate(true)
	for i in range(anim_retargeted.get_track_count()):
		if anim_retargeted.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var path = str(anim_retargeted.track_get_path(i))
			var bname = path.replace("Skeleton3D:", "")
			var bidx = sk.find_bone(bname)
			if bidx != -1:
				var rest_q = sk.get_bone_rest(bidx).basis.get_rotation_quaternion()
				for k in range(anim_retargeted.track_get_key_count(i)):
					var q = anim_retargeted.track_get_key_value(i, k)
					anim_retargeted.track_set_key_value(i, k, rest_q * q)

	var lib = AnimationLibrary.new()
	lib.add_animation("retargeted", anim_retargeted)
	ap.add_animation_library("retarget", lib)
	ap.play("retarget/retargeted")
	ap.seek(11.0, true)

	print("--- All Bones Retargeted (rest_q * q) at t=11.0 ---")
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("LeftFoot global pose: ", sk.get_bone_global_pose(l_foot_idx).origin)
	print("RightFoot global pose: ", sk.get_bone_global_pose(r_foot_idx).origin)

	# Now test (q * rest_q)
	var anim_retargeted2 = anim.duplicate(true)
	for i in range(anim_retargeted2.get_track_count()):
		if anim_retargeted2.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var path = str(anim_retargeted2.track_get_path(i))
			var bname = path.replace("Skeleton3D:", "")
			var bidx = sk.find_bone(bname)
			if bidx != -1:
				var rest_q = sk.get_bone_rest(bidx).basis.get_rotation_quaternion()
				for k in range(anim_retargeted2.track_get_key_count(i)):
					var q = anim_retargeted2.track_get_key_value(i, k)
					anim_retargeted2.track_set_key_value(i, k, q * rest_q)

	var lib2 = AnimationLibrary.new()
	lib2.add_animation("retargeted2", anim_retargeted2)
	ap.add_animation_library("retarget2", lib2)
	ap.play("retarget2/retargeted2")
	ap.seek(11.0, true)

	print("\n--- All Bones Retargeted (q * rest_q) at t=11.0 ---")
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("LeftFoot global pose: ", sk.get_bone_global_pose(l_foot_idx).origin)
	print("RightFoot global pose: ", sk.get_bone_global_pose(r_foot_idx).origin)

	quit(0)
