extends CharacterBody3D
class_name Player
## Pemain first-person dengan Rig Kamera Raw Found-Footage / VHS Handheld (ala Kane Pixels):
## - Goyangan napas & pergelangan tangan organik (summed non-harmonic sines, anti-robotik)
## - Ayunan langkah berat figure-8 + hentakan tumit marmer + kemiringan Dutch-roll saat belok/strafe
## - Inersia tangan senter (`Flashlight` & `FlashlightHand` menyusul putaran kepala secara pegas halus)
## - Zoom optik camcorder 1.8x (Klik Kanan / LT) lengkap suara servo lensa & efek autofocus hunt

const GRAVITY := 20.0
const HEAD_STAND := 1.62
const HEAD_CROUCH := 1.0
const TRAUMA_DECAY := 1.35
const BASE_FOV := 78.0
const ZOOM_FOV := 43.5
const SPRINT_FOV := 83.5

@export_group("Movement")
@export var walk_speed: float = 3.1
@export var sprint_speed: float = 5.3
@export var crouch_speed: float = 1.5

@export_group("Equipment & Custom Model")
@export var flashlight_energy: float = 4.0
@export var start_with_gun: bool = false
@export var custom_gun_model: PackedScene

@export_group("Custom Audio Overrides (.mp3 / .wav)")
@export var custom_footstep_stream: AudioStream
@export var custom_camcorder_click_stream: AudioStream
@export var custom_camcorder_zoom_stream: AudioStream

@onready var col: CollisionShape3D = %Col
@onready var head: Node3D = %Head
@onready var shake_pivot: Node3D = %ShakePivot
@onready var cam: Camera3D = %Camera3D
@onready var light: SpotLight3D = %Flashlight
@onready var flashlight_hand: Node3D = %FlashlightHand
@onready var ray: RayCast3D = %InteractRay
@onready var gun: Node3D = %Gun
@onready var muzzle: OmniLight3D = %MuzzleLight

var capsule: CapsuleShape3D
var sfx: AudioStreamPlayer
var click_sfx: AudioStreamPlayer
var cam_click_sfx: AudioStreamPlayer
var zoom_in_sfx: AudioStreamPlayer
var zoom_out_sfx: AudioStreamPlayer
var gasp_sfx: AudioStreamPlayer
var heart_sfx: AudioStreamPlayer
var gun_sfx: AudioStreamPlayer
var egg_music: AudioStreamPlayer

var pitch := 0.0
var crouching := false
var flashlight_on := false
var has_gun := false
var hiding_spot: Interactable = null
var frozen := false
const MAX_STAMINA := 5.6
var stamina := MAX_STAMINA
var trauma := 0.0
var zoom_amount := 0.0

var _step_t := 0.0
var _bob := 0.0
var _bob_weight := 0.0
var _step_kick := 0.0
var _step_side := 1.0
var _handheld_t := 0.0
var _shake_t := 0.0
var _heart_t := 0.0
var _strafe_in := 0.0
var _move_sprinting := false
var _look_vel := Vector2.ZERO
var _cam_roll := 0.0
var _cam_pitch_lag := 0.0
var _hand_sway := Vector2.ZERO
var _zooming := false
var _focus_hunt := 0.0
var _last_lens_sent := Vector2(-1.0, -1.0)
var _light_base_pos := Vector3.ZERO
var _light_base_rot := Vector3.ZERO
var _hand_base_pos := Vector3.ZERO
var _hand_base_rot := Vector3.ZERO
var _last_prompt := "<none>"
var _gun_cd := 0.0
var _recoil_tween: Tween
var _gun_rest_pos := Vector3.ZERO

signal prompt_changed(text: String)


