extends Node3D
## Demo perbandingan dataset animasi pada karakter VRM (three-vrm-girl):
##   - O3DE      : animasi bawaan template sebelumnya (22 klip panjang)
##   - Motorica  : 252 klip Motorica hasil retarget ke VRM (tools/retarget_motorica_to_vrm.gd)
## Fitur:
##   * 1-3 karakter berdampingan, masing-masing dataset + konfigurasi MM sendiri, input SAMA
##   * Panel konfigurasi (query_frequency, transition_halflife, blending, halflife, synchronizer,
##     root motion, history, kecepatan gait) + preset
##   * Skenario otomatis identik untuk semua karakter (adil untuk perbandingan)
##   * Browser klip: putar langsung SEMUA klip (22 O3DE + 252 Motorica), tur otomatis
##   * Cakupan: klip Motorica mana saja yang pernah dipilih motion matching
## Tombol: lihat tab "Bantuan" atau tekan F1 untuk menyembunyikan panel.

const VRM_SCENE := preload("res://animation/three_vrm_girl.tscn")
const CameraRig := preload("res://scripts/mm_camera_rig.gd")
const CATALOG_PATH := "res://animation/motorica_vrm_catalog.json"

const DATASETS := {
	"o3de": {"label": "O3DE (animasi sebelumnya)", "short": "O3DE", "library": &"vrm_motion_library",
			"speeds": [1.5, 3.0, 3.8]},
	"motorica": {"label": "Motorica (252 klip)", "short": "Motorica", "library": &"vrm_motorica_library",
			"speeds": [1.05, 3.1, 4.6]},
}
const DATASET_KEYS := ["o3de", "motorica"]

const SYNC_TYPES := ["mix", "clamp", "root_motion"]
const SYNC_LABELS := ["Mix (campur root motion + fisika)", "Clamp (batasi jarak)", "RootMotion (murni animasi)"]

const DEFAULT_CFG := {
	"query_frequency": 2.0, "transition_halflife": 0.1, "blending": true,
	"halflife": 0.5, "history_dt": 0.1, "traj_dt": 0.5, "check_env": true,
	"sync": "mix", "root_motion": 0.45, "clamp_distance": 0.2,
}
const CONFIG_PRESETS := {
	"Default proyek": {},
	"Responsif (query cepat)": {"query_frequency": 8.0, "transition_halflife": 0.05, "halflife": 0.2},
	"Halus (query lambat)": {"query_frequency": 1.0, "transition_halflife": 0.25, "halflife": 0.8},
	"Tanpa blending": {"blending": false},
	"Root motion 100%": {"root_motion": 1.0},
	"Tanpa root motion": {"root_motion": 0.0},
	"Sync RootMotion": {"sync": "root_motion"},
	"Sync Clamp": {"sync": "clamp"},
}

## Skenario otomatis: gait 0=diam 1=jalan 2=lari 3=sprint; turn = derajat/detik; dir = arah relatif (derajat)
const SCENARIO := [
	{"t": 2.0, "gait": 0}, {"t": 4.0, "gait": 1}, {"t": 5.0, "gait": 2}, {"t": 4.0, "gait": 3},
	{"t": 3.0, "gait": 2, "turn": 60.0}, {"t": 3.0, "gait": 2, "turn": -60.0},
	{"t": 3.0, "gait": 1, "turn": 90.0}, {"t": 2.5, "gait": 0},
	{"t": 4.0, "gait": 2, "strafe": true, "dir": 90.0}, {"t": 4.0, "gait": 2, "strafe": true, "dir": -90.0},
	{"t": 3.0, "gait": 1, "strafe": true, "dir": 180.0}, {"t": 3.0, "gait": 2, "strafe": true, "dir": 45.0},
	{"t": 3.0, "gait": 3}, {"t": 2.5, "gait": 0}, {"t": 3.0, "gait": 2, "turn": 180.0}, {"t": 2.0, "gait": 0},
]

const SLOT_NAMES := ["A", "B", "C"]
const SLOT_SPACING := 1.8
const SLOT_COLORS := [Color(0.35, 0.65, 1.0), Color(1.0, 0.6, 0.25), Color(0.5, 0.9, 0.5)]


class Slot extends RefCounted:
	var index := 0
	var character: MMCharacter
	var dataset := "o3de"
	var cfg: Dictionary = {}
	var used: Dictionary = {}
	var last: Dictionary = {}
	var label3d: Label3D
	var browser_clip := ""         # "lib/clip" bila sedang mode browser, kosong = gameplay MM
	var browser_pos := Vector3.ZERO
	var browser_yaw := 0.0
	var browser_loop := true
	var ui: Dictionary = {}
	var gait_speeds: Array = [1.5, 3.0, 3.8]
	var facing := 0.0
	var facing_vel := 0.0
	var query_count := 0


var slots: Array[Slot] = []
var catalog: Array = []
var catalog_by_name: Dictionary = {}
var o3de_clips: PackedStringArray = PackedStringArray()
var motorica_clips: PackedStringArray = PackedStringArray()

var cam_target: Node3D
var rig: Node3D
var active_slot := 0
var scenario_on := false
var scenario_t := 0.0
var scenario_heading := 0.0
var scenario_total := 0.0
var scenario_loops := 0
## Input terprogram (untuk tes/otomasi): {"dir": Vector3 (dunia), "gait": 1..3, "strafe": bool}; null = input pengguna
var test_input: Variant = null
## Eksplorasi acak: gait/belokan/strafe berubah acak (seed tetap) supaya MM menjelajah lebih banyak klip
var explore_on := false
var explore_step: Dictionary = {}
var explore_left := 0.0
var explore_rng := RandomNumberGenerator.new()

