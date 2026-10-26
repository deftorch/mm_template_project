extends SceneTree

func _initialize():
	var mot_scene = load("res://animation/animations/motorica/transitions/sprint_to_run/Transitions_Sprint_to_Run_Straight.fbx") as PackedScene
	var mot_sk: Skeleton3D = mot_scene.instantiate().find_children("*", "Skeleton3D")[0]

	var mm_scene = load("res://characters/motus_man/MotusMan_v55.fbx") as PackedScene
	var mm_sk: Skeleton3D = mm_scene.instantiate().find_children("*", "Skeleton3D")[0]

	print("--- Comparing all common bones ---")
	for i in range(mot_sk.get_bone_count()):
		var bname = mot_sk.get_bone_name(i)
		var mm_idx = mm_sk.find_bone(bname)
		if mm_idx != -1:
			var mot_rest_rot = mot_sk.get_bone_rest(i).basis.get_euler() * 180.0 / PI
			var mm_rest_rot = mm_sk.get_bone_rest(mm_idx).basis.get_euler() * 180.0 / PI
			var diff = (mot_sk.get_bone_rest(i).basis.inverse() * mm_sk.get_bone_rest(mm_idx).basis).get_euler() * 180.0 / PI
			if diff.length() > 1.0:
				print("Bone: %s -> Motorica rest rot: %s, MotusMan rest rot: %s, Diff: %s" % [bname, mot_rest_rot, mm_rest_rot, diff])

	quit(0)
