extends Node3D
class_name World
## Dunia 3D Gedung Sidang Paripurna (~70m x 60m) — Edisi Shader High-End & AStarGrid2D Presisi:
## Dilengkapi pemindaian fisika otomatis ke AStarGrid2D (0.5m) dengan penghindaran meja/kursi/pilar,
## bobot pintu sekuriti dinamis (agar Wowok memutar lewat pintu terbuka), dan penghalusan jalur string-pulling.

@export_group("Standalone F6 Editor Test")
@export_range(1, 6, 1) var standalone_test_night: int = 1
@export var standalone_infinite_power: bool = false
@export var standalone_god_mode: bool = false
@export var standalone_freeze_enemy: bool = false

const GRID_CELL := 0.5
const GRID_MIN := Vector2(-35.5, -30.5)
const GRID_SIZE := Vector2i(142, 122) # mencakup X[-35.5..+35.5], Z[-30.5..+30.5]

var managed_by_main := false
var player: Player
var enemy: Enemy
var nav := AStar3D.new()
var nav_grid := AStarGrid2D.new()
var nav_grid_ready := false
var patrol_ids := PackedInt32Array()
var generator_nav_id: int = -1
var cams: Array[Dictionary] = []

var _door_cells: Dictionary = {} # door_id -> Array[Vector2i]
var _lights: Array[Dictionary] = []
var _emergency: Array[Light3D] = []
var _shafts: Array[Node3D] = []
var _we: WorldEnvironment
var _flicker_t := 0.0
var _shadow_t := 0.0
var _max_shadow_lights := 5
var _is_compat := false
var _built := false
var _standalone_mode := false
var _standalone_hud: HUD
var _standalone_cctv: CCTV
var _standalone_fx: CanvasLayer
var _standalone_fx_mat: ShaderMaterial


func _ready() -> void:
	var method := RenderingServer.get_current_rendering_method()
	_is_compat = method == "gl_compatibility" or method == "mobile" or OS.has_feature("web")
	_collect_scene_nodes()
	_apply_graphics_preset(Game.graphics_preset)
	Game.graphics_changed.connect(_apply_graphics_preset)
	Game.door_state_changed.connect(_on_door_grid_weight)
	_bake_nav_grid_deferred.call_deferred()

	if not managed_by_main and get_tree().current_scene == self:
		_standalone_mode = true
		Game.debug_infinite_power = standalone_infinite_power
		Game.debug_god_mode = standalone_god_mode
		build(standalone_test_night)
		if enemy and standalone_freeze_enemy:
			enemy.freeze_ai = true
		_spawn_standalone_bodycam_fx()
		var cctv_packed := load("res://scenes/cctv.tscn") as PackedScene
		_standalone_cctv = cctv_packed.instantiate() as CCTV
		_standalone_cctv.bind(self)
		add_child(_standalone_cctv)
		var hud_packed := load("res://scenes/hud.tscn") as PackedScene
		_standalone_hud = hud_packed.instantiate() as HUD
		add_child(_standalone_hud)
		Game.start_night(standalone_test_night)
		_standalone_hud.bind(player)
		Game.camera_toggled.connect(func(o: bool) -> void:
			if _standalone_fx:
				_standalone_fx.visible = not o
			_update_standalone_mouse())
		Game.threat_changed.connect(func(lv: int) -> void:
			if _standalone_fx_mat:
				_standalone_fx_mat.set_shader_parameter("intensity", float(lv) * 0.5))
		Game.cam_lens_updated.connect(func(z: float, fb: float) -> void:
			if _standalone_fx_mat:
				_standalone_fx_mat.set_shader_parameter("zoom_amount", z)
				_standalone_fx_mat.set_shader_parameter("focus_blur", fb))
		_update_standalone_mouse()


func _bake_nav_grid_deferred() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	bake_nav_grid()


