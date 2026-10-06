extends SceneTree

# Capture the actual starting game, with normal UI and real initial state.
# Run with a display: godot --path . --resolution 1600x900 --script tests/s14_capture.gd
func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var scene := load("res://src/app/main.tscn") as PackedScene
	root.add_child(scene.instantiate())
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var target := "user://s14-gameplay.png"
	var error := capture.save_png(target)
	print("S14_SCREENSHOT: ", ProjectSettings.globalize_path(target), " error=", error)
	quit(0 if error == OK else 1)
