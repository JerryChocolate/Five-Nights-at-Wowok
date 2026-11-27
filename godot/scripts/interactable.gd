extends StaticBody3D
class_name Interactable
## Objek interaktif yang tampil penuh di Godot Editor: pintu, loker, terminal CCTV, baterai, generator.
## Mendukung slot `custom_model` di Inspector untuk mengganti mesh placeholder dengan aset 3D (.glb/.gltf).

enum Kind { DOOR, LOCKER, TERMINAL, BATTERY, GENERATOR }

const OPEN_LIFT := 2.8

@export_group("Interactable")
@export var kind: Kind = Kind.DOOR
@export var door_id: int = -1
@export var custom_model: PackedScene

var closed := false
var _col: CollisionShape3D
var _visual: Node3D
var _closed_y := 0.0
var _base_x := 0.0
var _tween: Tween
var _bang_tween: Tween
var _bang: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D
var _status_mat: StandardMaterial3D
var _status_light: OmniLight3D


## Kompatibilitas bila dipanggil lewat skrip prosedural.
func setup(k: Kind, size: Vector3, material: Material, p_door_id: int = -1) -> void:
	kind = k
	door_id = p_door_id
	collision_layer = 2 if k == Kind.BATTERY else 3
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
	_base_x = position.x
	_col = get_node_or_null("Col") as CollisionShape3D
	_visual = get_node_or_null("Visual") as Node3D

	if custom_model != null:
		if _visual:
			_visual.visible = false
		var slot := Node3D.new()
		slot.name = "CustomModel"
		slot.add_child(custom_model.instantiate())
		add_child(slot)

	collision_layer = 2 if kind == Kind.BATTERY else 3
	collision_mask = 0

	match kind:
		Kind.DOOR:
			if not is_in_group("doors"):
				add_to_group("doors")
			_bang = AudioStreamPlayer3D.new()
			_bang.bus = &"SFX"
			_bang.stream = Game.synth_tone(95.0, 38.0, 0.28, 2.2, 1.0, 0.35)
			_bang.unit_size = 9.0
			_bang.max_distance = 42.0
			add_child(_bang)
			_sfx = AudioStreamPlayer3D.new()
			_sfx.bus = &"SFX"
			_sfx.stream = Game.synth_tone(140.0, 65.0, 0.32, 1.8, 0.75, 0.45)
			_sfx.unit_size = 7.0
			_sfx.max_distance = 28.0
			add_child(_sfx)
			_closed_y = position.y
			position.y += OPEN_LIFT # di Editor tampil pada posisi pintu tertutup; saat runtime terangkat terbuka
			if _col:
				_col.disabled = true
			if door_id >= 0:
				Game.door_states[door_id] = false
			Game.power_out.connect(force_open)
		Kind.LOCKER:
			if not is_in_group("lockers"):
				add_to_group("lockers")
			_sfx = AudioStreamPlayer3D.new()
			_sfx.bus = &"SFX"
			_sfx.stream = Game.synth_tone(320.0, 170.0, 0.22, 2.0, 0.55, 0.3)
			_sfx.unit_size = 5.0
			_sfx.max_distance = 18.0
			add_child(_sfx)
		Kind.GENERATOR:
			if not is_in_group("generators"):
				add_to_group("generators")
			_sfx = AudioStreamPlayer3D.new()
			_sfx.bus = &"SFX"
			_sfx.stream = Game.synth_tone(75.0, 195.0, 0.65, 1.3, 0.95, 0.35)
			_sfx.unit_size = 11.0
			_sfx.max_distance = 48.0
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
			return "Buka pintu" if closed else "Tutup pintu (boros daya)"
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
				Game.toast.emit("Daya mati: cari Generator di R3 Server!")
				return
			set_closed(not closed)
			Game.add_noise(global_position, 9.0)
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
	Game.change_doors(1 if c else -1, door_id, c)
	if _col:
		_col.set_deferred("disabled", not c)
	if _sfx and is_inside_tree():
		_sfx.pitch_scale = 0.85 if c else 1.1
		_sfx.play()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:y", _closed_y if c else _closed_y + OPEN_LIFT, 0.32)


func force_open() -> void:
	if closed:
		set_closed(false)


## Dipanggil musuh saat menggedor pintu tertutup.
func bang() -> void:
	if _bang:
		_bang.pitch_scale = randf_range(0.65, 0.92)
		_bang.play()
	Game.add_trauma(0.22)
	if _bang_tween:
		_bang_tween.kill()
	position.x = _base_x
	_bang_tween = create_tween()
	_bang_tween.tween_property(self, "position:x", _base_x + 0.045, 0.035)
	_bang_tween.tween_property(self, "position:x", _base_x - 0.045, 0.035)
	_bang_tween.tween_property(self, "position:x", _base_x, 0.04)
