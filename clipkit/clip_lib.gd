extends RefCounted
## ClipLib: inti pipeline klip berbasis teks.
##
## Klip = JSON (channel bermakna + keyframe [waktu, nilai, easing]). Library ini:
##   - mengevaluasi channel menjadi pose skeleton (rotasi lokal per bone),
##   - membuat Animation Godot dari klip (build_animation),
##   - membaca pose dunia dari Animation apa pun (anim_pose) untuk validasi.
##
## Konvensi frame model MotusMan: +X = kiri karakter, +Y = atas, +Z = depan.
## Semua sumbu channel didefinisikan di frame model pada pose rest (T-pose) dan "dibawa"
## oleh rotasi parent (carry). Jadi hasil tidak bergantung pada rotasi rest per-bone
## (kelas bug yang sama dengan retarget Motorica).

const FPS := 30.0
const RIG_PATH := "res://clipkit/rig_motus_man.json"
const FORWARD := Vector3(0, 0, 1)


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func load_rig(path: String = RIG_PATH) -> Dictionary:
	var rig = read_json(path)
	if not (rig is Dictionary):
		push_error("Rig tidak terbaca: " + path)
		return {}
	return rig


static func load_skeleton(rig: Dictionary) -> Skeleton3D:
	var scene := load(rig["skeleton_scene"]) as PackedScene
	var inst := scene.instantiate()
	return inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


# ----------------------------------------------------------------------------------------
# Easing dan sampling keyframe
# ----------------------------------------------------------------------------------------

static func ease_fn(name: String, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match name:
		"linear": return u
		"hold": return 0.0 if u < 1.0 else 1.0
		"inQuad": return u * u
		"outQuad": return 1.0 - (1.0 - u) * (1.0 - u)
		"inOutQuad": return 2.0 * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 2.0) / 2.0
		"inCubic": return u * u * u
		"outCubic": return 1.0 - pow(1.0 - u, 3.0)
		"inOutCubic": return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
		"inSine": return 1.0 - cos(u * PI / 2.0)
		"outSine": return sin(u * PI / 2.0)
		"inOutSine": return -(cos(PI * u) - 1.0) / 2.0
		"outBack":
			var c1 := 1.70158
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)
	return u


