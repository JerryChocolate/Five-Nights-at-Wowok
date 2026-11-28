extends Node3D
class_name World
## Dunia 3D Gedung Kantor Wowok: seluruh ruangan, prop, lampu, kamera CCTV, waypoint, Player, & Enemy
## tersimpan nyata di `scenes/world.tscn` agar bisa diedit langsung di 3D Viewport Godot Editor
## maupun dijalankan mandiri dengan tombol F6 (Run Current Scene).

@export_group("Standalone F6 Editor Test")
@export_range(1, 6, 1) var standalone_test_night: int = 1
@export var standalone_infinite_power: bool = false
@export var standalone_god_mode: bool = false
@export var standalone_freeze_enemy: bool = false

var managed_by_main := false
var player: Player
var enemy: Enemy
var nav := AStar3D.new()
var patrol_ids := PackedInt32Array()
var generator_nav_id: int = -1
var cams: Array[Dictionary] = []

var _lights: Array[Dictionary] = []
var _emergency: Array[OmniLight3D] = []
var _flicker_t := 0.0
var _is_compat := false
var _built := false
var _standalone_mode := false
var _standalone_hud: HUD
var _standalone_cctv: CCTV


func _ready() -> void:
	var method := RenderingServer.get_current_rendering_method()
	_is_compat = method == "gl_compatibility" or method == "mobile" or OS.has_feature("web")
	_collect_scene_nodes()

	# Bila world.tscn dijalankan langsung dengan F6 (Run Current Scene) di Godot Editor:
	if not managed_by_main and get_tree().current_scene == self:
		_standalone_mode = true
		Game.debug_infinite_power = standalone_infinite_power
		Game.debug_god_mode = standalone_god_mode
		build(standalone_test_night)
		if enemy and standalone_freeze_enemy:
			enemy.freeze_ai = true
		var cctv_packed := load("res://scenes/cctv.tscn") as PackedScene
		_standalone_cctv = cctv_packed.instantiate() as CCTV
		_standalone_cctv.bind(self)
		add_child(_standalone_cctv)
		var hud_packed := load("res://scenes/hud.tscn") as PackedScene
		_standalone_hud = hud_packed.instantiate() as HUD
		add_child(_standalone_hud)
		Game.start_night(standalone_test_night)
		_standalone_hud.bind(player)
		Game.camera_toggled.connect(func(_o: bool) -> void: _update_standalone_mouse())
		_update_standalone_mouse()


