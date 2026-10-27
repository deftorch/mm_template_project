extends SceneTree
## Uji tanda/arah channel rig MotusMan secara numerik (tanpa mata).
## Jalankan: godot --headless --path . -s tests/test_clip_rig.gd
const ClipLib := preload("res://clipkit/clip_lib.gd")

var fails := 0
var sk: Skeleton3D
var rig: Dictionary
var ctx: Dictionary

func pose_pos(channels: Dictionary) -> Dictionary:
	var clip := {"duration": 1.0, "channels": {}}
	for k in channels:
		clip["channels"][k] = [[0.0, channels[k]]]
	var anim := ClipLib.build_animation(sk, rig, ctx, clip)
	var g := ClipLib.anim_pose(sk, anim, ClipLib.index_tracks(sk, anim), 0.0)
	var d := {}
	for i in sk.get_bone_count():
		d[sk.get_bone_name(i)] = (g[i] as Transform3D).origin
	return d

func check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  (%s)" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1

func _initialize() -> void:
	rig = ClipLib.load_rig()
	sk = ClipLib.load_skeleton(rig)
	ctx = ClipLib.make_ctx(sk, rig)
	var base := pose_pos({})
	var f := func(v: Vector3) -> String: return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

	# panjang tulang konstan (sanity FK)
	var up := pose_pos({"kneeL": 80.0, "legL_swing": 40.0, "lean": 30.0, "twist": 40.0})
	for pair in [["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["Spine", "Spine1"]]:
		var l0: float = (base[pair[0]] - base[pair[1]]).length()
		var l1: float = (up[pair[0]] - up[pair[1]]).length()
		check("panjang tulang %s-%s konstan" % pair, absf(l0 - l1) < 1e-3, "%.3f vs %.3f" % [l0, l1])
	print("INFO paha=%.3f m  betis=%.3f m  panggul y=%.3f" % [(base["LeftUpLeg"] - base["LeftLeg"]).length(), (base["LeftLeg"] - base["LeftFoot"]).length(), base["Hips"].y])

	# pose default: lengan tergantung, kaki lurus
	var lh: Vector3 = base["LeftHand"]; var ls: Vector3 = base["LeftArm"]
	check("default: tangan kiri tergantung di bawah bahu", lh.y < ls.y - 0.4, "tangan y=%.2f bahu y=%.2f" % [lh.y, ls.y])
	check("default: tangan kiri di sisi kiri (+X)", lh.x > 0.1, "x=%.2f" % lh.x)
	check("default: tangan kanan di sisi kanan (-X)", base["RightHand"].x < -0.1, "x=%.2f" % base["RightHand"].x)

	# arah gerak tiap channel
	var p := pose_pos({"lean": 30.0})
	check("lean +30 -> kepala maju (+Z)", p["Head"].z - base["Head"].z > 0.1, f.call(p["Head"] - base["Head"]))
	p = pose_pos({"side_lean": 20.0})
	check("side_lean +20 -> kepala ke kanan karakter (-X)", p["Head"].x - base["Head"].x < -0.05, f.call(p["Head"] - base["Head"]))
	p = pose_pos({"twist": 30.0})
	check("twist +30 -> dada berputar ke kiri (bahu kanan maju, bahu kiri mundur)", p["RightArm"].z - base["RightArm"].z > 0.05 and p["LeftArm"].z - base["LeftArm"].z < -0.05, "L dz=%.2f R dz=%.2f" % [p["LeftArm"].z - base["LeftArm"].z, p["RightArm"].z - base["RightArm"].z])
	p = pose_pos({"legL_swing": 30.0})
	check("legL_swing +30 -> kaki kiri maju (+Z)", p["LeftFoot"].z - base["LeftFoot"].z > 0.1, f.call(p["LeftFoot"] - base["LeftFoot"]))
	p = pose_pos({"legR_swing": 30.0})
	check("legR_swing +30 -> kaki kanan maju (+Z)", p["RightFoot"].z - base["RightFoot"].z > 0.1, f.call(p["RightFoot"] - base["RightFoot"]))
	p = pose_pos({"legL_abd": 20.0})
	check("legL_abd +20 -> kaki kiri keluar (+X)", p["LeftFoot"].x - base["LeftFoot"].x > 0.05, f.call(p["LeftFoot"] - base["LeftFoot"]))
	p = pose_pos({"legR_abd": 20.0})
	check("legR_abd +20 -> kaki kanan keluar (-X)", p["RightFoot"].x - base["RightFoot"].x < -0.05, f.call(p["RightFoot"] - base["RightFoot"]))
	p = pose_pos({"kneeL": 60.0})
	check("kneeL +60 -> kaki kiri mundur (-Z) dan naik", p["LeftFoot"].z - base["LeftFoot"].z < -0.1 and p["LeftFoot"].y > base["LeftFoot"].y + 0.05, f.call(p["LeftFoot"] - base["LeftFoot"]))
	p = pose_pos({"footL_pitch": 30.0})
	check("footL_pitch +30 -> ujung kaki turun", p["LeftToeBase"].y < base["LeftToeBase"].y - 0.03, f.call(p["LeftToeBase"] - base["LeftToeBase"]))
	p = pose_pos({"hip_y": 0.1, "hip_z": 0.2})
	check("hip_y/hip_z -> panggul bergeser", absf(p["Hips"].y - base["Hips"].y - 0.1) < 1e-3 and absf(p["Hips"].z - base["Hips"].z - 0.2) < 1e-3, f.call(p["Hips"] - base["Hips"]))
	p = pose_pos({"head_yaw": 40.0})
	check("head_yaw bergerak tanpa memindahkan Neck", (p["Neck"] - base["Neck"]).length() < 1e-3, "neck d=%.4f" % (p["Neck"] - base["Neck"]).length())

	# lengan (aim)
	p = pose_pos({"armL_elev": 0.0, "armL_azim": 0.0})
	check("armL elev=0 azim=0 -> tangan lurus ke samping (+X)", p["LeftHand"].x - p["LeftArm"].x > 0.5 and absf(p["LeftHand"].y - p["LeftArm"].y) < 0.08, f.call(p["LeftHand"] - p["LeftArm"]))
	p = pose_pos({"armL_elev": 0.0, "armL_azim": 90.0})
	check("armL elev=0 azim=90 -> tangan lurus ke depan (+Z)", p["LeftHand"].z - p["LeftArm"].z > 0.5, f.call(p["LeftHand"] - p["LeftArm"]))
	p = pose_pos({"armL_elev": 90.0})
	check("armL elev=90 -> tangan di atas bahu", p["LeftHand"].y - p["LeftArm"].y > 0.5, f.call(p["LeftHand"] - p["LeftArm"]))
	p = pose_pos({"armR_elev": 0.0})
	check("armR elev=0 -> tangan kanan ke samping (-X)", p["RightHand"].x - p["RightArm"].x < -0.5, f.call(p["RightHand"] - p["RightArm"]))
	p = pose_pos({"armL_elev": 0.0, "armL_azim": 90.0, "armR_elev": 0.0, "armR_azim": 90.0})
	check("armR elev=0 azim=90 -> tangan kanan ke depan (+Z)", p["RightHand"].z - p["RightArm"].z > 0.5, f.call(p["RightHand"] - p["RightArm"]))

	# siku: tangan menekuk ke depan saat lengan tergantung
	var e0 := pose_pos({"elbowL": 0.0, "elbowR": 0.0})
	var e1 := pose_pos({"elbowL": 80.0, "elbowR": 80.0})
	check("elbowL +80 (lengan tergantung) -> tangan kiri maju (+Z)", e1["LeftHand"].z - e0["LeftHand"].z > 0.15, f.call(e1["LeftHand"] - e0["LeftHand"]))
	check("elbowR +80 (lengan tergantung) -> tangan kanan maju (+Z)", e1["RightHand"].z - e0["RightHand"].z > 0.15, f.call(e1["RightHand"] - e0["RightHand"]))

	print("\nHASIL: %d gagal" % fails)
	quit(1 if fails > 0 else 0)
