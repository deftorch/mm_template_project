extends Node3D
## Demo pemutar klip clipkit pada MotusMan (tanpa motion matching).
## Buka scenes/clipkit_demo.tscn di editor Godot 4.6, lalu tekan F6 (Run Current Scene).
##
## Kontrol:
##   1..9 / Tab     pilih klip           Spasi   putar ulang dari awal
##   P              jeda / lanjut        , dan . mundur / maju 1 frame (otomatis jeda)
##   [ dan ]        kecepatan x0.5 / x2  A       auto-ulang on/off
##   F              kamera ikuti pinggul R       reset kamera
##   Mouse kiri     orbit kamera         Roda    zoom
##   H              sembunyikan / tampilkan HUD
##
## Mode tangkapan layar (untuk verifikasi tanpa editor):
##   godot --path . --resolution 1280x720 res://scenes/clipkit_demo.tscn -- \
##         --shot=/tmp/a.png --clip=slash --t=0.45 --yaw=35
##   Beberapa frame sekaligus: --shot=/tmp/slash --times=0,0.1,0.2 (-> slash_0.png, slash_1.png, ...)
##   Opsi kamera: --yaw=<derajat> --pitch=<derajat> --dist=<m> --follow --nohud

const ClipLib := preload("res://clipkit/clip_lib.gd")
const GRID_TEX := "res://textures/grid_texture.png"
const LIB_NAME := "clipkit"
const FPS := 30.0
const END_HOLD := 0.8  # detik diam di pose akhir sebelum auto-ulang

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _hips_idx: int = -1
var _rig: Dictionary = {}
var CLIP_DIR: String = "res://clipkit/out/"
var FBX_PATH: String = ""   # scene karakter (FBX/VRM); default dari rig, bisa ditimpa --skeleton=
var _names: Array[String] = []
var _current: String = ""
var _t: float = 0.0
var _speed: float = 1.0
var _paused: bool = false
var _auto: bool = true
var _end_timer: float = -1.0
var _follow: bool = false

var _cam: Camera3D
var _yaw: float = 35.0       # derajat; 0 = kamera di depan karakter (+Z)
var _pitch: float = -12.0
var _dist: float = 5.5
var _target: Vector3 = Vector3(0.0, 1.0, -0.6)
var _dragging: bool = false

var _hud: CanvasLayer
var _label: Label
var _bar: ProgressBar

var _shot_path: String = ""
var _shot_wait: int = 0
var _shot_times: Array[float] = []
var _shot_idx: int = 0
var _nohud: bool = false


func _ready() -> void:
	_build_world()
	if not _load_character():
		return
	_build_hud()
	_parse_args()
	if _shot_path == "":
		if _current == "" and not _names.is_empty():
			_select(_names[0])
	_update_camera()


# ---------------------------------------------------------------- dunia

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(GRID_TEX):
		mat.albedo_texture = load(GRID_TEX)
		mat.albedo_color = Color(0.62, 0.62, 0.62)
		mat.uv1_scale = Vector3(20.0, 20.0, 1.0)
	else:
		mat.albedo_color = Color(0.45, 0.45, 0.5)
	floor_mesh.material = mat
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	add_child(floor_node)

	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)


## --rig=<nama|path> (default motus) dan --skeleton=<res://scene> memilih karakter, mis.
## --rig=vrm --skeleton=res://testdata/vrm1/model.vrm. Klip dimuat dari out_dir rig.
func _select_rig() -> void:
	var rig_name := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rig="):
			rig_name = a.substr(6)
		elif a.begins_with("--skeleton="):
			FBX_PATH = a.substr(11)
	_rig = ClipLib.load_rig(ClipLib.rig_path_for(rig_name))
	if _rig.is_empty():
		return
	CLIP_DIR = str(_rig.get("out_dir", "res://clipkit/out/"))
	if FBX_PATH == "":
		FBX_PATH = str(_rig["skeleton_scene"])


