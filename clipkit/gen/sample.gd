extends SceneTree
## Alat kerja (di luar repo): evaluasi N pose konstan -> posisi sendi terpilih, tanpa kurva key (cepat).
##   godot --headless --path <proyek> -s sample.gd -- in.json out.json
const ClipLib := preload("res://clipkit/clip_lib.gd")

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var inp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var rig := ClipLib.load_rig()
	var sk := ClipLib.load_skeleton(rig)
	var ctx := ClipLib.make_ctx(sk, rig)
	var poses: Array = inp["poses"]
	var n := poses.size()
	var anim := Animation.new()
	anim.length = maxf((n - 1) / ClipLib.FPS, 1.0 / ClipLib.FPS)
	var tracks := {}
	for bname in rig["animated_bones"]:
		var bi := sk.find_bone(bname)
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("%s:%s" % [rig["path_prefix"], bname]))
		tracks[bi] = tr
	var hips_tr := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_tr, NodePath("%s:Hips" % rig["path_prefix"]))
	var root_tr := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(root_tr, NodePath("%s:Root" % rig["path_prefix"]))
	for i in n:
		var clip := {"duration": 0.0, "channels": {}}
		for k in (poses[i] as Dictionary):
			clip["channels"][k] = [[0.0, float(poses[i][k])]]
		var t: float = i / ClipLib.FPS
		var pose := ClipLib.eval_pose(sk, rig, ctx, clip, 0.0)
		for bi in tracks:
			anim.rotation_track_insert_key(tracks[bi], t, pose["rot"][bi])
		anim.position_track_insert_key(hips_tr, t, pose["hips_pos"])
		anim.position_track_insert_key(root_tr, t, Vector3.ZERO)
	var idx := ClipLib.index_tracks(sk, anim)
	var names: Array = inp["bones"]
	var bidx: Array = []
	for b in names:
		bidx.append(sk.find_bone(b))
	var out: Array = []
	for i in n:
		var g := ClipLib.anim_pose(sk, anim, idx, i / ClipLib.FPS)
		var row: Array = []
		for bi in bidx:
			var o: Vector3 = (g[bi] as Transform3D).origin
			row.append(snappedf(o.x, 0.0001)); row.append(snappedf(o.y, 0.0001)); row.append(snappedf(o.z, 0.0001))
		out.append(row)
	var fa := FileAccess.open(a[1], FileAccess.WRITE)
	fa.store_string(JSON.stringify({"bones": names, "pos": out}))
	fa.close()
	quit(0)
