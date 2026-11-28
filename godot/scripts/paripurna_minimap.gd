extends Control
class_name ParipurnaMinimap
## Menggambar Blueprint Vektor CRT Gedung Sidang Paripurna (rotunda bundar + amphitheater +
## 4 planter segitiga + sayap gedung + tangga Garuda + status real-time 8 pintu listrik).

const CX := 250.0
const CY := 180.0
const SX := 5.8
const SZ := 4.8

# (door_id, world_x, world_z, horizontal_bar)
const DOOR_MARKERS := [
	[0, 16.5, 20.8, false],   # Pintu Barat Sekuriti
	[1, 19.8, 14.5, true],    # Pintu Utara Sekuriti
	[2, 0.0, 11.5, true],     # Pintu Selatan Paripurna
	[3, 0.0, -11.5, true],    # Pintu Utara Paripurna
	[4, 0.0, -16.5, true],    # Pintu Ruang Pimpinan
	[5, -19.8, -14.5, true],  # Pintu Ruang Server & Gen
	[6, -19.8, 14.5, true],   # Pintu Gudang Barat Daya
	[7, 19.8, -14.5, true],   # Pintu Lounge Timur Laut
]

var door_closed: Dictionary[int, bool] = {}


func set_door_state(door_id: int, closed_val: bool) -> void:
	door_closed[door_id] = closed_val
	queue_redraw()


func _pt(wx: float, wz: float) -> Vector2:
	return Vector2(CX + wx * SX, CY + wz * SZ)


func _rect_w(x0: float, z0: float, x1: float, z1: float) -> Rect2:
	var p0 := _pt(x0, z0)
	var p1 := _pt(x1, z1)
	return Rect2(p0, p1 - p0)


