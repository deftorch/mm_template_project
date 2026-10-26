extends SceneTree

func _initialize():
	# Retarget Idle_Loop and Transitions_Sprint_to_Run_Straight first in-memory or save to test
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")
	var at: AnimationTree = inst.get_node("MotusMan_v55/AnimationTree")

	print("Running 30 frames with Motion Matching active...")
	for frame in range(30):
		await process_frame

	var head_idx = sk.find_bone("Head")
	var l_foot = sk.find_bone("LeftFoot")
	var r_foot = sk.find_bone("RightFoot")
	var hips = sk.find_bone("Hips")

	print("\nFrame 30 results:")
	print("  Hips: ", sk.get_bone_global_pose(hips).origin)
	print("  Head: ", sk.get_bone_global_pose(head_idx).origin)
	print("  LeftFoot: ", sk.get_bone_global_pose(l_foot).origin)
	print("  RightFoot: ", sk.get_bone_global_pose(r_foot).origin)
	quit(0)
