extends SceneTree

func _initialize():
	var prof = SkeletonProfileHumanoid.new()
	var bm = BoneMap.new()
	bm.profile = prof

	var mm_scene = load("res://characters/motus_man/MotusMan_v55.fbx") as PackedScene
	var mm_inst = mm_scene.instantiate()
	var sk: Skeleton3D = null
	for c in mm_inst.find_children("*", "Skeleton3D"):
		sk = c
		break

	print("MotusMan bone count: ", sk.get_bone_count())
	var bone_mapping = {
		"Root": "Root",
		"Hips": "Hips",
		"Spine": "Spine",
		"Chest": "Spine1",
		"UpperChest": "Spine2",
		"Neck": "Neck",
		"Head": "Head",
		
		"LeftUpperLeg": "LeftUpLeg",
		"LeftLowerLeg": "LeftLeg",
		"LeftFoot": "LeftFoot",
		"LeftToes": "LeftToeBase",
		
		"RightUpperLeg": "RightUpLeg",
		"RightLowerLeg": "RightLeg",
		"RightFoot": "RightFoot",
		"RightToes": "RightToeBase",
		
		"LeftShoulder": "LeftShoulder",
		"LeftUpperArm": "LeftArm",
		"LeftLowerArm": "LeftForeArm",
		"LeftHand": "LeftHand",
		
		"RightShoulder": "RightShoulder",
		"RightUpperArm": "RightArm",
		"RightLowerArm": "RightForeArm",
		"RightHand": "RightHand",
		
		"LeftThumbMetacarpal": "LeftHandThumb1",
		"LeftThumbProximal": "LeftHandThumb2",
		"LeftThumbDistal": "LeftHandThumb3",
		"LeftIndexProximal": "LeftHandIndex1",
		"LeftIndexIntermediate": "LeftHandIndex2",
		"LeftIndexDistal": "LeftHandIndex3",
		"LeftMiddleProximal": "LeftHandMiddle1",
		"LeftMiddleIntermediate": "LeftHandMiddle2",
		"LeftMiddleDistal": "LeftHandMiddle3",
		"LeftRingProximal": "LeftHandRing1",
		"LeftRingIntermediate": "LeftHandRing2",
		"LeftRingDistal": "LeftHandRing3",
		"LeftLittleProximal": "LeftHandPinky1",
		"LeftLittleIntermediate": "LeftHandPinky2",
		"LeftLittleDistal": "LeftHandPinky3",
		
		"RightThumbMetacarpal": "RightHandThumb1",
		"RightThumbProximal": "RightHandThumb2",
		"RightThumbDistal": "RightHandThumb3",
		"RightIndexProximal": "RightHandIndex1",
		"RightIndexIntermediate": "RightHandIndex2",
		"RightIndexDistal": "RightHandIndex3",
		"RightMiddleProximal": "RightHandMiddle1",
		"RightMiddleIntermediate": "RightHandMiddle2",
		"RightMiddleDistal": "RightHandMiddle3",
		"RightRingProximal": "RightHandRing1",
		"RightRingIntermediate": "RightHandRing2",
		"RightRingDistal": "RightHandRing3",
		"RightLittleProximal": "RightHandPinky1",
		"RightLittleIntermediate": "RightHandPinky2",
		"RightLittleDistal": "RightHandPinky3"
	}

	for prof_name in bone_mapping:
		var motus_name = bone_mapping[prof_name]
		if sk.find_bone(motus_name) != -1:
			bm.set_skeleton_bone_name(prof_name, motus_name)
		else:
			print("Warning: motus bone not found: ", motus_name)

	var save_path = "res://characters/motus_man/motus_man_bonemap.tres"
	var err = ResourceSaver.save(bm, save_path)
	print("Saved BoneMap to %s: result=%d" % [save_path, err])
	quit(0)
