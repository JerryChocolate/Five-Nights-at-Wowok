extends SceneTree
## Pemeriksaan kompilasi headless seluruh berkas `.gdshader` (godot-shaders Pattern 4):
## godot --headless --path godot --script res://tests/compile_shaders.gd

func _initialize() -> void:
	var paths := _find("res://", "gdshader")
	if paths.is_empty():
		push_error("FAIL: tidak ada berkas .gdshader ditemukan")
		quit(1)
		return
	var failed := 0
	for path in paths:
		print("compiling ", path)
		var shader := load(path) as Shader
		if shader == null:
			failed += 1
			push_error("FAIL load shader: " + path)
			continue
		shader.get_shader_uniform_list()
	print("Compiled %d shaders (%d failed)" % [paths.size(), failed])
	quit(1 if failed > 0 else 0)


func _find(dir: String, ext: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == ext:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			found.append_array(_find(dir.path_join(sub), ext))
	return found
