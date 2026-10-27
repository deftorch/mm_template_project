extends SceneTree
## Retarget semua klip Motorica (FBX) ke skeleton VRM (karakter three-vrm-girl).
##
## Jalankan:
##   godot --headless --path . -s tools/retarget_motorica_to_vrm.gd
##   godot --headless --path . -s tools/retarget_motorica_to_vrm.gd -- --only=Run_Circles_CCW
##   godot --headless --path . -s tools/retarget_motorica_to_vrm.gd -- --spine=mid_top --root-scale=auto
## Lalu bangun + bake library:
##   godot --headless --path . -s tools/build_vrm_motorica_library.gd
##   tools/bake_vrm_motorica.sh        (tombol "Bake" di editor, jalan di Xvfb)
##
## KENAPA TIDAK MEMAKAI tools/retarget_motorica_to_motus.gd LANGSUNG
## -----------------------------------------------------------------
## 1. Skeleton VRM punya 161 bone dan URUTAN bone-nya tidak parent-dulu (Hips index 0
##    punya parent Root index 160). Tool Motus mengandalkan "parent index < child index",
##    di VRM itu menghasilkan null. Di sini semua FK memakai urutan topologis.
## 2. Nama bone beda (Spine1 -> Chest, LeftArm -> LeftUpperArm, LeftToeBase -> LeftToes ...).
## 3. Proporsi beda: tinggi pinggul VRM 0.894 m vs Motorica 0.971 m (+ lengan jauh lebih pendek).
##    Posisi pinggul dan root motion diskalakan dengan rasio tinggi pinggul-ke-pergelangan
##    supaya langkah kaki tidak "meluncur".
## 4. Track path VRM memakai nama unik: "%GeneralSkeleton:<Bone>" (bukan "Skeleton3D:<Bone>").
##
## Rumus rotasi sama dengan tool Motus (world-space delta):
##   W_s        = Gs_pose(s) * Gs_rest(s)^-1       (rotasi dunia sumber dari rest ke pose)
##   Gt_pose(b) = W_s * Q_b * Gt_rest(b)           (Q_b = koreksi arah tulang rest target->sumber)
##   Lt(b)      = Gt_pose(parent)^-1 * Gt_pose(b)
## Bone sumber tanpa padanan (Spine3, Spine4, Neck1) otomatis "terlipat" ke bone berikutnya
## karena rotasi yang dipakai adalah rotasi global.

const SRC_DIR := "res://animation/animations/motorica/"
const OUT_DIR := "res://animation/animations/motorica_vrm/"
const CATALOG_PATH := "res://animation/motorica_vrm_catalog.json"
const TARGET_SCENE := "res://animation/three_vrm_girl_scene.tscn"
const TRACK_PREFIX := "%GeneralSkeleton"
const FPS := 30.0

## bone target -> bone sumber (bagian yang tetap, tidak tergantung mode spine)
const BONE_MAP_BASE := {
	"Root": "Root",
	"Hips": "Hips",
	"Spine": "Spine",
	"Neck": "Neck",
	"Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg",
	"LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg",
	"RightFoot": "RightFoot", "RightToes": "RightToeBase",
}

## Motorica punya 5 tulang spine (Spine..Spine4) + Neck1, VRM hanya 3 (Spine, Chest, UpperChest).
##   low     : sama seperti tool Motus (Chest<-Spine1, UpperChest<-Spine2)
##   mid_top : Chest<-Spine2, UpperChest<-Spine4 (bahu & leher menempel di Spine4)
##   mid_top3: Chest<-Spine2, UpperChest<-Spine3
const SPINE_MODES := {
	"low": {"Chest": "Spine1", "UpperChest": "Spine2"},
	"mid_top": {"Chest": "Spine2", "UpperChest": "Spine4"},
	"mid_top3": {"Chest": "Spine2", "UpperChest": "Spine3"},
}
const DEFAULT_SPINE_MODE := "mid_top"

