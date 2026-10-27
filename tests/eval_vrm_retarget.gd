extends SceneTree
## Evaluasi numerik retarget Motorica -> VRM.
## Membandingkan arah segmen tubuh (sumber vs target) per mode spine.
##   godot --headless --path . -s tests/eval_vrm_retarget.gd -- --clips=Idle_Loop,Run_Circles_CCW --modes=low,mid_top
const RT := preload("res://tools/retarget_motorica_to_vrm.gd")

func _initialize() -> void:
	var clips: PackedStringArray = PackedStringArray()
	var modes: PackedStringArray = PackedStringArray(["low", "mid_top", "mid_top3"])
	var nframes := 24
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = a.substr(8).split(",")
		elif a.begins_with("--modes="):
			modes = a.substr(8).split(",")
		elif a.begins_with("--frames="):
			nframes = int(a.substr(9))
	var tgt_root := (load(RT.TARGET_SCENE) as PackedScene).instantiate()
	var skT: Skeleton3D = tgt_root.find_children("*", "Skeleton3D", true, false)[0]
	var files: Array = []
	RT.collect_fbx(RT.SRC_DIR, files)
	files.sort()
	var chosen: Array = []
	for f in files:
		if clips.is_empty() or str(f).get_file().get_basename() in clips:
			chosen.append(f)
	print("klip dievaluasi: ", chosen.size())
	for mode in modes:
		var seg_sum := {}
		var seg_max := {}
		var seg_n := {}
		var head_err_sum := 0.0
		var head_err_max := 0.0
		var cnt := 0
		var ctx := {}
		for f in chosen:
			var inst := (load(f) as PackedScene).instantiate()
			var skS: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
			var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
			var src: Animation = ap.get_animation("Take 001")
			if ctx.is_empty():
				ctx = RT.build_context(skS, skT, mode)
			var track_of := RT.source_track_map(skS, src)
			var map: Dictionary = ctx["map"]
			for k in nframes:
				var t: float = src.length * float(k) / float(nframes)
				var lp := RT.source_local_pose(skS, src, track_of, t)
				var r := RT.retarget_pose(skS, skT, lp, ctx)
				# posisi global sumber
				var gS := RT.fk_rotations(skS, ctx["orderS"], lp[0])
				var pS := RT.fk_positions(skS, ctx["orderS"], gS, lp[1])
				# posisi global target
				var lpos: Array = []
				for i in skT.get_bone_count():
					lpos.append(skT.get_bone_rest(i).origin)
				lpos[skT.find_bone("Hips")] = r[1]
				var gT := RT.fk_rotations(skT, ctx["orderT"], r[0])
				var pT := RT.fk_positions(skT, ctx["orderT"], gT, lpos)
				for seg in RT.METRIC_SEGMENTS:
					var sa := skS.find_bone(map[seg[0]])
					var sb := skS.find_bone(map[seg[1]])
					var ta := skT.find_bone(seg[0])
					var tb := skT.find_bone(seg[1])
					var ds: Vector3 = ((pS[sb] as Vector3) - (pS[sa] as Vector3)).normalized()
					var dt: Vector3 = ((pT[tb] as Vector3) - (pT[ta] as Vector3)).normalized()
					var ang: float = rad_to_deg(ds.angle_to(dt))
					var key := "%s>%s" % [seg[0], seg[1]]
					seg_sum[key] = float(seg_sum.get(key, 0.0)) + ang
					seg_max[key] = maxf(float(seg_max.get(key, 0.0)), ang)
					seg_n[key] = int(seg_n.get(key, 0)) + 1
				# posisi kepala relatif pinggul (sumber x rasio) vs target
				var hs := skS.find_bone("Hips")
				var hd := skS.find_bone("Head")
				var ht := skT.find_bone("Hips")
				var hdt := skT.find_bone("Head")
				var es: Vector3 = ((pS[hd] as Vector3) - (pS[hs] as Vector3)) * (ctx["hips_ratio"] as float)
				var et: Vector3 = (pT[hdt] as Vector3) - (pT[ht] as Vector3)
				var he: float = (es - et).length()
				head_err_sum += he
				head_err_max = maxf(head_err_max, he)
				cnt += 1
			inst.free()
		print("=== mode=", mode, "  frames=", cnt, "  ratio=%.4f" % ctx["hips_ratio"])
		var total := 0.0
		for key in seg_sum:
			var mean: float = float(seg_sum[key]) / float(seg_n[key])
			total += mean
			print("   %-28s mean=%5.2f deg  max=%6.2f deg" % [key, mean, seg_max[key]])
		print("   rata-rata semua segmen = %.2f deg ; kepala vs pinggul: mean=%.3f m max=%.3f m" % [total / seg_sum.size(), head_err_sum / cnt, head_err_max])
	tgt_root.free()
	quit(0)
