class_name MMInputController
extends Node
## Turns player input into the three things MMCharacter needs:
## target_velocity, is_strafing and strafe_facing.
## MMCharacter itself does the spring simulation, trajectory prediction and movement.
##
## Camera convention (same as the demo's CameraPivot / MMCameraRig):
## the camera sits behind the pivot looking along the pivot's +Z, so
## forward = (sin yaw, 0, cos yaw) and right = (-cos yaw, 0, sin yaw).

@export var character: MMCharacter
## Node whose rotation.y is the camera yaw (MMCameraRig or the demo's CameraPivot).
@export var camera_pivot: Node3D

@export_group("Gait speeds (m/s)")
## IMPORTANT: keep these inside the speed range present in your animation data.
## Asking for 6 m/s when the data tops out at 3 m/s makes the matcher pick
## the closest thing it has, which looks like foot sliding.
@export var walk_speed := 1.4
@export var run_speed := 3.0
@export var sprint_speed := 4.5

@export_group("Strafe")
## true: strafe while the mm_strafe key is held. false: the key toggles strafe.
@export var strafe_on_hold := true
## How fast the body turns to face the camera while strafing (seconds to cover half
## the angle). MMCharacter applies strafe_facing instantly, so feeding it the raw
## camera yaw makes the body - and the trajectory sent to the matcher - jump when
## the mouse moves fast. Smaller = snappier, larger = heavier.
@export_range(0.01, 0.5, 0.01) var strafe_turn_halflife := 0.1

@export_group("Jump")
@export var jump_speed := 5.0

var _toggle_state := false
var _facing := 0.0
var _facing_vel := 0.0
var _facing_ready := false


func _ready() -> void:
	_ensure_input_actions()


func _physics_process(delta: float) -> void:
	if character == null or camera_pivot == null:
		return

	var yaw := camera_pivot.rotation.y
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))

	# get_vector returns y < 0 when mm_forward is pressed.
	var stick := Input.get_vector("mm_left", "mm_right", "mm_forward", "mm_back")
	var dir := right * stick.x + forward * (-stick.y)

	var speed := run_speed
	if Input.is_action_pressed("mm_walk"):
		speed = walk_speed
	elif Input.is_action_pressed("mm_sprint"):
		speed = sprint_speed

	character.target_velocity = dir * speed
	if strafe_on_hold:
		character.is_strafing = Input.is_action_pressed("mm_strafe")
	else:
		character.is_strafing = _toggle_state

	if not _facing_ready:
		_facing = character.rotation.y
		_facing_ready = true

	if character.is_strafing:
		# Chase the camera yaw with a critically damped spring.
		var r := _step_angle(_facing, _facing_vel, yaw, strafe_turn_halflife, delta)
		_facing = r[0]
		_facing_vel = r[1]
	else:
		# Track the body so entering strafe starts from the current facing (no snap),
		# and the standing-still trajectory facing matches the character.
		_facing = character.rotation.y
		_facing_vel = 0.0
	character.strafe_facing = _facing


func _unhandled_input(event: InputEvent) -> void:
	if character == null:
		return
	if event.is_action_pressed("mm_jump") and character.is_on_floor():
		character.velocity += Vector3.UP * jump_speed
	if not strafe_on_hold and event.is_action_pressed("mm_strafe"):
		_toggle_state = not _toggle_state


## Critically damped spring on an angle (radians), shortest path. Returns [angle, velocity].
static func _step_angle(angle: float, vel: float, goal: float,
		halflife: float, dt: float) -> Array:
	var y: float = (4.0 * 0.69314718056) / (halflife + 1e-5) / 2.0
	var j0: float = wrapf(angle - goal, -PI, PI)
	var j1: float = vel + j0 * y
	var e: float = exp(-y * dt)
	return [goal + e * (j0 + j1 * dt), e * (vel - j1 * y * dt)]


# Registers default bindings at runtime so no project.godot edits are needed.
func _ensure_input_actions() -> void:
	_add_key("mm_forward", KEY_W)
	_add_key("mm_back", KEY_S)
	_add_key("mm_left", KEY_A)
	_add_key("mm_right", KEY_D)
	_add_key("mm_sprint", KEY_SHIFT)
	_add_key("mm_walk", KEY_CTRL)
	_add_key("mm_jump", KEY_SPACE)
	if not InputMap.has_action("mm_strafe"):
		InputMap.add_action("mm_strafe")
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("mm_strafe", ev)


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