## keys = [[waktu, nilai, easing?], ...]. Easing sebuah key dipakai untuk segmen
## yang MENUJU key itu (dari key sebelumnya).
static func sample_keys(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	if t >= float(keys[-1][0]):
		return float(keys[-1][1])
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var span := maxf(float(b[0]) - float(a[0]), 1e-6)
			var u := (t - float(a[0])) / span
			var e: String = str(b[2]) if b.size() > 2 else "linear"
			return lerpf(float(a[1]), float(b[1]), ease_fn(e, u))
	return float(keys[-1][1])


# ----------------------------------------------------------------------------------------
# Konteks skeleton + rig
# ----------------------------------------------------------------------------------------

static func make_ctx(sk: Skeleton3D, rig: Dictionary) -> Dictionary:
	var n := sk.get_bone_count()
	var rest_q: Array = []
	var grest_q: Array = []
	var grest_t: Array = []
	for i in n:
		var p := sk.get_bone_parent(i)
		if p >= i:
			push_error("Urutan bone tidak parent-dulu: " + sk.get_bone_name(i))
		var l := sk.get_bone_rest(i)
		var rq := l.basis.get_rotation_quaternion()
		rest_q.append(rq)
		grest_q.append(rq if p < 0 else (grest_q[p] as Quaternion) * rq)
		grest_t.append(l if p < 0 else (grest_t[p] as Transform3D) * l)

	# channel axis/pos -> daftar target
	var ops := {}  # bone idx -> Array[{kind, ...}]
	var pos_ops: Array = []
	for cname in rig["channels"]:
		var c: Dictionary = rig["channels"][cname]
		if c["type"] == "axis":
			var axis := Vector3(c["axis"][0], c["axis"][1], c["axis"][2]).normalized() * float(c["sign"])
			for bname in c["bones"]:
				var bi := sk.find_bone(bname)
				if bi < 0:
					push_error("Bone tidak ada: " + bname)
					continue
				if not ops.has(bi):
					ops[bi] = []
				ops[bi].append({"kind": "axis", "ch": cname, "axis": axis, "w": float(c["bones"][bname])})
		elif c["type"] == "pos":
			pos_ops.append({"ch": cname, "axis": Vector3(c["axis"][0], c["axis"][1], c["axis"][2]), "bone": sk.find_bone(c["bone"])})
	for aname in rig.get("aims", {}):
		var a: Dictionary = rig["aims"][aname]
		var bi := sk.find_bone(a["bone"])
		var ci := sk.find_bone(a["child"])
		var rest_dir: Vector3 = ((grest_t[ci] as Transform3D).origin - (grest_t[bi] as Transform3D).origin).normalized()
		if not ops.has(bi):
			ops[bi] = []
		ops[bi].append({"kind": "aim", "name": aname, "rest_dir": rest_dir,
			"lateral": Vector3(a["lateral"][0], a["lateral"][1], a["lateral"][2])})
	return {"n": n, "rest_q": rest_q, "grest_q": grest_q, "grest_t": grest_t, "ops": ops, "pos_ops": pos_ops}


static func channel_default(rig: Dictionary, cname: String) -> float:
	if rig["channels"].has(cname):
		return float(rig["channels"][cname].get("default", 0.0))
	# channel aim: "<aim>_<elev|azim|roll>"
	var parts := cname.rsplit("_", true, 1)
	if parts.size() == 2 and rig.get("aims", {}).has(parts[0]):
		return float(rig["aims"][parts[0]]["default"].get(parts[1], 0.0))
	return 0.0


static func channel_value(rig: Dictionary, clip: Dictionary, cname: String, t: float) -> float:
	var chs: Dictionary = clip.get("channels", {})
	if chs.has(cname):
		return sample_keys(chs[cname], t)
	return channel_default(rig, cname)


## Semua nama channel yang valid (axis, pos, dan aim *_elev/_azim/_roll).
static func all_channel_names(rig: Dictionary) -> Array:
	var names: Array = rig["channels"].keys()
	for a in rig.get("aims", {}):
		for k in ["elev", "azim", "roll"]:
			names.append("%s_%s" % [a, k])
	return names


static func channel_range(rig: Dictionary, cname: String) -> Array:
	if rig["channels"].has(cname):
		return rig["channels"][cname]["range"]
	var parts := cname.rsplit("_", true, 1)
	if parts.size() == 2 and rig.get("aims", {}).has(parts[0]):
		return rig["aims"][parts[0]]["range"][parts[1]]
	return []


# ----------------------------------------------------------------------------------------
# Evaluasi pose
# ----------------------------------------------------------------------------------------

## Return {"rot": Array[Quaternion lokal per bone], "hips_pos": Vector3 lokal, "root_pos": Vector3}
static func eval_pose(sk: Skeleton3D, rig: Dictionary, ctx: Dictionary, clip: Dictionary, t: float) -> Dictionary:
	var n: int = ctx["n"]
	var gpose: Array = []
	var rot: Array = []
	gpose.resize(n)
	rot.resize(n)
	var cache := {}  # nilai channel pada t
	for cname in all_channel_names(rig):
		cache[cname] = channel_value(rig, clip, cname, t)

	for i in n:
		var p := sk.get_bone_parent(i)
		var gp: Quaternion = Quaternion.IDENTITY if p < 0 else gpose[p]
		var gpr: Quaternion = Quaternion.IDENTITY if p < 0 else (ctx["grest_q"][p] as Quaternion)
		var rest_l: Quaternion = ctx["rest_q"][i]
		var q_delta := Quaternion.IDENTITY
		if ctx["ops"].has(i):
			var carry: Quaternion = gp * gpr.inverse()
			for op in ctx["ops"][i]:
				if op["kind"] == "axis":
					var ang := deg_to_rad(float(cache[op["ch"]])) * float(op["w"])
					q_delta = Quaternion((carry * (op["axis"] as Vector3)).normalized(), ang) * q_delta
				else:
					var an: String = op["name"]
					var el := deg_to_rad(float(cache[an + "_elev"]))
					var az := deg_to_rad(float(cache[an + "_azim"]))
					var ro := deg_to_rad(float(cache[an + "_roll"]))
					var d: Vector3 = (op["lateral"] as Vector3) * cos(el) * cos(az) + Vector3.UP * sin(el) + FORWARD * cos(el) * sin(az)
					var d_c: Vector3 = (carry * d).normalized()
					var r_c: Vector3 = (carry * (op["rest_dir"] as Vector3)).normalized()
					var q_aim := Quaternion(r_c, d_c)
					q_delta = Quaternion(d_c, ro) * q_aim * q_delta
		var local: Quaternion = (gp.inverse() * q_delta * gp * rest_l).normalized()
		rot[i] = local
		gpose[i] = (gp * local).normalized()

	var hips_i := sk.find_bone("Hips")
	var hips_pos: Vector3 = sk.get_bone_rest(hips_i).origin
	for po in ctx["pos_ops"]:
		hips_pos += (po["axis"] as Vector3) * float(cache[po["ch"]])
	return {"rot": rot, "hips_pos": hips_pos, "root_pos": root_motion(clip, t)}


## Root motion dari blok "move": satu objek atau daftar segmen.
## {dir:[x,y,z], distance:m, t0:s, t1:s, ease:nama}
static func root_motion(clip: Dictionary, t: float) -> Vector3:
	if not clip.has("move"):
		return Vector3.ZERO
	var segs: Array = clip["move"] if clip["move"] is Array else [clip["move"]]
	var total := Vector3.ZERO
	for s in segs:
		var d := Vector3(s["dir"][0], s["dir"][1], s["dir"][2]).normalized()
		var t0 := float(s.get("t0", 0.0))
		var t1 := float(s.get("t1", clip["duration"]))
		var u := clampf((t - t0) / maxf(t1 - t0, 1e-6), 0.0, 1.0)
		total += d * float(s["distance"]) * ease_fn(str(s.get("ease", "linear")), u)
	return total


# ----------------------------------------------------------------------------------------
# Build Animation
# ----------------------------------------------------------------------------------------

static func build_animation(sk: Skeleton3D, rig: Dictionary, ctx: Dictionary, clip: Dictionary) -> Animation:
	var out := Animation.new()
	var dur := float(clip["duration"])
	out.length = dur
	out.step = 1.0 / FPS
	out.loop_mode = Animation.LOOP_LINEAR if clip.get("loop", false) else Animation.LOOP_NONE
	var prefix: String = rig["path_prefix"]

	var tracks := {}
	for bname in rig["animated_bones"]:
		var bi := sk.find_bone(bname)
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath("%s:%s" % [prefix, bname]))
		tracks[bi] = tr
	var hips_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_tr, NodePath("%s:Hips" % prefix))
	var root_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(root_tr, NodePath("%s:Root" % prefix))

	var frames := int(ceil(dur * FPS))
	for f in range(frames + 1):
		var t := minf(f / FPS, dur)
		var pose := eval_pose(sk, rig, ctx, clip, t)
		for bi in tracks:
			out.rotation_track_insert_key(tracks[bi], t, pose["rot"][bi])
		out.position_track_insert_key(hips_tr, t, pose["hips_pos"])
		out.position_track_insert_key(root_tr, t, pose["root_pos"])

	# jendela gameplay, event, klaim: disimpan sebagai metadata Animation
	out.set_meta("clip_name", clip.get("name", ""))
	out.set_meta("clip_version", clip.get("version", 1))
	out.set_meta("tags", clip.get("tags", []))
	out.set_meta("windows", clip.get("windows", {}))
	out.set_meta("events", clip.get("events", []))
	out.set_meta("claims", clip.get("claims", {}))
	out.set_meta("validate", clip.get("validate", {}))
	return out