## bone target -> anak target yang dipakai menentukan arah tulang saat koreksi rest-alignment
const CHILD_HINT := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftUpperArm", "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
	"LeftHand": "LeftMiddleProximal",
	"RightShoulder": "RightUpperArm", "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
	"RightHand": "RightMiddleProximal",
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot", "LeftFoot": "LeftToes",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot", "RightFoot": "RightToes",
}
## anak yang tidak dianimasikan tetapi dipakai sebagai petunjuk arah: bone target -> bone sumber
const HINT_ONLY_SOURCE := {
	"LeftMiddleProximal": "LeftHandMiddle1", "RightMiddleProximal": "RightHandMiddle1",
}

## Segmen untuk metrik arah (target_a, target_b) -> sumber dihitung lewat peta.
const METRIC_SEGMENTS := [
	["Hips", "Neck"], ["Neck", "Head"],
	["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"],
	["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"],
	["LeftUpperLeg", "LeftLowerLeg"], ["LeftLowerLeg", "LeftFoot"], ["LeftFoot", "LeftToes"],
	["RightUpperLeg", "RightLowerLeg"], ["RightLowerLeg", "RightFoot"], ["RightFoot", "RightToes"],
	["RightUpperLeg", "LeftUpperLeg"], ["RightShoulder", "LeftShoulder"],
]


func _initialize() -> void:
	var only := ""
	var spine_mode := DEFAULT_SPINE_MODE
	var root_scale_arg := "auto"
	var out_dir := OUT_DIR
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--spine="):
			spine_mode = a.substr(8)
		elif a.begins_with("--root-scale="):
			root_scale_arg = a.substr(13)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
			if not out_dir.ends_with("/"):
				out_dir += "/"

	var tgt_scene := load(TARGET_SCENE) as PackedScene
	if tgt_scene == null:
		printerr("Tidak bisa memuat ", TARGET_SCENE)
		quit(1)
		return
	var tgt_root := tgt_scene.instantiate()
	var skT: Skeleton3D = tgt_root.find_children("*", "Skeleton3D", true, false)[0]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var files: Array = []
	collect_fbx(SRC_DIR, files)
	files.sort()
	print("Ditemukan %d FBX Motorica. Mode spine=%s, root-scale=%s" % [files.size(), spine_mode, root_scale_arg])

	var ok := 0
	var fail := 0
	var ctx: Dictionary = {}
	var catalog: Array = []
	for f in files:
		var base: String = str(f).get_file().get_basename()
		if only != "" and base != only:
			continue
		var scene := load(f) as PackedScene
		if scene == null:
			printerr("Gagal memuat: ", f)
			fail += 1
			continue
		var inst := scene.instantiate()
		var skS: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var src: Animation = ap.get_animation("Take 001") if ap.has_animation("Take 001") else null
		if src == null:
			printerr("Tidak ada 'Take 001' di ", f)
			fail += 1
			inst.free()
			continue
		if ctx.is_empty():
			ctx = build_context(skS, skT, spine_mode, root_scale_arg)
			print("  rasio skala (pinggul->pergelangan) = %.4f, root motion x %.4f" % [ctx["hips_ratio"], ctx["root_scale"]])
		var out := retarget_clip(skS, skT, src, ctx)
		var save_path: String = out_dir + base + ".res"
		if ResourceSaver.save(out, save_path) == OK:
			ok += 1
			catalog.append(make_catalog_entry(str(f), base, src, out))
		else:
			printerr("Gagal menyimpan: ", save_path)
			fail += 1
		inst.free()
		if ok % 25 == 0 and ok > 0:
			print("  ... %d selesai" % ok)
	print("Retarget selesai: %d berhasil, %d gagal -> %s" % [ok, fail, out_dir])
	if only == "" and ok > 0:
		var fh := FileAccess.open(CATALOG_PATH, FileAccess.WRITE)
		if fh != null:
			fh.store_string(JSON.stringify({"spine_mode": spine_mode, "hips_ratio": ctx["hips_ratio"],
					"root_scale": ctx["root_scale"], "clips": catalog}, "\t"))
			fh.close()
			print("Katalog ditulis: ", CATALOG_PATH, " (", catalog.size(), " klip)")
	tgt_root.free()
	quit(0 if fail == 0 else 1)


