extends SceneTree

func _initialize() -> void:
	var dir := DirAccess.open("res://animation/animations")
	var all_speeds: Array[float] = []
	var rows := []
	for f in dir.get_files():
		if not f.ends_with(".res"):
			continue
		var anim := load("res://animation/animations/" + f) as Animation
		if anim == null:
			continue
		# find the root bone position track
		var track := -1
		for t in anim.get_track_count():
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(t)).to_lower().ends_with(":root"):
				track = t
				break
		if track == -1:
			rows.append([f, "no root pos track", anim.length])
			continue
		var win := 0.5
		var speeds: Array[float] = []
		var t0 := 0.0
		while t0 + win <= anim.length:
			var a: Vector3 = anim.position_track_interpolate(track, t0)
			var b: Vector3 = anim.position_track_interpolate(track, t0 + win)
			speeds.append(Vector2(b.x - a.x, b.z - a.z).length() / win)
			t0 += 0.1
		if speeds.is_empty():
			continue
		speeds.sort()
		all_speeds.append_array(speeds)
		rows.append([f, "max=%.2f p90=%.2f median=%.2f" % [speeds[-1], speeds[int(speeds.size() * 0.9)], speeds[speeds.size() / 2]], anim.length])
	for r in rows:
		print(r[0], "  ", r[1], "  len=", snapped(r[2], 0.1))
	all_speeds.sort()
	print("ALL clips: max=%.2f p99=%.2f p95=%.2f p75=%.2f median=%.2f" % [all_speeds[-1], all_speeds[int(all_speeds.size()*0.99)], all_speeds[int(all_speeds.size()*0.95)], all_speeds[int(all_speeds.size()*0.75)], all_speeds[all_speeds.size()/2]])
	quit()
