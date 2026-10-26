class_name MMTrajectoryDebug
extends Node3D
## Draws the trajectory MMCharacter feeds to the matcher:
## cyan = future path, magenta = history, yellow = facing, orange = velocity.
## Add as a child of anything, then assign `character`.

@export var character: MMCharacter
@export var facing_length := 0.4
@export var velocity_scale := 0.15
@export var lift := 0.05

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if character == null:
		return
	# Each entry: {position (global), velocity, facing (yaw radians), on_floor}
	var future: Array = character.get_trajectory()
	var past: Array = character.get_trajectory_history()
	if future.is_empty():
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_path(future, Color.CYAN, true)
	_draw_path(past, Color.MAGENTA, false)
	_mesh.surface_end()


func _draw_path(points: Array, color: Color, with_details: bool) -> void:
	var prev: Vector3 = character.global_position + Vector3.UP * lift
	for p: Dictionary in points:
		var pos: Vector3 = p["position"] + Vector3.UP * lift
		_line(prev, pos, color)
		if with_details:
			var f: float = p["facing"]
			_line(pos, pos + Vector3(sin(f), 0.0, cos(f)) * facing_length, Color.YELLOW)
			_line(pos, pos + (p["velocity"] as Vector3) * velocity_scale, Color.ORANGE)
		prev = pos


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)
