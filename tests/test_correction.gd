extends SceneTree

func _initialize():
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")
	var ap: AnimationPlayer = inst.get_node("MotusMan_v55/AnimationPlayer")

	var at: AnimationTree = inst.get_node("MotusMan_v55/AnimationTree")
	at.active = false

	# Play Transitions_Sprint_to_Run_Straight at t=11.0
	ap.play("motus_motion_library/Transitions_Sprint_to_Run_Straight")
	ap.seek(11.0, true)

	var hips_idx = sk.find_bone("Hips")
	var head_idx = sk.find_bone("Head")
	var foot_idx = sk.find_bone("LeftFoot")
	var anim_hips_rot = sk.get_bone_pose_rotation(hips_idx)
	var rest_hips_quat = sk.get_bone_rest(hips_idx).basis.get_rotation_quaternion()

	print("Before correction at t=11.0:")
	print("  Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("  Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("  LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)

	# Apply correction to Hips
	sk.set_bone_pose_rotation(hips_idx, anim_hips_rot * rest_hips_quat)
	sk.force_update_bone_child_transform(hips_idx)

	print("\nAfter Hips correction (anim_quat * rest_quat):")
	print("  Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("  Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("  LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)

	# Try other order
	sk.set_bone_pose_rotation(hips_idx, rest_hips_quat * anim_hips_rot)
	sk.force_update_bone_child_transform(hips_idx)

	print("\nAfter Hips correction (rest_quat * anim_quat):")
	print("  Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("  Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("  LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)

	quit(0)
