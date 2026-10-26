## DEPRECATED: retarget ini salah (rest_q * q) dan membuat pose terpelintir.
## Gunakan tools/retarget_motorica_to_motus.gd sebagai gantinya.
extends SceneTree

func _initialize():
	print("Extracting and retargeting all Motorica animations for MotusMan...")
	var base_path = "res://animation/animations/motorica/"
	var out_dir = "res://characters/motus_man/animations/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	# Load MotusMan skeleton to get bone rest transforms
	var mm_scene = load("res://characters/motus_man/MotusMan_v55.fbx") as PackedScene
	var mm_sk: Skeleton3D = mm_scene.instantiate().find_children("*", "Skeleton3D")[0]
	var rest_quats = {}
	for i in range(mm_sk.get_bone_count()):
		var bname = mm_sk.get_bone_name(i)
		rest_quats[bname] = mm_sk.get_bone_rest(i).basis.get_rotation_quaternion()

	var all_fbx = []
	_collect_fbx(base_path, all_fbx)
	print("Found %d FBX files." % all_fbx.size())

	var count = 0
	for fpath in all_fbx:
		var scene = load(fpath) as PackedScene
		if scene == null:
			printerr("Failed to load: ", fpath)
			continue
		var inst = scene.instantiate()
		var ap: AnimationPlayer = null
		for c in inst.get_children():
			if c is AnimationPlayer:
				ap = c
				break
		if ap != null:
			var lib = ap.get_animation_library("")
			if lib != null and lib.has_animation("Take 001"):
				var anim = lib.get_animation("Take 001").duplicate(true)
				# Retarget all rotation tracks
				for t in range(anim.get_track_count()):
					if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
						var path = str(anim.track_get_path(t))
						var bname = path.replace("Skeleton3D:", "")
						if rest_quats.has(bname):
							var rest_q: Quaternion = rest_quats[bname]
							for k in range(anim.track_get_key_count(t)):
								var q: Quaternion = anim.track_get_key_value(t, k)
								anim.track_set_key_value(t, k, rest_q * q)
				var fname = fpath.get_file().get_basename() + ".res"
				var save_path = out_dir + fname
				var err = ResourceSaver.save(anim, save_path)
				if err == OK:
					count += 1
				else:
					printerr("Failed to save: ", save_path)
		inst.free()

	print("Successfully extracted and retargeted %d animations!" % count)
	quit(0)

func _collect_fbx(dir_path: String, out: Array):
	var d = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fname = d.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full = dir_path + fname
			if d.current_is_dir():
				_collect_fbx(full + "/", out)
			elif fname.ends_with(".fbx"):
				out.append(full)
		fname = d.get_next()
