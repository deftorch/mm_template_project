extends SceneTree

func _initialize():
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")
	var ap: AnimationPlayer = inst.get_node("MotusMan_v55/AnimationPlayer")

	# Stop AnimationTree from overriding
	var at: AnimationTree = inst.get_node("MotusMan_v55/AnimationTree")
	at.active = false

	# Play Transitions_Sprint_to_Run_Straight
	ap.play("motus_motion_library/Transitions_Sprint_to_Run_Straight")
	ap.seek(11.0, true)

	var hips_idx = sk.find_bone("Hips")
	var head_idx = sk.find_bone("Head")
	var foot_idx = sk.find_bone("LeftFoot")

	print("\n--- Direct AnimationPlayer at t=11.0 ---")
	print("Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)

	# Print mesh bounds or global vertex positions if possible
	var mesh_inst: MeshInstance3D = inst.get_node("MotusMan_v55/Skeleton3D/MotusMan_v55")
	print("MeshInstance3D global transform: ", mesh_inst.global_transform)
	print("Skeleton3D global transform: ", sk.global_transform)

	quit(0)