func _ready() -> void:
	capsule = col.shape.duplicate() as CapsuleShape3D
	col.shape = capsule
	_gun_rest_pos = gun.position
	_light_base_pos = light.position
	_light_base_rot = light.rotation
	if flashlight_hand:
		_hand_base_pos = flashlight_hand.position
		_hand_base_rot = flashlight_hand.rotation
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		light.shadow_enabled = false
	light.light_energy = flashlight_energy
	if custom_gun_model != null:
		for ch in gun.get_children():
			ch.queue_free()
		gun.add_child(custom_gun_model.instantiate())

	sfx = AudioStreamPlayer.new()
	sfx.bus = &"SFX"
	sfx.max_polyphony = 4
	if custom_footstep_stream != null:
		sfx.stream = custom_footstep_stream
	else:
		var step_rnd := AudioStreamRandomizer.new()
		for v in 4:
			step_rnd.add_stream(-1, Game.synth_marble_step(false, v))
		step_rnd.random_pitch_semitones = 1.4
		step_rnd.random_volume_offset_db = 1.8
		sfx.stream = step_rnd
	sfx.volume_db = -12.0
	add_child(sfx)

	click_sfx = AudioStreamPlayer.new()
	click_sfx.bus = &"SFX"
	click_sfx.max_polyphony = 3
	click_sfx.stream = Game.synth_tone(920.0, 420.0, 0.045, 2.5, 0.55, 0.25)
	click_sfx.volume_db = -9.5
	add_child(click_sfx)

	cam_click_sfx = AudioStreamPlayer.new()
	cam_click_sfx.bus = &"SFX"
	cam_click_sfx.max_polyphony = 2
	cam_click_sfx.stream = custom_camcorder_click_stream if custom_camcorder_click_stream != null else Game.synth_camcorder_click(true)
	cam_click_sfx.volume_db = -7.5
	add_child(cam_click_sfx)

	zoom_in_sfx = AudioStreamPlayer.new()
	zoom_in_sfx.bus = &"SFX"
	zoom_in_sfx.stream = custom_camcorder_zoom_stream if custom_camcorder_zoom_stream != null else Game.synth_camcorder_zoom(true)
	zoom_in_sfx.volume_db = -13.5
	add_child(zoom_in_sfx)

	zoom_out_sfx = AudioStreamPlayer.new()
	zoom_out_sfx.bus = &"SFX"
	zoom_out_sfx.stream = custom_camcorder_zoom_stream if custom_camcorder_zoom_stream != null else Game.synth_camcorder_zoom(false)
	zoom_out_sfx.volume_db = -14.5
	add_child(zoom_out_sfx)

	gasp_sfx = AudioStreamPlayer.new()
	gasp_sfx.bus = &"SFX"
	gasp_sfx.stream = Game.synth_burst(0.32, 1.4, 0.85, 0.45)
	gasp_sfx.volume_db = -6.0
	add_child(gasp_sfx)

	heart_sfx = AudioStreamPlayer.new()
	heart_sfx.bus = &"SFX"
	heart_sfx.max_polyphony = 2
	heart_sfx.stream = Game.synth_tone(64.0, 32.0, 0.16, 2.1, 0.85, 0.04)
	heart_sfx.volume_db = -11.0
	add_child(heart_sfx)

	gun_sfx = AudioStreamPlayer.new()
	gun_sfx.bus = &"SFX"
	gun_sfx.stream = Game.synth_burst(0.35, 3.0, 1.0, 0.5)
	add_child(gun_sfx)

	egg_music = AudioStreamPlayer.new()
	egg_music.bus = &"Music"
	egg_music.stream = load("res://assets/audio/codWaw.mp3")
	egg_music.volume_db = -6.0
	add_child(egg_music)

	Game.camera_toggled.connect(func(open: bool) -> void:
		frozen = open or Game.state != Game.S.PLAYING
		if open:
			_zooming = false)
	Game.state_changed.connect(_on_game_state)
	Game.trauma_added.connect(add_trauma)
	Game.force_unhide.connect(_on_force_unhide)
	if start_with_gun:
		_arm.call_deferred()


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _on_game_state(s: int) -> void:
	frozen = (s != Game.S.PLAYING) or Game.camera_open
	if s != Game.S.PLAYING:
		_zooming = false
	if s == Game.S.DEAD:
		if hiding_spot:
			col.disabled = false
			hiding_spot = null
			Game.set_hidden(false)
		add_trauma(0.95)
		if egg_music and egg_music.playing:
			egg_music.stop()