## Pemindaian fisika 3D -> AStarGrid2D resolusi 0.5m agar meja, kursi, rak, & pilar terhindar otomatis!
func bake_nav_grid() -> void:
	nav_grid.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	nav_grid.cell_size = Vector2(GRID_CELL, GRID_CELL)
	nav_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav_grid.update()

	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	# Lebar 0.84m (radius agen 0.40m + margin aman), tinggi y=0.44..1.66m (di atas ramp podium 0.34m, mengenai meja 0.84m!)
	box.size = Vector3(0.84, 1.22, 0.84)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	var excl: Array[RID] = []
	if player:
		excl.append(player.get_rid())
	if enemy:
		excl.append(enemy.get_rid())
	# Abaikan pintu sekuriti saat memanggang peta dasar (pintu diatur dinamis lewat weight_scale!)
	for dn in get_tree().get_nodes_in_group("doors"):
		if dn is CollisionObject3D:
			excl.append((dn as CollisionObject3D).get_rid())
	q.exclude = excl

	for gx in GRID_SIZE.x:
		var wx := GRID_MIN.x + (float(gx) + 0.5) * GRID_CELL
		for gz in GRID_SIZE.y:
			var wz := GRID_MIN.y + (float(gz) + 0.5) * GRID_CELL
			# Tandai luar siluet stepped gedung Paripurna sebagai solid
			var outside := false
			if absf(wx) > 34.6 or absf(wz) > 29.6:
				outside = true
			elif absf(wx) > 13.7 and absf(wz) > 24.6:
				outside = true
			if outside:
				nav_grid.set_point_solid(Vector2i(gx, gz), true)
				continue
			q.transform = Transform3D(Basis.IDENTITY, Vector3(wx, 1.05, wz))
			if not space.intersect_shape(q, 1).is_empty():
				nav_grid.set_point_solid(Vector2i(gx, gz), true)

	# Petakan sel di bawah tiap pintu sekuriti agar menutup 1 pintu membuat Wowok memutar lewat pintu terbuka!
	_door_cells.clear()
	for dn in get_tree().get_nodes_in_group("doors"):
		if dn is Interactable:
			var d := dn as Interactable
			var cells: Array[Vector2i] = []
			var c_center := world_to_grid(d.global_position)
			for ox in range(-3, 4):
				for oz in range(-3, 4):
					var cell := c_center + Vector2i(ox, oz)
					if nav_grid.is_in_boundsv(cell) and not nav_grid.is_point_solid(cell):
						var wp := grid_to_world(cell)
						var local := d.global_transform.affine_inverse() * wp
						if absf(local.x) <= 1.25 and absf(local.z) <= 0.75:
							cells.append(cell)
			_door_cells[d.door_id] = cells
			_on_door_grid_weight(d.door_id, d.closed)

	nav_grid_ready = true


func _on_door_grid_weight(door_id: int, is_closed: bool) -> void:
	if not _door_cells.has(door_id):
		return
	var w_scale := 90.0 if is_closed else 1.0
	for cell: Vector2i in _door_cells[door_id]:
		if nav_grid.is_in_boundsv(cell) and not nav_grid.is_point_solid(cell):
			nav_grid.set_point_weight_scale(cell, w_scale)


func world_to_grid(pos: Vector3) -> Vector2i:
	var gx := clampi(int(floorf((pos.x - GRID_MIN.x) / GRID_CELL)), 0, GRID_SIZE.x - 1)
	var gz := clampi(int(floorf((pos.z - GRID_MIN.y) / GRID_CELL)), 0, GRID_SIZE.y - 1)
	return Vector2i(gx, gz)


func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		GRID_MIN.x + (float(cell.x) + 0.5) * GRID_CELL,
		0.0,
		GRID_MIN.y + (float(cell.y) + 0.5) * GRID_CELL
	)


func _nearest_walkable_cell(start_cell: Vector2i) -> Vector2i:
	if nav_grid.is_in_boundsv(start_cell) and not nav_grid.is_point_solid(start_cell):
		return start_cell
	for r in range(1, 9):
		var best := start_cell
		var best_d2 := 1e9
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := start_cell + Vector2i(dx, dz)
				if nav_grid.is_in_boundsv(c) and not nav_grid.is_point_solid(c):
					var d2 := float(dx * dx + dz * dz)
					if d2 < best_d2:
						best_d2 = d2
						best = c
		if best_d2 < 1e8:
			return best
	return start_cell


