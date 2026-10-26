extends SceneTree

func _initialize():
	var lib = load("res://characters/motus_man/motus_motion_library.tres") as MMAnimationLibrary
	print("Loaded library. Has bake_data method? ", lib.has_method("bake_data"))
	if lib.has_method("bake_data"):
		print("Calling bake_data() ...")
		lib.bake_data()
		var err = ResourceSaver.save(lib, "res://characters/motus_man/motus_motion_library.tres")
		print("Saved baked library: result=", err)
	quit(0)
