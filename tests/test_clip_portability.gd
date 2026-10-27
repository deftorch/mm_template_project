extends SceneTree
## Uji portabilitas ClipKit lintas skeleton (MotusMan, VRM 0.x, VRM 1.0).
##   godot --headless --path . -s tests/test_clip_portability.gd
## Model VRM 1.0 (testdata/vrm1/*.vrm) tidak ikut repo; uji bagian itu dilewati (SKIP) jika tidak ada.
## Ambil: tests/fetch_vrm1_sample.sh
const ClipLib := preload("res://clipkit/clip_lib.gd")

const VRM1 := "res://testdata/vrm1/VRM1_Constraint_Twist_Sample.vrm"
var fails := 0
var skips := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s  %s  (%s)" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _specs() -> Array:
	var out := [
		{"label": "MotusMan", "rig": "res://clipkit/rig_motus_man.json", "skel": ""},
		{"label": "VRM 0.x", "rig": "res://clipkit/rig_vrm.json", "skel": ""},
	]
	if ResourceLoader.exists(VRM1):
		out.append({"label": "VRM 1.0", "rig": "res://clipkit/rig_vrm.json", "skel": VRM1})
	else:
		skips += 1
		print("SKIP  VRM 1.0 (%s tidak ada; jalankan tests/fetch_vrm1_sample.sh)" % VRM1)
	return out


func _initialize() -> void:
	for sp in _specs():
		await _run_spec(sp)
	_test_optional_bone_fallback()
	_test_out_sync()
	print("\nRINGKASAN: %d FAIL, %d SKIP" % [fails, skips])
	quit(1 if fails > 0 else 0)


func _run_spec(sp: Dictionary) -> void:
	var label: String = sp["label"]
	var rig := ClipLib.load_rig(sp["rig"])
	var scene_path: String = sp["skel"] if sp["skel"] != "" else str(rig["skeleton_scene"])
	var scene := load(scene_path) as PackedScene
	var inst := scene.instantiate()
	get_root().add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var ctx := ClipLib.make_ctx(sk, rig)

	# 1. urutan bone: tiap bone muncul setelah parent-nya, semua bone tercakup
	var order := ClipLib.bone_order(sk)
	var pos := {}
	for k in order.size():
		pos[order[k]] = k
	var ok_order := order.size() == sk.get_bone_count()
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		if p >= 0 and int(pos[p]) > int(pos[i]):
			ok_order = false
	check("[%s] urutan topologis valid (%d bone)" % [label, order.size()], ok_order)

	# 2. semua nama kanonik yang dipakai rig ter-resolve
	var missing: Array = []
	for bn in rig["animated_bones"]:
		if ClipLib.find_bone(sk, rig, bn) < 0 and not (rig.get("optional_bones", []) as Array).has(bn):
			missing.append(bn)
	check("[%s] semua animated_bones ter-resolve" % label, missing.is_empty(), "hilang: %s" % str(missing))

	# 3. putar klip lewat AnimationPlayer sungguhan: path track harus ter-resolve ke skeleton
	var clip: Dictionary = ClipLib.read_json("res://clipkit/clips/slash.json")
	var anim := ClipLib.build_animation(sk, rig, ctx, clip)
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		check("[%s] ada AnimationPlayer" % label, false)
		inst.queue_free()
		return
	var ap := players[0] as AnimationPlayer
	var lib := AnimationLibrary.new()
	lib.add_animation("c", anim)
	ap.add_animation_library("port", lib)
	var t := 0.45
	ap.play("port/c")
	ap.pause()
	ap.seek(t, true)
	for f in 4:
		await process_frame
	var worst := 0.0
	var checked := 0
	for tr in anim.get_track_count():
		if anim.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var bn := str(anim.track_get_path(tr)).get_slice(":", 1)
		var bi := sk.find_bone(bn)
		var want: Quaternion = anim.rotation_track_interpolate(tr, t)
		var got: Quaternion = sk.get_bone_pose_rotation(bi)
		worst = maxf(worst, rad_to_deg(want.angle_to(got)))
		checked += 1
	check("[%s] pemutaran AnimationPlayer menggerakkan %d bone sesuai track" % [label, checked], checked > 0 and worst < 0.5, "selisih maks %.3f°" % worst)

	# 4. pose default tidak menembus lantai di luar toleransi dan kaki dari rest tidak berubah arah
	var tracks := ClipLib.index_tracks(sk, anim)
	var g := ClipLib.anim_pose(sk, anim, tracks, 0.0)
	var lt := ClipLib.find_bone(sk, rig, "LeftToeBase")
	var rt := ClipLib.find_bone(sk, rig, "RightToeBase")
	var grest := ClipLib.rest_globals(sk)
	var dy: float = absf((g[lt] as Transform3D).origin.y - (grest[lt] as Transform3D).origin.y)
	check("[%s] t=0 klip: toe tetap di tinggi rest" % label, dy < 0.01, "selisih %.4f m" % dy)
	inst.queue_free()


