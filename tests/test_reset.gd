extends SceneTree

func _initialize():
	var sk = Skeleton3D.new()
	var hips = sk.add_bone("Hips")
	sk.set_bone_rest(hips, Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	print("Before reset: pose=", sk.get_bone_pose(hips))
	sk.reset_bone_poses()
	print("After reset: pose=", sk.get_bone_pose(hips))
	print("Rest=", sk.get_bone_rest(hips))
	quit(0)