func _on_force_unhide() -> void:
	if not hiding_spot:
		return
	gasp_sfx.play()
	exit_hide()
	Game.add_noise(global_position, 17.0)
	add_trauma(0.38)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not frozen:
		var mrel: Vector2 = event.screen_relative if event.screen_relative != Vector2.ZERO else event.relative
		var sens_scale := lerpf(1.0, 0.56, zoom_amount)
		var dyaw := -mrel.x * Game.mouse_sens * sens_scale
		var dpitch := -mrel.y * Game.mouse_sens * sens_scale
		rotate_y(dyaw)
		pitch = clampf(pitch + dpitch, -1.42, 1.42)
		head.rotation.x = pitch
		_look_vel.x = clampf(_look_vel.x + dyaw * 22.0, -3.5, 3.5)
		_look_vel.y = clampf(_look_vel.y + dpitch * 22.0, -3.0, 3.0)
		return
	if Game.state != Game.S.PLAYING:
		return
	if event.is_action_pressed(&"camera_toggle") and not hiding_spot and not Game.camera_open:
		cam_click_sfx.pitch_scale = 1.04
		cam_click_sfx.play()
		Game.set_camera(true)
		get_viewport().set_input_as_handled()
		return
	if frozen:
		return
	if event.is_action_pressed(&"interact"):
		if hiding_spot:
			hiding_spot.play_creak()
			exit_hide()
		else:
			var t := _target()
			if t:
				t.interact(self)
	elif event.is_action_pressed(&"flashlight") and not hiding_spot:
		_toggle_flashlight()
	elif event.is_action_pressed(&"easter_egg"):
		_arm()
	elif event.is_action_pressed(&"fire"):
		_fire()


func _process(delta: float) -> void:
	if Game.state == Game.S.DEAD:
		_update_handheld_and_shake(delta)
		_look_at_killer(delta)
		return
	if Game.state != Game.S.PLAYING:
		_update_handheld_and_shake(delta)
		return
	_update_heartbeat(delta)
	if not frozen:
		var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		if look != Vector2.ZERO:
			var pad_scale := lerpf(1.0, 0.58, zoom_amount)
			var dyaw := -look.x * 2.8 * pad_scale * delta
			var dpitch := -look.y * 2.2 * pad_scale * delta
			rotate_y(dyaw)
			pitch = clampf(pitch + dpitch, -1.42, 1.42)
			head.rotation.x = pitch
			_look_vel.x = clampf(_look_vel.x + dyaw * 16.0, -3.5, 3.5)
			_look_vel.y = clampf(_look_vel.y + dpitch * 16.0, -3.0, 3.0)

		var want_zoom := Input.is_action_pressed(&"cam_zoom")
		if want_zoom != _zooming:
			_zooming = want_zoom
			_focus_hunt = maxf(_focus_hunt, 0.72 if want_zoom else 0.48)
			if want_zoom:
				zoom_in_sfx.pitch_scale = randf_range(0.97, 1.04)
				zoom_in_sfx.play()
			else:
				zoom_out_sfx.pitch_scale = randf_range(0.97, 1.04)
				zoom_out_sfx.play()

		_gun_cd = maxf(0.0, _gun_cd - delta)
		muzzle.light_energy = maxf(0.0, muzzle.light_energy - delta * 40.0)
		if flashlight_on:
			Game.drain_battery(0.72 * delta)
			if Game.battery <= 0.0:
				_set_flashlight(false)
				Game.toast.emit("Baterai senter habis")
			elif (Game.threat == 2 and randf() < 0.25) or (Game.night >= Game.SECRET_NIGHT and randf() < 0.06):
				light.light_energy = randf_range(0.15, flashlight_energy)
			else:
				light.light_energy = flashlight_energy
		_update_prompt()
	else:
		_zooming = false

	_update_zoom_and_fov(delta)
	_update_handheld_and_shake(delta)


func _update_zoom_and_fov(delta: float) -> void:
	var z_target := 1.0 if (_zooming and not frozen and Game.state == Game.S.PLAYING) else 0.0
	var z_alpha := 1.0 - exp(-7.5 * delta)
	zoom_amount = lerpf(zoom_amount, z_target, z_alpha)
	if absf(zoom_amount - z_target) < 0.003:
		zoom_amount = z_target

	_focus_hunt = maxf(0.0, _focus_hunt - delta * 3.4)
	# Ketika menoleh sangat cepat saat zoom penuh, lensa camcorder sedikit berburu fokus tipis
	if zoom_amount > 0.35 and _look_vel.length() > 1.8:
		_focus_hunt = maxf(_focus_hunt, minf(0.42, (_look_vel.length() - 1.8) * 0.22 * zoom_amount))

	var sprint_add := (SPRINT_FOV - BASE_FOV) if (_move_sprinting and zoom_amount < 0.1) else 0.0
	var stress_pulse := sin(_handheld_t * 6.4) * 0.85 if Game.threat >= 2 else 0.0
	var unzoomed_fov := BASE_FOV + sprint_add + stress_pulse
	var fov_target := lerpf(unzoomed_fov, ZOOM_FOV, zoom_amount)
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-9.0 * delta))

	var qz := snappedf(zoom_amount, 0.01)
	var qf := snappedf(_focus_hunt, 0.02)
	if absf(qz - _last_lens_sent.x) >= 0.01 or absf(qf - _last_lens_sent.y) >= 0.02:
		_last_lens_sent = Vector2(qz, qf)
		Game.set_cam_lens(zoom_amount, _focus_hunt)


