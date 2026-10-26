extends SceneTree

func _initialize():
	var sk = Skeleton3D.new()
	sk.add_bone("Hips")
	sk.set_bone_rest(0, Transform3D(Basis(Vector3(1, 0, 0), PI/2.0), Vector3(0, 1, 0)))
	sk.reset_bone_poses()
	print("Rest euler: ", sk.get_bone_rest(0).basis.get_euler() * 180.0 / PI)
	print("Pose euler after reset: ", sk.get_bone_pose(0).basis.get_euler() * 180.0 / PI)
	
	# Now simulate animation player setting rotation to (0, 0, 0)
	sk.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	print("Pose euler after setting IDENTITY: ", sk.get_bone_pose(0).basis.get_euler() * 180.0 / PI)
	print("Global pose euler: ", sk.get_bone_global_pose(0).basis.get_euler() * 180.0 / PI)
	quit(0)
