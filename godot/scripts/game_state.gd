extends Node
## Global state + event bus (autoload "Game"). UI listens to signals, nothing polls.

signal state_changed(new_state: int)
signal night_changed(night: int)
signal hour_changed(hour: int)
signal power_changed(value: float)
signal usage_changed(bars: int)
signal battery_changed(value: float)
signal breath_changed(value: float)
signal generator_changed(cooldown: float, sabotaged: bool)
signal power_out
signal power_restored
signal toast(text: String)
signal hidden_changed(is_hidden: bool)
signal force_unhide
signal noise_made(pos: Vector3, radius: float)
signal threat_changed(level: int)
signal trauma_added(amount: float)
signal player_caught
signal ammo_changed(count: int)
signal camera_toggled(open: bool)
signal door_count_changed(count: int)
signal door_state_changed(door_id: int, closed: bool)

enum S { MENU, PLAYING, DEAD, WON }

const NIGHT_LENGTH := 330.0 # detik nyata per malam (12 AM -> 6 AM)
const MAX_MAIN_NIGHT := 5
const SECRET_NIGHT := 6
const MAX_NIGHT := 6
const GEN_COOLDOWN := 40.0
const SAVE_PATH := "user://wowok.cfg"

var state: int = S.MENU
var night := 1
var unlocked_night := 1
var elapsed := 0.0
var hour := 0
var power := 100.0
var usage := 1
var battery := 100.0
var breath := 100.0
var gen_cooldown := 0.0
var generator_sabotaged := false
var closed_doors := 0
var door_states: Dictionary[int, bool] = {}
var camera_open := false
var power_is_out := false
var is_hidden := false
var flashlight_on := false
var threat := 0
var ammo := 0
var using_pad := false
var caught_killer_pos := Vector3.INF
var debug_infinite_power := false
var debug_god_mode := false

var master_volume := 0.85
var music_volume := 0.80
var sfx_volume := 0.85
var mouse_sens := 0.0025
var shake_strength := 1.0

var _last_power_q := 100.0
var _last_battery_q := 100.0
var _last_breath_q := 100.0
var _last_gen_q := 0.0


func _ready() -> void:
	_register_inputs()
	_load()
	apply_audio()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


# ---------- Input map ----------
func _ensure(a: StringName) -> void:
	if not InputMap.has_action(a):
		InputMap.add_action(a, 0.25)

func _key(a: StringName, k: Key) -> void:
	_ensure(a)
	var e := InputEventKey.new()
	e.physical_keycode = k
	InputMap.action_add_event(a, e)

func _btn(a: StringName, b: JoyButton) -> void:
	_ensure(a)
	var e := InputEventJoypadButton.new()
	e.button_index = b
	InputMap.action_add_event(a, e)

func _axis(a: StringName, ax: JoyAxis, v: float) -> void:
	_ensure(a)
	var e := InputEventJoypadMotion.new()
	e.axis = ax
	e.axis_value = v
	InputMap.action_add_event(a, e)

func _mouse(a: StringName, b: MouseButton) -> void:
	_ensure(a)
	var e := InputEventMouseButton.new()
	e.button_index = b
	InputMap.action_add_event(a, e)

func _register_inputs() -> void:
	_key(&"move_forward", KEY_W); _key(&"move_forward", KEY_UP); _axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_key(&"move_back", KEY_S); _key(&"move_back", KEY_DOWN); _axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0)
	_key(&"move_left", KEY_A); _key(&"move_left", KEY_LEFT); _axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_key(&"move_right", KEY_D); _key(&"move_right", KEY_RIGHT); _axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_key(&"sprint", KEY_SHIFT); _btn(&"sprint", JOY_BUTTON_LEFT_STICK)
	_key(&"crouch", KEY_CTRL); _btn(&"crouch", JOY_BUTTON_B)
	_key(&"interact", KEY_E); _btn(&"interact", JOY_BUTTON_A)
	_key(&"flashlight", KEY_F); _btn(&"flashlight", JOY_BUTTON_X)
	_key(&"camera_toggle", KEY_C); _btn(&"camera_toggle", JOY_BUTTON_Y)
	_key(&"pause", KEY_ESCAPE); _btn(&"pause", JOY_BUTTON_START)
	_mouse(&"fire", MOUSE_BUTTON_LEFT); _axis(&"fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key(&"easter_egg", KEY_K)
	_key(&"cam_prev", KEY_Q); _btn(&"cam_prev", JOY_BUTTON_LEFT_SHOULDER)
	_key(&"cam_next", KEY_R); _btn(&"cam_next", JOY_BUTTON_RIGHT_SHOULDER)


## Teks petunjuk tombol sesuai perangkat terakhir yang dipakai.
func hint(action: StringName) -> String:
	for e in InputMap.action_get_events(action):
		if using_pad and e is InputEventJoypadButton:
			var names := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start", 7: "L3", 9: "LB", 10: "RB"}
			return names.get(e.button_index, "Btn%d" % e.button_index)
		if not using_pad and e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode)
		if not using_pad and e is InputEventMouseButton:
			return "Klik"
	return "?"


