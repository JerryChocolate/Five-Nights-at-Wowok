extends Node
## Ambil screenshot pemeriksaan visual Gedung Sidang Paripurna (butuh display):
## godot --path godot res://tests/shots.tscn

func _ready() -> void:
	get_tree().root.add_child.call_deferred(load("res://scenes/main.tscn").instantiate())
	run.call_deferred()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out_dir := ProjectSettings.globalize_path("res://tests/shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png("res://tests/shots/%s.png" % name)
	print("saved ", name, " ", img.get_size())

func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var main: Node = get_tree().root.get_child(get_tree().root.get_child_count() - 1)
	var game: Node = get_tree().root.get_node("Game")
	var orig_unlocked: int = int(game.unlocked_night)

	# 1. Menu Utama CRT
	game.unlocked_night = 6
	main.show_main_menu()
	for i in 6:
		await get_tree().process_frame
	await shot("1_menu")

	# 2. Ruang Sidang Paripurna (Kubah Tengah, Kursi Amphitheater, Podium Garuda & Bendera)
	main.start_night(1)
	await get_tree().create_timer(3.2).timeout
	var p: Player = main.world.player
	var e: Enemy = main.world.enemy
	e.freeze_ai = true
	p.global_position = Vector3(0.0, 0.05, 8.8)
	p.rotation.y = 0.0
	p.head.rotation.x = 0.04
	p._set_flashlight(true)
	await get_tree().create_timer(0.4).timeout
	await shot("2_paripurna_rotunda_3d")

	# 3. Koridor Cincin & Taman Kaca + Sosok Wowok
	p.global_position = Vector3(-9.5, 0.05, -14.0)
	p.rotation.y = -PI / 2.0
	p.head.rotation.x = 0.0
	e.global_position = Vector3(-1.5, 0.0, -14.0)
	e.rotation.y = -PI / 2.0
	await get_tree().create_timer(0.5).timeout
	await shot("3_ring_corridor_wowok")

	# 4. Pos Sekuriti Tenggara (2 Pintu Listrik FNAF + Meja Monitor)
	var doors := get_tree().get_nodes_in_group("doors")
	if doors.size() > 0:
		(doors[0] as Interactable).set_closed(true)
	p.global_position = Vector3(26.3, 0.05, 19.2)
	p.rotation.y = PI
	p.head.rotation.x = -0.06
	await get_tree().create_timer(0.5).timeout
	await shot("4_pos_sekuriti_se")
	if doors.size() > 0:
		(doors[0] as Interactable).set_closed(false)

	# 5. Ruang Server & Generator Barat Laut
	p.global_position = Vector3(-20.2, 0.05, -19.2)
	p.rotation.y = PI / 2.0
	p.head.rotation.x = -0.05
	await get_tree().create_timer(0.5).timeout
	await shot("5_server_generator_nw")

	# 6. Tablet CCTV + Mini-Map Blueprint Vektor Paripurna (CAM 1 Sidang + ADA WOWOK!)
	e.global_position = Vector3(0.0, 0.35, -5.8)
	e.rotation.y = 0.0
	game.door_states[0] = true
	main.cctv._on_door_state(0, true)
	main.cctv.idx = 0
	game.set_camera(true)
	await get_tree().create_timer(0.6).timeout
	await shot("6_cctv_paripurna_minimap")
	game.set_camera(false)

	# 7. Sudut Koridor Barat (lokasi persis bug refleksi tembus dinding pada screenshot pengguna) + Marmer & Bodycam!
	p._set_flashlight(false)
	p._arm()
	if p.egg_music.playing:
		p.egg_music.stop()
	p.global_position = Vector3(-18.6, 0.05, 5.2)
	p.rotation.y = -0.22
	p.head.rotation.x = -0.04
	await get_tree().create_timer(0.5).timeout
	await shot("7_west_corridor_no_bleed_bodycam")

	# 9. Ruang Pimpinan Utara — Wowok memutari meja VIP saat DIKEJAR + Efek Kamera Jadul VHS 1998!
	game.debug_god_mode = true
	p._set_flashlight(true)
	p.global_position = Vector3(-2.2, 0.05, -19.8)
	p.rotation.y = 0.0
	p.head.rotation.x = -0.05
	e.global_position = Vector3(-2.2, 0.0, -25.6)
	e.rotation.y = PI
	e.freeze_ai = false
	e._set_state(Enemy.St.CHASE)
	await get_tree().create_timer(1.55).timeout
	e.freeze_ai = true
	await shot("9_vintage_vhs_camcorder_chase_desk")
	game.debug_god_mode = false

	# 8. Menu Pengaturan dengan opsi Preset Grafis baru
	main.show_main_menu()
	await get_tree().create_timer(0.2).timeout
	main._open_settings()
	await get_tree().create_timer(0.3).timeout
	await shot("8_settings_graphics_presets")

	game.unlocked_night = orig_unlocked
	game.save_settings()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