# UI
var ui_layer: CanvasLayer
var panel: PanelContainer
var tabs: TabContainer
var slot_tabs: TabContainer
var hud_box: HBoxContainer
var hud_labels: Array[Label] = []
var status_label: Label
var clip_list: ItemList
var clip_filter_edit: LineEdit
var clip_group_opt: OptionButton
var clip_dataset_opt: OptionButton
var clip_info: Label
var clip_speed: HSlider
var clip_loop_chk: CheckBox
var tour_on := false
var tour_index := 0
var tour_timer := 0.0
var tour_seconds := 4.0
var tour_label: Label
var coverage_bar: ProgressBar
var coverage_text: TextEdit
var coverage_label: Label
var slot_count_opt: OptionButton
var shown_clips: Array = []   # daftar klip yang tampil di ItemList (nama)


func _ready() -> void:
	_load_catalog()
	_build_world()
	_build_ui()
	set_slot_count(2)
	set_slot_dataset(0, "o3de")
	set_slot_dataset(1, "motorica")
	_refresh_clip_list()
	_refresh_coverage()


# ------------------------------------------------------------------------------------------
# Data

func _load_catalog() -> void:
	if FileAccess.file_exists(CATALOG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			catalog = parsed["clips"]
	for c in catalog:
		catalog_by_name[c["name"]] = c
	# daftar klip diambil dari library yang benar-benar terpasang di AnimationPlayer
	var probe: MMCharacter = VRM_SCENE.instantiate()
	var ap: AnimationPlayer = probe.animation_tree.get_node(probe.animation_tree.anim_player)
	if ap.has_animation_library(&"vrm_motion_library"):
		o3de_clips = ap.get_animation_library(&"vrm_motion_library").get_animation_list()
	if ap.has_animation_library(&"vrm_motorica_library"):
		motorica_clips = ap.get_animation_library(&"vrm_motorica_library").get_animation_list()
	probe.free()


func clip_names(dataset: String) -> PackedStringArray:
	return o3de_clips if dataset == "o3de" else motorica_clips


# ------------------------------------------------------------------------------------------
# Dunia 3D

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var mat := StandardMaterial3D.new()
	var grid := load("res://textures/grid_texture.png") as Texture2D
	if grid != null:
		mat.albedo_texture = grid
		mat.uv1_scale = Vector3(100, 100, 1)
	mat.albedo_color = Color(0.85, 0.85, 0.9)
	plane.material = mat
	mesh.mesh = plane
	floor_body.add_child(mesh)
	add_child(floor_body)

	cam_target = Node3D.new()
	cam_target.name = "CamTarget"
	add_child(cam_target)
	rig = Node3D.new()
	rig.set_script(CameraRig)
	rig.set("target", cam_target)
	rig.set("dynamic_fov", false)
	rig.set("distance", 5.0)
	rig.set("height", 1.2)
	rig.set("shoulder_offset", 0.0)
	rig.set("strafe_distance", 5.0)
	rig.set("collision_mask", 0)
	rig.name = "CameraRig"
	add_child(rig)


# ------------------------------------------------------------------------------------------
# Slot karakter

func set_slot_count(n: int) -> void:
	n = clampi(n, 1, 3)
	while slots.size() > n:
		var s: Slot = slots.pop_back()
		s.character.queue_free()
		slot_tabs.get_child(slot_tabs.get_child_count() - 1).queue_free()
	while slots.size() < n:
		_create_slot(slots.size())
	for s in slots:
		_place_slot(s)
	if active_slot >= slots.size():
		active_slot = 0
	_update_hud_visibility()
	if slot_count_opt != null:
		slot_count_opt.select(n - 1)


func _create_slot(i: int) -> void:
	var s := Slot.new()
	s.index = i
	s.cfg = DEFAULT_CFG.duplicate()
	var c: MMCharacter = VRM_SCENE.instantiate()
	# Tiap karakter WAJIB punya MMAnimationNode sendiri. Resource di scene bersifat shared dan
	# tree_root.duplicate(true) TIDAK menggandakan node di dalamnya (terbukti: dua slot saling menimpa
	# properti `library`), jadi blend tree dibangun ulang dengan salinan node.
	var src_bt: AnimationNodeBlendTree = c.animation_tree.tree_root
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"MMAnimationNode", src_bt.get_node(&"MMAnimationNode").duplicate(), Vector2(-300, 0))
	bt.connect_node(&"output", 0, &"MMAnimationNode")
	c.animation_tree.tree_root = bt
	c.emit_result_signal = true
	c.collision_layer = 2 << i
	c.collision_mask = 1
	c.name = "Girl%s" % SLOT_NAMES[i]
	add_child(c)
	s.character = c
	c.on_query_result.connect(_on_query_result.bind(s))
	s.label3d = Label3D.new()
	s.label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.label3d.position = Vector3(0, 1.85, 0)
	s.label3d.font_size = 40
	s.label3d.pixel_size = 0.003
	s.label3d.no_depth_test = true
	s.label3d.modulate = SLOT_COLORS[i]
	c.add_child(s.label3d)
	slots.append(s)
	_build_slot_tab(s)
	_apply_dataset_and_cfg(s)


func _place_slot(s: Slot) -> void:
	var x := (s.index - (slots.size() - 1) * 0.5) * SLOT_SPACING
	s.character.global_position = Vector3(x, 0.05, 0.0)
	s.character.global_rotation = Vector3.ZERO
	s.character.velocity = Vector3.ZERO
	s.browser_pos = s.character.global_position
	s.browser_yaw = 0.0


