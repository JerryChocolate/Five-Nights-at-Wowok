extends Node
## Uji tata letak & fokus UI lintas aspek rasio (godot-ui-control Pattern 4):
## godot --headless --path godot res://tests/layout.tscn
## Memastikan semua Control berada di dalam batas layar (16:9, 21:9 ultrawide, 4:3) & selalu memiliki fokus gamepad.

const SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(2560, 1080),
	Vector2i(1920, 1440),
]

var failed := 0
var checked := 0


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	await get_tree().process_frame
	for size in SIZES:
		await _check_at_size(size)
	if checked == 0:
		failed += 1
		push_error("FAIL: tidak ada elemen UI yang diperiksa")
	print("UI layout checks: %d assertions, %d failed" % [checked, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check_at_size(size: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.gui_embed_subwindows = true
	get_tree().root.add_child(vp)

	var stack := UIStack.new()
	vp.add_child(stack)
	await get_tree().process_frame

	var items := [
		{"text": "MALAM BARU", "cb": func() -> void: pass},
		{"text": "LANJUTKAN (MALAM 5)", "cb": func() -> void: pass},
		{"text": "MALAM 6 (MIMPI BURUK)", "cb": func() -> void: pass, "danger": true},
		{"text": "PENGATURAN", "cb": func() -> void: pass},
		{"text": "KELUAR", "cb": func() -> void: pass},
	]
	var bg: Texture2D = load("res://assets/img/wowok_menu.jpg")
	var menu := stack.make_menu("FIVE NIGHTS\nAT WOWOK", "Bertahan hidup sampai jam 06:00 pagi.", items, bg)
	stack.push(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_screen(vp, menu, "MainMenu@%s" % size, size)

	var settings := stack.make_settings(func() -> void: stack.pop())
	stack.push(settings)
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_screen(vp, settings, "Settings@%s" % size, size)

	stack.pop()
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_screen(vp, menu, "MainMenuAfterPop@%s" % size, size)

	vp.queue_free()
	await get_tree().process_frame


func _verify_screen(vp: SubViewport, screen_node: Control, label: String, size: Vector2i) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(size)).grow(2.0)
	for node in screen_node.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree():
			continue
		var rect := c.get_global_rect()
		checked += 1
		if not bounds.encloses(rect):
			failed += 1
			push_error("FAIL %s: %s off-screen (%s outside %s)" % [label, screen_node.get_path_to(c), rect, bounds])
	checked += 1
	if vp.gui_get_focus_owner() == null:
		failed += 1
		push_error("FAIL %s: nothing has focus (gamepad stranded)" % label)
