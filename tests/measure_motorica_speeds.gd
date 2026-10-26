extends SceneTree

func _initialize() -> void:
	print("Measuring Motorica clip speeds...")
	var subdirs = [
		"walking/forward",
		"walking/loops",
		"walking/strafe",
		"running/forward",
		"running/loops",
		"running/strafe",
		"sprinting/forward",
		"sprinting/loops"
	]
	
	var base_path = "res://animation/animations/motorica/"
	var all_stats = {}

	for sdir in subdirs:
		var full_path = base_path + sdir
		var d = DirAccess.open(full_path)
		if d == null:
			continue
		var speeds_in_category: Array[float] = []
		for f in d.get_files():
			if not f.ends_with(".fbx"):
				continue
			var scene = load(full_path + "/" + f) as PackedScene
			if scene == null:
				continue
			var inst = scene.instantiate()
			var anim: Animation = null
			var ap = _find_first_anim_player(inst)
			if ap != null:
				var lib = ap.get_animation_library("")
				if lib != null and lib.has_animation("Take 001"):
					anim = lib.get_animation("Take 001")
			if anim == null:
				inst.free()
				continue

			var track := -1
			for t in anim.get_track_count():
				if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(t)).to_lower().ends_with(":root"):
					track = t
					break

			if track != -1:
				var win := 0.5
				var t0 := 0.0
				while t0 + win <= anim.length:
					var a: Vector3 = anim.position_track_interpolate(track, t0)
					var b: Vector3 = anim.position_track_interpolate(track, t0 + win)
					var spd = Vector2(b.x - a.x, b.z - a.z).length() / win
					speeds_in_category.append(spd)
					t0 += 0.2

			inst.free()

		if not speeds_in_category.is_empty():
			speeds_in_category.sort()
			var med = speeds_in_category[speeds_in_category.size() / 2]
			var p90 = speeds_in_category[int(speeds_in_category.size() * 0.9)]
			var mx = speeds_in_category[-1]
			print("%-25s -> median=%.2f m/s, p90=%.2f m/s, max=%.2f m/s (samples: %d)" % [sdir, med, p90, mx, speeds_in_category.size()])

	quit(0)

func _find_first_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var res = _find_first_anim_player(c)
		if res != null:
			return res
	return null