func reset_slots() -> void:
	for s in slots:
		_place_slot(s)
		if s.browser_clip != "":
			_browser_play(s, s.browser_clip)


func set_slot_dataset(i: int, dataset: String) -> void:
	if i >= slots.size():
		return
	var s := slots[i]
	s.dataset = dataset
	s.used.clear()
	s.last = {}
	s.gait_speeds = (DATASETS[dataset]["speeds"] as Array).duplicate()
	_apply_dataset_and_cfg(s)
	_sync_slot_ui(s)
	_refresh_coverage()


func apply_preset(i: int, preset_name: String) -> void:
	var s := slots[i]
	s.cfg = DEFAULT_CFG.duplicate()
	for k in CONFIG_PRESETS[preset_name]:
		s.cfg[k] = CONFIG_PRESETS[preset_name][k]
	_apply_dataset_and_cfg(s)
	_sync_slot_ui(s)


func _mm_node(s: Slot) -> Object:
	var at: AnimationTree = s.character.animation_tree
	return at.tree_root.get_node("MMAnimationNode")


func _apply_dataset_and_cfg(s: Slot) -> void:
	var c := s.character
	var node := _mm_node(s)
	node.set("library", DATASETS[s.dataset]["library"])
	node.set("query_frequency", float(s.cfg["query_frequency"]))
	node.set("transition_halflife", float(s.cfg["transition_halflife"]))
	node.set("blending_enabled", bool(s.cfg["blending"]))
	c.halflife = float(s.cfg["halflife"])
	c.history_delta_time = float(s.cfg["history_dt"])
	c.trajectory_delta_time = float(s.cfg["traj_dt"])
	c.check_environment = bool(s.cfg["check_env"])
	var want: String = s.cfg["sync"]
	var cur: Variant = c.synchronizer
	var cur_type := ""
	if cur is MMMixSynchronizer:
		cur_type = "mix"
	elif cur is MMClampSynchronizer:
		cur_type = "clamp"
	elif cur is MMRootMotionSynchronizer:
		cur_type = "root_motion"
	if cur_type != want:
		match want:
			"mix":
				c.synchronizer = MMMixSynchronizer.new()
			"clamp":
				c.synchronizer = MMClampSynchronizer.new()
			_:
				c.synchronizer = MMRootMotionSynchronizer.new()
	if c.synchronizer is MMMixSynchronizer:
		(c.synchronizer as MMMixSynchronizer).root_motion_amount = float(s.cfg["root_motion"])
	elif c.synchronizer is MMClampSynchronizer:
		(c.synchronizer as MMClampSynchronizer).clamp_distance = float(s.cfg["clamp_distance"])
	s.label3d.text = "%s · %s" % [SLOT_NAMES[s.index], DATASETS[s.dataset]["short"]]


func _on_query_result(result: Dictionary, s: Slot) -> void:
	s.last = result
	s.query_count += 1
	var anim := str(result.get("animation", ""))
	if anim != "":
		var clip := anim.get_slice("/", 1)
		s.used[clip] = int(s.used.get(clip, 0)) + 1


# ------------------------------------------------------------------------------------------
# Input (satu input untuk semua karakter) + skenario

