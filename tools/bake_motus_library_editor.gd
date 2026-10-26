# Autoload SEMENTARA (tambahkan di Project Settings > Autoload, jalankan editor, hapus lagi setelah selesai).
# Menekan tombol "Bake" di panel MMEditor untuk motus_motion_library.tres lalu menyimpannya.
@tool
extends Node
const LIB_PATH = "res://characters/motus_man/motus_motion_library.tres"
func _ready():
	if not Engine.is_editor_hint(): return
	await get_tree().create_timer(3.0).timeout
	EditorInterface.open_scene_from_path("res://scenes/main_motus_man.tscn")
	await get_tree().create_timer(4.0).timeout
	var sroot = EditorInterface.get_edited_scene_root()
	print("[bake] edited scene: ", sroot.name if sroot else "none")
	var ch = sroot.get_node("MotusMan")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(ch)
	await get_tree().create_timer(2.0).timeout
	var lib: Resource = load(LIB_PATH)
	print("[bake] before: motion_data size=", lib.get_motion_data().size(), " anims=", lib.get_animation_list().size())
	EditorInterface.edit_resource(lib)
	await get_tree().create_timer(2.0).timeout
	var base = EditorInterface.get_base_control()
	var btn: Button = null
	for n in base.find_children("*", "Button", true, false):
		if n.text == "Bake" and "MMEditor" in str(n.get_path()):
			btn = n
	if btn == null:
		print("[bake] ERROR: Bake button not found"); get_tree().quit(1); return
	print("[bake] pressing Bake (disabled=", btn.disabled, ")")
	var t0 = Time.get_ticks_msec()
	btn.pressed.emit()
	var last = -1
	for i in 600:
		await get_tree().create_timer(1.0).timeout
		var sz = lib.get_motion_data().size()
		if sz > 0 and sz == last: break
		last = sz
	print("[bake] after: motion_data size=", lib.get_motion_data().size(), " db_anim_index=", lib.get_db_anim_index().size(), " node_indices=", lib.get_node_indices().size(), " schema_hash=", lib.get_schema_hash(), " elapsed_s=", (Time.get_ticks_msec()-t0)/1000.0)
	var err = ResourceSaver.save(lib, LIB_PATH)
	print("[bake] saved err=", err)
	get_tree().quit()