## Uji apakah koridor selebar bahu agen (y=0.55m, bebas meja/kursi/tembok) bersih untuk jalan lurus.
func has_clear_walk_corridor(from_pos: Vector3, to_pos: Vector3, half_width: float = 0.38) -> bool:
	var diff := Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)
	var dist := diff.length()
	if dist < 0.08:
		return true
	var dir := diff / dist
	var side := Vector3(-dir.z, 0.0, dir.x) * half_width
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = []
	if player:
		excl.append(player.get_rid())
	if enemy:
		excl.append(enemy.get_rid())
	for offs: Vector3 in [Vector3.ZERO, side, -side]:
		var a: Vector3 = Vector3(from_pos.x, 0.56, from_pos.z) + offs
		var b: Vector3 = Vector3(to_pos.x, 0.56, to_pos.z) + offs
		var q := PhysicsRayQueryParameters3D.create(a, b, 1, excl)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


## Menghasilkan jalur halus bebas meja/kursi/tembok dengan string-pulling pada AStarGrid2D!
func find_smooth_path(from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	if not nav_grid_ready:
		if nav.get_point_count() == 0:
			return PackedVector3Array([to_pos])
		var a := nav.get_closest_point(from_pos)
		var b := nav.get_closest_point(to_pos)
		return nav.get_point_path(a, b)

	var c_from := _nearest_walkable_cell(world_to_grid(from_pos))
	var c_to := _nearest_walkable_cell(world_to_grid(to_pos))
	var id_path := nav_grid.get_id_path(c_from, c_to, true)
	if id_path.is_empty():
		return PackedVector3Array([to_pos])

	var raw := PackedVector3Array()
	raw.resize(id_path.size())
	for i in id_path.size():
		raw[i] = grid_to_world(id_path[i])

	# String-pulling: lompati titik grid perantara selama koridor bahu lurus bebas hambatan & tanpa melewati pintu tertutup!
	var smooth := PackedVector3Array()
	var anchor := 0
	smooth.append(raw[0])
	while anchor < raw.size() - 1:
		var furthest := anchor + 1
		var max_look := mini(raw.size() - 1, anchor + 18)
		for probe in range(max_look, anchor + 1, -1):
			# Jangan melompati sel berpintu tertutup (weight > 1.5)
			var crosses_weighted := false
			for mid in range(anchor + 1, probe + 1):
				if nav_grid.get_point_weight_scale(id_path[mid]) > 1.5:
					crosses_weighted = true
					break
			if not crosses_weighted and has_clear_walk_corridor(raw[anchor], raw[probe], 0.40):
				furthest = probe
				break
		smooth.append(raw[furthest])
		anchor = furthest
	return smooth


func _spawn_standalone_bodycam_fx() -> void:
	_standalone_fx = CanvasLayer.new()
	_standalone_fx.layer = 5
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standalone_fx_mat = ShaderMaterial.new()
	_standalone_fx_mat.shader = load("res://shaders/bodycam_post.gdshader") as Shader
	rect.material = _standalone_fx_mat
	_standalone_fx.add_child(rect)
	add_child(_standalone_fx)


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

	_we = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _we and _we.environment:
		_we.environment = _we.environment.duplicate() as Environment
		if _is_compat:
			_we.environment.background_color = Color(0.02, 0.025, 0.035)
			_we.environment.ambient_light_color = Color(0.16, 0.19, 0.24)
			_we.environment.ambient_light_energy = 0.92
			_we.environment.glow_enabled = false
			_we.environment.ssao_enabled = false
			_we.environment.fog_density = 0.008
			_we.environment.volumetric_fog_enabled = false

	_lights.clear()
	var rl := get_node_or_null("Lighting/RoomLights")
	if rl:
		for ch in rl.get_children():
			if ch is Light3D:
				var l := ch as Light3D
				if _is_compat:
					l.light_energy *= 1.18
				l.shadow_enabled = false
				_lights.append({
					"node": l,
					"base": l.light_energy,
					"color": l.light_color,
					"flicker": bool(l.get_meta("flicker", false)),
				})

	_shafts.clear()
	var ls := get_node_or_null("Lighting/LightShafts")
	if ls:
		for ch in ls.get_children():
			if ch is Node3D:
				_shafts.append(ch as Node3D)

	_emergency.clear()
	var el := get_node_or_null("Lighting/EmergencyLights")
	if el:
		for ch in el.get_children():
			if ch is Light3D:
				_emergency.append(ch as Light3D)

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
					"look": cnode.position + fwd * 8.0,
					"room_center": Vector3(cnode.get_meta("room_center", Vector3.ZERO)),
					"half_extents": Vector2(cnode.get_meta("room_half_extents", Vector2(10.0, 10.0))),
					"is_ring": bool(cnode.get_meta("is_ring", false)),
				})