func _draw() -> void:
	var c_bg_room := Color(0.04, 0.19, 0.08, 0.52)
	var c_rotunda_fill := Color(0.06, 0.25, 0.11, 0.62)
	var c_sec_fill := Color(0.08, 0.28, 0.34, 0.58)
	var c_srv_fill := Color(0.24, 0.20, 0.05, 0.52)
	var c_line := Color(0.36, 0.96, 0.56, 0.88)
	var c_dim := Color(0.22, 0.62, 0.36, 0.52)
	var c_gold := Color(0.95, 0.82, 0.32, 0.85)

	# 1. Siluet Luar Parkiran Barat & Tangga Garuda Selatan (tipis bergaya blueprint)
	draw_rect(_rect_w(-43.0, -14.0, -36.5, 14.0), Color(0.02, 0.10, 0.04, 0.4), true)
	draw_rect(_rect_w(-43.0, -14.0, -36.5, 14.0), c_dim, false, 1.2)
	for bi in 5:
		var bz := -11.0 + float(bi) * 5.5
		draw_line(_pt(-42.5, bz), _pt(-39.0, bz), c_dim, 1.0)

	# Tangga Garuda Selatan
	for si in 3:
		var sz := 30.2 + float(si) * 1.4
		draw_line(_pt(-8.0 - si, sz), _pt(8.0 + si, sz), c_gold, 1.4)

	# 2. Isi Blok Gedung Paripurna (Stepped Cross Silhouette)
	draw_rect(_rect_w(-35.0, -25.0, 35.0, 25.0), c_bg_room, true)
	draw_rect(_rect_w(-14.0, -30.0, 14.0, -25.0), c_bg_room, true)
	draw_rect(_rect_w(-14.0, 25.0, 14.0, 30.0), c_bg_room, true)

	# Highlight Ruang Server NW & Pos Sekuriti SE
	draw_rect(_rect_w(-35.0, -25.0, -16.5, -14.5), c_srv_fill, true)
	draw_rect(_rect_w(16.5, 14.5, 35.0, 25.0), c_sec_fill, true)

	# 3. Garis Dinding Perimeter Stepped Gedung
	var perim := PackedVector2Array([
		_pt(-14.0, -30.0), _pt(14.0, -30.0), _pt(14.0, -25.0), _pt(35.0, -25.0),
		_pt(35.0, 25.0), _pt(14.0, 25.0), _pt(14.0, 30.0), _pt(-14.0, 30.0),
		_pt(-14.0, 25.0), _pt(-35.0, 25.0), _pt(-35.0, -25.0), _pt(-14.0, -25.0),
		_pt(-14.0, -30.0),
	])
	draw_polyline(perim, c_line, 2.2)

	# 4. Sekat Koridor Cincin & Sayap
	draw_rect(_rect_w(-16.5, -16.5, 16.5, 16.5), c_line, false, 1.6)
	draw_line(_pt(-35.0, -14.5), _pt(-16.5, -14.5), c_line, 1.5)
	draw_line(_pt(-35.0, 14.5), _pt(-16.5, 14.5), c_line, 1.5)
	draw_line(_pt(16.5, -14.5), _pt(35.0, -14.5), c_line, 1.5)
	draw_line(_pt(16.5, 14.5), _pt(35.0, 14.5), c_line, 1.5)
	draw_line(_pt(-22.5, -14.5), _pt(-22.5, 14.5), c_dim, 1.2)
	draw_line(_pt(22.5, -14.5), _pt(22.5, 14.5), c_dim, 1.2)
	draw_line(_pt(-35.0, -3.2), _pt(-22.5, -3.2), c_dim, 1.2)
	draw_line(_pt(-35.0, 3.2), _pt(-22.5, 3.2), c_dim, 1.2)
	draw_line(_pt(22.5, -3.2), _pt(35.0, -3.2), c_dim, 1.2)
	draw_line(_pt(22.5, 3.2), _pt(35.0, 3.2), c_dim, 1.2)

	# 5. 4 Planter Segitiga/Berlian di Sudut Koridor Cincin
	for corner in [Vector2(-12.3, -12.3), Vector2(12.3, -12.3), Vector2(-12.3, 12.3), Vector2(12.3, 12.3)]:
		var poly := PackedVector2Array([
			_pt(corner.x, corner.y - 2.1),
			_pt(corner.x + 2.1, corner.y),
			_pt(corner.x, corner.y + 2.1),
			_pt(corner.x - 2.1, corner.y),
			_pt(corner.x, corner.y - 2.1),
		])
		draw_polyline(poly, c_dim, 1.3)

	# 6. Rotunda Ruang Sidang Paripurna Bundar + Kursi Amphitheater Melengkung
	var rot_r := 11.5 * minf(SX, SZ)
	draw_circle(Vector2(CX, CY), rot_r, c_rotunda_fill)
	draw_arc(Vector2(CX, CY), rot_r, 0.0, TAU, 48, c_line, 2.4)
	# Podium Utara
	draw_rect(_rect_w(-4.8, -9.6, 4.8, -6.4), c_gold, false, 1.6)
	# Busur Kursi Amphitheater Kiri & Kanan
	for rr in [20.0, 29.0, 38.0]:
		draw_arc(Vector2(CX, CY - 8.0), rr, deg_to_rad(22.0), deg_to_rad(78.0), 14, c_dim, 1.5)
		draw_arc(Vector2(CX, CY - 8.0), rr, deg_to_rad(102.0), deg_to_rad(158.0), 14, c_dim, 1.5)

	# 7. Penanda POS SEKURITI (Titik Biru Terang) & GENERATOR NW (Titik Kuning)
	var p_sec := _pt(26.5, 20.5)
	draw_circle(p_sec, 5.5, Color(0.35, 0.88, 1.0, 0.95))
	var p_gen := _pt(-31.0, -21.5)
	draw_circle(p_gen, 5.0, c_gold)

	# 8. Indikator Live 8 Pintu Listrik (Hijau = Terbuka, Merah Menyala = Tertutup)
	for dm in DOOR_MARKERS:
		var did: int = dm[0]
		var dp := _pt(float(dm[1]), float(dm[2]))
		var horiz: bool = dm[3]
		var is_closed: bool = door_closed.get(did, false)
		var dcol := Color(1.0, 0.20, 0.18, 1.0) if is_closed else Color(0.22, 0.98, 0.45, 0.95)
		var sz_rect := Vector2(18.0, 5.0) if horiz else Vector2(5.0, 18.0)
		draw_rect(Rect2(dp - sz_rect * 0.5, sz_rect), dcol, true)
