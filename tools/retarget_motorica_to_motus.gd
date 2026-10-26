extends SceneTree
## Retarget semua klip Motorica (FBX) ke skeleton MotusMan_v55.
##
## Jalankan:
##   godot --headless --path . -s tools/retarget_motorica_to_motus.gd
## Lalu rebuild library:
##   godot --headless --path . -s tools/build_motus_library.gd
##
## KENAPA TOOL INI MENGGANTIKAN extract_and_retarget_motorica.gd
## -----------------------------------------------------------------
## Skeleton Motorica : semua rest rotation = IDENTITY, tulang memanjang di sumbu +Y.
## Skeleton MotusMan : rest rotation per-bone tidak identity (mis. Hips = (0,-90,90) derajat,
##                     tulang memanjang di sumbu X lokal).
## Track rotasi Motorica adalah rotasi LOKAL absolut dalam frame identity itu, jadi tidak bisa
## dipakai langsung di MotusMan. Tool lama melakukan `rest_q * q` per-bone; rumus itu salah
## (urutan perkalian salah dan tidak memperhitungkan rest rotasi parent), sehingga pose jadi
## terpelintir (tangan terangkat, langkah kaki hilang; error sendi rata-rata ~0.3 m).
##
## Rumus yang dipakai di sini (world-space delta):
##   W_b        = Gs_pose(b) * Gs_rest(b)^-1          (rotasi world sumber dari rest ke pose)
##   Gt_pose(b) = W_b * Q_b * Gt_rest(b)              (Q_b = koreksi arah tulang rest target->sumber)
##   Lt(b)      = Gt_pose(parent)^-1 * Gt_pose(b)
## Bone sumber yang tidak ada di target (Spine3, Spine4, Neck1) otomatis "terlipat" ke bone
## berikutnya karena memakai rotasi global.

const SRC_DIR := "res://animation/animations/motorica/"
const OUT_DIR := "res://characters/motus_man/animations/"
const TARGET_FBX := "res://characters/motus_man/MotusMan_v55.fbx"
const FPS := 30.0

# Bone anak yang dipakai untuk menentukan arah tulang saat koreksi rest-alignment.
const CHILD_HINT := {
	"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandMiddle1",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandMiddle1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}


func _initialize() -> void:
	var only := ""  # isi nama klip (tanpa .fbx) untuk memproses satu klip saja
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)

	var tgt_scene := load(TARGET_FBX) as PackedScene
	var tgt_root := tgt_scene.instantiate()
	var skT: Skeleton3D = tgt_root.find_children("*", "Skeleton3D", true, false)[0]
	var tgt_path_prefix := str(tgt_root.get_path_to(skT))  # biasanya "Skeleton3D"

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var files: Array = []
	_collect_fbx(SRC_DIR, files)
	files.sort()
	print("Found %d Motorica FBX files." % files.size())

	var ok := 0
	var ctx: Dictionary = {}
	for f in files:
		if only != "" and str(f).get_file().get_basename() != only:
			continue
		var scene := load(f) as PackedScene
		if scene == null:
			printerr("Failed to load: ", f)
			continue
		var inst := scene.instantiate()
		var skS: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var src: Animation = ap.get_animation("Take 001") if ap.has_animation("Take 001") else null
		if src == null:
			printerr("No 'Take 001' in ", f)
			inst.free()
			continue
		if ctx.is_empty():
			ctx = build_context(skS, skT)
		var out := retarget_clip(skS, skT, src, ctx, tgt_path_prefix)
		var save_path: String = OUT_DIR + str(f).get_file().get_basename() + ".res"
		if ResourceSaver.save(out, save_path) == OK:
			ok += 1
		else:
			printerr("Failed to save: ", save_path)
		inst.free()
		if ok % 25 == 0:
			print("  ... %d done" % ok)
	print("Retargeted %d animations -> %s" % [ok, OUT_DIR])
	quit(0)


# ---------------------------------------------------------------------------------------------

static func rest_globals(sk: Skeleton3D) -> Array:
	var n := sk.get_bone_count()
	var g: Array = []
	g.resize(n)
	for i in n:
		var l := sk.get_bone_rest(i)
		var p := sk.get_bone_parent(i)
		g[i] = l if p < 0 else (g[p] as Transform3D) * l
	return g


static func build_context(skS: Skeleton3D, skT: Skeleton3D) -> Dictionary:
	var rsg := rest_globals(skS)
	var rtg := rest_globals(skT)
	var Q := {}
	for i in skT.get_bone_count():
		var name := skT.get_bone_name(i)
		Q[name] = Quaternion.IDENTITY
		if not CHILD_HINT.has(name):
			continue
		var si := skS.find_bone(name)
		var sc := skS.find_bone(CHILD_HINT[name])
		var tc := skT.find_bone(CHILD_HINT[name])
		if si < 0 or sc < 0 or tc < 0:
			continue
		var ds: Vector3 = ((rsg[sc] as Transform3D).origin - (rsg[si] as Transform3D).origin).normalized()
		var dt: Vector3 = ((rtg[tc] as Transform3D).origin - (rtg[i] as Transform3D).origin).normalized()
		if ds.length() < 0.5 or dt.length() < 0.5 or dt.dot(ds) < -0.999:
			continue
		Q[name] = Quaternion(dt, ds)
	var hips_ratio: float = (rtg[skT.find_bone("Hips")] as Transform3D).origin.y \
			/ (rsg[skS.find_bone("Hips")] as Transform3D).origin.y
	return {"rsg": rsg, "rtg": rtg, "Q": Q, "hips_ratio": hips_ratio}


