extends CanvasLayer
class_name UIStack
## Tumpukan layar menu (game-ui-ux + godot-ui-control): hanya layar teratas menerima input/fokus, lengkap nuansa CRT.

const CRT_SHADER := """
shader_type canvas_item;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	float scan = step(0.5, fract(UV.y * 270.0)) * 0.16;
	float noise = h(UV * vec2(640.0, 360.0) + vec2(TIME * 41.0, TIME * 19.0)) * 0.055;
	float glitch = step(0.994, h(vec2(floor(UV.y * 32.0), floor(TIME * 6.0)))) * 0.12;
	float vig = smoothstep(0.32, 0.98, distance(UV, vec2(0.5))) * 0.55;
	COLOR = vec4(vec3(noise + glitch), clamp(scan + noise + glitch + vig, 0.0, 0.78));
}
"""

signal changed

var stack: Array[Control] = []
var ui_theme: Theme
var _focus_memory := {}
var _blip_sfx: AudioStreamPlayer


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui_theme = load("res://ui/theme.tres") as Theme
	if ui_theme == null:
		ui_theme = Theme.new()
	_blip_sfx = AudioStreamPlayer.new()
	_blip_sfx.bus = &"SFX"
	_blip_sfx.max_polyphony = 3
	_blip_sfx.stream = Game.synth_tone(880.0, 660.0, 0.05, 2.2, 0.4, 0.05)
	_blip_sfx.volume_db = -12.0
	add_child(_blip_sfx)


# ---------- Stack ----------
func push(screen: Control) -> void:
	if not stack.is_empty():
		var below: Control = stack.back()
		_focus_memory[below] = get_viewport().gui_get_focus_owner()
		_set_active(below, false)
		below.visible = false
	screen.theme = ui_theme
	stack.append(screen)
	add_child(screen)
	_set_active(screen, true)
	_focus_first.call_deferred(screen)
	changed.emit()

func pop() -> void:
	if stack.is_empty():
		return
	var top: Control = stack.pop_back()
	_focus_memory.erase(top)
	top.queue_free()
	if not stack.is_empty():
		var t: Control = stack.back()
		t.visible = true
		_set_active(t, true)
		var f: Control = _focus_memory.get(t)
		if is_instance_valid(f):
			f.grab_focus.call_deferred()
		else:
			_focus_first.call_deferred(t)
	changed.emit()

func clear() -> void:
	while not stack.is_empty():
		var top: Control = stack.pop_back()
		top.queue_free()
	_focus_memory.clear()
	changed.emit()

func is_empty() -> bool:
	return stack.is_empty()

func _set_active(s: Control, on: bool) -> void:
	s.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED
	s.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if on else Control.MOUSE_BEHAVIOR_DISABLED

func _find_focusable(n: Node) -> Control:
	if n is Control:
		var c: Control = n
		if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
			if not (c is BaseButton and (c as BaseButton).disabled):
				return c
	for ch in n.get_children():
		var r := _find_focusable(ch)
		if r:
			return r
	return null

func _focus_first(screen: Control) -> void:
	if not is_instance_valid(screen):
		return
	var f := _find_focusable(screen)
	if f:
		f.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if stack.is_empty():
		return
	var top: Control = stack.back()
	if event.is_action_pressed(&"ui_cancel") and top.has_meta("on_cancel"):
		(top.get_meta("on_cancel") as Callable).call()
		get_viewport().set_input_as_handled()
		return
	# Jangan pernah biarkan layar tanpa fokus (mouse bisa melepasnya).
	if get_viewport().gui_get_focus_owner() == null:
		for a in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]:
			if event.is_action_pressed(a):
				_focus_first(top)
				get_viewport().set_input_as_handled()
				return


func _wire_fnaf_btn(b: Button, base_text: String, danger: bool = false) -> void:
	b.text = "   " + base_text
	if danger and not b.disabled:
		b.add_theme_color_override("font_color", Color(1.0, 0.34, 0.34))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.6, 0.6))
		b.add_theme_color_override("font_focus_color", Color(1.0, 0.45, 0.45))
	var hi := func() -> void:
		if not b.disabled:
			b.text = ">> " + base_text
	var lo := func() -> void:
		if not b.has_focus():
			b.text = "   " + base_text
	b.focus_entered.connect(func() -> void:
		hi.call()
		if _blip_sfx and is_inside_tree():
			_blip_sfx.pitch_scale = 1.0
			_blip_sfx.play())
	b.focus_exited.connect(func() -> void: b.text = "   " + base_text)
	b.mouse_entered.connect(hi)
	b.mouse_exited.connect(lo)
	b.pressed.connect(func() -> void:
		if _blip_sfx and is_inside_tree():
			_blip_sfx.pitch_scale = 1.25
			_blip_sfx.play())


