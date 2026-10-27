# Autoload SEMENTARA, dipasang otomatis oleh tools/bake_vrm_motorica.sh (jangan dipasang manual).
# Menekan tombol "Bake" di panel MMEditor untuk sebuah MMAnimationLibrary lalu menyimpannya.
# Parameter lewat environment: BAKE_LIB, BAKE_SCENE, BAKE_NODE.
@tool
extends Node

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var lib_path := OS.get_environment("BAKE_LIB")
	var scene_path := OS.get_environment("BAKE_SCENE")
	var node_name := OS.get_environment("BAKE_NODE")
	await get_tree().create_timer(3.0).timeout
	EditorInterface.open_scene_from_path(scene_path)
	await get_tree().create_timer(4.0).timeout
	var sroot := EditorInterface.get_edited_scene_root()
	print("[bake] scene: ", sroot.name if sroot else "none")
	var ch := sroot.get_node(node_name)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(ch)
	await get_tree().create_timer(2.0).timeout
	var lib: Resource = load(lib_path)
	print("[bake] sebelum: motion_data=", lib.get_motion_data().size(), " anims=", lib.get_animation_list().size())
	EditorInterface.edit_resource(lib)
	await get_tree().create_timer(2.0).timeout
	# Tombol Bake membake library yang DIPILIH di OptionButton di sebelahnya (daftar library
	# di AnimationPlayer karakter). Ada beberapa instans panel MMEditor; pakai yang dropdown-nya terisi.
	var lib_name := lib_path.get_file().get_basename()
	var btn: Button = null
	for n in EditorInterface.get_base_control().find_children("*", "Button", true, false):
		if n.text != "Bake" or not ("MMEditor" in str(n.get_path())):
			continue
		for sib in n.get_parent().get_children():
			if sib is OptionButton and sib.item_count > 0:
				for k in sib.item_count:
					if sib.get_item_text(k) == lib_name:
						sib.select(k)
						sib.item_selected.emit(k)
						btn = n
	if btn == null:
		print("[bake] ERROR: library '", lib_name, "' tidak ada di dropdown MMEditor (harus terpasang di AnimationPlayer karakter)")
		get_tree().quit(1)
		return
	print("[bake] tombol: ", btn.get_path(), " disabled=", btn.disabled, " visible=", btn.is_visible_in_tree())
	var t0 := Time.get_ticks_msec()
	btn.pressed.emit()
	print("[bake] pressed.emit() kembali setelah ms=", Time.get_ticks_msec() - t0)
	var last := -1
	var stable := 0
	for i in 1800:
		await get_tree().create_timer(1.0).timeout
		var sz: int = lib.get_motion_data().size()
		if i % 10 == 0:
			print("[bake] t=", i, "s motion_data=", sz)
		if sz > 0 and sz == last:
			stable += 1
			if stable >= 3:
				break
		else:
			stable = 0
		last = sz
	print("[bake] sesudah: motion_data=", lib.get_motion_data().size(), " db_anim_index=", lib.get_db_anim_index().size(),
			" node_indices=", lib.get_node_indices().size(), " schema_hash=", lib.get_schema_hash(),
			" detik=", (Time.get_ticks_msec() - t0) / 1000.0)
	var err := ResourceSaver.save(lib, lib_path)
	print("[bake] tersimpan err=", err)
	get_tree().quit(0 if err == OK and lib.get_motion_data().size() > 0 else 1)
