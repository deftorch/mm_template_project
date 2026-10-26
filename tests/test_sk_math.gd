extends SceneTree

func _initialize():
	var sk = Skeleton3D.new()
	sk.add_bone("Hips")
	var t = Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0, 1, 0)) # rotated 90 deg around Z
	sk.set_bone_rest(0, t)
	sk.reset_bone_poses()
	
	print("Initial global pose basis: ", sk.get_bone_global_pose(0).basis)
	
	# Apply an animation pose rotation of Identity
	sk.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	print("After setting pose_rotation=IDENTITY:")
	print("Global pose basis: ", sk.get_bone_global_pose(0).basis)
	print("Bone pose: ", sk.get_bone_pose(0))
	quit(0)
