extends Node
## Benchmark waktu frame nyata (tanpa VSync) & jumlah draw call per Preset Grafis
## sesuai workflow `performance-optimization`:
## godot --disable-vsync --max-fps 0 --path godot res://tests/bench_perf.tscn

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	get_tree().root.add_child.call_deferred(load("res://scenes/main.tscn").instantiate())
	run.call_deferred()


func run() -> void:
	for _i in 20:
		await get_tree().process_frame
	var main: Node = get_tree().root.get_child(get_tree().root.get_child_count() - 1)
	var orig_preset: int = Game.graphics_preset

	main.start_night(1)
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.world.player
	var e: Enemy = main.world.enemy
	e.freeze_ai = true
	# Posisi terberat: menghadap ke dalam Ruang Sidang Paripurna + Koridor Cincin + Taman Kaca + Light Shafts
	p.global_position = Vector3(-13.8, 0.05, 3.8)
	p.rotation.y = -0.72
	p._set_flashlight(true)

	var labels := ["RENDAH (75%)", "SEIMBANG (90%)", "TINGGI (100%)"]
	for preset in [0, 1, 2]:
		Game.set_graphics_preset(preset)
		for _w in 45:
			await get_tree().process_frame
		var ms := PackedFloat64Array()
		var last := Time.get_ticks_usec()
		for _f in 140:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			ms.append(float(now - last) / 1000.0)
			last = now
		ms.sort()
		var avg := 0.0
		for v in ms:
			avg += v / float(ms.size())
		var p95 := ms[int(float(ms.size()) * 0.95)]
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		print("BENCH [%s] avg=%.2fms (%.0f FPS) p95=%.2fms draws=%d objects=%d prims=%d" % [
			labels[preset], avg, 1000.0 / maxf(avg, 0.01), p95, draws, objs, prims
		])

	Game.set_graphics_preset(orig_preset)
	await get_tree().process_frame
	get_tree().quit(0)
