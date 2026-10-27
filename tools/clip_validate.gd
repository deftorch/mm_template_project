extends SceneTree
## Validator klip: mengukur Animation (hasil clip_build maupun klip .res lain, mis. Motorica retarget).
##
##   godot --headless --path . -s tools/clip_validate.gd                          # semua di clipkit/out/
##   godot --headless --path . -s tools/clip_validate.gd -- <file.res|dir> ...    # target lain
##   godot --headless --path . -s tools/clip_validate.gd -- --style=realistic     # realistic|stylized|exaggerated
##   godot --headless --path . -s tools/clip_validate.gd -- --quiet               # hanya WARN/FAIL
##
## Exit code 1 jika ada FAIL. Batas ada di clipkit/limits.json.
## Metrik: kecepatan/percepatan sudut, kontinuitas loop, batas lutut/siku/leher, penetrasi lantai,
## foot sliding, klaim (jarak/durasi), jendela gameplay dan event.

const ClipLib := preload("res://clipkit/clip_lib.gd")

var limits: Dictionary
var style := "stylized"
var quiet := false
var sk: Skeleton3D
var rig: Dictionary
var total_fail := 0
var total_warn := 0
var floor_y := 0.0


func _initialize() -> void:
	var targets: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--style="):
			style = a.substr(8)
		elif a == "--quiet":
			quiet = true
		elif not a.begins_with("--"):
			targets.append(a)
	if targets.is_empty():
		targets.append("res://clipkit/out/")
	limits = ClipLib.read_json("res://clipkit/limits.json")
	if not limits["styles"].has(style):
		printerr("Style tidak dikenal: ", style)
		quit(2)
		return
	rig = ClipLib.load_rig()
	sk = ClipLib.load_skeleton(rig)

	var rest_toe_y := INF
	var grest := _rest_globals()
	for tn in ["LeftToeBase", "RightToeBase"]:
		rest_toe_y = minf(rest_toe_y, (grest[sk.find_bone(tn)] as Transform3D).origin.y)
	floor_y = rest_toe_y

	var files: Array = []
	for t in targets:
		if t.ends_with(".res"):
			files.append(t)
		else:
			var d := DirAccess.open(t)
			if d == null:
				printerr("Tidak bisa membuka: ", t)
				continue
			for f in d.get_files():
				if f.ends_with(".res"):
					files.append(str(t).path_join(f))
	files.sort()
	print("Style: %s | lantai (toe rest y) = %.3f m | %d klip" % [style, floor_y, files.size()])
	for f in files:
		var anim := load(f) as Animation
		if anim == null:
			printerr("Bukan Animation: ", f)
			continue
		_validate(f, anim)
	print("\nRINGKASAN: %d klip, %d FAIL, %d WARN" % [files.size(), total_fail, total_warn])
	quit(1 if total_fail > 0 else 0)


func _rest_globals() -> Array:
	var g: Array = []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var l := sk.get_bone_rest(i)
		g.append(l if p < 0 else (g[p] as Transform3D) * l)
	return g


