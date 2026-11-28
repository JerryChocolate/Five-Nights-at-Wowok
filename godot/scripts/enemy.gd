extends CharacterBody3D
class_name Enemy
## Prabowo (Wowok): AI horor dengan navigasi AStarGrid2D 0.5m bebas nyangkut meja/kursi,
## steering kumis 3-arah (priority-truncated), memutar otomatis saat pintu sebelah ditutup,
## serta variasi langkah AudioStreamRandomizer (/godot-audio) & slot MP3 kustom di Inspector.

enum St { IDLE, PATROL, INVESTIGATE, CHASE, SEARCH, BLOCKED, STUNNED, SABOTAGE }

@export_group("Enemy Config & Custom Model")
@export var freeze_ai: bool = false
@export var use_3d_head_instead_of_photo: bool = false
@export var custom_body_model: PackedScene

@export_group("Custom Audio Overrides (.mp3 / .wav)")
@export var custom_footstep_stream: AudioStream
@export var custom_voice_stream: AudioStream

@onready var rig: Node3D = %Rig
@onready var model_root: Node3D = %BusinessmanModel
@onready var face: Sprite3D = %Face
@onready var eye_light: OmniLight3D = %EyeLight
@onready var voice: AudioStreamPlayer3D = %Voice

var anim_player: AnimationPlayer
var skel: Skeleton3D
var head_bone_idx: int = -1
var step_sfx: AudioStreamPlayer3D
var _cur_anim: StringName = &""

var st: int = St.IDLE
var world: World
var nav: AStar3D
var patrol_ids: PackedInt32Array
var generator_nav_id: int = -1
var player: Player
var night := 1

var path := PackedVector3Array()
var path_i := 0
var timer := 0.0
var wait_t := 0.0
var lost_t := 0.0
var repath_t := 0.0
var bang_t := 0.0
var inspect_t := 0.0
var voice_cd := 0.0
var sabotage_cd := 35.0
var last_known := Vector3.ZERO
var _last_chase_target := Vector3.INF
var saw_hide := false
var blocked_door: Interactable

var _stride_phase := 0.0
var _last_step_half := 0
var _stuck_pos := Vector3.ZERO
var _stuck_t := 0.0
var _stuck_strikes := 0
var _smooth_vel := Vector3.ZERO


func setup(p_nav: AStar3D, p_patrol: PackedInt32Array, p_gen_id: int, p_player: Player, p_night: int, p_world: World = null) -> void:
	nav = p_nav
	patrol_ids = p_patrol
	generator_nav_id = p_gen_id
	player = p_player
	night = p_night
	world = p_world if p_world != null else (get_parent() as World)
	timer = 4.0 if night >= Game.SECRET_NIGHT else maxf(6.0, 28.0 - float(night) * 4.5)
	sabotage_cd = 26.0 if night >= Game.SECRET_NIGHT else 52.0


func _ready() -> void:
	if custom_body_model != null and rig != null:
		if model_root:
			model_root.visible = false
		var custom_inst := custom_body_model.instantiate() as Node3D
		custom_inst.name = "CustomBodyModel"
		rig.add_child(custom_inst)
		model_root = custom_inst

	if face and face.texture:
		face.pixel_size = 0.48 / float(face.texture.get_height())
		face.visible = not use_3d_head_instead_of_photo

	_setup_character_rig()

	if custom_voice_stream != null and voice != null:
		voice.stream = custom_voice_stream

	# Langkah kaki ber-variasi AudioStreamRandomizer (anti suara mesin tik repetitif!)
	step_sfx = AudioStreamPlayer3D.new()
	step_sfx.bus = &"SFX"
	step_sfx.max_polyphony = 4
	if custom_footstep_stream != null:
		step_sfx.stream = custom_footstep_stream
	else:
		var rnd := AudioStreamRandomizer.new()
		for v in 3:
			rnd.add_stream(-1, Game.synth_marble_step(true, v))
		rnd.random_pitch_semitones = 1.3
		rnd.random_volume_offset_db = 1.6
		step_sfx.stream = rnd
	step_sfx.unit_size = 11.5
	step_sfx.max_distance = 58.0
	add_child(step_sfx)

	Game.noise_made.connect(_on_noise)
	Game.hidden_changed.connect(_on_player_hidden)
	_stuck_pos = global_position


