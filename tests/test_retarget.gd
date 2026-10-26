extends SceneTree

func _initialize():
	var mm_scene = load("res://characters/motus_man/MotusMan_v55.fbx") as PackedScene
	var mm_inst = mm_scene.instantiate()
	var mm_sk: Skeleton3D = null
	for c in mm_inst.find_children("*", "Skeleton3D"):
		mm_sk = c
		break

	print("--- MotusMan Bone Rest Transforms ---")
	for b in ["Root", "Hips", "Spine", "LeftUpLeg", "RightUpLeg", "LeftArm"]:
		var idx = mm_sk.find_bone(b)
		if idx != -1:
			var t = mm_sk.get_bone_rest(idx)
			print(b, " origin: ", t.origin)
			print(b, " basis X: ", t.basis.x)
			print(b, " basis Y: ", t.basis.y)
			print(b, " basis Z: ", t.basis.z)
			print(b, " quat: ", t.basis.get_rotation_quaternion())
	quit(0)
