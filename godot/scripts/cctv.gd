extends CanvasLayer
class_name CCTV
## Tablet Monitor CCTV: tampil penuh di 2D Editor (`cctv.tscn`) dan tersembunyi otomatis saat awal malam.

@onready var sv: SubViewport = %SubViewport
@onready var cam: Camera3D = %CCTVCam
@onready var fx: ColorRect = %CRTStaticFX
@onready var name_label: Label = %NameLabel
@onready var alert_label: Label = %AlertLabel
@onready var clock_label: Label = %ClockLabel
@onready var power_label: Label = %PowerLabel
@onready var gen_map_label: Label = %GenMapLabel
@onready var map_vbox: VBoxContainer = %MapVBox

var world: World
var idx := 0
var buttons: Array[Button] = []
var door_badges: Array[ColorRect] = []
var static_sfx: AudioStreamPlayer
var _burst_tween: Tween
var _scan_t := 0.0


func bind(w: World) -> void:
	world = w
	if sv and world and world.is_inside_tree():
		sv.world_3d = world.get_world_3d()
	if is_inside_tree():
		_refresh_button_labels()
		_select(idx, false)


func _ready() -> void:
	layer = 20
	visible = Game.camera_open

	buttons.resize(7)
	for i in 7:
		var b := map_vbox.find_child("CamBtn%d" % i, true, false) as Button
		if b:
			b.focus_entered.connect(_select.bind(i))
			b.pressed.connect(_select.bind(i))
			buttons[i] = b

	door_badges.resize(6)
	for did in 6:
		var db := map_vbox.find_child("DoorBadge%d" % did, true, false) as ColorRect
		if db:
			door_badges[did] = db

	static_sfx = AudioStreamPlayer.new()
	static_sfx.bus = &"SFX"
	static_sfx.stream = Game.synth_burst(0.28, 1.2, 0.65, 0.8)
	static_sfx.volume_db = -10.0
	add_child(static_sfx)

	if world and world.is_inside_tree():
		sv.world_3d = world.get_world_3d()
	_refresh_button_labels()

	Game.camera_toggled.connect(_on_toggle)
	Game.hour_changed.connect(func(h: int) -> void: clock_label.text = "12 AM" if h == 0 else "%d AM" % h)
	Game.power_changed.connect(func(p: float) -> void: power_label.text = "DAYA GEDUNG: %d%%" % int(ceilf(p)))
	Game.door_state_changed.connect(_on_door_state)
	Game.generator_changed.connect(func(_cd: float, _sab: bool) -> void: _refresh_gen_status())
	Game.power_out.connect(_refresh_gen_status)
	Game.power_restored.connect(_refresh_gen_status)

	clock_label.text = "12 AM"
	power_label.text = "DAYA GEDUNG: %d%%" % int(ceilf(Game.power))
	_refresh_gen_status()
	for did in 6:
		_on_door_state(did, Game.door_states.get(did, false))
	_select(idx, false)


func _refresh_button_labels() -> void:
	if world == null:
		return
	for i in mini(buttons.size(), world.cams.size()):
		if buttons[i]:
			buttons[i].text = "%d • %s" % [i + 1, String(world.cams[i].get("short", "CAM"))]

func _on_door_state(door_id: int, closed_val: bool) -> void:
	if door_id >= 0 and door_id < door_badges.size() and door_badges[door_id] != null:
		door_badges[door_id].color = Color(1.0, 0.22, 0.2) if closed_val else Color(0.25, 0.95, 0.45)

func _refresh_gen_status() -> void:
	if gen_map_label == null:
		return
	if Game.generator_sabotaged:
		gen_map_label.text = "⚠ PERINGATAN: Sekring R3 Server Rusak!"
		gen_map_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	elif Game.gen_cooldown > 0.0:
		gen_map_label.text = "⚡ Generator R3: Cooldown %ds" % int(ceilf(Game.gen_cooldown))
		gen_map_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	else:
		gen_map_label.text = "⚡ Generator R3 Server: Normal"
		gen_map_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.72))

func _on_toggle(open: bool) -> void:
	visible = open
	cam.current = open
	if open:
		if sv and world and world.is_inside_tree():
			sv.world_3d = world.get_world_3d()
		_select(idx, true)
		_focus_active_btn.call_deferred()
	else:
		var f := get_viewport().gui_get_focus_owner()
		if f:
			f.release_focus()

func _focus_active_btn() -> void:
	if visible and idx >= 0 and idx < buttons.size() and buttons[idx]:
		buttons[idx].grab_focus()

func _select(i: int, burst: bool = true) -> void:
	if world == null or i < 0 or i >= world.cams.size():
		return
	idx = i
	var c: Dictionary = world.cams[i]
	cam.global_position = c.pos
	cam.look_at(c.look, Vector3.UP)
	name_label.text = "● REC  " + String(c.name)
	_update_enemy_alert()
	if burst and visible:
		static_sfx.play()
		var sm := fx.material as ShaderMaterial
		if _burst_tween:
			_burst_tween.kill()
		sm.set_shader_parameter("burst", 1.0)
		_burst_tween = create_tween()
		_burst_tween.tween_method(func(v: float) -> void: sm.set_shader_parameter("burst", v), 1.0, 0.0, 0.32)

func _update_enemy_alert() -> void:
	if alert_label == null or world == null or world.enemy == null or idx < 0 or idx >= world.cams.size():
		return
	var ep := world.enemy.global_position
	var in_feed := false
	if idx == 3:
		in_feed = absf(ep.z) <= 2.3
	else:
		var rc: Vector3 = world.cams[idx].get("room_center", Vector3.ZERO)
		in_feed = absf(ep.x - rc.x) <= 5.2 and absf(ep.z - rc.z) <= 5.2
	alert_label.text = "⚠ ADA WOWOK!" if in_feed else ""

func _process(delta: float) -> void:
	if not visible:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_update_enemy_alert()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"camera_toggle") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"crouch"):
		Game.set_camera(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cam_prev"):
		buttons[posmod(idx - 1, buttons.size())].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cam_next"):
		buttons[posmod(idx + 1, buttons.size())].grab_focus()
		get_viewport().set_input_as_handled()
