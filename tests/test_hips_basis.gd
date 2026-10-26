extends SceneTree

func _initialize():
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")
	var ap: AnimationPlayer = inst.get_node("MotusMan_v55/AnimationPlayer")

	var at: AnimationTree = inst.get_node("MotusMan_v55/AnimationTree")
	at.active = false

	ap.play("motus_motion_library/Transitions_Sprint_to_Run_Straight")
	ap.seek(11.0, true)

	var hips_idx = sk.find_bone("Hips")
	var gp = sk.get_bone_global_pose(hips_idx)
	print("Hips global pose basis:")
	print("  basis X: ", gp.basis.x)
	print("  basis Y: ", gp.basis.y)
	print("  basis Z: ", gp.basis.z)
	print("  basis euler: ", gp.basis.get_euler() * 180.0 / PI)

	quit(0)