func _apply_graphics_preset(preset: int) -> void:
	match preset:
		Game.Gfx.LOW:
			_max_shadow_lights = 0 if _is_compat else 2
			if _we and _we.environment and not _is_compat:
				_we.environment.ssao_enabled = false
				_we.environment.glow_enabled = false
				_we.environment.volumetric_fog_enabled = false
		Game.Gfx.BALANCED:
			_max_shadow_lights = 0 if _is_compat else 5
			if _we and _we.environment and not _is_compat:
				_we.environment.ssao_enabled = false
				_we.environment.glow_enabled = true
				_we.environment.volumetric_fog_enabled = false
		_:
			_max_shadow_lights = 0 if _is_compat else 9
			if _we and _we.environment and not _is_compat:
				_we.environment.ssao_enabled = true
				_we.environment.glow_enabled = true
				_we.environment.volumetric_fog_enabled = false
	if player and player.light:
		player.light.shadow_enabled = (not _is_compat) and (preset >= Game.Gfx.BALANCED)
	_update_nearest_shadows()


func _update_nearest_shadows() -> void:
	if _is_compat or _lights.is_empty():
		return
	var ref_pos := Vector3.ZERO
	var vcam := get_viewport().get_camera_3d() if get_viewport() else null
	if vcam and vcam.is_inside_tree():
		ref_pos = vcam.global_position
	elif player and player.is_inside_tree():
		ref_pos = player.global_position

	var pairs: Array[Vector2] = []
	for i in _lights.size():
		var ln: Light3D = _lights[i].node
		if is_instance_valid(ln):
			var d2 := ref_pos.distance_squared_to(ln.global_position)
			pairs.append(Vector2(d2, float(i)))
	pairs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	for rank in pairs.size():
		var idx := int(pairs[rank].y)
		var ln: Light3D = _lights[idx].node
		var want_shadow := (rank < _max_shadow_lights) and (pairs[rank].x <= 625.0) and not Game.power_is_out
		if ln.shadow_enabled != want_shadow:
			ln.shadow_enabled = want_shadow


func build(night: int) -> void:
	if nav.get_point_count() == 0:
		_collect_scene_nodes()

	var night6_tint := Color(1.0, 0.55, 0.5)
	for l in _lights:
		var n: Light3D = l.node
		var base_col: Color = l.color
		n.light_color = base_col.lerp(night6_tint, 0.3) if night >= Game.SECRET_NIGHT else base_col
		n.light_energy = float(l.base)
	for s in _shafts:
		if is_instance_valid(s):
			s.visible = true

	if enemy and player:
		enemy.setup(nav, patrol_ids, generator_nav_id, player, night, self)

	_update_nearest_shadows()

	if not _built:
		_built = true
		Game.power_out.connect(_on_power_out)
		Game.power_restored.connect(_on_power_restored)


func _process(delta: float) -> void:
	_shadow_t -= delta
	if _shadow_t <= 0.0:
		_shadow_t = 0.18
		_update_nearest_shadows()

	if Game.power_is_out:
		return
	_flicker_t -= delta
	if _flicker_t > 0.0:
		return
	_flicker_t = 0.07
	var chance := 0.04 + 0.18 * float(Game.threat) + (0.12 if Game.generator_sabotaged else 0.0)
	for l in _lights:
		if l.flicker or Game.generator_sabotaged:
			var n: Light3D = l.node
			if is_instance_valid(n):
				n.light_energy = float(l.base) * (randf_range(0.08, 0.55) if randf() < chance else 1.0)


func _on_power_out() -> void:
	for s in _shafts:
		if is_instance_valid(s):
			s.visible = false
	for l in _lights:
		var n: Light3D = l.node
		if is_instance_valid(n):
			n.shadow_enabled = false
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
	for s in _shafts:
		if is_instance_valid(s):
			s.visible = true
	for l in _lights:
		var n: Light3D = l.node
		if is_instance_valid(n):
			var t := create_tween()
			t.tween_property(n, "light_energy", float(l.base), 0.7)
	_update_nearest_shadows()
