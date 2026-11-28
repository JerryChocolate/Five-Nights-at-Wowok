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
signal cam_lens_updated(zoom_amount: float, focus_blur: float)
signal door_count_changed(count: int)
signal door_state_changed(door_id: int, closed: bool)
signal graphics_changed(preset: int)

enum S { MENU, PLAYING, DEAD, WON }
enum Gfx { LOW = 0, BALANCED = 1, HIGH = 2 }

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
var graphics_preset: int = Gfx.BALANCED

var _last_power_q := 100.0
var _last_battery_q := 100.0
var _last_breath_q := 100.0
var _last_gen_q := 0.0


func _ready() -> void:
	_register_inputs()
	_load()
	apply_audio()
	apply_graphics.call_deferred()


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
	_mouse(&"cam_zoom", MOUSE_BUTTON_RIGHT); _axis(&"cam_zoom", JOY_AXIS_TRIGGER_LEFT, 1.0)
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
	cam_lens_updated.emit(0.0, 0.0)
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

	# Cooldown generator: gunakan ceilf agar transisi 1s -> 0s (Siap) tidak pernah macet di 1s!
	if gen_cooldown > 0.0:
		gen_cooldown = maxf(0.0, gen_cooldown - delta)
		var gq := ceilf(gen_cooldown)
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
	var rate := (0.042 + 0.012 * float(night) + 0.095 * float(closed_doors)
			+ (0.10 if camera_open else 0.0)
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
		toast.emit("DAYA HABIS! Cari Generator Darurat di Ruang Server Barat Laut!")


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

func set_cam_lens(zoom_amount: float, focus_blur: float) -> void:
	cam_lens_updated.emit(clampf(zoom_amount, 0.0, 1.0), clampf(focus_blur, 0.0, 1.0))

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
	toast.emit("PERINGATAN: Panel Sekring di Ruang Server Barat Laut disabotase! Daya bocor deras!")

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
	_last_gen_q = ceilf(gen_cooldown)
	_recalc_usage()
	power_changed.emit(power)
	generator_changed.emit(gen_cooldown, false)
	if was_out:
		power_restored.emit()
	add_noise(world_pos, 42.0)
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

func set_graphics_preset(p: int) -> void:
	graphics_preset = clampi(p, Gfx.LOW, Gfx.HIGH)
	apply_graphics()
	_save()

func apply_graphics() -> void:
	var vp := get_viewport()
	if vp:
		match graphics_preset:
			Gfx.LOW:
				vp.scaling_3d_scale = 0.75
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			Gfx.BALANCED:
				vp.scaling_3d_scale = 0.90
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			Gfx.HIGH:
				vp.scaling_3d_scale = 1.0
				vp.msaa_3d = Viewport.MSAA_2X
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	graphics_changed.emit(graphics_preset)

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
	c.set_value("settings", "graphics_preset", graphics_preset)
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
	shake_strength = clampf(float(c.get_value("settings", "shake", 1.0)), 0.0, 1.5)
	graphics_preset = clampi(int(c.get_value("settings", "graphics_preset", Gfx.BALANCED)), Gfx.LOW, Gfx.HIGH)


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


## Sound Cue Horor (Chase Stinger): gesekan biola/logam disonan (tritone + minor 2nd) + dentuman sub-bass.
func synth_scare_stinger() -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.35
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var p_sub := 0.0
	for i in n:
		var t := float(i) / float(n)
		var atk := minf(1.0, t / 0.025)
		var env := atk * pow(1.0 - t, 1.55)
		var vib := sin(TAU * 13.5 * t * dur) * 14.0
		p1 += TAU * (587.3 + t * 95.0 + vib) / float(rate)
		p2 += TAU * (622.3 + t * 130.0 - vib) / float(rate)
		p3 += TAU * (830.6 - t * 60.0) / float(rate)
		p_sub += TAU * lerpf(115.0, 36.0, minf(1.0, t * 2.4)) / float(rate)
		var metallic := tanh((sin(p1) + sin(p2) * 0.9 + sin(p3) * 0.75) * 1.6) * 0.48
		var sub := sin(p_sub) * pow(1.0 - minf(1.0, t * 1.4), 2.0) * 0.72
		var grit := (randf() * 2.0 - 1.0) * pow(1.0 - t, 3.2) * 0.22
		var v := (metallic + sub + grit) * env * 0.88
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Sound Cue Waspada (Investigate Swell): dengung cello/brass rendah mencekam saat Wowok curiga.
func synth_alert_cue() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.95
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := sin(t * PI) * pow(1.0 - t * 0.45, 1.2)
		p1 += TAU * lerpf(92.5, 87.3, t) / float(rate)
		p2 += TAU * lerpf(138.6, 130.8, t) / float(rate)
		var sig := tanh((sin(p1) * 0.8 + sin(p2) * 0.55 + sin(p1 * 2.0) * 0.3) * 1.4)
		var v := sig * env * 0.62
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Sound Cue Listrik Padam / Pulih (Turbin Trafo Turun / Naik + Klik Relai).
func synth_power_transition(down: bool) -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.45 if down else 1.05
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(360.0, 32.0, pow(t, 0.65)) if down else lerpf(42.0, 290.0, pow(t, 1.25))
		ph += TAU * f / float(rate)
		var clack := (randf() * 2.0 - 1.0) * (1.0 if t < 0.035 else 0.0) * 0.85
		var env := (1.0 - pow(t, 2.2)) if down else sin(t * PI * 0.85)
		var hum := (sin(ph) * 0.65 + sin(ph * 2.0) * 0.28) * env
		var v := (hum + clack) * 0.78
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Ketukan Sepatu di Lantai Marmer (untuk variasi AudioStreamRandomizer pemain & pantofel berat Wowok).
func synth_marble_step(heavy: bool, variant: int = 0) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.22 if heavy else 0.13
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var p_thud := 0.0
	var p_click := 0.0
	var base_f := (68.0 if heavy else 145.0) + float(variant) * 11.0
	var click_f := (620.0 if heavy else 1180.0) + float(variant) * 95.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		p_thud += TAU * lerpf(base_f, base_f * 0.42, t) / float(rate)
		p_click += TAU * click_f / float(rate)
		var raw_n := randf() * 2.0 - 1.0
		lp = lerpf(lp, raw_n, 0.38 if heavy else 0.62)
		var heel := (sin(p_click) * 0.35 + lp * 0.65) * pow(1.0 - minf(1.0, t * 5.5), 2.4)
		var body := sin(p_thud) * pow(1.0 - t, 2.6 if heavy else 3.4) * (0.95 if heavy else 0.55)
		var v := (heel + body) * (0.92 if heavy else 0.68)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Klik Mekanis Tombol Kaset Kamera Jadul (Camcorder / VHS Button Clack).
func synth_camcorder_click(open_mode: bool) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.14
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var click1 := (randf() * 2.0 - 1.0) * exp(-t * 95.0) * 0.85
		var click2 := (randf() * 2.0 - 1.0) * exp(-absf(t - 0.045) * 120.0) * (0.65 if t >= 0.04 else 0.0)
		ph += TAU * (1450.0 if open_mode else 980.0) / float(rate)
		var whirr := sin(ph) * exp(-t * 24.0) * 0.22
		var v := (click1 + click2 + whirr) * 0.78
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Motor Servo Lensa Zoom Optik Camcorder Hi8 / VHS (dengung halus motor lensa + klik mikro).
func synth_camcorder_zoom(zoom_in: bool) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.22
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f_base := lerpf(285.0, 355.0, t) if zoom_in else lerpf(340.0, 265.0, t)
		p1 += TAU * f_base / float(rate)
		p2 += TAU * (f_base * 2.02) / float(rate)
		var env := sin(t * PI) * 0.85
		var gear := (randf() * 2.0 - 1.0) * 0.14 * env
		var end_tick := (randf() * 2.0 - 1.0) * exp(-absf(t - 0.92) * 90.0) * 0.32
		var v := ((sin(p1) * 0.42 + sin(p2) * 0.22) * env + gear + end_tick) * 0.52
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Pulsa Drone Ketegangan Saat Dikejar (Loop pendek berdetak rendah di bus Music/Ambience).
func synth_chase_pulse_loop() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.96 # 125 BPM (2 ketuk @ 0.48s)
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var sec := float(i) / float(rate)
		var beat_t := fmod(sec, 0.48) / 0.48
		var kick := sin(TAU * lerpf(96.0, 38.0, minf(1.0, beat_t * 3.5)) * beat_t * 0.48) * pow(1.0 - beat_t, 2.6) * 0.75
		p1 += TAU * 55.0 / float(rate)
		p2 += TAU * 58.27 / float(rate) # minor 2nd sub-dread
		var drone := tanh((sin(p1) + sin(p2) * 0.8) * 1.3) * 0.28
		var hat := (randf() * 2.0 - 1.0) * pow(1.0 - fmod(beat_t * 2.0, 1.0), 6.0) * 0.14
		var v := (kick + drone + hat) * 0.72
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	w.data = data
	return w
