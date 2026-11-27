extends Node
## Ambil screenshot untuk pemeriksaan visual seluruh model 3D baru (butuh display):
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

	# 2. Kantor R1: meja kerja, kursi, rak arsip, & terminal CRT 3D
	main.start_night(1)
	await get_tree().create_timer(3.4).timeout
	var p: Player = main.world.player
	var e: Enemy = main.world.enemy
	e.timer = 9999.0
	p.global_position = Vector3(-10.0, 0.05, -8.3)
	p.rotation.y = 0.0
	p.head.rotation.x = -0.08
	p._set_flashlight(true)
	await get_tree().create_timer(0.4).timeout
	await shot("2_office_3d")

	# 3. Lorong tengah: pintu keamanan 3D, senter + revolver 3D di tangan, & sosok businessman Wowok
	var doors := get_tree().get_nodes_in_group("doors")
	if doors.size() > 1:
		(doors[1] as Interactable).set_closed(true)
	p._arm()
	if p.egg_music.playing:
		p.egg_music.stop()
	p.global_position = Vector3(-5.8, 0.05, -0.25)
	p.rotation.y = -PI / 2.0
	p.head.rotation.x = 0.0
	e.global_position = Vector3(-2.0, 0.0, 0.15)
	e.rotation.y = PI / 2.0
	await get_tree().create_timer(0.6).timeout
	await shot("3_hall_wowok_weapons")
	if doors.size() > 1:
		(doors[1] as Interactable).set_closed(false)

	# 4. Ruang Server R3: rak server 3D bertekstur, loker 3D, baterai 3D, & generator 3D
	p.global_position = Vector3(9.6, 0.05, -7.6)
	p.rotation.y = -PI / 2.0
	p.head.rotation.x = -0.06
	await get_tree().create_timer(0.5).timeout
	await shot("4_server_generator_3d")

	# 5. Ruang Istirahat R4: sofa tua, vending machine menyala, meja, & baterai di atas meja
	p.global_position = Vector3(-8.4, 0.05, 4.2)
	p.rotation.y = 2.75
	p.head.rotation.x = -0.08
	await get_tree().create_timer(0.5).timeout
	await shot("5_breakroom_vending_sofa")

	# 6. Tablet CCTV Portabel: CAM 6 Lobi Utama (meja resepsionis, sofa, & ADA WOWOK!)
	e.global_position = Vector3(-0.5, 0.0, 6.3)
	e.rotation.y = 0.25
	game.door_states[0] = true
	main.cctv._on_door_state(0, true)
	main.cctv.idx = 5
	game.set_camera(true)
	await get_tree().create_timer(0.6).timeout
	await shot("6_cctv_lobby_3d")
	game.set_camera(false)

	game.unlocked_night = orig_unlocked
	game.save_settings()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