# ---------- Flow ----------
func set_state(s: int) -> void:
	state = s
	state_changed.emit(s)

func start_night(n: int) -> void:
	night = clampi(n, 1, MAX_NIGHT)
	elapsed = 0.0
	hour = 0
	power = 100.0
	usage = 1
	battery = 100.0
	breath = 100.0
	gen_cooldown = 0.0
	generator_sabotaged = false
	closed_doors = 0
	door_states.clear()
	camera_open = false
	power_is_out = false
	is_hidden = false
	flashlight_on = false
	threat = 0
	ammo = 0
	caught_killer_pos = Vector3.INF
	_last_power_q = 100.0
	_last_battery_q = 100.0
	_last_breath_q = 100.0
	_last_gen_q = 0.0
	night_changed.emit(night)
	hour_changed.emit(0)
	power_changed.emit(power)
	usage_changed.emit(usage)
	battery_changed.emit(battery)
	breath_changed.emit(breath)
	generator_changed.emit(0.0, false)
	hidden_changed.emit(false)
	threat_changed.emit(0)
	ammo_changed.emit(0)
	camera_toggled.emit(false)
	door_count_changed.emit(0)
	set_state(S.PLAYING)

func die(killer_pos: Vector3 = Vector3.INF) -> void:
	if state != S.PLAYING or debug_god_mode:
		return
	caught_killer_pos = killer_pos
	set_state(S.DEAD)
	player_caught.emit()

func win() -> void:
	if state != S.PLAYING:
		return
	unlocked_night = maxi(unlocked_night, mini(night + 1, MAX_NIGHT))
	_save()
	set_state(S.WON)

func _recalc_usage() -> void:
	var u := 1 + mini(closed_doors, 3) + (1 if camera_open else 0) + (1 if generator_sabotaged else 0)
	u = clampi(u, 1, 5)
	if u != usage:
		usage = u
		usage_changed.emit(usage)

func _process(delta: float) -> void:
	if state != S.PLAYING:
		return
	elapsed += delta
	var h := int(elapsed / NIGHT_LENGTH * 6.0)
	if h != hour:
		hour = h
		hour_changed.emit(hour)
	if hour >= 6:
		win()
		return

	# Cooldown generator
	if gen_cooldown > 0.0:
		gen_cooldown = maxf(0.0, gen_cooldown - delta)
		var gq := snappedf(gen_cooldown, 0.5)
		if gq != _last_gen_q:
			_last_gen_q = gq
			generator_changed.emit(gen_cooldown, generator_sabotaged)

	# Napas / ketenangan di loker (anti-camping)
	if is_hidden:
		var b_rate := 7.2 + float(night) * 0.8 + (3.2 if threat >= 2 else 0.0)
		breath = maxf(0.0, breath - b_rate * delta)
		if breath <= 0.0:
			toast.emit("Napas habis! Kamu panik keluar dari loker!")
			force_unhide.emit()
	elif breath < 100.0:
		breath = minf(100.0, breath + 18.0 * delta)
	var bq := snappedf(breath, 0.5)
	if bq != _last_breath_q:
		_last_breath_q = bq
		breath_changed.emit(breath)

	if power_is_out or debug_infinite_power:
		return

	var night_mult := 1.25 if night >= SECRET_NIGHT else 1.0
	var rate := (0.048 + 0.013 * float(night) + 0.11 * float(closed_doors)
			+ (0.11 if camera_open else 0.0)
			+ (0.22 if generator_sabotaged else 0.0)) * night_mult
	power = maxf(0.0, power - rate * delta)
	var q := snappedf(power, 0.1)
	if q != _last_power_q:
		_last_power_q = q
		power_changed.emit(power)
	if power <= 0.0:
		power_is_out = true
		if camera_open:
			set_camera(false)
		_recalc_usage()
		power_out.emit()
		add_trauma(0.45)
		toast.emit("DAYA HABIS! Cari Generator Darurat di R3 Server!")


# ---------- Helpers used by gameplay ----------
func add_noise(pos: Vector3, radius: float) -> void:
	noise_made.emit(pos, radius)

func add_trauma(amount: float) -> void:
	if amount > 0.0:
		trauma_added.emit(amount)

func set_threat(level: int) -> void:
	if level != threat:
		threat = level
		threat_changed.emit(level)

func set_hidden(h: bool) -> void:
	if h != is_hidden:
		is_hidden = h
		if h and camera_open:
			set_camera(false)
		hidden_changed.emit(h)

func set_camera(open: bool) -> void:
	if open and (power_is_out or is_hidden or state != S.PLAYING):
		if power_is_out and open:
			toast.emit("Tablet CCTV mati — daya gedung habis!")
		return
	if open != camera_open:
		camera_open = open
		_recalc_usage()
		camera_toggled.emit(open)

func toggle_camera() -> void:
	set_camera(not camera_open)