func _update_handheld_and_shake(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)
	var decay_look := 1.0 - exp(-11.0 * real_dt)
	_look_vel = _look_vel.lerp(Vector2.ZERO, decay_look)
	_step_kick = lerpf(_step_kick, 0.0, 1.0 - exp(-14.0 * real_dt))

	# Skala goyangan kamera dari menu Pengaturan (0.0 = tenang/anti-mabuk, 1.0 = Raw Found-Footage penuh, 1.5 = ekstrem)
	var hh_scale := clampf(Game.shake_strength, 0.0, 1.5)
	var active_play := (Game.state == Game.S.PLAYING) and not frozen

	# 1. Goyangan Tangan Operator Camcorder (Raw Found-Footage: napas + tremor mikro non-periodik)
	var fatigue := clampf(1.0 - stamina / MAX_STAMINA, 0.0, 1.0)
	var panic := 1.0 if Game.threat >= 2 else (0.42 if Game.threat == 1 else 0.0)
	if hiding_spot and Game.breath < 40.0:
		panic = maxf(panic, (40.0 - Game.breath) / 40.0)

	var breath_rate := 1.0 + fatigue * 0.65 + panic * 0.85
	if active_play:
		_handheld_t += real_dt * breath_rate

	var idle_amp := (0.0068 + fatigue * 0.0055 + panic * 0.0085) * hh_scale * (1.0 if active_play else 0.0)
	# Saat zoom telephoto masuk, getaran mikro sudut tangan sedikit lebih kentara layaknya camcorder tanpa tripod
	var zoom_wobble := lerpf(1.0, 1.35, zoom_amount)
	var hh_pitch := (sin(_handheld_t * 1.42) * 0.65 + sin(_handheld_t * 3.17) * 0.35) * idle_amp * zoom_wobble
	var hh_yaw := (sin(_handheld_t * 0.93) * 0.70 + cos(_handheld_t * 2.31) * 0.30) * idle_amp * 0.9 * zoom_wobble
	var hh_roll := (sin(_handheld_t * 1.13) * 0.60 + sin(_handheld_t * 2.77) * 0.40) * idle_amp * 1.15

	# 2. Ayunan Langkah Berat Figure-8 + Hentakan Tumit & Dutch-Roll Banking
	var step_amp := _bob_weight * hh_scale * (1.45 if _move_sprinting else (0.52 if crouching else 1.0))
	var fig8_x := cos(_bob * 0.5) * 0.036 * step_amp
	var fig8_y := (sin(_bob) - 0.28 * sin(_bob * 2.0)) * 0.044 * step_amp - _step_kick * 0.026 * hh_scale
	var step_pitch := (cos(_bob) * 0.018 * step_amp) - _step_kick * 0.022 * hh_scale
	var step_roll := sin(_bob * 0.5) * 0.026 * step_amp + _step_kick * _step_side * 0.014 * hh_scale

	# Kemiringan pergelangan tangan saat strafe (A/D) dan saat membanting mouse menoleh
	var target_roll := (-_strafe_in * 0.034 - _look_vel.x * 0.016) * hh_scale
	_cam_roll = lerpf(_cam_roll, target_roll, 1.0 - exp(-8.5 * real_dt))
	_cam_pitch_lag = lerpf(_cam_pitch_lag, -_look_vel.y * 0.012 * hh_scale, 1.0 - exp(-9.5 * real_dt))

	# 3. Trauma Shake (benturan, teriakan, napas habis, generator, tertangkap) di atas gerak handheld
	var extra_trauma := 0.0
	if hiding_spot and Game.breath < 32.0:
		extra_trauma = (32.0 - Game.breath) / 32.0 * 0.24
	if trauma > 0.0:
		trauma = maxf(trauma - TRAUMA_DECAY * real_dt, 0.0)
	var eff_t := clampf(trauma + extra_trauma, 0.0, 1.0)
	var tr_amt := eff_t * eff_t * maxf(0.2, hh_scale)
	if tr_amt > 0.0001:
		_shake_t += real_dt * 30.0

	var tr_pos := Vector3(
		0.060 * tr_amt * sin(_shake_t * 1.7),
		0.046 * tr_amt * sin(_shake_t * 2.3),
		0.0
	)
	var tr_rot := Vector3(
		0.030 * tr_amt * sin(_shake_t * 1.9),
		0.016 * tr_amt * cos(_shake_t * 1.5),
		0.072 * tr_amt * sin(_shake_t * 1.3)
	)

	shake_pivot.position = Vector3(fig8_x, fig8_y, 0.0) + tr_pos
	shake_pivot.rotation = Vector3(
		hh_pitch + step_pitch + _cam_pitch_lag + tr_rot.x,
		hh_yaw + tr_rot.y,
		hh_roll + step_roll + _cam_roll + tr_rot.z
	)

	# 4. Inersia Pegas Tangan Senter (sorot senter sedikit menyusul gerakan kamera & ikut berayun langkah)
	var sway_target := Vector2(
		clampf(-_look_vel.x * 0.055, -0.16, 0.16),
		clampf(_look_vel.y * 0.048, -0.13, 0.13)
	)
	_hand_sway = _hand_sway.lerp(sway_target, 1.0 - exp(-11.5 * real_dt))
	var hand_bob_ofs := Vector3(
		cos(_bob * 0.5) * 0.014 * step_amp + _hand_sway.x * 0.09,
		sin(_bob) * 0.016 * step_amp - _step_kick * 0.014 - absf(_hand_sway.x) * 0.02,
		0.0
	)
	var beam_rot_ofs := Vector3(
		-_hand_sway.y + hh_pitch * 0.55 - _step_kick * 0.018,
		_hand_sway.x + hh_yaw * 0.55,
		-_cam_roll * 0.45
	)
	light.position = _light_base_pos + hand_bob_ofs * 0.65
	light.rotation = _light_base_rot + beam_rot_ofs
	if flashlight_hand:
		flashlight_hand.position = _hand_base_pos + hand_bob_ofs
		flashlight_hand.rotation = _hand_base_rot + Vector3(-beam_rot_ofs.x, beam_rot_ofs.y, -beam_rot_ofs.z)


