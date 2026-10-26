extends SceneTree

func _initialize():
	var motus_scene = load("res://characters/motus_man/motus_man_character.tscn") as PackedScene
	var inst = motus_scene.instantiate()
	get_root().add_child(inst)

	var sk: Skeleton3D = inst.get_node("MotusMan_v55/Skeleton3D")

	var bones_to_check = ["Root", "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]
	print("--- REST Bone Hierarchy (NO ANIMATION) ---")
	for b in bones_to_check:
		var idx = sk.find_bone(b)
		if idx != -1:
			var gp = sk.get_bone_global_rest(idx)
			print("Bone: %s global rest origin: %s" % [b, gp.origin])

	quit(0)
