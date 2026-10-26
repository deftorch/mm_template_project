extends SceneTree

func _initialize():
	var anim = load("res://characters/motus_man/animations/Transitions_Sprint_to_Run_Straight.res") as Animation
	var mm_scene = load("res://characters/motus_man/MotusMan_v55.fbx") as PackedScene
	var mm_inst = mm_scene.instantiate()
	var mm_sk: Skeleton3D = null
	for c in mm_inst.find_children("*", "Skeleton3D"):
		mm_sk = c
		break

	var hips_idx = mm_sk.find_bone("Hips")
	print("MotusMan Hips rest transform:")
	print("  origin: ", mm_sk.get_bone_rest(hips_idx).origin)
	print("  basis: ", mm_sk.get_bone_rest(hips_idx).basis)
	print("  basis euler: ", mm_sk.get_bone_rest(hips_idx).basis.get_euler() * 180.0 / PI)

	for i in range(anim.get_track_count()):
		var p = str(anim.track_get_path(i))
		if "Hips" in p and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var rot11 = anim.rotation_track_interpolate(i, 11.0)
			print("Anim Track Hips rot at t=11.0:")
			print("  quat: ", rot11)
			print("  euler: ", rot11.get_euler() * 180.0 / PI)
			
			var full_basis = mm_sk.get_bone_rest(hips_idx).basis * Basis(rot11)
			print("Combined Hips basis (rest * pose):")
			print("  basis X: ", full_basis.x)
			print("  basis Y: ", full_basis.y)
			print("  basis Z: ", full_basis.z)
			print("  euler: ", full_basis.get_euler() * 180.0 / PI)

			var inv_basis = Basis(rot11) * mm_sk.get_bone_rest(hips_idx).basis
			print("If basis was pose * rest:")
			print("  euler: ", inv_basis.get_euler() * 180.0 / PI)

	quit(0)
