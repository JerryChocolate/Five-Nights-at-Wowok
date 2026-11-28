extends Node
## Smoke test headless: godot --headless --path godot res://tests/smoke.tscn
## Gagal (exit 1) bila ada layar tanpa fokus atau mekanik inti game rusak.

var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		push_error("FAIL: " + msg)
		fails += 1

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	run.call_deferred(main)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func focus_ok() -> bool:
	return get_tree().root.gui_get_focus_owner() != null

func run(main: Node) -> void:
	var game: Node = get_tree().root.get_node("Game")
	var orig_unlocked: int = int(game.unlocked_night)
	await frames(3)

	print("== Bus Audio & Menu Utama")
	for bname in [&"Master", &"Music", &"SFX", &"Ambience", &"Voice"]:
		check(AudioServer.get_bus_index(bname) >= 0, "bus audio %s tersedia" % bname)
	check(main.ui.stack.size() == 1, "menu utama di stack")
	check(main.menu_music.playing and not main.music.playing, "codWaw.mp3 aktif di menu utama")
	await frames(2)
	check(focus_ok(), "menu utama punya fokus")

	print("== Pengaturan")
	main._open_settings()
	await frames(3)
	check(main.ui.stack.size() == 2, "pengaturan di-push")
	check(focus_ok(), "pengaturan punya fokus")
	main.ui.pop()
	await frames(3)
	check(focus_ok(), "fokus kembali ke menu setelah pop")

	print("== Mulai Malam 1")
	main.start_night(1)
	await frames(10)
	check(game.state == game.S.PLAYING, "state PLAYING")
	check(main.music.playing and not main.menu_music.playing, "ambiance.mp3 aktif saat bermain")
	var w: World = main.world as World
	check(w != null and w.player != null and w.enemy != null, "dunia, pemain, musuh ada")
	check(w.nav.get_point_count() > 20, "waypoint navigasi dibuat")
	var p: Player = w.player
	var e: Enemy = w.enemy

	print("== Verifikasi Anti-Eksploitasi Loker (Semua 6 Loker Dijangkau Patroli)")
	var lockers := get_tree().get_nodes_in_group("lockers")
	check(lockers.size() == 6, "6 loker ditemukan")
	var all_reachable := true
	for l in lockers:
		var best_d := 1e9
		var l_pos: Vector3 = (l as Node3D).global_position
		for pid in w.patrol_ids:
			var d_wp: float = w.nav.get_point_position(pid).distance_to(l_pos)
			if d_wp < best_d:
				best_d = d_wp
		if best_d > 2.5:
			all_reachable = false
	check(all_reachable, "semua 6 loker berjarak < 2.5m dari waypoint patroli")

	print("== Interaksi Pintu & Beban Daya")
	var doors := get_tree().get_nodes_in_group("doors")
	check(doors.size() == 6, "6 pintu")
	var d: Interactable = doors[0] as Interactable
	d.set_closed(true)
	check(game.closed_doors == 1 and game.usage == 2, "pintu tutup menambah hitungan & beban")
	d.set_closed(false)
	check(game.closed_doors == 0 and game.usage == 1, "pintu buka mengurangi hitungan & beban")

	print("== Sembunyi Loker, Batas Napas, & Tablet CCTV Portabel")
	var locker: Interactable = lockers[0] as Interactable
	p.enter_hide(locker)
	check(game.is_hidden, "pemain tersembunyi")
	game.set_camera(true)
	check(not game.camera_open, "tablet CCTV diblokir saat di dalam loker")
	game.breath = 0.05
	await frames(5)
	check(not game.is_hidden and p.hiding_spot == null, "napas habis memaksa keluar loker")

	var cctv_node: CCTV = main.cctv as CCTV
	game.toggle_camera()
	await frames(3)
	check(cctv_node.visible and game.camera_open, "tablet CCTV portabel tampil")
	check(focus_ok(), "CCTV punya fokus")
	e.global_position = Vector3(-0.5, 0.0, 7.0)
	cctv_node._select(5, false)
	check(cctv_node.alert_label.text != "", "CCTV mendeteksi keberadaan Wowok di ruangan")
	game.toggle_camera()
	await frames(2)
	check(not cctv_node.visible, "tablet CCTV tertutup kembali")

	print("== Pause")
	main._show_pause()
	await frames(3)
	check(get_tree().paused, "tree paused")
	check(focus_ok(), "pause punya fokus")
	main._resume()
	await frames(2)
	check(not get_tree().paused, "resume melepas pause")

	print("== Trauma Camera Shake")
	game.add_trauma(0.5)
	await frames(2)
	check(p.trauma > 0.0, "trauma diterima kamera pemain")

	print("== Simulasi Musuh (Keluar dari IDLE)")
	e.timer = 0.0
	for i in 300:
		await get_tree().physics_frame
	check(e.st != Enemy.St.IDLE, "musuh keluar dari IDLE (state=%d)" % e.st)

	print("== Tertangkap & Jumpscare Hibrida")
	e.global_position = p.global_position + Vector3(0.5, 0, 0)
	e.st = Enemy.St.CHASE
	game.flashlight_on = true
	for i in 30:
		await get_tree().physics_frame
	check(game.state == game.S.DEAD, "pemain tertangkap -> DEAD")
	await get_tree().create_timer(2.1).timeout
	check(main.ui.stack.size() == 1 and focus_ok(), "layar game over punya fokus")

	print("== Menang Malam 5 -> Buka Secret Night 6")
	main.start_night(5)
	await frames(5)
	game.elapsed = game.NIGHT_LENGTH - 0.1
	await get_tree().create_timer(0.35).timeout
	check(game.state == game.S.WON, "jam 6 pagi -> WON")
	await frames(3)
	check(main.ui.stack.size() == 1 and focus_ok(), "layar menang punya fokus")
	check(game.unlocked_night == game.SECRET_NIGHT, "Secret Night 6 terbuka setelah tamat Malam 5")

	print("== Daya Habis, Sabotase, & Pemulihan Generator R3")
	main.start_night(6)
	await frames(5)
	var w6: World = main.world as World
	game.sabotage_generator()
	check(game.generator_sabotaged, "sabotase generator terekam")
	game.power = 0.001
	await get_tree().create_timer(0.3).timeout
	check(game.power_is_out, "daya habis terdeteksi")
	var gens := get_tree().get_nodes_in_group("generators")
	check(gens.size() == 1, "unit Generator R3 ditemukan")
	(gens[0] as Interactable).interact(w6.player)
	await frames(2)
	check(not game.power_is_out and not game.generator_sabotaged and game.power >= 34.0, "Generator R3 memulihkan listrik & memperbaiki sabotase")

	# Kembalikan progres simpanan awal agar tes tidak mengotori save pengguna
	game.unlocked_night = orig_unlocked
	game.save_settings()
	await frames(2)

	print("\nHASIL: ", "LULUS" if fails == 0 else "%d GAGAL" % fails)
	get_tree().quit(1 if fails > 0 else 0)