func _load_character() -> bool:
	_select_rig()
	if _rig.is_empty():
		_fatal("Rig tidak terbaca (cek --rig=).")
		return false
	var scene: PackedScene = load(FBX_PATH)
	if scene == null:
		_fatal("Tidak bisa memuat %s.\nJalankan: godot --headless --path . --import" % FBX_PATH)
		return false
	var model: Node = scene.instantiate()
	add_child(model)

	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skels.is_empty():
		_fatal("Scene karakter tidak berisi AnimationPlayer/Skeleton3D.")
		return false
	_player = players[0] as AnimationPlayer
	_skeleton = skels[0] as Skeleton3D
	_hips_idx = ClipLib.find_bone(_skeleton, _rig, "Hips")

	var lib := AnimationLibrary.new()
	var dir := DirAccess.open(CLIP_DIR)
	if dir != null:
		for f in dir.get_files():
			var fname: String = f
			if fname.ends_with(".remap"):
				fname = fname.trim_suffix(".remap")
			if not fname.ends_with(".res"):
				continue
			var anim: Animation = load(CLIP_DIR + fname) as Animation
			if anim == null:
				continue
			var nm: String = fname.get_basename()
			lib.add_animation(nm, anim)
			_names.append(nm)
	_names.sort()
	if _names.is_empty():
		_fatal("Tidak ada klip di %s.\nJalankan: godot --headless --path . -s tools/clip_build.gd -- --rig=<rig>" % CLIP_DIR)
		return false
	_player.add_animation_library(LIB_NAME, lib)
	return true


func _fatal(msg: String) -> void:
	push_error(msg)
	var l := Label.new()
	l.text = msg
	l.position = Vector2(20, 20)
	var layer := CanvasLayer.new()
	layer.add_child(l)
	add_child(layer)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_label = Label.new()
	_label.position = Vector2(14, 10)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(360, 10)
	_hud.add_child(_bar)


func _update_hud() -> void:
	if _hud == null or not _hud.visible:
		return
	var anim: Animation = _player.get_animation(LIB_NAME + "/" + _current)
	var active: Array[String] = []
	var listed: Array[String] = []
	var wins: Dictionary = anim.get_meta("windows", {})
	for k in wins:
		var arr: Array = wins[k]
		listed.append("%s %.2f-%.2f" % [str(k), float(arr[0]), float(arr[1])])
		if _t >= float(arr[0]) and _t <= float(arr[1]):
			active.append(str(k).to_upper())
	var win_txt: String = "AKTIF: %s    (jadwal: %s)" % [
		", ".join(active) if not active.is_empty() else "-", " | ".join(listed)]
	var ev_txt: String = ""
	for e in anim.get_meta("events", []):
		if float(e["t"]) <= _t:
			ev_txt = "%s:%s" % [e["type"], e["id"]]
	var frame: int = int(round(_t * FPS))
	var total: int = int(round(anim.length * FPS))
	var clips_line: String = ""
	for i in _names.size():
		clips_line += ("<%d:%s> " if _names[i] == _current else " %d:%s  ") % [i + 1, _names[i]]
	var state: String = "JEDA" if _paused else "main"
	_label.text = "%s\nklip %s   t=%.2f/%.2f s   frame %d/%d   x%.2f   %s%s\njendela %s\nevent terakhir: %s\n1-9 klip | Spasi ulang | P jeda | , . langkah | [ ] kecepatan | A auto | F ikuti | H sembunyikan" % [
		clips_line, _current, _t, anim.length, frame, total, _speed, state,
		"   (auto-ulang)" if _auto else "", win_txt, ev_txt if ev_txt != "" else "-"]
	_bar.position = Vector2(14, _label.position.y + _label.get_minimum_size().y + 6)
	_bar.value = _t / maxf(anim.length, 0.001)


# ---------------------------------------------------------------- kontrol

