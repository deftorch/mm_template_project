extends SceneTree

var frames := 0
var main: Node
var ch: MMCharacter
var rig: MMCameraRig
var last_anim := ""
var anims_seen := {}
var phase_anim := {}

func _initialize() -> void:
	main = (load("res://scenes/main_template.tscn") as PackedScene).instantiate()
	root.add_child(main)
	ch = main.get_node("ThreeVRMGirl") as MMCharacter
	rig = main.get_node("CameraPivot")
	ch.on_query_result.connect(func(r):
		last_anim = str(r.get("animation", ""))
		anims_seen[last_anim] = anims_seen.get(last_anim, 0) + 1)

func _speed() -> float:
	return Vector2(ch.velocity.x, ch.velocity.z).length()

func _press(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _physics_process(_d: float) -> bool:
	frames += 1
	match frames:
		2:
			rig.yaw = PI  # run away from the demo wall (toward -Z)
		20:
			Input.action_press("mm_forward")
		150:
			print("[run]    speed=", snapped(_speed(), 0.01), " pos.z=", snapped(ch.global_position.z, 0.1), " anim=", last_anim, " fov=", snapped(rig._camera.fov, 0.1))
			Input.action_press("mm_sprint")
		300:
			print("[sprint] speed=", snapped(_speed(), 0.01), " pos.z=", snapped(ch.global_position.z, 0.1), " anim=", last_anim, " fov=", snapped(rig._camera.fov, 0.1))
			Input.action_release("mm_sprint")
		420:
			print("[run again] speed=", snapped(_speed(), 0.01), " anim=", last_anim, " fov=", snapped(rig._camera.fov, 0.1))
			_press("mm_jump", true)
		422:
			_press("mm_jump", false)
		440:
			print("[jump +18f] y=", snapped(ch.global_position.y, 0.01), " vel.y=", snapped(ch.velocity.y, 0.01), " on_floor=", ch.is_on_floor(), " anim=", last_anim)
		470:
			print("[jump +48f] y=", snapped(ch.global_position.y, 0.01), " on_floor=", ch.is_on_floor(), " anim=", last_anim)
		560:
			Input.action_release("mm_forward")
		700:
			print("[stopped] speed=", snapped(_speed(), 0.01), " anim=", last_anim)
			print("clips chosen by the matcher (query count): ", anims_seen)
			quit()
	return false