# ---------------------------------------------------------------------------------------------
# Skeleton helpers (urutan topologis -> aman untuk skeleton dengan index bone sembarang)

static func topo_order(sk: Skeleton3D) -> PackedInt32Array:
	var order := PackedInt32Array()
	var queue: Array = Array(sk.get_parentless_bones())
	while not queue.is_empty():
		var b: int = queue.pop_front()
		order.append(b)
		for c in sk.get_bone_children(b):
			queue.append(c)
	return order


static func bone_map(spine_mode: String) -> Dictionary:
	var m: Dictionary = BONE_MAP_BASE.duplicate()
	var spine: Dictionary = SPINE_MODES.get(spine_mode, SPINE_MODES[DEFAULT_SPINE_MODE])
	for k in spine:
		m[k] = spine[k]
	return m


static func rest_globals(sk: Skeleton3D, order: PackedInt32Array) -> Array:
	var g: Array = []
	g.resize(sk.get_bone_count())
	for i in order:
		var l := sk.get_bone_rest(i)
		var p := sk.get_bone_parent(i)
		g[i] = l if p < 0 else (g[p] as Transform3D) * l
	return g


## rasio untuk menskalakan translasi sumber -> target.
## Dihitung dari jarak pinggul ke pergelangan kaki (rest), bukan tinggi total (lengan/kepala
## tidak relevan untuk foot-sliding).
static func compute_hips_ratio(skS: Skeleton3D, skT: Skeleton3D, rsg: Array, rtg: Array) -> float:
	var hs := skS.find_bone("Hips")
	var fs := skS.find_bone("LeftFoot")
	var ht := skT.find_bone("Hips")
	var ft := skT.find_bone("LeftFoot")
	var ds: float = (rsg[hs] as Transform3D).origin.y - (rsg[fs] as Transform3D).origin.y
	var dt: float = (rtg[ht] as Transform3D).origin.y - (rtg[ft] as Transform3D).origin.y
	return dt / ds


static func build_context(skS: Skeleton3D, skT: Skeleton3D, spine_mode: String = DEFAULT_SPINE_MODE,
		root_scale_arg: String = "auto") -> Dictionary:
	var orderS := topo_order(skS)
	var orderT := topo_order(skT)
	var rsg := rest_globals(skS, orderS)
	var rtg := rest_globals(skT, orderT)
	var map := bone_map(spine_mode)
	var Q := {}
	for name in map:
		Q[name] = Quaternion.IDENTITY
		if not CHILD_HINT.has(name):
			continue
		var child_t: String = CHILD_HINT[name]
		var child_s: String = map[child_t] if map.has(child_t) else HINT_ONLY_SOURCE.get(child_t, "")
		var si := skS.find_bone(map[name])
		var sc := skS.find_bone(child_s)
		var ti := skT.find_bone(name)
		var tc := skT.find_bone(child_t)
		if si < 0 or sc < 0 or ti < 0 or tc < 0:
			continue
		var ds: Vector3 = ((rsg[sc] as Transform3D).origin - (rsg[si] as Transform3D).origin).normalized()
		var dt: Vector3 = ((rtg[tc] as Transform3D).origin - (rtg[ti] as Transform3D).origin).normalized()
		if ds.length() < 0.5 or dt.length() < 0.5 or dt.dot(ds) < -0.999:
			continue
		Q[name] = Quaternion(dt, ds)
	var ratio := compute_hips_ratio(skS, skT, rsg, rtg)
	var root_scale := ratio if root_scale_arg == "auto" else float(root_scale_arg)
	return {
		"orderS": orderS, "orderT": orderT, "rsg": rsg, "rtg": rtg, "Q": Q, "map": map,
		"hips_ratio": ratio, "root_scale": root_scale,
		"src_hips_rest": skS.get_bone_rest(skS.find_bone("Hips")).origin,
		"tgt_hips_rest": skT.get_bone_rest(skT.find_bone("Hips")).origin,
	}


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


