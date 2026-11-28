extends CanvasLayer
class_name CCTV
## Tablet Monitor CCTV Gedung Sidang Paripurna: 8 titik pantau + Mini-Map Blueprint Vektor interaktif.

@onready var sv: SubViewport = %SubViewport
@onready var cam: Camera3D = %CCTVCam
@onready var fx: ColorRect = %CRTStaticFX
@onready var name_label: Label = %NameLabel
@onready var alert_label: Label = %AlertLabel
@onready var clock_label: Label = %ClockLabel
@onready var power_label: Label = %PowerLabel
@onready var gen_map_label: Label = %GenMapLabel
@onready var minimap: ParipurnaMinimap = %ParipurnaMapCanvas

const CAM_COUNT := 8
const DOOR_COUNT := 8

var world: World
var idx := 0
var buttons: Array[Button] = []
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
	if sv:
		sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if visible else SubViewport.UPDATE_DISABLED

	buttons.resize(CAM_COUNT)
	for i in CAM_COUNT:
		var b := minimap.find_child("CamBtn%d" % i, true, false) as Button
		if b:
			b.focus_entered.connect(_select.bind(i))
			b.pressed.connect(_select.bind(i))
			buttons[i] = b

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
	for did in DOOR_COUNT:
		_on_door_state(did, Game.door_states.get(did, false))
	_select(idx, false)


func _refresh_button_labels() -> void:
	if world == null:
		return
	for i in mini(buttons.size(), world.cams.size()):
		if buttons[i]:
			buttons[i].text = "%d•%s" % [i + 1, String(world.cams[i].get("short", "CAM"))]


func _on_door_state(door_id: int, closed_val: bool) -> void:
	if minimap:
		minimap.set_door_state(door_id, closed_val)


func _refresh_gen_status() -> void:
	if gen_map_label == null:
		return
	if Game.generator_sabotaged:
		gen_map_label.text = "⚠ PERINGATAN: Sekring Ruang Server Barat Laut Rusak!"
		gen_map_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	elif Game.gen_cooldown > 0.0:
		gen_map_label.text = "⚡ Generator Barat Laut: Cooldown %ds" % int(ceilf(Game.gen_cooldown))
		gen_map_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	else:
		gen_map_label.text = "⚡ Generator Barat Laut: Normal  |  ● Biru = Pos Sekuriti"
		gen_map_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.72))


func _on_toggle(open: bool) -> void:
	visible = open
	cam.current = open
	if sv:
		sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if open else SubViewport.UPDATE_DISABLED
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
	var c: Dictionary = world.cams[idx]
	var in_feed := false
	if bool(c.get("is_ring", false)):
		var r_radial := Vector2(ep.x, ep.z).length()
		in_feed = maxf(absf(ep.x), absf(ep.z)) <= 16.8 and r_radial >= 11.0
	elif idx == 0:
		# Kamera 1: Ruang Sidang Paripurna bundar (R <= 11.6m)
		in_feed = Vector2(ep.x, ep.z).length() <= 11.7
	else:
		var rc: Vector3 = c.get("room_center", Vector3.ZERO)
		var he: Vector2 = c.get("half_extents", Vector2(10.0, 10.0))
		in_feed = absf(ep.x - rc.x) <= he.x and absf(ep.z - rc.z) <= he.y
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