func _look_at_killer(delta: float) -> void:
	if not Game.caught_killer_pos.is_finite():
		return
	var target := Game.caught_killer_pos + Vector3(0, 1.72, 0)
	var to := target - head.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.05:
		var desired_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, 18.0 * delta))
		var desired_pitch := clampf(atan2(to.y, flat.length()), -1.1, 1.1)
		head.rotation.x = lerpf(head.rotation.x, desired_pitch, minf(1.0, 18.0 * delta))


func _update_heartbeat(delta: float) -> void:
	var stress := 0.0
	if Game.threat == 2:
		stress = 1.0
	elif Game.threat == 1:
		stress = 0.45
	if hiding_spot and Game.breath < 45.0:
		stress = maxf(stress, (45.0 - Game.breath) / 45.0)
	if stress <= 0.05:
		_heart_t = 0.0
		return
	_heart_t -= delta
	if _heart_t <= 0.0:
		_heart_t = lerpf(0.95, 0.42, stress)
		heart_sfx.volume_db = lerpf(-16.0, -5.0, stress)
		heart_sfx.pitch_scale = lerpf(0.92, 1.18, stress)
		heart_sfx.play()


func _physics_process(delta: float) -> void:
	if hiding_spot:
		velocity = Vector3.ZERO
		_bob_weight = lerpf(_bob_weight, 0.0, 1.0 - exp(-10.0 * delta))
		_strafe_in = lerpf(_strafe_in, 0.0, 1.0 - exp(-10.0 * delta))
		_move_sprinting = false
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	var dir := Vector3.ZERO
	var moving := false
	var sprinting := false
	var raw_inp := Vector2.ZERO
	if not frozen and Game.state == Game.S.PLAYING:
		crouching = Input.is_action_pressed(&"crouch")
		raw_inp = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		moving = raw_inp.length() > 0.1
		dir = (global_transform.basis * Vector3(raw_inp.x, 0, raw_inp.y)).normalized() * minf(raw_inp.length(), 1.0)
		sprinting = Input.is_action_pressed(&"sprint") and moving and not crouching and stamina > 0.0 and not _zooming
		if sprinting:
			stamina = maxf(0.0, stamina - delta)
		else:
			stamina = minf(MAX_STAMINA, stamina + 1.05 * delta)
	var speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	if _zooming and moving and not crouching:
		speed *= 0.78
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	var actual_horiz := Vector2(velocity.x, velocity.z).length()
	var actually_moving := moving and actual_horiz > 0.25
	_move_sprinting = sprinting and actually_moving
	_strafe_in = lerpf(_strafe_in, raw_inp.x if actually_moving else 0.0, 1.0 - exp(-10.0 * delta))
	_bob_weight = lerpf(_bob_weight, 1.0 if actually_moving else 0.0, 1.0 - exp(-9.5 * delta))

	var h_target := HEAD_CROUCH if crouching else HEAD_STAND
	var h_alpha := 1.0 - exp(-12.0 * delta)
	head.position.y = lerpf(head.position.y, h_target, h_alpha)
	capsule.height = lerpf(capsule.height, 1.2 if crouching else 1.8, h_alpha)
	col.position.y = capsule.height / 2.0

	if actually_moving:
		_bob += delta * (speed * 2.85)
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.36 if sprinting else (0.68 if crouching else 0.54)
			_step_side = -_step_side
			_step_kick = 1.0 if sprinting else (0.35 if crouching else 0.68)
			var r := 2.5 if crouching else (14.0 if sprinting else 6.5)
			Game.add_noise(global_position, r)
			sfx.pitch_scale = 1.08 if sprinting else (0.86 if crouching else 0.98)
			sfx.volume_db = -21.0 if crouching else (-9.5 if sprinting else -13.0)
			sfx.play()