static func fk_rotations(sk: Skeleton3D, order: PackedInt32Array, rot: Array) -> Array:
	var g: Array = []
	g.resize(sk.get_bone_count())
	for i in order:
		var p := sk.get_bone_parent(i)
		g[i] = (rot[i] as Quaternion) if p < 0 else ((g[p] as Quaternion) * (rot[i] as Quaternion)).normalized()
	return g


## Posisi global tiap bone. `local_pos` berisi origin lokal per bone (rest, kecuali Hips dari animasi).
static func fk_positions(sk: Skeleton3D, order: PackedInt32Array, grot: Array, local_pos: Array) -> Array:
	var gp: Array = []
	gp.resize(sk.get_bone_count())
	for i in order:
		var p := sk.get_bone_parent(i)
		gp[i] = (local_pos[i] as Vector3) if p < 0 else (gp[p] as Vector3) + (grot[p] as Quaternion) * (local_pos[i] as Vector3)
	return gp


## Retarget satu pose. Return [rot_lokal_target[], hips_pos_lokal_target].
static func retarget_pose(skS: Skeleton3D, skT: Skeleton3D, lp: Array, ctx: Dictionary) -> Array:
	var gS := fk_rotations(skS, ctx["orderS"], lp[0])
	var rsg: Array = ctx["rsg"]
	var rtg: Array = ctx["rtg"]
	var Q: Dictionary = ctx["Q"]
	var map: Dictionary = ctx["map"]
	var n := skT.get_bone_count()
	var gq: Array = []
	gq.resize(n)
	var rot: Array = []
	rot.resize(n)
	for i in ctx["orderT"]:
		var name := skT.get_bone_name(i)
		var p := skT.get_bone_parent(i)
		var gp: Quaternion = Quaternion.IDENTITY if p < 0 else gq[p]
		var si := -1
		if map.has(name):
			si = skS.find_bone(map[name])
		if si >= 0:
			var W: Quaternion = (gS[si] as Quaternion) * (rsg[si] as Transform3D).basis.get_rotation_quaternion().inverse()
			gq[i] = (W * (Q[name] as Quaternion) * (rtg[i] as Transform3D).basis.get_rotation_quaternion()).normalized()
			rot[i] = (gp.inverse() * (gq[i] as Quaternion)).normalized()
		else:
			rot[i] = skT.get_bone_rest(i).basis.get_rotation_quaternion()
			gq[i] = (gp * (rot[i] as Quaternion)).normalized()
	var hips_si := skS.find_bone("Hips")
	var hips_delta: Vector3 = (lp[1][hips_si] as Vector3) - (ctx["src_hips_rest"] as Vector3)
	var hips_pos: Vector3 = (ctx["tgt_hips_rest"] as Vector3) + hips_delta * (ctx["hips_ratio"] as float)
	return [rot, hips_pos]


static func source_track_map(skS: Skeleton3D, src: Animation) -> Dictionary:
	var track_of := {"rot": {}, "pos": {}, "root_pos": -1, "root_rot": -1}
	for t in src.get_track_count():
		var bn := str(src.track_get_path(t)).get_slice(":", 1)
		var bi := skS.find_bone(bn)
		if bi < 0:
			continue
		match src.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				track_of["rot"][bi] = t
				if bn == "Root":
					track_of["root_rot"] = t
			Animation.TYPE_POSITION_3D:
				track_of["pos"][bi] = t
				if bn == "Root":
					track_of["root_pos"] = t
	return track_of


