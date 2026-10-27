extends SceneTree
## Tangkapan layar demo (butuh renderer: xvfb-run + --rendering-driver opengl3, BUKAN --headless).
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --fixed-fps 30 -s tests/render_vrm_demo.gd -- --out=/tmp/shot
func _initialize() -> void:
	var out := "/tmp/shot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	root.size = Vector2i(1280, 720)
	var demo = (load("res://scenes/vrm_dataset_demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await process_frame
	demo.set_scenario(true)
	for i in 30 * 14:
		await process_frame
	root.get_texture().get_image().save_png(out + "_gameplay.png")
	demo.set_scenario(false)
	demo.test_input = null
	demo.active_slot = 1
	demo.reset_slots()
	await process_frame
	demo._browser_play(demo.slots[1], "vrm_motorica_library/Run_Strafe_Spins_45_90_variation_1")
	demo._browser_play(demo.slots[0], "vrm_motion_library/Walk1")
	for i in 40:
		await process_frame
	demo.tabs.current_tab = 1
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "_browser.png")
	quit(0)
