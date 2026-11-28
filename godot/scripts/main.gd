extends Node
## Alur utama: menu CRT (codWaw.mp3 + Night 6) -> malam (ambiance.mp3) -> jumpscare hibrida 3D->2D / menang.
## Semua komponen utama tampil di Scene Tree Godot Editor (`main.tscn`), lengkap opsi Debug di Inspector.

const WORLD_SCENE := preload("res://scenes/world.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const CCTV_SCENE := preload("res://scenes/cctv.tscn")
const MENU_BG := "res://assets/img/wowok_menu.jpg"

@export_group("Editor Debug & Quick Test")
@export_range(0, 6, 1) var skip_menu_to_night: int = 0
@export var unlock_all_nights_debug: bool = false
@export var infinite_power_debug: bool = false
@export var god_mode_debug: bool = false

@export_group("Custom Audio Cues (.mp3 / .wav)")
@export var custom_ambience_music: AudioStream
@export var custom_chase_stinger: AudioStream
@export var custom_alert_cue: AudioStream
@export var custom_chase_loop: AudioStream
@export var custom_jumpscare_scream: AudioStream
@export var custom_power_down: AudioStream
@export var custom_power_up: AudioStream

@onready var editor_preview: Control = %EditorMenuPreview
@onready var ui: UIStack = %UI
@onready var fx_layer: CanvasLayer = %FXLayer
@onready var vignette_fx: ColorRect = %VignetteFX
@onready var menu_music: AudioStreamPlayer = %MenuMusic
@onready var music: AudioStreamPlayer = %AmbienceMusic

var world: World
var hud: HUD
var cctv: CCTV
var fx_mat: ShaderMaterial
var scare_layer: CanvasLayer
var intro_layer: CanvasLayer
var stinger_sfx: AudioStreamPlayer
var alert_sfx: AudioStreamPlayer
var power_sfx: AudioStreamPlayer
var chase_pulse_music: AudioStreamPlayer
var _fx_tween: Tween
var _chase_music_tween: Tween
var _stinger_cd := 0.0
var _alert_cd := 0.0
var _prev_threat := 0
var _death_seq := 0


func _ready() -> void:
	if is_instance_valid(editor_preview):
		editor_preview.queue_free()

	fx_mat = vignette_fx.material as ShaderMaterial
	if custom_ambience_music != null:
		music.stream = custom_ambience_music
	var mms := menu_music.stream as AudioStreamMP3
	if mms:
		mms.loop = true
	var ms := music.stream as AudioStreamMP3
	if ms:
		ms.loop = true

	stinger_sfx = AudioStreamPlayer.new()
	stinger_sfx.bus = &"SFX"
	stinger_sfx.stream = custom_chase_stinger if custom_chase_stinger != null else Game.synth_scare_stinger()
	stinger_sfx.volume_db = -3.0
	add_child(stinger_sfx)

	alert_sfx = AudioStreamPlayer.new()
	alert_sfx.bus = &"SFX"
	alert_sfx.stream = custom_alert_cue if custom_alert_cue != null else Game.synth_alert_cue()
	alert_sfx.volume_db = -6.5
	add_child(alert_sfx)

	power_sfx = AudioStreamPlayer.new()
	power_sfx.bus = &"SFX"
	power_sfx.volume_db = -3.5
	add_child(power_sfx)

	chase_pulse_music = AudioStreamPlayer.new()
	chase_pulse_music.bus = &"Music"
	chase_pulse_music.stream = custom_chase_loop if custom_chase_loop != null else Game.synth_chase_pulse_loop()
	if chase_pulse_music.stream is AudioStreamMP3:
		(chase_pulse_music.stream as AudioStreamMP3).loop = true
	chase_pulse_music.volume_db = -28.0
	add_child(chase_pulse_music)

	if unlock_all_nights_debug:
		Game.unlocked_night = Game.MAX_NIGHT
	Game.debug_infinite_power = infinite_power_debug
	Game.debug_god_mode = god_mode_debug

	ui.changed.connect(_update_mouse)
	Game.player_caught.connect(_on_caught)
	Game.state_changed.connect(_on_state)
	Game.power_out.connect(func() -> void:
		if music.playing:
			music.stop()
		power_sfx.stream = custom_power_down if custom_power_down != null else Game.synth_power_transition(true)
		power_sfx.play())
	Game.power_restored.connect(func() -> void:
		if Game.state == Game.S.PLAYING and not music.playing:
			music.play()
		power_sfx.stream = custom_power_up if custom_power_up != null else Game.synth_power_transition(false)
		power_sfx.play())
	Game.camera_toggled.connect(func(o: bool) -> void:
		if fx_layer:
			fx_layer.visible = (Game.state == Game.S.PLAYING) and not o
		_update_mouse())
	Game.threat_changed.connect(_on_threat_audio_and_fx)
	Game.cam_lens_updated.connect(func(z: float, fb: float) -> void:
		if fx_mat:
			fx_mat.set_shader_parameter("zoom_amount", z)
			fx_mat.set_shader_parameter("focus_blur", fb))

	if skip_menu_to_night > 0:
		start_night(skip_menu_to_night)
	else:
		show_main_menu()


func _process(delta: float) -> void:
	_stinger_cd = maxf(0.0, _stinger_cd - delta)
	_alert_cd = maxf(0.0, _alert_cd - delta)


func _on_threat_audio_and_fx(l: int) -> void:
	if _fx_tween:
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_method(func(v: float) -> void: fx_mat.set_shader_parameter("intensity", v), float(fx_mat.get_shader_parameter("intensity")), l * 0.5, 0.5)

	if Game.state == Game.S.PLAYING:
		if l == 2 and _prev_threat < 2:
			if _stinger_cd <= 0.0:
				_stinger_cd = 7.0
				stinger_sfx.pitch_scale = randf_range(0.95, 1.06)
				stinger_sfx.play()
			_fade_chase_pulse(true)
		elif l == 1 and _prev_threat == 0:
			if _alert_cd <= 0.0:
				_alert_cd = 6.5
				alert_sfx.pitch_scale = randf_range(0.94, 1.05)
				alert_sfx.play()
			_fade_chase_pulse(false)
		elif l < 2:
			_fade_chase_pulse(false)
	_prev_threat = l


func _fade_chase_pulse(active: bool) -> void:
	if chase_pulse_music == null:
		return
	if _chase_music_tween:
		_chase_music_tween.kill()
	if active:
		if not chase_pulse_music.playing:
			chase_pulse_music.volume_db = -26.0
			chase_pulse_music.play()
		_chase_music_tween = create_tween()
		_chase_music_tween.tween_property(chase_pulse_music, "volume_db", -5.5, 0.45)
	elif chase_pulse_music.playing:
		_chase_music_tween = create_tween()
		_chase_music_tween.tween_property(chase_pulse_music, "volume_db", -30.0, 0.85)
		_chase_music_tween.tween_callback(func() -> void:
			if chase_pulse_music:
				chase_pulse_music.stop())


# ---------- Mouse ----------
func _update_mouse() -> void:
	var play := Game.state == Game.S.PLAYING and ui.is_empty() and not Game.camera_open
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if play else Input.MOUSE_MODE_VISIBLE


# ---------- Layar ----------
func show_main_menu() -> void:
	_teardown_world()
	get_tree().paused = false
	ui.clear()
	if music.playing:
		music.stop()
	if not menu_music.playing:
		menu_music.play()
	Game.set_state(Game.S.MENU)
	var cont_night := mini(Game.unlocked_night, Game.MAX_MAIN_NIGHT)
	var items := [
		{"text": "MALAM BARU", "cb": func() -> void: start_night(1)},
		{"text": "LANJUTKAN (MALAM %d)" % cont_night, "cb": func() -> void: start_night(cont_night), "disabled": Game.unlocked_night <= 1},
		{"text": "MALAM 6 (MIMPI BURUK)", "cb": func() -> void: start_night(Game.SECRET_NIGHT), "disabled": Game.unlocked_night < Game.SECRET_NIGHT, "danger": true},
		{"text": "PENGATURAN", "cb": _open_settings},
		{"text": "KELUAR", "cb": func() -> void: get_tree().quit()},
	]
	var bg: Texture2D = load(MENU_BG)
	ui.push(ui.make_menu("FIVE NIGHTS\nAT WOWOK", "Bertahan hidup sampai jam 06:00 pagi.", items, bg))

func _open_settings() -> void:
	ui.push(ui.make_settings(func() -> void: ui.pop()))

func _show_pause() -> void:
	get_tree().paused = true
	var items := [
		{"text": "LANJUT", "cb": _resume},
		{"text": "PENGATURAN", "cb": _open_settings},
		{"text": "MENU UTAMA", "cb": show_main_menu},
	]
	ui.push(ui.make_menu("JEDA", "Malam %d" % Game.night, items, null, _resume))

func _resume() -> void:
	ui.clear()
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and Game.state == Game.S.PLAYING and ui.is_empty() and not Game.camera_open:
		_show_pause()
		get_viewport().set_input_as_handled()


# ---------- Malam ----------
func _teardown_world() -> void:
	_prev_threat = 0
	if _chase_music_tween:
		_chase_music_tween.kill()
	if chase_pulse_music and chase_pulse_music.playing:
		chase_pulse_music.stop()
	for n in [world, hud, cctv, scare_layer, intro_layer]:
		if is_instance_valid(n):
			n.queue_free()
	world = null
	hud = null
	cctv = null
	scare_layer = null
	intro_layer = null
	if fx_mat:
		fx_mat.set_shader_parameter("intensity", 0.0)
		fx_mat.set_shader_parameter("zoom_amount", 0.0)
		fx_mat.set_shader_parameter("focus_blur", 0.0)

func start_night(n: int) -> void:
	_death_seq += 1
	_teardown_world()
	get_tree().paused = false
	ui.clear()
	if menu_music.playing:
		menu_music.stop()
	if not music.playing:
		music.play()

	Game.night = clampi(n, 1, Game.MAX_NIGHT)
	world = WORLD_SCENE.instantiate() as World
	world.managed_by_main = true
	add_child(world)
	world.build(Game.night)

	cctv = CCTV_SCENE.instantiate() as CCTV
	cctv.bind(world)
	add_child(cctv)

	hud = HUD_SCENE.instantiate() as HUD
	add_child(hud)

	Game.start_night(Game.night)
	hud.bind(world.player)
	_night_intro(Game.night)
	_update_mouse()

func _night_intro(n: int) -> void:
	intro_layer = CanvasLayer.new()
	intro_layer.layer = 35
	add_child(intro_layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_layer.add_child(bg)
	var l := Label.new()
	l.text = ("MALAM 6 • LEMBUR\n12:00 AM" if n >= Game.SECRET_NIGHT else "MALAM %d\n12:00 AM" % n)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 88)
	if n >= Game.SECRET_NIGHT:
		l.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	l.theme = ui.ui_theme
	bg.add_child(l)
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(bg, "modulate:a", 0.0, 0.9)
	t.tween_callback(func() -> void:
		if is_instance_valid(intro_layer):
			intro_layer.queue_free())


# ---------- Hasil ----------
func _on_state(s: int) -> void:
	if fx_layer:
		fx_layer.visible = (s == Game.S.PLAYING) and not Game.camera_open
	_update_mouse()
	if s == Game.S.WON:
		_show_win()

func _show_win() -> void:
	if chase_pulse_music and chase_pulse_music.playing:
		chase_pulse_music.stop()
	if music.playing:
		music.stop()
	if not menu_music.playing:
		menu_music.play()
	var items: Array = []
	if Game.night < Game.MAX_MAIN_NIGHT:
		items.append({"text": "MALAM BERIKUTNYA", "cb": func() -> void: start_night(Game.night + 1)})
	elif Game.night == Game.MAX_MAIN_NIGHT:
		items.append({"text": "MASUK MALAM 6 (MIMPI BURUK)", "cb": func() -> void: start_night(Game.SECRET_NIGHT), "danger": true})
	items.append({"text": "MENU UTAMA", "cb": show_main_menu})
	var sub := "Kamu selamat sampai jam 6 pagi!"
	if Game.night == Game.MAX_MAIN_NIGHT:
		sub = "Selamat! Malam 5 tamat — Mode Rahasia MALAM 6 kini terbuka!"
	elif Game.night >= Game.SECRET_NIGHT:
		sub = "LUAR BIASA! Kamu menaklukkan Lembur Malam 6 Wowok!"
	ui.push(ui.make_menu("06:00 AM", sub, items))

func _on_caught() -> void:
	_death_seq += 1
	var my := _death_seq
	if chase_pulse_music and chase_pulse_music.playing:
		chase_pulse_music.stop()
	if music.playing:
		music.stop()
	if menu_music.playing:
		menu_music.stop()
	if Game.camera_open:
		Game.camera_open = false
		Game.camera_toggled.emit(false)

	fx_mat.set_shader_parameter("intensity", 1.0)
	scare_layer = CanvasLayer.new()
	scare_layer.layer = 40
	add_child(scare_layer)

	var a := AudioStreamPlayer.new()
	a.bus = &"Voice"
	a.stream = custom_jumpscare_scream if custom_jumpscare_scream != null else load("res://assets/audio/antek-antek.mp3")
	a.volume_db = 2.0
	scare_layer.add_child(a)
	a.play()

	# Tahap 1 (0.45s): Kamera 3D pemain terkunci menatap sosok Wowok dengan trauma shake
	await get_tree().create_timer(0.45).timeout
	if my != _death_seq or not is_inside_tree():
		return

	# Tahap 2 (1.35s): Smash-cut wajah penuh prabowo.jpg berguncang dengan kilatan merah
	var tr := TextureRect.new()
	tr.texture = load("res://assets/img/prabowo.jpg")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scare_layer.add_child(tr)

	var red_flash := ColorRect.new()
	red_flash.color = Color(0.85, 0.0, 0.0, 0.28)
	red_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	red_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scare_layer.add_child(red_flash)

	var shake_amp := 32.0 * maxf(0.25, Game.shake_strength)
	var t := create_tween().set_loops(18)
	t.tween_property(tr, "position", Vector2(randf_range(-shake_amp, shake_amp), randf_range(-shake_amp, shake_amp)), 0.038)
	t.tween_property(tr, "position", Vector2(randf_range(-shake_amp, shake_amp), randf_range(-shake_amp, shake_amp)), 0.038)

	await get_tree().create_timer(1.35).timeout
	if my != _death_seq or not is_inside_tree():
		return
	t.kill()
	if is_instance_valid(scare_layer):
		scare_layer.queue_free()
	var items := [
		{"text": "COBA LAGI", "cb": func() -> void: start_night(Game.night)},
		{"text": "MENU UTAMA", "cb": show_main_menu},
	]
	ui.push(ui.make_menu("KAMU TERTANGKAP", "Malam %d, jam %s" % [Game.night, "12 AM" if Game.hour == 0 else "%d AM" % Game.hour], items))
