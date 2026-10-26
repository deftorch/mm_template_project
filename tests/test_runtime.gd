extends SceneTree

func _initialize():
	# Load main_motus_man scene
	var scene = load("res://scenes/main_motus_man.tscn") as PackedScene
	var inst = scene.instantiate()
	get_root().add_child(inst)

	# Let process run a few frames
	for frame in range(15):
		await process_frame

	var char = inst.get_node("MotusMan")
	var sk: Skeleton3D = char.get_node("MotusMan_v55/Skeleton3D")

	print("\n--- Runtime check after 15 frames ---")
	print("char global pos: ", char.global_position)
	var head_idx = sk.find_bone("Head")
	var hips_idx = sk.find_bone("Hips")
	var foot_idx = sk.find_bone("LeftFoot")
	print("Hips global pose: ", sk.get_bone_global_pose(hips_idx).origin)
	print("Head global pose: ", sk.get_bone_global_pose(head_idx).origin)
	print("LeftFoot global pose: ", sk.get_bone_global_pose(foot_idx).origin)
	print("Hips pose rot deg: ", sk.get_bone_pose_rotation(hips_idx).get_euler() * 180.0 / PI)
	print("Spine pose rot deg: ", sk.get_bone_pose_rotation(sk.find_bone("Spine")).get_euler() * 180.0 / PI)
	print("LeftUpLeg pose rot deg: ", sk.get_bone_pose_rotation(sk.find_bone("LeftUpLeg")).get_euler() * 180.0 / PI)

	quit(0)