func _physics_process(delta: float) -> void:
	if slots.is_empty():
		return
	var yaw: float = rig.rotation.y
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))
	var dir := Vector3.ZERO
	var gait := 2          # 1 jalan, 2 lari, 3 sprint
	var strafing := false
	var moving := false

	if test_input is Dictionary:
		dir = (test_input["dir"] as Vector3).normalized()
		gait = int(test_input.get("gait", 2))
		strafing = bool(test_input.get("strafe", false))
		moving = dir.length() > 0.01
	elif scenario_on or explore_on:
		var st: Dictionary
		if explore_on:
			explore_left -= delta
			if explore_left <= 0.0:
				_explore_pick()
			st = explore_step
		else:
			scenario_t += delta
			st = SCENARIO[_scenario_step_index()]
		scenario_heading += deg_to_rad(float(st.get("turn", 0.0))) * delta
		var rel := deg_to_rad(float(st.get("dir", 0.0)))
		var h := scenario_heading + rel
		dir = (fwd * cos(h) + right * (-sin(h))).normalized()
		gait = int(st["gait"])
		moving = gait > 0
		strafing = bool(st.get("strafe", false))
		if not moving:
			dir = Vector3.ZERO
	else:
		var stick := Vector2(
				float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
				float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		dir = right * stick.x + fwd * (-stick.y)
		moving = dir.length() > 0.01
		if Input.is_key_pressed(KEY_CTRL):
			gait = 1
		elif Input.is_key_pressed(KEY_SHIFT):
			gait = 3
		strafing = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	for s in slots:
		if s.browser_clip != "":
			continue
		var sp: float = 0.0
		if moving:
			sp = float(s.gait_speeds[clampi(gait, 1, 3) - 1])
		s.character.target_velocity = dir * sp
		s.character.is_strafing = strafing
		if strafing:
			var r := _step_angle(s.facing, s.facing_vel, yaw, 0.1, delta)
			s.facing = r[0]
			s.facing_vel = r[1]
		else:
			s.facing = s.character.rotation.y
			s.facing_vel = 0.0
		s.character.strafe_facing = s.facing

	if scenario_on and test_input == null and scenario_t >= scenario_total:
		scenario_t = 0.0
		scenario_loops += 1
		scenario_heading = 0.0
		if _far_from_origin():
			reset_slots()


func _explore_pick() -> void:
	var r := explore_rng
	var gait_roll := r.randf()
	var gait := 0 if gait_roll < 0.12 else (1 if gait_roll < 0.37 else (2 if gait_roll < 0.72 else 3))
	var st := {"gait": gait}
	if r.randf() < 0.6:
		st["turn"] = r.randf_range(30.0, 150.0) * (1.0 if r.randf() < 0.5 else -1.0)
	if r.randf() < 0.4:
		st["strafe"] = true
		st["dir"] = [0.0, 45.0, 90.0, 135.0, 180.0, -45.0, -90.0, -135.0][r.randi() % 8]
	explore_step = st
	explore_left = r.randf_range(1.5, 5.0)
	if _far_from_origin() and gait == 0:
		reset_slots()


func set_explore(on: bool) -> void:
	explore_on = on
	explore_left = 0.0
	scenario_heading = 0.0
	explore_rng.seed = 20260428
	if on:
		scenario_on = false
		for s in slots:
			if s.browser_clip != "":
				_browser_stop(s)


func _far_from_origin() -> bool:
	for s in slots:
		if s.character.global_position.length() > 25.0:
			return true
	return false


func _scenario_step_index() -> int:
	var t := scenario_t
	for i in SCENARIO.size():
		t -= float(SCENARIO[i]["t"])
		if t < 0.0:
			return i
	return SCENARIO.size() - 1


func set_scenario(on: bool) -> void:
	if on:
		explore_on = false
	scenario_on = on
	scenario_t = 0.0
	scenario_heading = 0.0
	if scenario_total == 0.0:
		for st in SCENARIO:
			scenario_total += float(st["t"])
	if on:
		for s in slots:
			if s.browser_clip != "":
				_browser_stop(s)


static func _step_angle(angle: float, vel: float, goal: float, halflife: float, dt: float) -> Array:
	var y: float = (4.0 * 0.69314718056) / (halflife + 1e-5) / 2.0
	var j0: float = wrapf(angle - goal, -PI, PI)
	var j1: float = vel + j0 * y
	var e: float = exp(-y * dt)
	return [goal + e * (j0 + j1 * dt), e * (vel - j1 * y * dt)]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				panel.visible = not panel.visible
			KEY_F2:
				set_scenario(not scenario_on)
			KEY_F3:
				set_explore(not explore_on)
			KEY_R:
				reset_slots()
			KEY_SPACE:
				for s in slots:
					if s.browser_clip == "" and s.character.is_on_floor():
						s.character.velocity += Vector3.UP * 5.0
			KEY_1, KEY_2, KEY_3:
				var idx: int = int(event.keycode - KEY_1)
				if idx < slots.size():
					active_slot = idx
					slot_tabs.current_tab = idx


# ------------------------------------------------------------------------------------------
# Browser klip (putar langsung satu klip, melewati motion matching)

func _anim_player(s: Slot) -> AnimationPlayer:
	var at: AnimationTree = s.character.animation_tree
	return at.get_node(at.anim_player) as AnimationPlayer


func _skeleton(s: Slot) -> Skeleton3D:
	return s.character.skeleton


func _browser_play(s: Slot, full_name: String) -> void:
	var ap := _anim_player(s)
	if not ap.has_animation(full_name):
		push_warning("Klip tidak ada: " + full_name)
		return
	s.browser_clip = full_name
	var at: AnimationTree = s.character.animation_tree
	at.active = false
	s.character.set_physics_process(false)
	s.character.velocity = Vector3.ZERO
	var sk := _skeleton(s)
	s.browser_pos = Vector3(s.character.global_position.x, 0.0, s.character.global_position.z)
	s.browser_yaw = 0.0
	sk.global_transform = Transform3D(Basis.IDENTITY, s.browser_pos)
	ap.speed_scale = clip_speed.value if clip_speed != null else 1.0
	ap.play(full_name)
	if not ap.animation_finished.is_connected(_on_browser_finished.bind(s)):
		ap.animation_finished.connect(_on_browser_finished.bind(s))
	s.label3d.text = "%s · klip" % SLOT_NAMES[s.index]
	if s.index == active_slot:
		_update_clip_info(full_name)


func _on_browser_finished(_anim: StringName, s: Slot) -> void:
	if s.browser_clip == "":
		return
	if s.browser_loop and not tour_on:
		_browser_play(s, s.browser_clip)


func _browser_stop(s: Slot) -> void:
	if s.browser_clip == "":
		return
	var ap := _anim_player(s)
	ap.stop()
	s.browser_clip = ""
	var sk := _skeleton(s)
	# kembalikan badan fisika ke posisi skeleton terakhir lalu aktifkan lagi MM
	s.character.global_position = Vector3(sk.global_position.x, 0.05, sk.global_position.z)
	s.character.global_rotation = Vector3(0.0, sk.global_basis.get_euler().y, 0.0)
	s.character.velocity = Vector3.ZERO
	s.character.set_physics_process(true)
	s.character.animation_tree.active = true
	s.label3d.text = "%s · %s" % [SLOT_NAMES[s.index], DATASETS[s.dataset]["short"]]


func _process(delta: float) -> void:
	# kamera mengikuti titik tengah semua karakter
	if not slots.is_empty():
		var sum := Vector3.ZERO
		for s in slots:
			sum += _slot_position(s)
		cam_target.global_position = sum / float(slots.size())
	for s in slots:
		if s.browser_clip != "":
			_browser_apply_root_motion(s)
	if tour_on:
		_tour_step(delta)
	_update_hud()


func _slot_position(s: Slot) -> Vector3:
	if s.browser_clip != "":
		return s.browser_pos
	return s.character.global_position


func _browser_apply_root_motion(s: Slot) -> void:
	var ap := _anim_player(s)
	if not ap.is_playing():
		return
	var sk := _skeleton(s)
	var rp := ap.get_root_motion_position()
	var racc := ap.get_root_motion_rotation_accumulator()
	s.browser_pos += rp
	sk.global_transform = Transform3D(Basis(racc), s.browser_pos)
	if Vector2(s.browser_pos.x - s.character.global_position.x, s.browser_pos.z - s.character.global_position.z).length() > 30.0:
		_browser_play(s, s.browser_clip)


func _tour_step(delta: float) -> void:
	tour_timer -= delta
	if tour_timer > 0.0:
		return
	if tour_index >= shown_clips.size():
		_tour_stop()
		return
	var s := slots[active_slot]
	var ds := _clip_dataset()
	var lib: String = str(DATASETS[ds]["library"])
	s.character.global_position = Vector3(s.character.global_position.x, 0.05, s.character.global_position.z)
	_browser_play(s, "%s/%s" % [lib, shown_clips[tour_index]])
	clip_list.select(tour_index)
	clip_list.ensure_current_is_visible()
	tour_label.text = "Tur: %d / %d  (%s)" % [tour_index + 1, shown_clips.size(), shown_clips[tour_index]]
	tour_index += 1
	tour_timer = tour_seconds


func _tour_stop() -> void:
	tour_on = false
	tour_label.text = "Tur selesai."


# ------------------------------------------------------------------------------------------
# UI

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	hud_box = HBoxContainer.new()
	hud_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud_box.offset_right = -400
	hud_box.offset_left = 8
	hud_box.offset_top = 8
	hud_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_box.add_theme_constant_override("separation", 8)
	ui_layer.add_child(hud_box)
	for i in 3:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.border_color = SLOT_COLORS[i]
		sb.set_border_width_all(2)
		sb.set_content_margin_all(6)
		pc.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		pc.add_child(l)
		hud_box.add_child(pc)
		hud_labels.append(l)

	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(12, -70)
	status_label.size = Vector2(740, 56)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(status_label)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -392
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	ui_layer.add_child(panel)
	tabs = TabContainer.new()
	panel.add_child(tabs)

	_build_tab_config()
	_build_tab_clips()
	_build_tab_coverage()
	_build_tab_help()


func _scroll_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return vb


func _build_tab_config() -> void:
	var vb := _scroll_tab("Konfigurasi")
	vb.add_child(_header("Jumlah karakter (perbandingan)"))
	slot_count_opt = OptionButton.new()
	for n in ["1 karakter", "2 karakter (A vs B)", "3 karakter"]:
		slot_count_opt.add_item(n)
	slot_count_opt.item_selected.connect(func(i: int) -> void: set_slot_count(i + 1))
	vb.add_child(slot_count_opt)

	var hb := HFlowContainer.new()
	var b1 := Button.new()
	b1.text = "Skenario (F2)"
	b1.toggle_mode = true
	b1.toggled.connect(func(on: bool) -> void: set_scenario(on))
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "Reset (R)"
	b2.pressed.connect(reset_slots)
	hb.add_child(b2)
	var b2b := Button.new()
	b2b.text = "Acak (F3)"
	b2b.toggle_mode = true
	b2b.toggled.connect(func(on: bool) -> void: set_explore(on))
	hb.add_child(b2b)
	vb.add_child(hb)
	var b3 := Button.new()
	b3.text = "Salin config A -> slot lain"
	b3.pressed.connect(_copy_cfg_from_a)
	vb.add_child(b3)
	var b4 := Button.new()
	b4.text = "Salin config (JSON) ke clipboard"
	b4.pressed.connect(func() -> void: DisplayServer.clipboard_set(export_config_json()))
	vb.add_child(b4)

	slot_tabs = TabContainer.new()
	slot_tabs.custom_minimum_size = Vector2(0, 520)
	slot_tabs.tab_changed.connect(func(i: int) -> void: active_slot = i)
	vb.add_child(slot_tabs)


func _build_slot_tab(s: Slot) -> void:
	var sc := ScrollContainer.new()
	sc.name = "Slot " + SLOT_NAMES[s.index]
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_tabs.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)

	vb.add_child(_header("Dataset animasi"))
	var ds := OptionButton.new()
	for k in DATASET_KEYS:
		ds.add_item(DATASETS[k]["label"])
	ds.item_selected.connect(func(i: int) -> void: set_slot_dataset(s.index, DATASET_KEYS[i]))
	vb.add_child(ds)
	s.ui["dataset"] = ds

	vb.add_child(_header("Preset konfigurasi"))
	var pr := OptionButton.new()
	for k in CONFIG_PRESETS:
		pr.add_item(k)
	pr.item_selected.connect(func(i: int) -> void: apply_preset(s.index, pr.get_item_text(i)))
	vb.add_child(pr)

	vb.add_child(_header("Motion matching (MMAnimationNode)"))
	_cfg_slider(vb, s, "query_frequency", "query_frequency (Hz)", 0.5, 12.0, 0.5)
	_cfg_slider(vb, s, "transition_halflife", "transition_halflife (dtk)", 0.01, 0.6, 0.01)
	_cfg_check(vb, s, "blending", "blending_enabled")

	vb.add_child(_header("Karakter (MMCharacter)"))
	_cfg_slider(vb, s, "halflife", "halflife gerak (dtk)", 0.05, 1.5, 0.05)
	_cfg_slider(vb, s, "history_dt", "history_delta_time (dtk)", 0.03, 0.4, 0.01)
	_cfg_slider(vb, s, "traj_dt", "trajectory_delta_time (dtk)", 0.2, 1.0, 0.05)
	_cfg_check(vb, s, "check_env", "check_environment")

	vb.add_child(_header("Synchronizer (animasi <-> fisika)"))
	var so := OptionButton.new()
	for t in SYNC_LABELS:
		so.add_item(t)
	so.item_selected.connect(func(i: int) -> void:
		s.cfg["sync"] = SYNC_TYPES[i]
		_apply_dataset_and_cfg(s))
	vb.add_child(so)
	s.ui["sync"] = so
	_cfg_slider(vb, s, "root_motion", "root_motion_amount (Mix)", 0.0, 1.0, 0.05)
	_cfg_slider(vb, s, "clamp_distance", "clamp_distance (Clamp)", 0.0, 1.0, 0.05)

	vb.add_child(_header("Kecepatan gait input (m/s)"))
	var gl := ["jalan (Ctrl)", "lari (default)", "sprint (Shift)"]
	for gi in 3:
		var sp := _slider_row(vb, "kecepatan " + gl[gi], 0.3, 7.0, 0.05, float(s.gait_speeds[gi]),
				func(v: float) -> void: s.gait_speeds[gi] = v)
		s.ui["gait%d" % gi] = sp
	var hint := Label.new()
	hint.text = "Jaga kecepatan di dalam rentang data animasi. Kecepatan di luar rentang\nmembuat matcher memilih klip terdekat -> kaki terlihat meluncur."
	hint.add_theme_font_size_override("font_size", 11)
	vb.add_child(hint)
	_sync_slot_ui(s)