## Pose lokal sumber (rotasi + posisi per bone) pada waktu t.
static func source_local_pose(skS: Skeleton3D, anim: Animation, track_of: Dictionary, t: float) -> Array:
	var n := skS.get_bone_count()
	var rot: Array = []
	var pos: Array = []
	for i in n:
		rot.append(skS.get_bone_rest(i).basis.get_rotation_quaternion())
		pos.append(skS.get_bone_rest(i).origin)
	for bi in track_of["rot"]:
		rot[bi] = anim.rotation_track_interpolate(track_of["rot"][bi], t)
	for bi in track_of["pos"]:
		pos[bi] = anim.position_track_interpolate(track_of["pos"][bi], t)
	return [rot, pos]


static func fk_rotations(sk: Skeleton3D, rot: Array) -> Array:
	var n := sk.get_bone_count()
	var g: Array = []
	g.resize(n)
	for i in n:
		var p := sk.get_bone_parent(i)
		g[i] = (rot[i] as Quaternion) if p < 0 else ((g[p] as Quaternion) * (rot[i] as Quaternion)).normalized()
	return g


## Retarget satu pose. Return [rot_lokal_target[], hips_pos_lokal_target].
static func retarget_pose(skS: Skeleton3D, skT: Skeleton3D, lp: Array, ctx: Dictionary) -> Array:
	var gS := fk_rotations(skS, lp[0])
	var rsg: Array = ctx["rsg"]
	var rtg: Array = ctx["rtg"]
	var Q: Dictionary = ctx["Q"]
	var n := skT.get_bone_count()
	var gq: Array = []
	gq.resize(n)
	var rot: Array = []
	rot.resize(n)
	for i in n:
		var name := skT.get_bone_name(i)
		var p := skT.get_bone_parent(i)
		var gp: Quaternion = Quaternion.IDENTITY if p < 0 else gq[p]
		var si := skS.find_bone(name)
		if si >= 0:
			var W: Quaternion = (gS[si] as Quaternion) * (rsg[si] as Transform3D).basis.get_rotation_quaternion().inverse()
			gq[i] = (W * (Q[name] as Quaternion) * (rtg[i] as Transform3D).basis.get_rotation_quaternion()).normalized()
			rot[i] = (gp.inverse() * (gq[i] as Quaternion)).normalized()
		else:
			rot[i] = skT.get_bone_rest(i).basis.get_rotation_quaternion()
			gq[i] = (gp * (rot[i] as Quaternion)).normalized()
	var hips_si := skS.find_bone("Hips")
	var hips_pos: Vector3 = (lp[1][hips_si] as Vector3) * (ctx["hips_ratio"] as float)
	return [rot, hips_pos]


static func retarget_clip(skS: Skeleton3D, skT: Skeleton3D, src: Animation, ctx: Dictionary, tgt_prefix: String) -> Animation:
	# peta bone sumber -> index track
	var track_of := {"rot": {}, "pos": {}}
	var root_pos_track := -1
	for t in src.get_track_count():
		var bn := str(src.track_get_path(t)).get_slice(":", 1)
		var bi := skS.find_bone(bn)
		if bi < 0:
			continue
		match src.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				track_of["rot"][bi] = t
			Animation.TYPE_POSITION_3D:
				track_of["pos"][bi] = t
				if bn == "Root":
					root_pos_track = t

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	out.step = src.step

	# track rotasi: hanya bone target yang punya padanan di sumber
	var n := skT.get_bone_count()
	var rot_tracks := {}
	for i in n:
		var name := skT.get_bone_name(i)
		if skS.find_bone(name) >= 0 and track_of["rot"].has(skS.find_bone(name)):
			var tr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr, NodePath("%s:%s" % [tgt_prefix, name]))
			rot_tracks[i] = tr
	var hips_i := skT.find_bone("Hips")
	var hips_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_tr, NodePath("%s:Hips" % tgt_prefix))

	var frames := int(ceil(src.length * FPS))
	for f in range(frames + 1):
		var t: float = min(f / FPS, src.length)
		var lp := source_local_pose(skS, src, track_of, t)
		var r := retarget_pose(skS, skT, lp, ctx)
		for i in rot_tracks:
			out.rotation_track_insert_key(rot_tracks[i], t, r[0][i])
		out.position_track_insert_key(hips_tr, t, r[1])

	# root motion: salin apa adanya (Root Motorica = Root MotusMan, keduanya identity di rest)
	if root_pos_track >= 0:
		var rt := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(rt, NodePath("%s:Root" % tgt_prefix))
		for k in src.track_get_key_count(root_pos_track):
			out.position_track_insert_key(rt, src.track_get_key_time(root_pos_track, k), src.track_get_key_value(root_pos_track, k))
	return out


static func _collect_fbx(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full := dir_path + fname
			if d.current_is_dir():
				_collect_fbx(full + "/", out)
			elif fname.ends_with(".fbx"):
				out.append(full)
		fname = d.get_next()
