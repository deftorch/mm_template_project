class_name MMCameraRig
extends Node3D
## Third-person orbit camera. Same convention as the demo's CameraPivot:
## the camera sits behind the pivot and looks along the pivot's +Z,
## so `rotation.y` is directly the camera yaw (what MMInputController reads).
## Builds its own SpringArm3D + Camera3D, so it only needs a target.

## Body the camera orbits. Usually the MMCharacter.
@export var target: Node3D
## Optional: follow this node's position instead of `target`'s. MMCharacter makes its
## Skeleton3D top-level and synchronizes it with root motion, so the mesh can drift a
## little from the physics body. Assign the Skeleton3D (or a bone attachment) here if
## the camera feels offset from the model.
@export var follow_node: Node3D

@export_group("Framing")
@export var distance := 3.5
@export var height := 1.4
@export var follow_smoothing := 14.0

@export_group("Dynamic FOV")
## Widens the FOV as the character speeds up (needs `target` to be an MMCharacter).
@export var dynamic_fov := true
@export var fov_base := 75.0
@export var fov_boost := 8.0
## Horizontal speed (m/s) where the boost starts and where it is full.
## Match these to your gait speeds: start ~ run speed, full ~ sprint speed.
@export var fov_speed_start := 3.2
@export var fov_speed_full := 4.5
@export var fov_smoothing := 5.0

@export_group("Strafe (over the shoulder)")
## Camera slides to this side of the character while strafing. + = right, - = left, 0 = off.
@export var shoulder_offset := 0.55
@export var strafe_distance := 2.4
## How quickly the camera blends in and out of the strafe framing.
@export var strafe_blend_speed := 7.0

@export_group("Look")
@export var mouse_sensitivity := 0.003
## Positive pitch = camera above the character, looking down.
@export var min_pitch := -0.3
@export var max_pitch := 1.1

@export_group("Collision")
## Layers that push the camera forward. Leave out triggers, other characters, etc.
@export_flags_3d_physics var collision_mask := 1
## Radius of the sphere swept along the arm. Bigger = keeps more distance from walls.
@export_range(0.05, 1.0, 0.01) var collision_radius := 0.25
@export var margin := 0.1

var yaw := 0.0
var pitch := 0.25

var _arm: SpringArm3D
var _camera: Camera3D
var _use_interpolated_target := false
var _mm: MMCharacter
var _strafe_blend := 0.0


func _ready() -> void:
	top_level = true
	# This node moves in _process and does its own smoothing. If it were also
	# physics-interpolated the camera would be smoothed twice and lag.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# Arm extends along its local +Z; turning it by PI puts the camera at the
	# pivot's -Z (behind) while it still looks toward +Z.
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = margin
	_arm.collision_mask = collision_mask
	var sphere := SphereShape3D.new()
	sphere.radius = collision_radius
	_arm.shape = sphere
	_arm.rotation.y = PI
	add_child(_arm)
	_camera = Camera3D.new()
	_arm.add_child(_camera)
	_camera.current = true
	_camera.fov = fov_base
	_mm = target as MMCharacter

	for n in [target, follow_node]:
		if n is CollisionObject3D:
			_arm.add_excluded_object((n as CollisionObject3D).get_rid())

	# With physics interpolation on, a node's global_position is the last *physics*
	# value, so reading it every rendered frame makes the camera stutter against the
	# interpolated mesh. Use the interpolated transform instead.
	_use_interpolated_target = ProjectSettings.get_setting(
			"physics/common/physics_interpolation", false)

	global_position = _follow_position()
	rotation = Vector3(pitch, yaw, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_yaw() -> float:
	return yaw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		# mouse up (relative.y < 0) lowers the camera = looks up
		pitch = clampf(pitch + event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if target == null and follow_node == null:
		return
	global_position = global_position.lerp(
			_follow_position(), 1.0 - exp(-follow_smoothing * delta))
	rotation = Vector3(pitch, yaw, 0.0)
	_update_framing(delta)


## Over-the-shoulder blend + speed-based FOV. Everything uses exp() smoothing so the
## result is independent of framerate.
func _update_framing(delta: float) -> void:
	var strafing := _mm != null and _mm.is_strafing
	_strafe_blend = lerpf(_strafe_blend, 1.0 if strafing else 0.0,
			1.0 - exp(-strafe_blend_speed * delta))
	# Rig +X is the camera's *left* (the camera looks along +Z), so a positive
	# (right-hand) shoulder offset moves the arm toward -X.
	_arm.position.x = -shoulder_offset * _strafe_blend
	_arm.spring_length = lerpf(distance, strafe_distance, _strafe_blend)

	var goal_fov := fov_base
	if dynamic_fov and _mm != null:
		var speed := Vector2(_mm.velocity.x, _mm.velocity.z).length()
		var t := clampf(inverse_lerp(fov_speed_start, fov_speed_full, speed), 0.0, 1.0)
		goal_fov = fov_base + fov_boost * t
	_camera.fov = lerpf(_camera.fov, goal_fov, 1.0 - exp(-fov_smoothing * delta))


func _follow_position() -> Vector3:
	var n: Node3D = follow_node if follow_node != null else target
	if n == null:
		return global_position
	var p := n.global_position
	if _use_interpolated_target and n.is_inside_tree():
		p = n.get_global_transform_interpolated().origin
	return p + Vector3.UP * height
