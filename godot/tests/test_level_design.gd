extends Node
## Pengujian otomatis `level-design` + fisika 3D Gedung Sidang Paripurna (70m x 60m):
## godot --headless --path godot res://tests/level_design.tscn

var passed := 0
var failed := 0
var _completed := false


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	await _run_all()
	if not _completed:
		failed += 1
		push_error("FAIL: _run_all berhenti di tengah jalan (runtime error)")
	print("Level-Design & 3D Map Checks: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _run_all() -> void:
	await get_tree().process_frame

	# 1. Validasi Grafik Ruangan & Anti-Soft-Lock (level-design Pattern 3)
	for room_name: String in LevelGraph.ROOMS.keys():
		_check(
			LevelGraph.goal_reachable(LevelGraph.ROOMS, "pos_sekuriti", room_name),
			"ketercapaian dari pos_sekuriti ke " + room_name
		)
		_check(
			LevelGraph.goal_reachable(LevelGraph.ROOMS, room_name, "pos_sekuriti"),
			"anti-soft-lock kembali ke pos_sekuriti dari " + room_name
		)

	# 2. Validasi Kurva Pacing Sawtooth (level-design Pattern 2)
	var p_probs := LevelGraph.pacing_problems(LevelGraph.BEATS)
	_check(p_probs.is_empty(), "kurva pacing sawtooth bebas masalah")

	# 3. Muat World 3D Nyata & Uji Fisika Headless
	var world_packed := load("res://scenes/world.tscn") as PackedScene
	_check(world_packed != null, "world.tscn berhasil dimuat")
	if world_packed == null:
		return

	var w := world_packed.instantiate() as World
	w.managed_by_main = true
	add_child(w)
	w.build(1)
	w.enemy.freeze_ai = true
	for _i in 4:
		await get_tree().physics_frame

	_check(w.cams.size() == 8, "8 kamera CCTV terdaftar (aktual=%d)" % w.cams.size())
	_check(w.nav.get_point_count() >= 50, "grafik AStar3D memiliki >= 50 titik (%d)" % w.nav.get_point_count())
	_check(w.generator_nav_id >= 0, "waypoint generator Barat Laut ditemukan")

	# 4. Keterhubungan penuh AStar3D dari Wowok Spawn (28) ke semua titik lainnya
	var ids := w.nav.get_point_ids()
	var disconnected := 0
	for id in ids:
		var path := w.nav.get_point_path(28, id)
		if path.is_empty():
			disconnected += 1
			push_error("Waypoint %d tidak terhubung dari Wowok spawn (28)" % id)
	_check(disconnected == 0, "seluruh %d waypoint AStar3D saling terhubung utuh" % ids.size())

	# 5. Uji Raycast Fisika pada SETIAP Sisi (Edge) AStar3D saat pintu terbuka (anti-tembok-menghalangi-AI!)
	var space := w.get_world_3d().direct_space_state
	var excl: Array[RID] = [w.player.get_rid(), w.enemy.get_rid()]
	var blocked_edges := 0
	for u in ids:
		var pu := w.nav.get_point_position(u) + Vector3(0, 1.05, 0)
		for v in w.nav.get_point_connections(u):
			if u < v:
				var pv := w.nav.get_point_position(v) + Vector3(0, 1.05, 0)
				var q := PhysicsRayQueryParameters3D.create(pu, pv, 1, excl)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					blocked_edges += 1
					var cname := String((hit.collider as Node).name) if hit.collider is Node else "?"
					var p_name := String((hit.collider as Node).get_parent().name) if (hit.collider is Node and hit.collider.get_parent()) else ""
					push_error("Edge AStar3D %d -> %d terhalang geometri: %s/%s di %s" % [u, v, p_name, cname, hit.position])
	_check(blocked_edges == 0, "0 edge AStar3D terhalang tembok/prop saat pintu terbuka")

	# 6. Uji 8 Pintu Sekuriti (sakelar layer 2 saat buka, blokir layer 1 saat tutup)
	var doors := get_tree().get_nodes_in_group("doors")
	_check(doors.size() == 8, "8 pintu sekuriti ditemukan (aktual=%d)" % doors.size())
	var door_ok := true
	for dn in doors:
		var d := dn as Interactable
		d.set_closed(true)
	for _i in 3:
		await get_tree().physics_frame
	for dn in doors:
		var d := dn as Interactable
		var nrm := d.global_transform.basis.z.normalized()
		var p_a := d.global_position + nrm * 1.2
		var p_b := d.global_position - nrm * 1.2
		var q_closed := PhysicsRayQueryParameters3D.create(p_a, p_b, 1, excl)
		var hit_c := space.intersect_ray(q_closed)
		if hit_c.is_empty() or hit_c.collider != d:
			door_ok = false
			push_error("Pintu %s gagal memblokir raycast saat tertutup" % d.name)
		d.set_closed(false)
	for _i in 3:
		await get_tree().physics_frame
	for dn in doors:
		var d := dn as Interactable
		var sw := d.get_node_or_null("SwitchColFront") as Node3D
		if sw:
			var nrm := d.global_transform.basis.z.normalized()
			var from_sw := sw.global_position + nrm * 0.9
			var to_sw := sw.global_position - nrm * 0.3
			var q_sw := PhysicsRayQueryParameters3D.create(from_sw, to_sw, 3, excl)
			var hit_sw := space.intersect_ray(q_sw)
			if hit_sw.is_empty() or hit_sw.collider != d:
				door_ok = false
				push_error("Sakelar pintu %s tidak terjangkau raycast interaksi saat terbuka" % d.name)
	_check(door_ok, "ke-8 pintu memblokir jalan saat tutup & sakelarnya aktif saat buka")

	# 7. Uji Anti-Eksploitasi 8 Loker (< 2.5m dari waypoint patroli)
	var lockers := get_tree().get_nodes_in_group("lockers")
	_check(lockers.size() == 8, "8 loker ditemukan (aktual=%d)" % lockers.size())
	var lockers_ok := true
	for ln in lockers:
		var l := ln as Node3D
		var best := 1e9
		for pid in w.patrol_ids:
			best = minf(best, w.nav.get_point_position(pid).distance_to(l.global_position))
		if best > 2.5:
			lockers_ok = false
			push_error("Loker %s terlalu jauh dari patroli (%.2fm)" % [l.name, best])
	_check(lockers_ok, "ke-8 loker berjarak < 2.5m dari titik patroli Wowok")

	# 8. Pengukuran Metrik Nyata Karakter & Tanjakan Podium Paripurna (level-design Pattern 1)
	Game.start_night(1)
	w.player.frozen = false
	w.player.global_position = Vector3(0.0, 0.05, -4.0)
	w.player.rotation = Vector3.ZERO
	for _i in 5:
		await get_tree().physics_frame
	var start_pos := w.player.global_position
	Input.action_press(&"move_forward")
	for _i in 60:
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	var walked_dist := start_pos.distance_to(w.player.global_position)
	print("METRIC walk_1s=%.2fm podium_y=%.2fm stamina_max=%.1fs" % [
		walked_dist, w.player.global_position.y, Player.MAX_STAMINA
	])
	_check(walked_dist > 2.5 and w.player.global_position.y >= 0.25, "pemain mulus menaiki ramp Podium Presidium Paripurna")

	# 9. Uji Regresi Pathfinding Meja Ruang Pimpinan Utara (skenario persis screenshot bug nyangkut meja!)
	_check(w.nav_grid_ready, "AStarGrid2D 0.5m selesai dipanggang dari fisika 3D")
	var orig_god := Game.debug_god_mode
	Game.debug_god_mode = true
	w.player.frozen = true
	w.player.global_position = Vector3(-2.2, 0.05, -20.2) # Selatan VIPTable_1 (-2.2, -23.0)
	w.enemy.global_position = Vector3(-2.2, 0.0, -25.6)   # Utara VIPTable_1 (terhalang meja & kursi VIP!)
	w.enemy.rotation.y = PI # Menghadap Selatan ke arah pemain (melihat kepala pemain di atas meja!)
	for _i in 3:
		await get_tree().physics_frame
	_check(
		not w.has_clear_walk_corridor(w.enemy.global_position, w.player.global_position, 0.36),
		"detektor koridor pinggang mendeteksi meja VIPTable_1 menghalangi jalur lurus"
	)
	w.enemy.freeze_ai = false
	w.enemy._set_state(Enemy.St.CHASE)
	for _i in 210: # 3.5 detik simulasi fisika nyata 60 Hz
		await get_tree().physics_frame
	var chase_dist := w.enemy.global_position.distance_to(w.player.global_position)
	print("METRIC desk_chase enemy_pos=%s dist_to_player=%.2fm" % [w.enemy.global_position, chase_dist])
	_check(
		w.enemy.global_position.z > -21.8 and chase_dist < 2.2,
		"Wowok mulus memutari meja VIP Ruang Pimpinan saat St.CHASE tanpa nyangkut (dist=%.2fm)" % chase_dist
	)
	w.enemy.freeze_ai = true
	Game.debug_god_mode = orig_god

	# 10. Uji Taktik Memutar Pintu Sekuriti (Flanking lewat pintu terbuka saat pintu terdekat ditutup!)
	var door_0: Interactable = null
	var door_1: Interactable = null
	for dn in doors:
		var d := dn as Interactable
		if d.door_id == 0:
			door_0 = d
		elif d.door_id == 1:
			door_1 = d
	if door_0 != null and door_1 != null:
		door_0.set_closed(true)
		door_1.set_closed(false)
		for _i in 2:
			await get_tree().physics_frame
		var flank_path := w.find_smooth_path(Vector3(12.0, 0.0, 20.8), Vector3(24.0, 0.0, 20.2))
		var d0_2d := Vector2(door_0.global_position.x, door_0.global_position.z)
		var d1_2d := Vector2(door_1.global_position.x, door_1.global_position.z)
		var min_d0 := 1e9
		var min_d1 := 1e9
		for seg_i in range(flank_path.size() - 1):
			var sa := Vector2(flank_path[seg_i].x, flank_path[seg_i].z)
			var sb := Vector2(flank_path[seg_i + 1].x, flank_path[seg_i + 1].z)
			min_d0 = minf(min_d0, Geometry2D.get_closest_point_to_segment(d0_2d, sa, sb).distance_to(d0_2d))
			min_d1 = minf(min_d1, Geometry2D.get_closest_point_to_segment(d1_2d, sa, sb).distance_to(d1_2d))
		print("METRIC flank_door min_dist_closed_door0=%.2fm min_dist_open_door1=%.2fm" % [min_d0, min_d1])
		_check(
			min_d0 > 2.0 and min_d1 < 1.2,
			"AStarGrid2D otomatis memutar lewat Pintu Utara yang terbuka saat Pintu Barat ditutup"
		)
		door_0.set_closed(false)

	# 11. Uji Kedap Fisika 20 Segmen Dinding Melingkar Rotunda & 4 Bukaan Masuk Bebas Tembok Gaib
	for dn in doors:
		(dn as Interactable).set_closed(false)
	for _i in 2:
		await get_tree().physics_frame
	var rot_walls_ok := true
	var rot_arch_ok := true
	for k in 24:
		var ang := float(k) * (TAU / 24.0)
		var dir_rad := Vector3(cos(ang), 0.0, sin(ang))
		var r_from := dir_rad * 9.8 + Vector3(0.0, 1.5, 0.0)
		var r_to := dir_rad * 13.0 + Vector3(0.0, 1.5, 0.0)
		var rq := PhysicsRayQueryParameters3D.create(r_from, r_to, 1, excl)
		var rhit := space.intersect_ray(rq)
		if k in [0, 6, 12, 18]:
			if not rhit.is_empty():
				rot_arch_ok = false
				push_error("Bukaan Rotunda k=%d terhalang collision gaib: %s" % [k, (rhit.collider as Node).name])
		else:
			var expected_name := "RotSeg_%02d" % k
			if rhit.is_empty() or String((rhit.collider as Node).name) != expected_name:
				rot_walls_ok = false
				var got_n := "KOSONG/BOLONG" if rhit.is_empty() else String((rhit.collider as Node).name)
				push_error("Segmen Rotunda %s meleset/bolong (kena: %s)" % [expected_name, got_n])
	_check(rot_walls_ok, "ke-20 segmen dinding melingkar Rotunda rapat sempurna & selaras antara Mesh dan Collision")
	_check(rot_arch_ok, "ke-4 bukaan pintu/gerbang Rotunda bersih dari collision miring tak terlihat")

	# 12. Uji Masuk/Keluar 8 Loker Bebas Tembus Tembok (arah +basis.z menghadap ke dalam ruangan)
	var locker_exit_ok := true
	for ln in lockers:
		var lk := ln as Interactable
		var out_dir := lk.global_transform.basis.z.normalized()
		var p_start := lk.global_position + out_dir * 0.50 + Vector3(0.0, 0.5, 0.0)
		var p_exit := lk.global_position + out_dir * 1.25 + Vector3(0.0, 0.5, 0.0)
		var lq := PhysicsRayQueryParameters3D.create(p_start, p_exit, 1, [lk.get_rid(), w.player.get_rid(), w.enemy.get_rid()])
		var lhit := space.intersect_ray(lq)
		var exit_cell := w.world_to_grid(lk.global_position + out_dir * 1.35)
		if not lhit.is_empty() or w.nav_grid.is_point_solid(exit_cell):
			locker_exit_ok = false
			push_error("Loker %s menghadap tembok / titik keluarnya solid di %s" % [lk.name, p_exit])
	_check(locker_exit_ok, "ke-8 loker menghadap ruangan terbuka & aman saat keluar tanpa menembus tembok")

	# 13. Uji Zoom Optik Camcorder 1.8x (Klik Kanan / cam_zoom) & Kembalinya FOV
	w.player.frozen = false
	Input.action_press(&"cam_zoom")
	await get_tree().create_timer(0.50).timeout
	var zoomed_fov := w.player.cam.fov
	var zoomed_amt := w.player.zoom_amount
	Input.action_release(&"cam_zoom")
	await get_tree().create_timer(0.75).timeout
	var rest_fov := w.player.cam.fov
	print("METRIC camcorder_zoom zoomed_fov=%.1f zoom_amt=%.2f rest_fov=%.1f" % [zoomed_fov, zoomed_amt, rest_fov])
	_check(zoomed_fov < 46.5 and zoomed_amt > 0.92 and rest_fov > 76.5, "zoom optik camcorder 1.8x & pemulihan FOV berfungsi mulus")

	w.queue_free()
	await get_tree().process_frame
	_completed = true