static func retarget_clip(skS: Skeleton3D, skT: Skeleton3D, src: Animation, ctx: Dictionary) -> Animation:
	var track_of := source_track_map(skS, src)
	var map: Dictionary = ctx["map"]

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	out.step = src.step

	# track rotasi: semua bone humanoid yang dipetakan (Root ditangani terpisah, salinan persis)
	var rot_tracks := {}
	for i in ctx["orderT"]:
		var name := skT.get_bone_name(i)
		if name == "Root" or not map.has(name):
			continue
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath("%s:%s" % [TRACK_PREFIX, name]))
		rot_tracks[i] = tr
	var hips_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_tr, NodePath("%s:Hips" % TRACK_PREFIX))

	var prev_q := {}
	var frames := int(ceil(src.length * FPS))
	for f in range(frames + 1):
		var t: float = minf(f / FPS, src.length)
		var lp := source_local_pose(skS, src, track_of, t)
		var r := retarget_pose(skS, skT, lp, ctx)
		for i in rot_tracks:
			var q: Quaternion = r[0][i]
			# kontinuitas tanda (hindari lompatan q / -q)
			if prev_q.has(i) and (prev_q[i] as Quaternion).dot(q) < 0.0:
				q = -q
			prev_q[i] = q
			out.rotation_track_insert_key(rot_tracks[i], t, q)
		out.position_track_insert_key(hips_tr, t, r[1])

	# Root motion: posisi diskalakan, rotasi disalin apa adanya (yaw saat berbelok).
	var rt := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(rt, NodePath("%s:Root" % TRACK_PREFIX))
	var root_scale: float = ctx["root_scale"]
	if track_of["root_pos"] >= 0:
		var tsrc: int = track_of["root_pos"]
		for k in src.track_get_key_count(tsrc):
			out.position_track_insert_key(rt, src.track_get_key_time(tsrc, k),
					(src.track_get_key_value(tsrc, k) as Vector3) * root_scale)
	else:
		out.position_track_insert_key(rt, 0.0, Vector3.ZERO)
		out.position_track_insert_key(rt, src.length, Vector3.ZERO)
	if track_of["root_rot"] >= 0:
		var rr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rr, NodePath("%s:Root" % TRACK_PREFIX))
		var tsrc2: int = track_of["root_rot"]
		for k in src.track_get_key_count(tsrc2):
			out.rotation_track_insert_key(rr, src.track_get_key_time(tsrc2, k), src.track_get_key_value(tsrc2, k))
	return out


# ---------------------------------------------------------------------------------------------
# Katalog (dipakai demo untuk daftar klip, kategori, kecepatan)

static func make_catalog_entry(src_path: String, base: String, src: Animation, out: Animation) -> Dictionary:
	var rel := src_path.replace(SRC_DIR, "")
	var parts := rel.split("/")
	var rt := -1
	for t in out.get_track_count():
		if str(out.track_get_path(t)).ends_with(":Root") and out.track_get_type(t) == Animation.TYPE_POSITION_3D:
			rt = t
	var path_len := 0.0
	var disp := Vector3.ZERO
	var yaw_total := 0.0
	if rt >= 0 and out.track_get_key_count(rt) > 1:
		var n := out.track_get_key_count(rt)
		var prev: Vector3 = out.track_get_key_value(rt, 0)
		for k in range(1, n):
			var cur: Vector3 = out.track_get_key_value(rt, k)
			path_len += Vector2(cur.x - prev.x, cur.z - prev.z).length()
			prev = cur
		disp = (out.track_get_key_value(rt, n - 1) as Vector3) - (out.track_get_key_value(rt, 0) as Vector3)
	for t in out.get_track_count():
		if str(out.track_get_path(t)).ends_with(":Root") and out.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var n2 := out.track_get_key_count(t)
			if n2 > 1:
				yaw_total = rad_to_deg(_yaw((out.track_get_key_value(t, n2 - 1) as Quaternion)) - _yaw((out.track_get_key_value(t, 0) as Quaternion)))
	var length := src.length
	return {
		"name": base,
		"category": parts[0],
		"group": parts[1] if parts.size() > 2 else parts[0],
		"length": snappedf(length, 0.001),
		"path_speed": snappedf(path_len / maxf(length, 0.001), 0.001),
		"net_speed": snappedf(Vector2(disp.x, disp.z).length() / maxf(length, 0.001), 0.001),
		"yaw_change_deg": snappedf(wrapf(yaw_total, -180.0, 180.0), 0.1),
		"is_loop": base.ends_with("_Loop") or parts[1] == "loops",
		"source": rel,
	}


static func _yaw(q: Quaternion) -> float:
	var f := q * Vector3.FORWARD
	return atan2(f.x, f.z)


static func collect_fbx(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full := dir_path + fname
			if d.current_is_dir():
				collect_fbx(full + "/", out)
			elif fname.ends_with(".fbx"):
				out.append(full)
		fname = d.get_next()