# ---------- Interaksi ----------
func _target() -> Interactable:
	if ray.is_colliding():
		var c := ray.get_collider()
		if c is Interactable:
			return c
	return null

func _update_prompt() -> void:
	var txt := ""
	if hiding_spot:
		txt = "[%s] Keluar dari loker (tahan napas %d%%)" % [Game.hint(&"interact"), int(ceilf(Game.breath))]
	else:
		var t := _target()
		if t:
			txt = "[%s] %s" % [Game.hint(&"interact"), t.prompt_text()]
	if txt != _last_prompt:
		_last_prompt = txt
		prompt_changed.emit(txt)

func enter_hide(spot: Interactable) -> void:
	hiding_spot = spot
	_zooming = false
	col.disabled = true
	global_position = spot.global_position
	velocity = Vector3.ZERO
	rotation.y = spot.global_rotation.y + PI
	pitch = 0.0
	head.rotation.x = 0.0
	_set_flashlight(false)
	crouching = false
	Game.set_hidden(true)

func exit_hide() -> void:
	if not hiding_spot:
		return
	global_position = hiding_spot.global_position + hiding_spot.global_transform.basis.z * 1.12
	col.disabled = false
	hiding_spot = null
	Game.set_hidden(false)

func _toggle_flashlight() -> void:
	if not flashlight_on and Game.battery <= 0.0:
		Game.toast.emit("Baterai senter habis")
		return
	click_sfx.pitch_scale = 1.0 if not flashlight_on else 0.82
	click_sfx.play()
	_set_flashlight(not flashlight_on)

func _set_flashlight(on: bool) -> void:
	flashlight_on = on
	Game.flashlight_on = on
	light.visible = on
	if flashlight_hand:
		flashlight_hand.visible = on

func _arm() -> void:
	if has_gun:
		return
	has_gun = true
	gun.visible = true
	Game.set_ammo(6)
	egg_music.play()
	Game.toast.emit("??? Revolver rahasia aktif! [%s] menembak (6 peluru)" % Game.hint(&"fire"))

func _fire() -> void:
	if not has_gun or Game.ammo <= 0 or _gun_cd > 0.0 or hiding_spot:
		return
	_gun_cd = 0.5
	Game.set_ammo(Game.ammo - 1)
	gun_sfx.play()
	muzzle.light_energy = 6.0
	if _recoil_tween:
		_recoil_tween.kill()
	gun.position = _gun_rest_pos + Vector3(0.0, 0.045, 0.07)
	_recoil_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(gun, "position", _gun_rest_pos, 0.22)
	add_trauma(0.32)
	Game.add_noise(global_position, 40.0)
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * 85.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Enemy:
		(hit.collider as Enemy).stun()
		Game.toast.emit("Kena! Wowok terhuyung!")
