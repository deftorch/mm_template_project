extends SceneTree
## Tes smoke demo perbandingan dataset VRM (scenes/vrm_dataset_demo.tscn).
##   godot --headless --fixed-fps 60 --path . -s tests/test_vrm_dataset_demo.gd
## Opsi: -- --skip-sweep (lewati sapuan 274 klip)
## Exit code 1 bila ada FAIL.
var demo: Node
var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func step(n: int) -> void:
	for i in n:
		await process_frame

func hips_world(s) -> Vector3:
	var sk: Skeleton3D = s.character.skeleton
	var hi := sk.find_bone("Hips")
	return (sk.global_transform * sk.get_bone_global_pose(hi)).origin

func finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _initialize() -> void:
	demo = (load("res://scenes/vrm_dataset_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)
	await step(5)
	await run_tests()
	print("=== %s (%d FAIL)" % ["LULUS" if fails == 0 else "GAGAL", fails])
	quit(0 if fails == 0 else 1)

func run_tests() -> void:
	var skip_sweep := "--skip-sweep" in OS.get_cmdline_user_args()
	check(demo.slots.size() == 2, "demo mulai dengan 2 slot")
	check(demo.o3de_clips.size() == 22, "library O3DE terpasang: %d klip" % demo.o3de_clips.size())
	check(demo.motorica_clips.size() == 252, "library Motorica terpasang: %d klip" % demo.motorica_clips.size())
	check(demo._mm_node(demo.slots[0]) != demo._mm_node(demo.slots[1]), "tiap slot punya MMAnimationNode sendiri")

	# T1: isolasi dataset + skenario
	demo.set_scenario(true)
	await step(60 * 30)
	for s in demo.slots:
		var wrong := 0
		for n in s.used:
			if (s.dataset == "o3de") != (n in demo.o3de_clips):
				wrong += 1
		check(s.query_count > 20 and wrong == 0, "slot %d (%s): %d query, %d klip unik, klip dari dataset salah=%d" % [s.index, s.dataset, s.query_count, s.used.size(), wrong])
		check(finite(hips_world(s)) and hips_world(s).y > 0.5 and hips_world(s).y < 1.3, "slot %d pinggul sehat (y=%.2f)" % [s.index, hips_world(s).y])
	demo.set_scenario(false)
	demo.test_input = null

	# T2: semua preset konfigurasi (pada slot Motorica) tanpa error dan MM tetap jalan
	for p in demo.CONFIG_PRESETS:
		demo.apply_preset(1, p)
		var q0: int = demo.slots[1].query_count
		demo.test_input = {"dir": Vector3(0, 0, 1), "gait": 2}
		await step(150)
		var ok: bool = demo.slots[1].query_count > q0 and finite(hips_world(demo.slots[1]))
		check(ok, "preset '%s': +%d query, kecepatan %.2f m/s" % [p, demo.slots[1].query_count - q0, Vector2(demo.slots[1].character.velocity.x, demo.slots[1].character.velocity.z).length()])
	demo.apply_preset(1, "Default proyek")

	# T3: ganti dataset saat runtime (A -> Motorica -> O3DE)
	for ds in ["motorica", "o3de"]:
		demo.set_slot_dataset(0, ds)
		demo.test_input = {"dir": Vector3(0, 0, 1), "gait": 2}
		await step(240)
		var wrong := 0
		for n in demo.slots[0].used:
			if (ds == "o3de") != (n in demo.o3de_clips):
				wrong += 1
		check(demo.slots[0].used.size() > 0 and wrong == 0, "ganti dataset runtime -> %s: %d klip unik, salah=%d" % [ds, demo.slots[0].used.size(), wrong])
	demo.set_slot_dataset(0, "o3de")
	demo.test_input = null

	# T4: jumlah slot
	demo.set_slot_count(3)
	await step(5)
	check(demo.slots.size() == 3, "3 slot")
	demo.set_slot_count(1)
	await step(5)
	check(demo.slots.size() == 1, "1 slot")
	demo.set_slot_count(2)
	demo.set_slot_dataset(0, "o3de")
	demo.set_slot_dataset(1, "motorica")
	await step(5)

	# T5: browser klip -> gerak root, lalu kembali ke MM
	var s0 = demo.slots[1]
	demo.active_slot = 1
	var runfwd := ""
	for c in demo.catalog:
		if c["category"] == "running" and c["group"] == "forward":
			runfwd = c["name"]
			break
	demo.reset_slots()
	await step(5)
	var p_before: Vector3 = demo._slot_position(s0)
	demo._browser_play(s0, "vrm_motorica_library/" + runfwd)
	await step(120)
	var moved: float = (demo._slot_position(s0) - p_before).length()
	check(s0.browser_clip != "" and moved > 1.5, "browser: klip %s menggerakkan root %.2f m dalam 2 dtk" % [runfwd, moved])
	check(hips_world(s0).y > 0.5 and hips_world(s0).y < 1.3, "browser: pinggul wajar (y=%.2f)" % hips_world(s0).y)
	demo._browser_stop(s0)
	var qb: int = s0.query_count
	demo.test_input = {"dir": Vector3(0, 0, 1), "gait": 2}
	await step(180)
	check(s0.browser_clip == "" and s0.query_count > qb and Vector2(s0.character.velocity.x, s0.character.velocity.z).length() > 1.0,
			"kembali ke gameplay MM: +%d query, kecepatan %.2f" % [s0.query_count - qb, Vector2(s0.character.velocity.x, s0.character.velocity.z).length()])

	if skip_sweep:
		return
	# T6: sapuan semua klip (Motorica 252 + O3DE 22) lewat browser
	var bad: Array = []
	var total := 0
	var sweep_slot = demo.slots[1]
	for pair in [["vrm_motorica_library", demo.motorica_clips], ["vrm_motion_library", demo.o3de_clips]]:
		for name in pair[1]:
			demo._browser_play(sweep_slot, "%s/%s" % [pair[0], name])
			await step(25)
			total += 1
			var h := hips_world(sweep_slot)
			var ap: AnimationPlayer = demo._anim_player(sweep_slot)
			if not (finite(h) and h.y > 0.45 and h.y < 1.35 and ap.is_playing() and ap.current_animation_position > 0.0):
				bad.append("%s/%s (y=%.2f playing=%s)" % [pair[0], name, h.y, ap.is_playing()])
	check(bad.is_empty(), "sapuan %d klip: %d bermasalah %s" % [total, bad.size(), str(bad.slice(0, 5))])
	demo._browser_stop(sweep_slot)