func _header(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	l.add_theme_font_size_override("font_size", 14)
	return l


func _slider_row(parent: Control, title: String, mn: float, mx: float, st: float, val: float, cb: Callable) -> HSlider:
	var row := VBoxContainer.new()
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 12)
	l.text = "%s: %s" % [title, str(snappedf(val, 0.001))]
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = st
	sl.value = val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float) -> void:
		l.text = "%s: %s" % [title, str(snappedf(v, 0.001))]
		cb.call(v))
	sl.set_meta("label", l)
	sl.set_meta("title", title)
	row.add_child(sl)
	parent.add_child(row)
	return sl


func _cfg_slider(parent: Control, s: Slot, key: String, title: String, mn: float, mx: float, st: float) -> void:
	var sl := _slider_row(parent, title, mn, mx, st, float(s.cfg[key]), func(v: float) -> void:
		s.cfg[key] = v
		_apply_dataset_and_cfg(s))
	s.ui[key] = sl


func _cfg_check(parent: Control, s: Slot, key: String, title: String) -> void:
	var cb := CheckBox.new()
	cb.text = title
	cb.button_pressed = bool(s.cfg[key])
	cb.toggled.connect(func(on: bool) -> void:
		s.cfg[key] = on
		_apply_dataset_and_cfg(s))
	parent.add_child(cb)
	s.ui[key] = cb