func _add_crt_overlay(root: Control) -> void:
	var crt := ColorRect.new()
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = CRT_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	crt.material = sm
	root.add_child(crt)


# ---------- Builder layar ----------
## items: [{text: String, cb: Callable, disabled: bool, danger: bool}]
func make_menu(title: String, subtitle: String, items: Array, bg: Texture2D = null, on_cancel: Callable = Callable()) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if bg:
		var tr := TextureRect.new()
		tr.texture = bg
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.58 if bg else 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	_add_crt_overlay(root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin(margin, 96, 40)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 78)
	t.add_theme_color_override("font_color", Color(0.9, 0.12, 0.12))
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 10)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)

	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.add_theme_font_size_override("font_size", 26)
		s.add_theme_color_override("font_outline_color", Color.BLACK)
		s.add_theme_constant_override("outline_size", 6)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(s)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)

	for it in items:
		var b := Button.new()
		b.custom_minimum_size = Vector2(560, 62)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = it.get("disabled", false)
		_wire_fnaf_btn(b, String(it.text), bool(it.get("danger", false)))
		b.pressed.connect(it.cb)
		col.add_child(b)

	if bg:
		var ver := Label.new()
		ver.text = "v2.0 Remake • Godot 4.7"
		ver.add_theme_font_size_override("font_size", 20)
		ver.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
		ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
		ver.offset_right = -32
		ver.offset_bottom = -20
		ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ver)

	if on_cancel.is_valid():
		root.set_meta("on_cancel", on_cancel)
	return root

func make_settings(on_back: Callable) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	_add_crt_overlay(root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin(margin, 96, 36)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var t := Label.new()
	t.text = "PENGATURAN"
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", Color(0.9, 0.12, 0.12))
	col.add_child(t)

	_slider_row(col, "Volume Utama", 0.0, 1.0, Game.master_volume, func(v: float) -> void:
		Game.master_volume = v
		Game.apply_audio())
	_slider_row(col, "Volume Musik", 0.0, 1.0, Game.music_volume, func(v: float) -> void:
		Game.music_volume = v
		Game.apply_audio())
	_slider_row(col, "Efek Suara & Suara", 0.0, 1.0, Game.sfx_volume, func(v: float) -> void:
		Game.sfx_volume = v
		Game.apply_audio())
	_slider_row(col, "Sensitivitas Mouse", 0.0005, 0.006, Game.mouse_sens, func(v: float) -> void:
		Game.mouse_sens = v)
	_slider_row(col, "Guncangan Kamera", 0.0, 1.0, Game.shake_strength, func(v: float) -> void:
		Game.shake_strength = v)

	var back := Button.new()
	back.custom_minimum_size = Vector2(560, 62)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wire_fnaf_btn(back, "KEMBALI")
	back.pressed.connect(on_back)
	col.add_child(back)
	root.set_meta("on_cancel", on_back)
	return root

func _slider_row(parent: Control, label: String, lo: float, hi: float, val: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(360, 0)
	l.add_theme_font_size_override("font_size", 26)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 40.0
	s.value = val
	s.custom_minimum_size = Vector2(440, 38)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		cb.call(v)
		Game.save_settings())
	row.add_child(s)
	parent.add_child(row)

## Inset area aman (hanya perangkat mobile yang melaporkan nilai nyata) + margin dasar.
func _safe_margin(m: MarginContainer, base_x: int, base_y: int) -> void:
	var apply := func() -> void:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var win := Rect2(Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size()))
		var inner := safe.intersection(win)
		var l := 0
		var t := 0
		var r := 0
		var b := 0
		if win.size.x > 0.0 and win.size.y > 0.0 and inner.size.x > 0.0:
			var k := get_viewport().get_visible_rect().size / win.size
			l = int(maxf(0.0, inner.position.x - win.position.x) * k.x)
			t = int(maxf(0.0, inner.position.y - win.position.y) * k.y)
			r = int(maxf(0.0, win.end.x - inner.end.x) * k.x)
			b = int(maxf(0.0, win.end.y - inner.end.y) * k.y)
		m.add_theme_constant_override("margin_left", base_x + l)
		m.add_theme_constant_override("margin_top", base_y + t)
		m.add_theme_constant_override("margin_right", base_x + r)
		m.add_theme_constant_override("margin_bottom", base_y + b)
	apply.call()
	get_viewport().size_changed.connect(apply)