func change_doors(delta: int, door_id: int = -1, closed_val: bool = false) -> void:
	closed_doors = maxi(0, closed_doors + delta)
	if door_id >= 0:
		door_states[door_id] = closed_val
		door_state_changed.emit(door_id, closed_val)
	_recalc_usage()
	door_count_changed.emit(closed_doors)

func sabotage_generator() -> void:
	if generator_sabotaged or power_is_out:
		return
	generator_sabotaged = true
	_recalc_usage()
	generator_changed.emit(gen_cooldown, true)
	add_trauma(0.35)
	toast.emit("PERINGATAN: Panel Sekring di R3 Server disabotase! Daya bocor deras!")

func use_generator(world_pos: Vector3) -> bool:
	if gen_cooldown > 0.0 and not power_is_out and not generator_sabotaged:
		toast.emit("Generator masih dingin (%ds)" % int(ceilf(gen_cooldown)))
		return false
	if power >= 95.0 and not power_is_out and not generator_sabotaged:
		toast.emit("Daya gedung masih penuh")
		return false
	var was_out := power_is_out
	power_is_out = false
	generator_sabotaged = false
	power = clampf((35.0 if was_out else power + 35.0), 0.0, 100.0)
	_last_power_q = snappedf(power, 0.1)
	gen_cooldown = GEN_COOLDOWN
	_last_gen_q = gen_cooldown
	_recalc_usage()
	power_changed.emit(power)
	generator_changed.emit(gen_cooldown, false)
	if was_out:
		power_restored.emit()
	add_noise(world_pos, 26.0)
	add_trauma(0.45)
	toast.emit("Generator dinyalakan (+35% daya) — suara mesin memancing Wowok!")
	return true

func add_battery(v: float) -> void:
	battery = clampf(battery + v, 0.0, 100.0)
	_last_battery_q = snappedf(battery, 0.5)
	battery_changed.emit(battery)

func drain_battery(v: float) -> void:
	battery = maxf(0.0, battery - v)
	var q := snappedf(battery, 0.5)
	if q != _last_battery_q:
		_last_battery_q = q
		battery_changed.emit(battery)

func set_ammo(n: int) -> void:
	ammo = n
	ammo_changed.emit(n)


# ---------- Settings & save ----------
func _set_bus_gain(bus_name: StringName, slider01: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var g := clampf(slider01, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, g <= 0.0001)
	if g > 0.0001:
		AudioServer.set_bus_volume_linear(idx, g * g)

func apply_audio() -> void:
	_set_bus_gain(&"Master", master_volume)
	_set_bus_gain(&"Music", music_volume)
	_set_bus_gain(&"SFX", sfx_volume)
	_set_bus_gain(&"Ambience", sfx_volume)
	_set_bus_gain(&"Voice", clampf(sfx_volume * 1.05, 0.0, 1.0))

func save_settings() -> void:
	_save()

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("progress", "unlocked_night", unlocked_night)
	c.set_value("settings", "volume", master_volume)
	c.set_value("settings", "music_volume", music_volume)
	c.set_value("settings", "sfx_volume", sfx_volume)
	c.set_value("settings", "sens", mouse_sens)
	c.set_value("settings", "shake", shake_strength)
	c.save(SAVE_PATH)

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	unlocked_night = clampi(int(c.get_value("progress", "unlocked_night", 1)), 1, MAX_NIGHT)
	master_volume = clampf(float(c.get_value("settings", "volume", 0.85)), 0.0, 1.0)
	music_volume = clampf(float(c.get_value("settings", "music_volume", 0.80)), 0.0, 1.0)
	sfx_volume = clampf(float(c.get_value("settings", "sfx_volume", 0.85)), 0.0, 1.0)
	mouse_sens = clampf(float(c.get_value("settings", "sens", 0.0025)), 0.0005, 0.006)
	shake_strength = clampf(float(c.get_value("settings", "shake", 1.0)), 0.0, 1.0)


## Suara sintetis (derau meluruh) tanpa file aset: tembakan, statis kamera, ketukan, klik senter.
func synth_burst(duration: float, decay: float, volume: float, lowpass: float = 1.0) -> AudioStreamWAV:
	var rate := 22050
	var n := maxi(1, int(duration * rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i in n:
		var t := float(i) / float(n)
		var raw := randf() * 2.0 - 1.0
		prev = lerpf(prev, raw, lowpass)
		var v := prev * pow(1.0 - t, decay) * volume
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

## Suara sintetis bernada (dentuman langkah berat, detak jantung, deru generator, decit loker).
func synth_tone(freq_start: float, freq_end: float, duration: float, decay: float, volume: float, noise_mix: float = 0.15) -> AudioStreamWAV:
	var rate := 22050
	var n := maxi(1, int(duration * rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(freq_start, freq_end, t)
		phase += TAU * f / float(rate)
		var env := pow(1.0 - t, decay)
		var sig := sin(phase) * (1.0 - noise_mix) + (randf() * 2.0 - 1.0) * noise_mix
		var v := sig * env * volume
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