## sinkronkan kontrol UI dengan nilai cfg (setelah preset / ganti dataset)
func _sync_slot_ui(s: Slot) -> void:
	if s.ui.is_empty():
		return
	(s.ui["dataset"] as OptionButton).select(DATASET_KEYS.find(s.dataset))
	(s.ui["sync"] as OptionButton).select(SYNC_TYPES.find(s.cfg["sync"]))
	for k in s.cfg:
		if not s.ui.has(k):
			continue
		var c: Control = s.ui[k]
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(s.cfg[k]))
			(c.get_meta("label") as Label).text = "%s: %s" % [c.get_meta("title"), str(snappedf(float(s.cfg[k]), 0.001))]
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(s.cfg[k]))
	for gi in 3:
		var g := s.ui["gait%d" % gi] as HSlider
		g.set_value_no_signal(float(s.gait_speeds[gi]))
		(g.get_meta("label") as Label).text = "%s: %s" % [g.get_meta("title"), str(snappedf(float(s.gait_speeds[gi]), 0.001))]


func _copy_cfg_from_a() -> void:
	for i in range(1, slots.size()):
		slots[i].cfg = slots[0].cfg.duplicate()
		slots[i].gait_speeds = slots[0].gait_speeds.duplicate()
		_apply_dataset_and_cfg(slots[i])
		_sync_slot_ui(slots[i])


func export_config_json() -> String:
	var out := []
	for s in slots:
		out.append({"slot": SLOT_NAMES[s.index], "dataset": s.dataset, "config": s.cfg, "gait_speeds": s.gait_speeds})
	return JSON.stringify(out, "\t")


func _update_hud_visibility() -> void:
	for i in hud_labels.size():
		hud_labels[i].get_parent().visible = i < slots.size()