func _validate(path: String, anim: Animation) -> void:
	var lim: Dictionary = limits["styles"][style]
	var an: Dictionary = limits["anatomy"]
	var fl: Dictionary = limits["floor"]
	var vmeta: Dictionary = anim.get_meta("validate", {})
	var name := str(anim.get_meta("clip_name", path.get_file().get_basename()))
	var lines: Array = []  # [sev, text]
	var fps := ClipLib.FPS
	var frames := int(ceil(anim.length * fps))
	var tracks := ClipLib.index_tracks(sk, anim)

	# pose dunia per frame
	var poses: Array = []
	for f in range(frames + 1):
		poses.append(ClipLib.anim_pose(sk, anim, tracks, minf(f / fps, anim.length)))
	var ix := {}
	for bn in ["Hips", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
		ix[bn] = sk.find_bone(bn)

	# 1. kecepatan & percepatan sudut per track rotasi
	var max_speed := 0.0
	var max_speed_bone := ""
	var max_speed_t := 0.0
	var max_acc := 0.0
	var max_acc_bone := ""
	var max_acc_t := 0.0
	for bi in tracks:
		if not tracks[bi].has("rot"):
			continue
		var tr: int = tracks[bi]["rot"]
		var prev_q: Quaternion = anim.rotation_track_interpolate(tr, 0.0)
		var prev_s := 0.0
		for f in range(1, frames + 1):
			var q: Quaternion = anim.rotation_track_interpolate(tr, minf(f / fps, anim.length))
			var ang := 2.0 * acos(clampf(absf(prev_q.dot(q)), 0.0, 1.0))
			var s := rad_to_deg(ang) * fps
			if s > max_speed:
				max_speed = s
				max_speed_bone = sk.get_bone_name(bi)
				max_speed_t = f / fps
			var acc := absf(s - prev_s) * fps
			if f > 1 and acc > max_acc:
				max_acc = acc
				max_acc_bone = sk.get_bone_name(bi)
				max_acc_t = f / fps
			prev_q = q
			prev_s = s
	var sp_txt := "kecepatan sudut maks %.0f °/s (%s @%.2fs)" % [max_speed, max_speed_bone, max_speed_t]
	if max_speed > lim["ang_speed_fail"]:
		lines.append(["FAIL", sp_txt + " > %d" % lim["ang_speed_fail"]])
	elif max_speed > lim["ang_speed_warn"]:
		lines.append(["WARN", sp_txt + " > %d (menyentak?)" % lim["ang_speed_warn"]])
	else:
		lines.append(["PASS", sp_txt])
	var ac_txt := "percepatan sudut maks %.0f °/s² (%s @%.2fs)" % [max_acc, max_acc_bone, max_acc_t]
	lines.append(["WARN" if max_acc > lim["ang_accel_warn"] else "PASS", ac_txt])

	# 2. kontinuitas loop
	if anim.loop_mode != Animation.LOOP_NONE:
		var worst := 0.0
		var worst_b := ""
		for bi in tracks:
			if tracks[bi].has("rot"):
				var q0: Quaternion = anim.rotation_track_interpolate(tracks[bi]["rot"], 0.0)
				var q1: Quaternion = anim.rotation_track_interpolate(tracks[bi]["rot"], anim.length)
				var d := rad_to_deg(2.0 * acos(clampf(absf(q0.dot(q1)), 0.0, 1.0)))
				if d > worst:
					worst = d
					worst_b = sk.get_bone_name(bi)
		var txt := "loop: selisih pose awal-akhir maks %.1f° (%s)" % [worst, worst_b]
		lines.append(["FAIL" if worst > lim["loop_pose_diff_deg"] else "PASS", txt])

	# 3. anatomi
	var left_axis_ok := true
	var knee_min := INF
	var knee_max := -INF
	var elbow_max := 0.0
	var neck_max := 0.0
	for pose in poses:
		var lax: Vector3 = ((pose[ix["LeftUpLeg"]] as Transform3D).origin - (pose[ix["RightUpLeg"]] as Transform3D).origin).normalized()
		for side in ["Left", "Right"]:
			var hip: Vector3 = (pose[sk.find_bone(side + "UpLeg")] as Transform3D).origin
			var knee: Vector3 = (pose[sk.find_bone(side + "Leg")] as Transform3D).origin
			var foot: Vector3 = (pose[sk.find_bone(side + "Foot")] as Transform3D).origin
			var th := (knee - hip).normalized()
			var sh := (foot - knee).normalized()
			var flex := rad_to_deg(atan2(th.cross(sh).dot(lax), th.dot(sh)))
			knee_min = minf(knee_min, flex)
			knee_max = maxf(knee_max, flex)
			var sh_o: Vector3 = (pose[sk.find_bone(side + "Arm")] as Transform3D).origin
			var el_o: Vector3 = (pose[sk.find_bone(side + "ForeArm")] as Transform3D).origin
			var wr_o: Vector3 = (pose[sk.find_bone(side + "Hand")] as Transform3D).origin
			var ua := (el_o - sh_o).normalized()
			var fa := (wr_o - el_o).normalized()
			elbow_max = maxf(elbow_max, rad_to_deg(acos(clampf(ua.dot(fa), -1.0, 1.0))))
		var s2: Vector3 = (pose[ix["Spine2"]] as Transform3D).origin
		var nk: Vector3 = (pose[ix["Neck"]] as Transform3D).origin
		var hd: Vector3 = (pose[ix["Head"]] as Transform3D).origin
		neck_max = maxf(neck_max, rad_to_deg(acos(clampf((nk - s2).normalized().dot((hd - nk).normalized()), -1.0, 1.0))))
	var ktxt := "lutut: fleksi %.0f° sampai %.0f°" % [knee_min, knee_max]
	if knee_min < an["knee_flex_min"] or knee_max > an["knee_flex_max"]:
		lines.append(["FAIL", ktxt + " (batas %d..%d, negatif = menekuk terbalik)" % [an["knee_flex_min"], an["knee_flex_max"]]])
	else:
		lines.append(["PASS", ktxt])
	var etxt := "siku: tekuk maks %.0f°" % elbow_max
	lines.append(["FAIL" if elbow_max > an["elbow_flex_max"] else "PASS", etxt])
	var ntxt := "leher-kepala: tekuk maks %.0f°" % neck_max
	lines.append(["FAIL" if neck_max > an["neck_bend_max"] else "PASS", ntxt])

	# 4. lantai dan foot sliding
	var min_toe := INF
	var slide: Array = []
	var contact_frames := 0
	for f in range(poses.size()):
		for side in ["Left", "Right"]:
			var ti := sk.find_bone(side + "ToeBase")
			var tp: Vector3 = (poses[f][ti] as Transform3D).origin
			min_toe = minf(min_toe, tp.y)
			var in_c: bool = (tp.y - floor_y) < float(fl["contact_height_m"])
			if in_c:
				contact_frames += 1
			if f + 1 < poses.size() and in_c:
				var tn: Vector3 = (poses[f + 1][ti] as Transform3D).origin
				if tn.y - floor_y < fl["contact_height_m"]:
					slide.append(Vector2(tn.x - tp.x, tn.z - tp.z).length() * fps)
	var pen := floor_y - min_toe
	if vmeta.get("check_floor", true):
		var ptxt := "lantai: toe terendah %.3f m dari lantai (penetrasi %.3f m)" % [min_toe - floor_y, maxf(pen, 0.0)]
		lines.append(["FAIL" if pen > fl["penetration_fail_m"] else "PASS", ptxt])
	if vmeta.get("foot_slide", true):
		if slide.is_empty():
			lines.append(["PASS", "foot sliding: tidak ada frame kontak (klip melayang/tanpa tumpuan)"])
		else:
			slide.sort()
			var mean := 0.0
			for s in slide:
				mean += s
			mean /= slide.size()
			var p95: float = slide[int(slide.size() * 0.95)]
			var stxt := "foot sliding: %d frame kontak, rata-rata %.2f m/s, p95 %.2f m/s" % [contact_frames, mean, p95]
			lines.append(["WARN" if p95 > fl["slide_warn_ms"] else "PASS", stxt])

	# 5. root motion & klaim
	var claims: Dictionary = anim.get_meta("claims", {})
	var root_tr: int = tracks.get(sk.find_bone("Root"), {}).get("pos", -1)
	var dist := 0.0
	if root_tr >= 0:
		var r0: Vector3 = anim.position_track_interpolate(root_tr, 0.0)
		var r1: Vector3 = anim.position_track_interpolate(root_tr, anim.length)
		dist = Vector2(r1.x - r0.x, r1.z - r0.z).length()
	lines.append(["PASS", "root motion: %.2f m horizontal dalam %.2f s" % [dist, anim.length]])
	if root_tr >= 0:
		var rmax := 0.0
		var rmax_t := 0.0
		var rprev: Vector3 = anim.position_track_interpolate(root_tr, 0.0)
		for f in range(1, frames + 1):
			var rp: Vector3 = anim.position_track_interpolate(root_tr, minf(f / fps, anim.length))
			var rs := Vector2(rp.x - rprev.x, rp.z - rprev.z).length() * fps
			if rs > rmax:
				rmax = rs
				rmax_t = f / fps
			rprev = rp
		if rmax > 0.01:
			var rtxt := "kecepatan root maks %.1f m/s @%.2fs" % [rmax, rmax_t]
			if rmax > lim["root_speed_fail"]:
				lines.append(["FAIL", rtxt + " > %s (terasa seperti teleport)" % lim["root_speed_fail"]])
			elif rmax > lim["root_speed_warn"]:
				lines.append(["WARN", rtxt + " > %s" % lim["root_speed_warn"]])
			else:
				lines.append(["PASS", rtxt])
	if claims.has("distance"):
		var tol := float(claims.get("tolerance", 0.1))
		var cd := float(claims["distance"])
		var ok := absf(dist - cd) <= cd * tol
		lines.append(["PASS" if ok else "FAIL", "klaim jarak %.2f m (±%d%%): terukur %.2f m" % [cd, int(tol * 100), dist]])
	if claims.has("duration"):
		var cdur := float(claims["duration"])
		var ok2 := absf(anim.length - cdur) <= cdur * float(claims.get("tolerance", 0.1))
		lines.append(["PASS" if ok2 else "FAIL", "klaim durasi %.2f s: terukur %.2f s" % [cdur, anim.length]])

	# 6. jendela dan event
	var wins: Dictionary = anim.get_meta("windows", {})
	for wn in wins:
		var w: Array = wins[wn]
		var okw := w.size() == 2 and float(w[0]) >= 0.0 and float(w[0]) < float(w[1]) and float(w[1]) <= anim.length + 1e-4
		lines.append(["PASS" if okw else "FAIL", "jendela %s %s %s" % [wn, str(w), "valid" if okw else "tidak valid (harus 0 <= mulai < akhir <= durasi)"]])
	var hit_name := "hitbox" if wins.has("hitbox") else ("active" if wins.has("active") else "")
	if hit_name != "" and wins.has("cancel"):
		var okc: bool = float(wins["cancel"][0]) >= float(wins[hit_name][1]) - 1e-4
		lines.append(["PASS" if okc else "FAIL", "urutan: cancel (%.2f) dimulai setelah %s selesai (%.2f)" % [wins["cancel"][0], hit_name, wins[hit_name][1]]])
	for ev in anim.get_meta("events", []):
		var te := float(ev.get("t", -1.0))
		if te < 0.0 or te > anim.length + 1e-4:
			lines.append(["FAIL", "event %s di t=%.2f di luar durasi" % [ev.get("id", "?"), te]])

	# cetak
	var nf := 0
	var nw := 0
	for l in lines:
		if l[0] == "FAIL":
			nf += 1
		elif l[0] == "WARN":
			nw += 1
	total_fail += nf
	total_warn += nw
	print("\n== %s  (%.2fs, %d frame)  %s" % [name, anim.length, frames + 1, "FAIL" if nf > 0 else ("WARN" if nw > 0 else "OK")])
	for l in lines:
		if quiet and l[0] == "PASS":
			continue
		print("  [%s] %s" % [l[0], l[1]])