func _update_standalone_mouse() -> void:
	if not _standalone_mode:
		return
	var cap := Game.state == Game.S.PLAYING and not Game.camera_open
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if cap else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not _standalone_mode:
		return
	if event.is_action_pressed(&"pause") and not Game.camera_open:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Game.toast.emit("Kursor dilepas (tekan Esc lagi untuk mengunci mouse)")
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _collect_scene_nodes() -> void:
	player = get_node_or_null("Player") as Player
	enemy = get_node_or_null("Enemy") as Enemy

	# Sesuaikan Environment bila berjalan di Compatibility / Web
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment and _is_compat:
		var env := we.environment.duplicate() as Environment
		env.background_color = Color(0.02, 0.025, 0.035)
		env.ambient_light_color = Color(0.16, 0.19, 0.24)
		env.ambient_light_energy = 0.95
		env.glow_enabled = false
		env.ssao_enabled = false
		env.fog_density = 0.014
		env.volumetric_fog_enabled = false
		we.environment = env

	# Kumpulkan lampu ruangan & lampu darurat dari pohon scene
	_lights.clear()
	var rl := get_node_or_null("Lighting/RoomLights")
	if rl:
		for ch in rl.get_children():
			if ch is OmniLight3D:
				var l := ch as OmniLight3D
				if _is_compat:
					l.light_energy *= 1.25
					l.omni_range *= 1.12
					l.shadow_enabled = false
				_lights.append({
					"node": l,
					"base": l.light_energy,
					"color": l.light_color,
					"flicker": bool(l.get_meta("flicker", false)),
				})

	_emergency.clear()
	var el := get_node_or_null("Lighting/EmergencyLights")
	if el:
		for ch in el.get_children():
			if ch is OmniLight3D:
				_emergency.append(ch as OmniLight3D)

	# Bangun grafik AStar3D dari node Marker3D di $NavWaypoints
	nav.clear()
	patrol_ids.clear()
	generator_nav_id = -1
	var nw := get_node_or_null("NavWaypoints")
	if nw:
		var pending_edges: Array[Vector2i] = []
		for ch in nw.get_children():
			if ch is Node3D:
				var m := ch as Node3D
				var wid := int(m.get_meta("wp_id", -1))
				if wid < 0:
					continue
				nav.add_point(wid, m.position)
				if bool(m.get_meta("is_patrol", false)):
					patrol_ids.append(wid)
				if bool(m.get_meta("is_generator", false)):
					generator_nav_id = wid
				var conns: PackedInt32Array = m.get_meta("connect_to", PackedInt32Array())
				for target_id in conns:
					pending_edges.append(Vector2i(wid, target_id))
		for edge in pending_edges:
			if nav.has_point(edge.x) and nav.has_point(edge.y) and not nav.are_points_connected(edge.x, edge.y):
				nav.connect_points(edge.x, edge.y)

	# Kumpulkan titik kamera CCTV langsung dari node Camera3D di $CCTVCameras
	cams.clear()
	var cc := get_node_or_null("CCTVCameras")
	if cc:
		for ch in cc.get_children():
			if ch is Node3D:
				var cnode := ch as Node3D
				var fwd := -cnode.global_transform.basis.z
				cams.append({
					"name": String(cnode.get_meta("cam_title", cnode.name)),
					"short": String(cnode.get_meta("cam_short", "CAM")),
					"pos": cnode.position,
					"look": cnode.position + fwd * 6.0,
					"room_center": Vector3(cnode.get_meta("room_center", Vector3.ZERO)),
				})


func build(night: int) -> void:
	if nav.get_point_count() == 0:
		_collect_scene_nodes()

	# Nuansa merah mencekam khusus Secret Night 6
	var night6_tint := Color(1.0, 0.55, 0.5)
	for l in _lights:
		var n: OmniLight3D = l.node
		var base_col: Color = l.color
		n.light_color = base_col.lerp(night6_tint, 0.3) if night >= Game.SECRET_NIGHT else base_col
		n.light_energy = float(l.base)

	if enemy and player:
		enemy.setup(nav, patrol_ids, generator_nav_id, player, night)

	if not _built:
		_built = true
		Game.power_out.connect(_on_power_out)
		Game.power_restored.connect(_on_power_restored)


func _process(delta: float) -> void:
	if Game.power_is_out:
		return
	_flicker_t -= delta
	if _flicker_t > 0.0:
		return
	_flicker_t = 0.07
	var chance := 0.04 + 0.18 * float(Game.threat) + (0.12 if Game.generator_sabotaged else 0.0)
	for l in _lights:
		if l.flicker or Game.generator_sabotaged:
			var n: OmniLight3D = l.node
			if is_instance_valid(n):
				n.light_energy = float(l.base) * (randf_range(0.08, 0.55) if randf() < chance else 1.0)


func _on_power_out() -> void:
	for l in _lights:
		var n: OmniLight3D = l.node
		if is_instance_valid(n):
			var t := create_tween()
			t.tween_property(n, "light_energy", 0.0, 1.1)
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree() or not Game.power_is_out:
		return
	for e in _emergency:
		if is_instance_valid(e):
			e.visible = true


func _on_power_restored() -> void:
	for e in _emergency:
		if is_instance_valid(e):
			e.visible = false
	for l in _lights:
		var n: OmniLight3D = l.node
		if is_instance_valid(n):
			var t := create_tween()
			t.tween_property(n, "light_energy", float(l.base), 0.7)