func _update_hud() -> void:
	for s in slots:
		var l := hud_labels[s.index]
		var v := Vector2(s.character.velocity.x, s.character.velocity.z).length()
		var t := "%s · %s\n" % [SLOT_NAMES[s.index], DATASETS[s.dataset]["label"]]
		if s.browser_clip != "":
			var ap := _anim_player(s)
			t += "MODE KLIP: %s\nwaktu %.1f / %.1f dtk" % [s.browser_clip.get_slice("/", 1), ap.current_animation_position, ap.current_animation_length]
		else:
			var clip := str(s.last.get("animation", "-")).get_slice("/", 1)
			t += "klip: %s @ %.2f dtk\n" % [clip, float(s.last.get("time", 0.0))]
			t += "cost %.2f (traj %.2f / bone %.2f)\n" % [float(s.last.get("total_cost", 0.0)),
					float(s.last.get("MMTrajectoryFeature", 0.0)), float(s.last.get("MMBoneDataFeature", 0.0))]
			t += "kecepatan %.2f m/s (target %.2f) · klip unik: %d" % [v,
					Vector2(s.character.target_velocity.x, s.character.target_velocity.z).length(), s.used.size()]
		l.text = t
	var mode := "MANUAL"
	if scenario_on:
		mode = "SKENARIO OTOMATIS (%.0f/%.0f dtk, putaran %d)" % [scenario_t, scenario_total, scenario_loops]
	elif explore_on:
		mode = "EKSPLORASI ACAK (cakupan klip)"
	status_label.text = "%s\nWASD jalan · Shift sprint · Ctrl pelan · klik kanan strafe · Spasi lompat · R reset · F1 panel · F2 skenario · F3 acak · Esc lepas mouse" % mode
	if Engine.get_process_frames() % 30 == 0:
		_refresh_coverage()


# --- tab klip -------------------------------------------------------------------------------

func _clip_dataset() -> String:
	return DATASET_KEYS[clip_dataset_opt.selected]


func _build_tab_clips() -> void:
	var vb := _scroll_tab("Klip")
	vb.add_child(_header("Putar langsung klip pada karakter terpilih (melewati MM)"))
	clip_dataset_opt = OptionButton.new()
	clip_dataset_opt.add_item("O3DE (22 klip)")
	clip_dataset_opt.add_item("Motorica VRM (252 klip)")
	clip_dataset_opt.select(1)
	clip_dataset_opt.item_selected.connect(func(_i: int) -> void:
		_rebuild_group_filter()
		_refresh_clip_list())
	vb.add_child(clip_dataset_opt)
	clip_group_opt = OptionButton.new()
	clip_group_opt.item_selected.connect(func(_i: int) -> void: _refresh_clip_list())
	vb.add_child(clip_group_opt)
	clip_filter_edit = LineEdit.new()
	clip_filter_edit.placeholder_text = "cari nama klip..."
	clip_filter_edit.text_changed.connect(func(_t: String) -> void: _refresh_clip_list())
	vb.add_child(clip_filter_edit)
	clip_list = ItemList.new()
	clip_list.custom_minimum_size = Vector2(0, 280)
	clip_list.item_selected.connect(_on_clip_selected)
	vb.add_child(clip_list)
	clip_info = Label.new()
	clip_info.add_theme_font_size_override("font_size", 12)
	clip_info.text = "Pilih klip dari daftar."
	vb.add_child(clip_info)

	var hb := HBoxContainer.new()
	for spec in [["< Sebelumnya", -1], ["Berikutnya >", 1]]:
		var b := Button.new()
		b.text = spec[0]
		var d: int = spec[1]
		b.pressed.connect(func() -> void: _step_clip(d))
		hb.add_child(b)
	vb.add_child(hb)
	clip_loop_chk = CheckBox.new()
	clip_loop_chk.text = "Ulangi klip"
	clip_loop_chk.button_pressed = true
	clip_loop_chk.toggled.connect(func(on: bool) -> void:
		for s in slots:
			s.browser_loop = on)
	vb.add_child(clip_loop_chk)
	clip_speed = _slider_row(vb, "kecepatan putar", 0.1, 2.0, 0.05, 1.0, func(v: float) -> void:
		for s in slots:
			if s.browser_clip != "":
				_anim_player(s).speed_scale = v)
	var back := Button.new()
	back.text = "Kembali ke gameplay motion matching"
	back.pressed.connect(func() -> void:
		tour_on = false
		for s in slots:
			_browser_stop(s))
	vb.add_child(back)

	vb.add_child(_header("Tur otomatis semua klip pada daftar"))
	var hb2 := HBoxContainer.new()
	var secs := SpinBox.new()
	secs.min_value = 1.0
	secs.max_value = 30.0
	secs.value = tour_seconds
	secs.suffix = "dtk/klip"
	secs.value_changed.connect(func(v: float) -> void: tour_seconds = v)
	hb2.add_child(secs)
	var tb := Button.new()
	tb.text = "Mulai tur"
	tb.pressed.connect(start_tour)
	hb2.add_child(tb)
	var ts := Button.new()
	ts.text = "Stop"
	ts.pressed.connect(func() -> void: tour_on = false)
	hb2.add_child(ts)
	vb.add_child(hb2)
	tour_label = Label.new()
	tour_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(tour_label)
	_rebuild_group_filter()


func _rebuild_group_filter() -> void:
	clip_group_opt.clear()
	clip_group_opt.add_item("Semua kategori")
	if _clip_dataset() == "motorica":
		var seen := {}
		for c in catalog:
			seen["%s/%s" % [c["category"], c["group"]]] = true
		var keys := seen.keys()
		keys.sort()
		for k in keys:
			clip_group_opt.add_item(k)


func _refresh_clip_list() -> void:
	if clip_list == null:
		return
	clip_list.clear()
	shown_clips.clear()
	var ds := _clip_dataset()
	var q := clip_filter_edit.text.to_lower()
	var grp := "" if clip_group_opt.selected <= 0 else clip_group_opt.get_item_text(clip_group_opt.selected)
	for n in clip_names(ds):
		if q != "" and not n.to_lower().contains(q):
			continue
		var meta: Dictionary = catalog_by_name.get(n, {}) if ds == "motorica" else {}
		if grp != "" and ("%s/%s" % [meta.get("category", ""), meta.get("group", "")]) != grp:
			continue
		shown_clips.append(n)
		clip_list.add_item(n)
	clip_list.tooltip_text = "%d klip" % shown_clips.size()


