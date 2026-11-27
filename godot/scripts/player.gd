extends CharacterBody3D
class_name Player
## Pemain first-person: gerak, jongkok, senter 3D (`flashlight.glb`), revolver rahasia (`revolver.glb`),
## tablet CCTV (C), sembunyi loker, detak jantung, & trauma camera shake.

const GRAVITY := 20.0
const HEAD_STAND := 1.62
const HEAD_CROUCH := 1.0
const TRAUMA_DECAY := 1.35

@export_group("Movement")
@export var walk_speed: float = 3.1
@export var sprint_speed: float = 5.3
@export var crouch_speed: float = 1.5

@export_group("Equipment & Custom Model")
@export var flashlight_energy: float = 4.0
@export var start_with_gun: bool = false
@export var custom_gun_model: PackedScene

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
var stamina := 3.0
var trauma := 0.0

var _step_t := 0.0
var _bob := 0.0
var _shake_t := 0.0
var _heart_t := 0.0
var _last_prompt := "<none>"
var _gun_cd := 0.0
var _recoil_tween: Tween
var _gun_rest_pos := Vector3.ZERO

signal prompt_changed(text: String)


func _ready() -> void:
	capsule = col.shape.duplicate() as CapsuleShape3D
	col.shape = capsule
	_gun_rest_pos = gun.position
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		light.shadow_enabled = false
	light.light_energy = flashlight_energy
	if custom_gun_model != null:
		for ch in gun.get_children():
			ch.queue_free()
		gun.add_child(custom_gun_model.instantiate())

	sfx = AudioStreamPlayer.new()
	sfx.bus = &"SFX"
	sfx.max_polyphony = 3
	sfx.stream = Game.synth_burst(0.08, 2.0, 0.6, 0.3)
	sfx.volume_db = -14.0
	add_child(sfx)

	click_sfx = AudioStreamPlayer.new()
	click_sfx.bus = &"SFX"
	click_sfx.max_polyphony = 3
	click_sfx.stream = Game.synth_tone(920.0, 420.0, 0.045, 2.5, 0.55, 0.25)
	click_sfx.volume_db = -10.0
	add_child(click_sfx)

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

	Game.camera_toggled.connect(func(open: bool) -> void: frozen = open or Game.state != Game.S.PLAYING)
	Game.state_changed.connect(_on_game_state)
	Game.trauma_added.connect(add_trauma)
	Game.force_unhide.connect(_on_force_unhide)
	if start_with_gun:
		_arm.call_deferred()


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _on_game_state(s: int) -> void:
	frozen = (s != Game.S.PLAYING) or Game.camera_open
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
		rotate_y(-event.relative.x * Game.mouse_sens)
		pitch = clampf(pitch - event.relative.y * Game.mouse_sens, -1.45, 1.45)
		head.rotation.x = pitch
		return
	if Game.state != Game.S.PLAYING:
		return
	if event.is_action_pressed(&"camera_toggle") and not hiding_spot and not Game.camera_open:
		click_sfx.pitch_scale = 1.15
		click_sfx.play()
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
	_update_shake(delta)
	if Game.state == Game.S.DEAD:
		_look_at_killer(delta)
		return
	if Game.state != Game.S.PLAYING:
		return
	_update_heartbeat(delta)
	if frozen:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		rotate_y(-look.x * 2.8 * delta)
		pitch = clampf(pitch - look.y * 2.2 * delta, -1.45, 1.45)
		head.rotation.x = pitch
	_gun_cd = maxf(0.0, _gun_cd - delta)
	muzzle.light_energy = maxf(0.0, muzzle.light_energy - delta * 40.0)
	if flashlight_on:
		Game.drain_battery(0.9 * delta)
		if Game.battery <= 0.0:
			_set_flashlight(false)
			Game.toast.emit("Baterai senter habis")
		elif (Game.threat == 2 and randf() < 0.25) or (Game.night >= Game.SECRET_NIGHT and randf() < 0.06):
			light.light_energy = randf_range(0.15, flashlight_energy)
		else:
			light.light_energy = flashlight_energy
	_update_prompt()


func _update_shake(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)
	var extra := 0.0
	if hiding_spot and Game.breath < 32.0:
		extra = (32.0 - Game.breath) / 32.0 * 0.22
	if trauma <= 0.0 and extra <= 0.0:
		if shake_pivot.position != Vector3.ZERO or shake_pivot.rotation != Vector3.ZERO:
			shake_pivot.position = Vector3.ZERO
			shake_pivot.rotation = Vector3.ZERO
		return
	trauma = maxf(trauma - TRAUMA_DECAY * real_dt, 0.0)
	var eff := clampf(trauma + extra, 0.0, 1.0)
	var amt := eff * eff * Game.shake_strength
	_shake_t += real_dt * 30.0
	shake_pivot.position = Vector3(
		0.055 * amt * sin(_shake_t * 1.7),
		0.042 * amt * sin(_shake_t * 2.3),
		0.0
	)
	shake_pivot.rotation = Vector3(
		0.025 * amt * sin(_shake_t * 1.9),
		0.0,
		0.065 * amt * sin(_shake_t * 1.3)
	)


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
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	var dir := Vector3.ZERO
	var moving := false
	var sprinting := false
	if not frozen and Game.state == Game.S.PLAYING:
		crouching = Input.is_action_pressed(&"crouch")
		var inp := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		moving = inp.length() > 0.1
		dir = (global_transform.basis * Vector3(inp.x, 0, inp.y)).normalized() * minf(inp.length(), 1.0)
		sprinting = Input.is_action_pressed(&"sprint") and moving and not crouching and stamina > 0.0
		if sprinting:
			stamina = maxf(0.0, stamina - delta)
		else:
			stamina = minf(3.0, stamina + 0.6 * delta)
	var speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	var h_target := HEAD_CROUCH if crouching else HEAD_STAND
	head.position.y = lerpf(head.position.y, h_target + sin(_bob) * 0.025, 12.0 * delta)
	capsule.height = lerpf(capsule.height, 1.2 if crouching else 1.8, 12.0 * delta)
	col.position.y = capsule.height / 2.0
	if moving:
		_bob += delta * (speed * 2.4)
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.38 if sprinting else 0.6
			var r := 2.5 if crouching else (14.0 if sprinting else 6.5)
			Game.add_noise(global_position, r)
			sfx.pitch_scale = randf_range(0.72, 1.08)
			sfx.volume_db = -22.0 if crouching else -14.0
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
	global_position = hiding_spot.global_position + hiding_spot.global_transform.basis.z * 1.0
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
	var to := from + (-cam.global_transform.basis.z) * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Enemy:
		(hit.collider as Enemy).stun()
		Game.toast.emit("Kena! Wowok terhuyung!")
