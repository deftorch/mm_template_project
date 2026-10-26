extends SceneTree

func _initialize():
	print("can_instantiate MMEditorPlugin: ", ClassDB.can_instantiate("MMEditorPlugin"))
	print("can_instantiate MMAnimationLibrary: ", ClassDB.can_instantiate("MMAnimationLibrary"))
	print("can_instantiate MMCharacter: ", ClassDB.can_instantiate("MMCharacter"))
	quit(0)