func _parse_args() -> void:
	var clip_arg: String = ""
	var t_arg: float = 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--clip="):
			clip_arg = a.substr(7)
		elif a.begins_with("--t="):
			t_arg = float(a.substr(4))
		elif a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		elif a.begins_with("--pitch="):
			_pitch = float(a.substr(8))
		elif a.begins_with("--dist="):
			_dist = float(a.substr(7))
		elif a.begins_with("--times="):
			for part in a.substr(8).split(","):
				_shot_times.append(float(part))
		elif a == "--follow":
			_follow = true
		elif a == "--nohud":
			_nohud = true
	if clip_arg != "" and _names.has(clip_arg):
		_select(clip_arg)
	if _shot_path != "":
		if _current == "":
			_select(_names[0])
		_paused = true
		_auto = false
		if _shot_times.is_empty():
			_shot_times.append(t_arg)
		_t = _shot_times[0]
		_shot_wait = 4
		if _nohud:
			_hud.visible = false


func _select(nm: String) -> void:
	_current = nm
	_t = 0.0
	_end_timer = -1.0
	_paused = false
	_player.play(LIB_NAME + "/" + nm)
	_player.pause()
	_apply_pose()


func _apply_pose() -> void:
	var anim: Animation = _player.get_animation(LIB_NAME + "/" + _current)
	_t = clampf(_t, 0.0, anim.length)
	_player.seek(_t, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			var i: int = k - KEY_1
			if i < _names.size():
				_select(_names[i])
		elif k == KEY_TAB:
			_select(_names[(_names.find(_current) + 1) % _names.size()])
		elif k == KEY_SPACE:
			_select(_current)
		elif k == KEY_P:
			_paused = not _paused
		elif k == KEY_COMMA or k == KEY_PERIOD:
			_paused = true
			_t += (-1.0 if k == KEY_COMMA else 1.0) / FPS
			_end_timer = -1.0
			_apply_pose()
		elif k == KEY_BRACKETLEFT:
			_speed = maxf(_speed * 0.5, 0.0625)
		elif k == KEY_BRACKETRIGHT:
			_speed = minf(_speed * 2.0, 4.0)
		elif k == KEY_A:
			_auto = not _auto
		elif k == KEY_F:
			_follow = not _follow
		elif k == KEY_R:
			_yaw = 35.0
			_pitch = -12.0
			_dist = 5.5
		elif k == KEY_H:
			_hud.visible = not _hud.visible
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, 1.5)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.1, 20.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.4
		_pitch = clampf(_pitch - mm.relative.y * 0.3, -80.0, 30.0)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if _player == null or _current == "":
		return
	var anim: Animation = _player.get_animation(LIB_NAME + "/" + _current)
	if not _paused:
		if _t < anim.length:
			_t += delta * _speed
			_apply_pose()
			if _t >= anim.length:
				_end_timer = END_HOLD
		elif _auto and _end_timer >= 0.0:
			_end_timer -= delta
			if _end_timer < 0.0:
				_select(_current)
	_update_camera()
	_update_hud()

	if _shot_path != "":
		_apply_pose()
		_shot_wait -= 1
		if _shot_wait <= 0:
			var img: Image = get_viewport().get_texture().get_image()
			var path: String = _shot_path
			if _shot_times.size() > 1:
				path = "%s_%d.png" % [_shot_path, _shot_idx]
			var err: int = img.save_png(path)
			print("SHOT %s t=%.3f err=%d" % [path, _t, err])
			_shot_idx += 1
			if err != OK or _shot_idx >= _shot_times.size():
				get_tree().quit(0 if err == OK else 1)
			else:
				_t = _shot_times[_shot_idx]
				_shot_wait = 3


func _update_camera() -> void:
	var center: Vector3 = _target
	if _follow and _hips_idx >= 0:
		var hp: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_hips_idx)).origin
		center = Vector3(hp.x, 1.0, hp.z)
	var yaw_r: float = deg_to_rad(_yaw)
	var pit_r: float = deg_to_rad(_pitch)
	var dir := Vector3(sin(yaw_r) * cos(pit_r), -sin(pit_r), cos(yaw_r) * cos(pit_r))
	_cam.global_position = center + dir * _dist
	_cam.look_at(center, Vector3.UP)
