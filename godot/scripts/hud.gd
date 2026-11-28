extends CanvasLayer
class_name HUD
## HUD tampil penuh di 2D Editor (`hud.tscn`) dan digerakkan sinyal saat bermain (tanpa polling).

@onready var bars: Control = %LockerPeekBars
@onready var safe_margin: MarginContainer = %SafeMargin
@onready var time_label: Label = %TimeLabel
@onready var night_label: Label = %NightLabel
@onready var controls_label: Label = %ControlsLabel
@onready var threat_label: Label = %ThreatLabel
@onready var gen_label: Label = %GenLabel
@onready var hidden_label: Label = %HiddenLabel
@onready var breath_box: VBoxContainer = %BreathBox
@onready var breath_label: Label = %BreathLabel
@onready var breath_bar: ProgressBar = %BreathBar
@onready var ammo_label: Label = %AmmoLabel
@onready var power_label: Label = %PowerLabel
@onready var power_bar: ProgressBar = %PowerBar
@onready var usage_row: HBoxContainer = %UsageRow
@onready var doors_label: Label = %DoorsLabel
@onready var battery_label: Label = %BatteryLabel
@onready var battery_bar: ProgressBar = %BatteryBar
@onready var toast_label: Label = %ToastLabel
@onready var prompt_label: Label = %PromptLabel

var player: Player
var usage_boxes: Array[ColorRect] = []
var _toast_tween: Tween
var _power_fill: StyleBoxFlat
var _breath_fill: StyleBoxFlat


func bind(p: Player) -> void:
	player = p
	if p:
		p.prompt_changed.connect(func(t: String) -> void: prompt_label.text = t)


func _ready() -> void:
	layer = 10
	for ch in usage_row.get_children():
		if ch is ColorRect:
			usage_boxes.append(ch as ColorRect)

	var pf := power_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if pf:
		_power_fill = pf.duplicate() as StyleBoxFlat
		power_bar.add_theme_stylebox_override("fill", _power_fill)
	var bf := breath_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if bf:
		_breath_fill = bf.duplicate() as StyleBoxFlat
		breath_bar.add_theme_stylebox_override("fill", _breath_fill)

	_apply_safe(safe_margin)

	Game.hour_changed.connect(_on_hour)
	Game.night_changed.connect(_on_night)
	Game.power_changed.connect(_on_power)
	Game.usage_changed.connect(_on_usage)
	Game.battery_changed.connect(_on_battery)
	Game.breath_changed.connect(_on_breath)
	Game.generator_changed.connect(_on_gen)
	Game.power_out.connect(func() -> void: _on_gen(Game.gen_cooldown, Game.generator_sabotaged))
	Game.power_restored.connect(func() -> void: _on_gen(Game.gen_cooldown, Game.generator_sabotaged))
	Game.threat_changed.connect(_on_threat)
	Game.hidden_changed.connect(_on_hidden)
	Game.ammo_changed.connect(_on_ammo)
	Game.door_count_changed.connect(_on_doors)
	Game.toast.connect(show_toast)

	_on_night(Game.night)
	_on_hour(Game.hour)
	_on_power(Game.power)
	_on_usage(Game.usage)
	_on_battery(Game.battery)
	_on_breath(Game.breath)
	_on_gen(Game.gen_cooldown, Game.generator_sabotaged)
	_on_threat(Game.threat)
	_on_hidden(Game.is_hidden)
	_on_ammo(Game.ammo)
	_on_doors(Game.closed_doors)


func _on_night(n: int) -> void:
	if n >= Game.SECRET_NIGHT:
		night_label.text = "MALAM 6 • LEMBUR"
		night_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.28))
	else:
		night_label.text = "MALAM %d" % n
		night_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))

func _on_hour(h: int) -> void:
	time_label.text = "12 AM" if h == 0 else "%d AM" % h

func _on_power(v: float) -> void:
	power_label.text = "DAYA %d%%" % int(ceilf(v))
	power_bar.value = v
	var col := Color(0.32, 0.85, 0.42)
	if v <= 20.0:
		col = Color(0.95, 0.25, 0.22)
	elif v <= 50.0:
		col = Color(0.95, 0.78, 0.2)
	if _power_fill:
		_power_fill.bg_color = col
	power_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if v < 20.0 else Color(0.92, 0.92, 0.92))

func _on_usage(u: int) -> void:
	var cols := [
		Color(0.3, 0.85, 0.4),
		Color(0.55, 0.85, 0.3),
		Color(0.95, 0.8, 0.2),
		Color(0.95, 0.5, 0.18),
		Color(0.95, 0.2, 0.2),
	]
	for i in usage_boxes.size():
		usage_boxes[i].color = cols[i] if i < u else Color(0.15, 0.16, 0.18, 0.8)

func _on_battery(v: float) -> void:
	battery_label.text = "SENTER %d%%" % int(ceilf(v))
	battery_bar.value = v

func _on_breath(v: float) -> void:
	breath_label.text = "NAPAS %d%%" % int(ceilf(v))
	breath_bar.value = v
	breath_box.visible = Game.is_hidden or v < 98.5
	if _breath_fill:
		_breath_fill.bg_color = Color(0.95, 0.28, 0.25) if v < 30.0 else Color(0.35, 0.82, 0.95)

func _on_gen(cd: float, sab: bool) -> void:
	if Game.power_is_out:
		gen_label.text = "⚡ LISTRIK PADAM — Nyalakan Generator R3!"
		gen_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.25))
	elif sab:
		gen_label.text = "⚠ SEKRING R3 DISABOTASE — Daya Bocor!"
		gen_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.2))
	elif cd > 0.0:
		gen_label.text = "⚡ Generator R3: Dingin (%ds)" % int(ceilf(cd))
		gen_label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.35))
	else:
		gen_label.text = "⚡ Generator R3: Siap"
		gen_label.add_theme_color_override("font_color", Color(0.62, 0.88, 0.72))

func _on_doors(n: int) -> void:
	doors_label.text = "Pintu tertutup: %d / 6" % n

func _on_threat(level: int) -> void:
	match level:
		0:
			threat_label.text = "● AMAN"
			threat_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		1:
			threat_label.text = "▲ WASPADA"
			threat_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_:
			threat_label.text = "■ DIKEJAR!"
			threat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _on_hidden(h: bool) -> void:
	hidden_label.text = "◐ BERSEMBUNYI DI LOKER" if h else ""
	bars.visible = h
	breath_box.visible = h or Game.breath < 98.5

func _on_ammo(n: int) -> void:
	ammo_label.text = "" if (n == 0 and not (player and player.has_gun)) else "PELURU: %d" % n

func show_toast(t: String) -> void:
	if t == "":
		return
	toast_label.text = t
	toast_label.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.8)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func _apply_safe(m: MarginContainer) -> void:
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
		m.add_theme_constant_override("margin_left", 44 + l)
		m.add_theme_constant_override("margin_top", 32 + t)
		m.add_theme_constant_override("margin_right", 44 + r)
		m.add_theme_constant_override("margin_bottom", 32 + b)
	apply.call()
	get_viewport().size_changed.connect(apply)
