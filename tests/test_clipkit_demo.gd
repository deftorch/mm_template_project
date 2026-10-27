extends SceneTree
## Uji jalur input scene demo clipkit (headless).
##   godot --headless --path . -s tests/test_clipkit_demo.gd

var _fail: int = 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fail += 1

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	root.push_input(ev)

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/clipkit_demo.tscn")
	var demo: Node = scene.instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	_check(demo._names.size() >= 3, "klip termuat: %s" % str(demo._names))
	_check(demo._current == demo._names[0], "klip awal = %s" % demo._current)

	_key(KEY_3)
	await process_frame
	_check(demo._current == demo._names[2], "tombol 3 memilih %s" % demo._names[2])
	_check(demo._t < 0.1, "waktu direset saat ganti klip (t=%.3f)" % demo._t)

	_key(KEY_P)
	await process_frame
	_check(demo._paused, "P menjeda")
	var t0: float = demo._t
	_key(KEY_PERIOD)
	await process_frame
	_check(absf(demo._t - (t0 + 1.0 / 30.0)) < 0.002, "'.' maju 1 frame (%.4f -> %.4f)" % [t0, demo._t])
	_key(KEY_COMMA)
	await process_frame
	_check(absf(demo._t - t0) < 0.002, "',' mundur 1 frame")

	_key(KEY_BRACKETRIGHT)
	_check(is_equal_approx(demo._speed, 2.0), "] menggandakan kecepatan")
	_key(KEY_BRACKETLEFT)
	_key(KEY_BRACKETLEFT)
	_check(is_equal_approx(demo._speed, 0.5), "[ [ menjadi x0.5")

	_key(KEY_SPACE)
	await process_frame
	_check(not demo._paused and demo._t < 0.1, "Spasi memutar ulang")

	# pose benar-benar berubah mengikuti klip: tangan kanan bergerak saat slash
	_key(KEY_3)
	demo._speed = 1.0
	demo._paused = true
	demo._t = 0.0
	demo._apply_pose()
	var sk: Skeleton3D = demo._skeleton
	var hand: int = sk.find_bone("RightHand")
	var p0: Vector3 = sk.get_bone_global_pose(hand).origin
	demo._t = 0.45
	demo._apply_pose()
	var p1: Vector3 = sk.get_bone_global_pose(hand).origin
	_check(p0.distance_to(p1) > 0.3, "tangan kanan bergerak %.2f m antara t=0 dan t=0.45" % p0.distance_to(p1))

	# putar normal ~1.2 detik lalu pastikan auto-ulang tidak error
	demo._paused = false
	demo._t = 0.0
	for i in 90:
		await process_frame
	_check(true, "putar normal 90 frame tanpa error")
	print("HASIL: %d gagal" % _fail)
	quit(1 if _fail > 0 else 0)