func _setup_character_rig() -> void:
	if model_root == null:
		return
	var aps := model_root.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim_player = aps[0] as AnimationPlayer
		for clip in [
			"CharacterArmature|Idle_Neutral",
			"CharacterArmature|Idle",
			"CharacterArmature|Walk",
			"CharacterArmature|Run",
			"CharacterArmature|Punch_Right",
		]:
			if anim_player.has_animation(clip):
				var a := anim_player.get_animation(clip)
				if a:
					a.loop_mode = Animation.LOOP_LINEAR
		_play_anim(&"CharacterArmature|Idle_Neutral", 1.0)

	var skels := model_root.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skel = skels[0] as Skeleton3D
		head_bone_idx = skel.find_bone("Head")
		var suit_head := skel.get_node_or_null("Suit_Head") as MeshInstance3D
		if suit_head:
			suit_head.visible = use_3d_head_instead_of_photo
		var suit_body := skel.get_node_or_null("Suit_Body") as MeshInstance3D
		if suit_body and suit_body.mesh:
			for s in suit_body.mesh.get_surface_count():
				var sm := suit_body.get_active_material(s) as StandardMaterial3D
				if sm and sm.resource_name == "Tie":
					var red_tie := sm.duplicate() as StandardMaterial3D
					red_tie.albedo_color = Color(0.68, 0.06, 0.06)
					suit_body.set_surface_override_material(s, red_tie)
				elif sm and sm.resource_name == "Suit":
					var dark_suit := sm.duplicate() as StandardMaterial3D
					dark_suit.albedo_color = Color(0.08, 0.09, 0.11)
					suit_body.set_surface_override_material(s, dark_suit)


func _play_anim(anim_name: StringName, speed_scale: float = 1.0) -> void:
	if anim_player == null or not anim_player.has_animation(anim_name):
		return
	anim_player.speed_scale = speed_scale
	if _cur_anim != anim_name or not anim_player.is_playing():
		_cur_anim = anim_name
		anim_player.play(anim_name, 0.18)


func _sync_face_to_head_bone() -> void:
	if face == null or not face.visible or skel == null or head_bone_idx < 0:
		return
	var bone_world := skel.global_transform * skel.get_bone_global_pose(head_bone_idx).origin
	face.global_position = bone_world + Vector3(0.0, 0.12, 0.0)


# ---------- Persepsi ----------
func _eye() -> Vector3:
	return global_position + Vector3(0, 1.65, 0)

func _los(max_dist: float) -> bool:
	var eye := _eye()
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = [get_rid(), player.get_rid()]
	for h in [1.45, 0.95]:
		var target := player.global_position + Vector3(0, h, 0)
		if eye.distance_to(target) <= max_dist:
			var q := PhysicsRayQueryParameters3D.create(eye, target, 1, excl)
			if space.intersect_ray(q).is_empty():
				return true
	return false

func _can_see() -> bool:
	if Game.is_hidden or player == null:
		return false
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var max_d := 22.5 if Game.flashlight_on else (16.5 if night >= Game.SECRET_NIGHT else 13.5)
	if player.crouching:
		max_d *= 0.62
	if dist > max_d:
		return false
	if dist > 2.8:
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		var half_cone := 68.0 if st == St.CHASE else 58.0
		if fwd.normalized().angle_to(to.normalized()) > deg_to_rad(half_cone):
			return false
	return _los(max_d + 1.0)

func _on_noise(pos: Vector3, radius: float) -> void:
	if st == St.IDLE or st == St.CHASE or st == St.STUNNED or st == St.BLOCKED:
		return
	var flat := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	if flat < radius * (0.9 + float(night) * 0.08):
		last_known = pos
		_go_to(pos)
		_set_state(St.INVESTIGATE)

func _on_player_hidden(h: bool) -> void:
	saw_hide = h and (st == St.CHASE or _los(14.0))


# ---------- Navigasi Presisi AStarGrid2D + Whisker Steering ----------
func _go_to(pos: Vector3) -> void:
	if world != null and world.nav_grid_ready:
		path = world.find_smooth_path(global_position, pos)
	elif nav != null and nav.get_point_count() > 0:
		var a := nav.get_closest_point(global_position)
		var b := nav.get_closest_point(pos)
		path = nav.get_point_path(a, b)
	else:
		path = PackedVector3Array([pos])
	path_i = 0
	if path.size() > 1 and Vector2(path[0].x - global_position.x, path[0].z - global_position.z).length() < 0.65:
		path_i = 1
	_stuck_pos = global_position
	_stuck_t = 0.0