## Model tanpa bone opsional (mis. VRM tanpa UpperChest): total rotasi lean harus tetap sama.
func _test_optional_bone_fallback() -> void:
	var rig := ClipLib.load_rig("res://clipkit/rig_motus_man.json")
	var sk := ClipLib.load_skeleton(rig)
	var full_ctx := ClipLib.make_ctx(sk, rig)
	var rig2: Dictionary = rig.duplicate(true)
	rig2["bone_alias"] = {"Spine2": "BoneYangTidakAda"}
	rig2["optional_bones"] = ["Spine2"]
	var ctx2 := ClipLib.make_ctx(sk, rig2)
	var clip := {"duration": 1.0, "channels": {"lean": [[0.0, 30.0]]}}
	var head: int = ClipLib.find_bone(sk, rig, "Head")
	var angles: Array = []
	for pair in [[rig, full_ctx], [rig2, ctx2]]:
		var anim := ClipLib.build_animation(sk, pair[0], pair[1], clip)
		var g := ClipLib.anim_pose(sk, anim, ClipLib.index_tracks(sk, anim), 0.0)
		var base := ClipLib.rest_globals(sk)
		angles.append(rad_to_deg((g[head] as Transform3D).basis.get_rotation_quaternion().angle_to((base[head] as Transform3D).basis.get_rotation_quaternion())))
	check("bone opsional hilang: total rotasi lean tetap 30°", absf(angles[0] - 30.0) < 0.5 and absf(angles[1] - 30.0) < 0.5, "penuh %.2f° / tanpa Spine2 %.2f°" % [angles[0], angles[1]])


## clipkit/out*/ harus sinkron dengan JSON: bangun ulang di memori dan bandingkan dengan .res tersimpan.
func _test_out_sync() -> void:
	for rig_path in ["res://clipkit/rig_motus_man.json", "res://clipkit/rig_vrm.json"]:
		var rig := ClipLib.load_rig(rig_path)
		var sk := ClipLib.load_skeleton(rig)
		var ctx := ClipLib.make_ctx(sk, rig)
		var out_dir := str(rig.get("out_dir", "res://clipkit/out/"))
		for cp in ClipLib.load_clips("res://clipkit/clips/"):
			var clip: Dictionary = ClipLib.read_json(cp)
			var saved := load(out_dir + str(clip["name"]) + ".res") as Animation
			if saved == null:
				check("[%s] out/%s.res ada" % [rig["name"], clip["name"]], false, "jalankan clip_build.gd")
				continue
			var fresh := ClipLib.build_animation(sk, rig, ctx, clip)
			var worst := 0.0
			var same_tracks := fresh.get_track_count() == saved.get_track_count()
			if same_tracks:
				for tr in fresh.get_track_count():
					same_tracks = same_tracks and fresh.track_get_path(tr) == saved.track_get_path(tr)
					for fi in int(ceil(fresh.length * ClipLib.FPS)) + 1:
						var k := minf(fi / ClipLib.FPS, fresh.length)
						if fresh.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
							worst = maxf(worst, rad_to_deg((fresh.rotation_track_interpolate(tr, k) as Quaternion).angle_to(saved.rotation_track_interpolate(tr, k))))
						else:
							worst = maxf(worst, ((fresh.position_track_interpolate(tr, k) as Vector3) - saved.position_track_interpolate(tr, k)).length() * 100.0)
			check("[%s] out/%s.res sinkron dengan JSON" % [rig["name"], clip["name"]], same_tracks and worst < 1.0, "selisih maks %.3f (deg/cm; presisi simpan Godot ~0.06)" % worst)
