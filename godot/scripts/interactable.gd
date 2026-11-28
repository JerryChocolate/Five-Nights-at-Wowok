extends StaticBody3D
class_name Interactable
## Objek interaktif yang tampil penuh di Godot Editor: pintu, loker, terminal CCTV, baterai, generator.
## Pintu sekuriti memiliki panel sakelar di kedua sisi kusen (layer 2) sehingga selalu mudah ditutup/dibuka.

enum Kind { DOOR, LOCKER, TERMINAL, BATTERY, GENERATOR }

const OPEN_LIFT := 2.65

@export_group("Interactable")
@export var kind: Kind = Kind.DOOR
@export var door_id: int = -1
@export var custom_model: PackedScene

var closed := false
var _col: CollisionShape3D
var _visual: Node3D
var _closed_vis_y := 0.0
var _tween: Tween
var _bang_tween: Tween
var _bang: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D
var _status_mat: StandardMaterial3D
var _status_light: OmniLight3D
var _door_lamp_mat: StandardMaterial3D


## Kompatibilitas bila dipanggil lewat skrip prosedural.
func setup(k: Kind, size: Vector3, material: Material, p_door_id: int = -1) -> void:
	kind = k
	door_id = p_door_id
	collision_layer = 2 if (k == Kind.BATTERY or k == Kind.DOOR) else 3
	collision_mask = 0
	var vis := Node3D.new()
	vis.name = "Visual"
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	vis.add_child(mi)
	add_child(vis)
	_col = CollisionShape3D.new()
	_col.name = "Col"
	var bs := BoxShape3D.new()
	bs.size = size
	_col.shape = bs
	add_child(_col)


func _ready() -> void:
	_col = get_node_or_null("Col") as CollisionShape3D
	_visual = get_node_or_null("Visual") as Node3D

	if custom_model != null:
		if _visual:
			_visual.visible = false
		var slot := Node3D.new()
		slot.name = "CustomModel"
		slot.add_child(custom_model.instantiate())
		add_child(slot)
		_visual = slot

	collision_layer = 2 if (kind == Kind.BATTERY or kind == Kind.DOOR) else 3
	collision_mask = 0

	match kind:
		Kind.DOOR:
			if not is_in_group("doors"):
				add_to_group("doors")
			_bang = AudioStreamPlayer3D.new()
			_bang.bus = &"SFX"
			_bang.stream = Game.synth_tone(95.0, 38.0, 0.28, 2.2, 1.0, 0.35)
			_bang.unit_size = 12.0
			_bang.max_distance = 58.0
			add_child(_bang)
			_sfx = AudioStreamPlayer3D.new()
			_sfx.bus = &"SFX"
			_sfx.stream = Game.synth_tone(140.0, 65.0, 0.32, 1.8, 0.75, 0.45)
			_sfx.unit_size = 9.0
			_sfx.max_distance = 38.0
			add_child(_sfx)
			_door_lamp_mat = StandardMaterial3D.new()
			_door_lamp_mat.emission_enabled = true
			_door_lamp_mat.emission_energy_multiplier = 1.6
			for lp in ["SwitchPanelFront/SwitchLampFront", "SwitchPanelBack/SwitchLampBack"]:
				var lm := get_node_or_null(lp) as MeshInstance3D
				if lm:
					lm.material_override = _door_lamp_mat
			if _visual:
				_closed_vis_y = _visual.position.y
				_visual.position.y = _closed_vis_y + OPEN_LIFT
			if _col:
				_col.disabled = true
			collision_layer = 2
			_refresh_door_lamp()
			if door_id >= 0:
				Game.door_states[door_id] = false
			Game.power_out.connect(force_open)
		Kind.LOCKER:
			if not is_in_group("lockers"):
				add_to_group("lockers")
			_sfx = AudioStreamPlayer3D.new()
			_sfx.bus = &"SFX"
			_sfx.stream = Game.synth_tone(320.0, 170.0, 0.22, 2.0, 0.55, 0.3)
			_sfx.unit_size = 7.0
			_sfx.max_distance = 26.0
			add_child(_sfx)
		Kind.GENERATOR:
			if not is_in_group("generators"):
				add_to_group("generators")
			_sfx = AudioStreamPlayer3D.new()
			_sfx.bus = &"SFX"
			_sfx.stream = Game.synth_tone(75.0, 195.0, 0.65, 1.3, 0.95, 0.35)
			_sfx.unit_size = 15.0
			_sfx.max_distance = 72.0
			add_child(_sfx)
			var ind := get_node_or_null("Visual/StatusLamp") as MeshInstance3D
			if ind:
				_status_mat = (ind.material_override as StandardMaterial3D)
				if _status_mat:
					_status_mat = _status_mat.duplicate() as StandardMaterial3D
					ind.material_override = _status_mat
			if _status_mat == null:
				_status_mat = StandardMaterial3D.new()
				_status_mat.emission_enabled = true
				_status_mat.emission_energy_multiplier = 2.6
			_status_light = get_node_or_null("StatusLight") as OmniLight3D
			Game.generator_changed.connect(func(_cd: float, _sab: bool) -> void: _refresh_gen_visual())
			Game.power_out.connect(_refresh_gen_visual)
			Game.power_restored.connect(_refresh_gen_visual)
			_refresh_gen_visual()