## Steering kumis (whiskers) setinggi pinggang (y=0.55m) agar mulus melewati sudut meja/kursi/kusen.
func _steer_dir(desired_dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = [get_rid()]
	if player:
		excl.append(player.get_rid())
	var origin := global_position + Vector3(0.0, 0.55, 0.0)
	var avoid := Vector3.ZERO
	for ang_deg: float in [-36.0, 0.0, 36.0]:
		var ray_dir := desired_dir.rotated(Vector3.UP, deg_to_rad(ang_deg))
		var probe_len := 1.15 if ang_deg == 0.0 else 0.95
		var q := PhysicsRayQueryParameters3D.create(origin, origin + ray_dir * probe_len, 1, excl)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			# Jangan hindari pintu tertutup jika memang sedang menuju pintu itu untuk menggedornya!
			if hit.collider is Interactable and (hit.collider as Interactable).kind == Interactable.Kind.DOOR:
				continue
			var nrm: Vector3 = hit.normal
			nrm.y = 0.0
			var frac := 1.0 - clampf(origin.distance_to(hit.position) / probe_len, 0.0, 1.0)
			if nrm.length_squared() > 0.01:
				# Dorong ke arah tangensial menyusuri sisi meja, bukan sekadar memantul mundur!
				var slide := desired_dir - nrm.normalized() * desired_dir.dot(nrm.normalized())
				if slide.length_squared() > 0.01:
					avoid += slide.normalized() * (frac * 1.15)
				else:
					avoid += nrm.normalized() * (frac * 0.95)
	var combined := desired_dir + avoid
	combined.y = 0.0
	return combined.normalized() if combined.length_squared() > 0.001 else desired_dir


func _move_along(delta: float, speed: float) -> bool:
	if path_i >= path.size():
		_smooth_vel = _smooth_vel.move_toward(Vector3.ZERO, speed * 8.0 * delta)
		velocity.x = _smooth_vel.x
		velocity.z = _smooth_vel.z
		_animate_rig(delta, 0.0)
		return true

	# String-pull dinamis ke waypoint berikutnya bila koridor bahu sudah terbuka
	if world != null and world.nav_grid_ready and path_i + 1 < path.size():
		if world.has_clear_walk_corridor(global_position, path[path_i + 1], 0.36):
			# Pastikan tidak melompati pintu tertutup di titik path_i
			var c_mid := world.world_to_grid(path[path_i])
			if world.nav_grid.get_point_weight_scale(c_mid) <= 1.5:
				path_i += 1

	var d := path[path_i] - global_position
	d.y = 0.0
	var is_last := (path_i == path.size() - 1)
	var reach := maxf(0.45 if is_last else 0.58, speed * delta * 2.0)
	if d.length() < reach:
		path_i += 1
		_stuck_pos = global_position
		_stuck_t = 0.0
		return path_i >= path.size()

	var raw_dir := d.normalized()
	var steered := _steer_dir(raw_dir)
	var target_vel := steered * speed
	_smooth_vel = _smooth_vel.lerp(target_vel, minf(1.0, 12.0 * delta))
	velocity = Vector3(_smooth_vel.x, -3.5 if is_on_floor() else velocity.y - 20.0 * delta, _smooth_vel.z)
	if Vector2(_smooth_vel.x, _smooth_vel.z).length_squared() > 0.04:
		rotation.y = lerp_angle(rotation.y, atan2(-_smooth_vel.x, -_smooth_vel.z), minf(1.0, 10.5 * delta))
	move_and_slide()
	_animate_rig(delta, Vector2(velocity.x, velocity.z).length())

	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c is Interactable and c.kind == Interactable.Kind.DOOR and c.closed:
			blocked_door = c
			timer = 2.0 if night >= Game.SECRET_NIGHT else maxf(2.5, randf_range(4.0, 7.5) - float(night) * 0.5)
			bang_t = 0.0
			_set_state(St.BLOCKED)
			return false

	_stuck_t += delta
	if _stuck_t >= 1.2:
		var moved := Vector2(global_position.x - _stuck_pos.x, global_position.z - _stuck_pos.z).length()
		_stuck_pos = global_position
		_stuck_t = 0.0
		if moved < 0.32:
			_stuck_strikes += 1
			if st == St.CHASE and player != null:
				_go_to(player.global_position)
			elif path_i + 1 < path.size() and _stuck_strikes < 2:
				path_i += 1
			else:
				_stuck_strikes = 0
				_pick_patrol()
				if st == St.SABOTAGE:
					_set_state(St.PATROL)
		else:
			_stuck_strikes = 0
	return false


func _animate_rig(delta: float, horiz_speed: float) -> void:
	if st == St.BLOCKED:
		_play_anim(&"CharacterArmature|Punch_Right", 1.1)
		_sync_face_to_head_bone()
		return
	if st == St.STUNNED:
		_sync_face_to_head_bone()
		return
	if horiz_speed < 0.15:
		_play_anim(&"CharacterArmature|Idle_Neutral", 1.0)
		_sync_face_to_head_bone()
		return

	if st == St.CHASE or st == St.INVESTIGATE or st == St.SABOTAGE:
		_play_anim(&"CharacterArmature|Run", clampf(horiz_speed / 3.6, 0.85, 1.45))
	else:
		_play_anim(&"CharacterArmature|Walk", clampf(horiz_speed / 1.75, 0.85, 1.35))

	_stride_phase += delta * horiz_speed * 2.25
	var half := int(floor(_stride_phase / PI))
	if half != _last_step_half:
		_last_step_half = half
		if step_sfx:
			step_sfx.volume_db = -2.0 if st == St.CHASE else -6.5
			step_sfx.play()
		if player and global_position.distance_to(player.global_position) < 11.5:
			Game.add_trauma(0.09 if st == St.CHASE else 0.04)
	_sync_face_to_head_bone()


func _pick_patrol() -> void:
	if patrol_ids.is_empty():
		return
	var best_id := patrol_ids[randi() % patrol_ids.size()]
	for _try in 6:
		var cand := patrol_ids[randi() % patrol_ids.size()]
		var p := nav.get_point_position(cand)
		if p.distance_to(global_position) > 8.0:
			best_id = cand
			break
	_go_to(nav.get_point_position(best_id))


func _set_state(s: int) -> void:
	if st == s:
		return
	var prev := st
	st = s
	wait_t = 0.0
	match s:
		St.CHASE:
			Game.set_threat(2)
			if prev != St.CHASE:
				_speak(true)
		St.INVESTIGATE, St.SEARCH:
			Game.set_threat(1)
		St.BLOCKED:
			Game.set_threat(1)
		_:
			Game.set_threat(0)


func _speak(force: bool) -> void:
	if voice == null:
		return
	if voice_cd <= 0.0 or force:
		voice_cd = 8.5
		voice.pitch_scale = randf_range(0.76, 0.96) if night >= Game.SECRET_NIGHT else randf_range(0.82, 1.0)
		voice.play()


func stun() -> void:
	timer = 6.5 if night >= Game.SECRET_NIGHT else 9.0
	voice.stop()
	_play_anim(&"CharacterArmature|HitRecieve", 1.0)
	_set_state(St.STUNNED)


func _catch() -> void:
	if Game.state != Game.S.PLAYING:
		return
	var to_p := player.global_position - global_position
	to_p.y = 0.0
	if to_p.length() > 0.05:
		rotation.y = atan2(-to_p.x, -to_p.z)
	_play_anim(&"CharacterArmature|Punch_Right", 1.4)
	if eye_light:
		eye_light.light_energy = 2.8
	Game.die(global_position)


func _speeds() -> Vector2:
	var m := 1.12 if Game.power_is_out else 1.0
	if night >= Game.SECRET_NIGHT:
		return Vector2(4.25 * m, 5.45 * m)
	return Vector2((2.25 + float(night) * 0.36) * m, (3.75 + float(night) * 0.35) * m)


func _physics_process(delta: float) -> void:
	if Game.state != Game.S.PLAYING or freeze_ai:
		velocity = Vector3.ZERO
		_sync_face_to_head_bone()
		return
	voice_cd = maxf(0.0, voice_cd - delta)
	sabotage_cd = maxf(0.0, sabotage_cd - delta)
	eye_light.light_energy = (0.75 + randf() * 0.45) if st == St.CHASE else (0.65 if night >= Game.SECRET_NIGHT else 0.48)
	var sp := _speeds()
	var dist := global_position.distance_to(player.global_position)

	if st != St.STUNNED and st != St.CHASE and st != St.IDLE and _can_see():
		lost_t = 0.0
		last_known = player.global_position
		_last_chase_target = Vector3.INF
		repath_t = 0.0
		_set_state(St.CHASE)

	if st == St.PATROL and night >= 4 and sabotage_cd <= 0.0 and generator_nav_id >= 0 and not Game.generator_sabotaged and not Game.power_is_out:
		sabotage_cd = 34.0 if night >= Game.SECRET_NIGHT else 60.0
		if night >= Game.SECRET_NIGHT or randf() < 0.45:
			_go_to(nav.get_point_position(generator_nav_id))
			_set_state(St.SABOTAGE)

	match st:
		St.IDLE:
			_animate_rig(delta, 0.0)
			timer -= delta
			if timer <= 0.0:
				_pick_patrol()
				_set_state(St.PATROL)
		St.PATROL:
			if _move_along(delta, sp.x):
				wait_t += delta
				if wait_t > randf_range(0.6, 1.8):
					wait_t = 0.0
					_pick_patrol()
			if randf() < delta / 24.0:
				_speak(false)
			_check_locker(delta, dist)
		St.SABOTAGE:
			if _move_along(delta, sp.x * 1.25):
				Game.sabotage_generator()
				_speak(false)
				_pick_patrol()
				_set_state(St.PATROL)
			_check_locker(delta, dist)
		St.INVESTIGATE:
			if _move_along(delta, sp.x * 1.35):
				timer = 7.0
				_set_state(St.SEARCH)
			_check_locker(delta, dist)
		St.SEARCH:
			timer -= delta
			if _move_along(delta, sp.x):
				wait_t += delta
				if wait_t > 1.1:
					wait_t = 0.0
					var near := nav.get_closest_point(last_known)
					var ids := nav.get_point_connections(near)
					var pick := near if ids.is_empty() else ids[randi() % ids.size()]
					_go_to(nav.get_point_position(pick))
			_check_locker(delta, dist)
			if timer <= 0.0:
				_set_state(St.PATROL)
				_pick_patrol()
		St.CHASE:
			var seen := _can_see()
			repath_t -= delta
			if seen:
				lost_t = 0.0
				last_known = player.global_position
				# HANYA lari lurus bila koridor setinggi pinggang (y=0.56m) benar-benar kosong dari meja/kursi!
				# Bila terhalang meja (seperti di Ruang Pimpinan/Sidang), gunakan AStarGrid2D untuk memutari meja!
				if world != null and world.has_clear_walk_corridor(global_position, player.global_position, 0.36):
					path = PackedVector3Array([player.global_position])
					path_i = 0
					_last_chase_target = player.global_position
				elif repath_t <= 0.0 or not _last_chase_target.is_finite() or _last_chase_target.distance_to(player.global_position) > 0.85 or path_i >= path.size():
					repath_t = 0.22
					_last_chase_target = player.global_position
					_go_to(player.global_position)
			else:
				lost_t += delta
				if repath_t <= 0.0:
					repath_t = 0.38
					_go_to(last_known)
				if lost_t > 4.2:
					timer = 9.0
					_set_state(St.SEARCH)
			_move_along(delta, sp.y)
			# Pastikan penangkapan tidak menembus meja/tembok!
			if seen and dist < 1.52 and (world == null or world.has_clear_walk_corridor(global_position, player.global_position, 0.15)):
				_catch()
		St.BLOCKED:
			_animate_rig(delta, 0.0)
			if not is_instance_valid(blocked_door) or not blocked_door.closed:
				_set_state(St.PATROL)
				return
			var look := blocked_door.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), 6.0 * delta)
			bang_t -= delta
			timer -= delta
			if bang_t <= 0.0:
				bang_t = 0.75 if night >= Game.SECRET_NIGHT else 1.1
				blocked_door.bang()
			if timer <= 0.0:
				var break_chance := 0.9 if night >= Game.SECRET_NIGHT else (0.3 + float(night) * 0.1)
				if randf() < break_chance:
					blocked_door.force_open()
					_set_state(St.SEARCH)
					timer = 8.0
				else:
					_pick_patrol()
					_set_state(St.PATROL)
		St.STUNNED:
			velocity = Vector3.ZERO
			_animate_rig(delta, 0.0)
			face.modulate = Color(1, 1, 1) if int(Time.get_ticks_msec() / 120.0) % 2 == 0 else Color(0.4, 0.4, 0.4)
			timer -= delta
			if timer <= 0.0:
				face.modulate = Color(0.9, 0.9, 0.9)
				_set_state(St.SEARCH)
				timer = 8.0
				last_known = player.global_position


func _check_locker(delta: float, dist: float) -> void:
	if Game.is_hidden and dist < 2.8:
		inspect_t += delta
		var need := 1.1 if saw_hide else (1.7 if night >= Game.SECRET_NIGHT else 2.2)
		if inspect_t >= need:
			if saw_hide or randf() < (0.14 + float(night) * 0.1):
				_catch()
			else:
				inspect_t = -4.0
	elif inspect_t > 0.0:
		inspect_t = 0.0
	elif inspect_t < 0.0:
		inspect_t = minf(0.0, inspect_t + delta)