## Peringatan jika nilai channel keluar dari range anatomi di rig. Return Array[String].
static func check_channel_ranges(rig: Dictionary, clip: Dictionary) -> Array:
	var warns: Array = []
	var valid := all_channel_names(rig)
	var chs: Dictionary = clip.get("channels", {})
	var dur := float(clip["duration"])
	for cname in chs:
		if not valid.has(cname):
			warns.append("channel tidak dikenal: %s" % cname)
			continue
		var rg := channel_range(rig, cname)
		var f := 0
		var worst := 0.0
		var worst_t := 0.0
		var bad := false
		while f <= int(ceil(dur * FPS)):
			var t := minf(f / FPS, dur)
			var v := sample_keys(chs[cname], t)
			if v < float(rg[0]) - 1e-4 or v > float(rg[1]) + 1e-4:
				var over := maxf(float(rg[0]) - v, v - float(rg[1]))
				if over > worst:
					worst = over
					worst_t = t
				bad = true
			f += 1
		if bad:
			warns.append("channel %s keluar range [%s, %s] maks %.1f di t=%.2fs" % [cname, rg[0], rg[1], worst, worst_t])
	return warns


# ----------------------------------------------------------------------------------------
# Baca pose dunia dari Animation apa pun (untuk validasi)
# ----------------------------------------------------------------------------------------

static func index_tracks(sk: Skeleton3D, anim: Animation) -> Dictionary:
	var m := {}
	for t in anim.get_track_count():
		var bn := str(anim.track_get_path(t)).get_slice(":", 1)
		var bi := sk.find_bone(bn)
		if bi < 0:
			continue
		if not m.has(bi):
			m[bi] = {}
		match anim.track_get_type(t):
			Animation.TYPE_ROTATION_3D: m[bi]["rot"] = t
			Animation.TYPE_POSITION_3D: m[bi]["pos"] = t
	return m


## Transform3D global (frame model, termasuk posisi Root) tiap bone pada waktu t.
static func anim_pose(sk: Skeleton3D, anim: Animation, tracks: Dictionary, t: float) -> Array:
	var n := sk.get_bone_count()
	var g: Array = []
	g.resize(n)
	for i in n:
		var rest := sk.get_bone_rest(i)
		var q := rest.basis.get_rotation_quaternion()
		var o := rest.origin
		if tracks.has(i):
			if tracks[i].has("rot"):
				q = anim.rotation_track_interpolate(tracks[i]["rot"], t)
			if tracks[i].has("pos"):
				o = anim.position_track_interpolate(tracks[i]["pos"], t)
		var l := Transform3D(Basis(q), o)
		var p := sk.get_bone_parent(i)
		g[i] = l if p < 0 else (g[p] as Transform3D) * l
	return g


static func load_clips(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
