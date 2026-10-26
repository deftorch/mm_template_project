extends SceneTree

func _initialize():
	var sk = Skeleton3D.new()
	get_root().add_child(sk)

	var hips = sk.add_bone("Hips")
	var spine = sk.add_bone("Spine")
	sk.set_bone_parent(spine, hips)
	
	sk.set_bone_rest(hips, Transform3D(Basis(Vector3(0, 0, 1), PI/2.0), Vector3(0, 1, 0)))
	sk.set_bone_rest(spine, Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)))
	sk.reset_bone_poses()

	print("Initial spine global pose: ", sk.get_bone_global_pose(spine).origin)

	# In Godot 4, global pose calculation is:
	# parent_global_pose * get_bone_pose(bone)
	# BUT only if global pose dirty flag is set!
	sk.set_bone_pose_rotation(hips, Quaternion(Vector3(0, 0, 1), -PI/2.0))
	sk.force_update_all_bone_transforms()
	print("After force_update_all_bone_transforms: ", sk.get_bone_global_pose(spine).origin)

	# What about manual calculation?
	var hips_pose = sk.get_bone_pose(hips)
	var spine_pose = sk.get_bone_pose(spine)
	print("Manual: hips_pose * spine_pose = ", (hips_pose * spine_pose).origin)
	quit(0)