func _refresh_door_lamp() -> void:
	if _door_lamp_mat == null:
		return
	var col := Color(0.95, 0.18, 0.15) if closed else Color(0.22, 0.95, 0.45)
	_door_lamp_mat.albedo_color = col
	_door_lamp_mat.emission = col


func _refresh_gen_visual() -> void:
	if kind != Kind.GENERATOR or _status_mat == null:
		return
	var col := Color(0.2, 0.95, 0.4)
	if Game.power_is_out or Game.generator_sabotaged:
		col = Color(1.0, 0.18, 0.12)
	elif Game.gen_cooldown > 0.0:
		col = Color(1.0, 0.72, 0.18)
	_status_mat.albedo_color = col
	_status_mat.emission = col
	if _status_light:
		_status_light.light_color = col
		_status_light.light_energy = 1.2 if (Game.power_is_out or Game.generator_sabotaged) else 0.65


func prompt_text() -> String:
	match kind:
		Kind.DOOR:
			return "Buka pintu sekuriti" if closed else "Tutup pintu sekuriti (boros daya)"
		Kind.LOCKER:
			return "Sembunyi di loker (tahan napas terbatas)"
		Kind.TERMINAL:
			return "Buka monitor CCTV"
		Kind.BATTERY:
			return "Ambil baterai senter"
		Kind.GENERATOR:
			if Game.power_is_out:
				return "Nyalakan Generator Darurat (+35% daya, BISING!)"
			if Game.generator_sabotaged:
				return "Perbaiki Sekring & Isi Daya (+35%, BISING!)"
			if Game.gen_cooldown > 0.0:
				return "Generator mendingin (%ds)" % int(ceilf(Game.gen_cooldown))
			return "Pompa Generator (+35% daya, BISING!)"
	return ""


func play_creak() -> void:
	if _sfx:
		_sfx.pitch_scale = randf_range(0.88, 1.12)
		_sfx.play()


func interact(player: Player) -> void:
	match kind:
		Kind.DOOR:
			if Game.power_is_out:
				Game.toast.emit("Daya mati: nyalakan Generator di Ruang Server Barat Laut!")
				return
			set_closed(not closed)
			Game.add_noise(global_position, 12.0)
		Kind.LOCKER:
			play_creak()
			player.enter_hide(self)
		Kind.TERMINAL:
			Game.set_camera(true)
		Kind.BATTERY:
			Game.add_battery(45.0)
			Game.toast.emit("+ Baterai senter (+45%)")
			queue_free()
		Kind.GENERATOR:
			if Game.use_generator(global_position):
				if _sfx:
					_sfx.pitch_scale = randf_range(0.92, 1.06)
					_sfx.play()
				_refresh_gen_visual()


func set_closed(c: bool) -> void:
	if c == closed or kind != Kind.DOOR:
		return
	closed = c
	collision_layer = 3 if c else 2
	Game.change_doors(1 if c else -1, door_id, c)
	_refresh_door_lamp()
	if _col:
		_col.set_deferred("disabled", not c)
	if _sfx and is_inside_tree():
		_sfx.pitch_scale = 0.85 if c else 1.1
		_sfx.play()
	if _visual:
		if _tween:
			_tween.kill()
		_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_visual, "position:y", _closed_vis_y if c else _closed_vis_y + OPEN_LIFT, 0.32)


func force_open() -> void:
	if closed:
		set_closed(false)


## Dipanggil musuh saat menggedor pintu tertutup.
func bang() -> void:
	if _bang:
		_bang.pitch_scale = randf_range(0.65, 0.92)
		_bang.play()
	Game.add_trauma(0.22)
	if _visual == null:
		return
	if _bang_tween:
		_bang_tween.kill()
	_visual.position.z = 0.0
	_bang_tween = create_tween()
	_bang_tween.tween_property(_visual, "position:z", 0.055, 0.035)
	_bang_tween.tween_property(_visual, "position:z", -0.055, 0.035)
	_bang_tween.tween_property(_visual, "position:z", 0.0, 0.04)