func _on_clip_selected(i: int) -> void:
	if slots.is_empty():
		return
	var s := slots[active_slot]
	var lib: String = str(DATASETS[_clip_dataset()]["library"])
	set_scenario(false)
	set_explore(false)
	_browser_play(s, "%s/%s" % [lib, shown_clips[i]])


func _step_clip(d: int) -> void:
	if shown_clips.is_empty():
		return
	var cur := clip_list.get_selected_items()
	var i := 0 if cur.is_empty() else clampi(cur[0] + d, 0, shown_clips.size() - 1)
	clip_list.select(i)
	_on_clip_selected(i)


func _update_clip_info(full_name: String) -> void:
	var n := full_name.get_slice("/", 1)
	if catalog_by_name.has(n):
		var m: Dictionary = catalog_by_name[n]
		clip_info.text = "%s\n%s · %.1f dtk · kecepatan lintasan %.2f m/s · perubahan arah %.0f°" % [n, m["source"], m["length"], m["path_speed"], m["yaw_change_deg"]]
	else:
		var a := _anim_player(slots[active_slot]).get_animation(full_name)
		clip_info.text = "%s\n(O3DE) %.1f dtk" % [n, a.length]


func start_tour() -> void:
	if shown_clips.is_empty() or slots.is_empty():
		return
	set_scenario(false)
	set_explore(false)
	tour_on = true
	tour_index = 0
	tour_timer = 0.0


# --- tab cakupan ----------------------------------------------------------------------------

func _build_tab_coverage() -> void:
	var vb := _scroll_tab("Cakupan")
	vb.add_child(_header("Klip Motorica yang pernah dipilih motion matching"))
	coverage_label = Label.new()
	vb.add_child(coverage_label)
	coverage_bar = ProgressBar.new()
	coverage_bar.min_value = 0
	coverage_bar.max_value = 252
	vb.add_child(coverage_bar)
	var info := Label.new()
	info.text = "Semua 252 klip ADA di database MM (tab Dataset). MM hanya memilih klip yang cocok\ndengan input; klip yang belum pernah muncul bisa dicoba lewat Skenario atau Browser Klip."
	info.add_theme_font_size_override("font_size", 11)
	vb.add_child(info)
	coverage_text = TextEdit.new()
	coverage_text.editable = false
	coverage_text.custom_minimum_size = Vector2(0, 420)
	vb.add_child(coverage_text)
	var b := Button.new()
	b.text = "Kosongkan statistik"
	b.pressed.connect(func() -> void:
		for s in slots:
			s.used.clear()
		_refresh_coverage())
	vb.add_child(b)


func motorica_used_union() -> Dictionary:
	var u := {}
	for s in slots:
		if s.dataset == "motorica":
			for k in s.used:
				u[k] = int(u.get(k, 0)) + int(s.used[k])
	return u


func _refresh_coverage() -> void:
	if coverage_bar == null:
		return
	var u := motorica_used_union()
	var total := motorica_clips.size()
	coverage_bar.max_value = maxi(total, 1)
	coverage_bar.value = u.size()
	coverage_label.text = "%d / %d klip Motorica pernah dipilih" % [u.size(), total]
	var txt := "SUDAH DIPAKAI (%d):\n" % u.size()
	var names := u.keys()
	names.sort()
	for n in names:
		txt += "  %s  x%d\n" % [n, u[n]]
	txt += "\nBELUM DIPAKAI (%d):\n" % (total - u.size())
	for n in motorica_clips:
		if not u.has(n):
			txt += "  %s\n" % n
	coverage_text.text = txt


func _build_tab_help() -> void:
	var vb := _scroll_tab("Bantuan")
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	l.text = """CARA MEMBANDINGKAN
1. Biarkan 2 karakter (A=O3DE, B=Motorica). Keduanya menerima input yang sama.
2. Tekan F2 (skenario otomatis) atau F3 (eksplorasi acak, menjangkau lebih banyak klip) supaya keduanya menjalani urutan gerak identik: diam, jalan, lari, sprint, belok, strafe, berhenti.
3. Ubah dataset tiap slot di tab 'Konfigurasi'. Untuk membandingkan KONFIGURASI, pilih dataset yang sama di A dan B lalu beri preset berbeda (mis. Responsif vs Halus).
4. Perhatikan di HUD: klip terpilih, cost, kecepatan nyata vs target, jumlah klip unik.

YANG PERLU DIATUR SENDIRI
- query_frequency: seberapa sering MM mencari ulang (tinggi = responsif, boros CPU).
- transition_halflife + blending: kehalusan perpindahan antar klip.
- halflife gerak: seberapa cepat karakter mengejar kecepatan target.
- Synchronizer: Mix (gabung root motion + fisika), Clamp, RootMotion.
- root_motion_amount: seberapa besar root motion animasi dipakai (0 = fisika murni).
- Kecepatan gait: set ke rentang data. Preset O3DE 1.5/3.0/3.8, Motorica 1.05/3.1/4.6.

KONTROL
WASD jalan · Shift sprint · Ctrl jalan pelan · klik kanan tahan strafe · Spasi lompat
R reset posisi · F1 sembunyi panel · F2 skenario · 1/2/3 pilih slot · Esc lepas mouse (klik dunia untuk menangkap lagi)

BROWSER KLIP
Pilih dataset + klip lalu klik: klip diputar langsung pada slot terpilih (tanpa MM), lengkap dengan root motion. 'Mulai tur' memutar semua klip pada daftar bergantian.
"""
	vb.add_child(l)
