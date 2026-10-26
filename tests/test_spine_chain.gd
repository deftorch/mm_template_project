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

	var bones_to_check = ["Root", "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]
	print("--- Bone Hierarchy at t=11.0 ---")
	for b in bones_to_check:
		var idx = sk.find_bone(b)
		if idx != -1:
			var parent_idx = sk.get_bone_parent(idx)
			var parent_name = sk.get_bone_name(parent_idx) if parent_idx != -1 else "None"
			var gp = sk.get_bone_global_pose(idx)
			var rest = sk.get_bone_rest(idx)
			var pose = sk.get_bone_pose(idx)
			print("Bone: %s (parent: %s)" % [b, parent_name])
			print("  rest origin: ", rest.origin, " basis X: ", rest.basis.x)
			print("  pose rot deg: ", sk.get_bone_pose_rotation(idx).get_euler() * 180.0 / PI)
			print("  global pose origin: ", gp.origin)

	quit(0)
