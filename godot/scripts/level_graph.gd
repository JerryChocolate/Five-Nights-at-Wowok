extends RefCounted
class_name LevelGraph
## Data grafik ruangan & kurva ketegangan (beats) Gedung Sidang Paripurna (70m x 60m)
## sesuai workflow `level-design`: ketercapaian kritis, anti-soft-lock, dan pacing sawtooth.

const ROOMS := {
	"pos_sekuriti": {
		"exits": [
			{"to": "lobi_garuda"},
			{"to": "koridor_timur"},
		],
		"grants": "cctv_access",
	},
	"lobi_garuda": {
		"exits": [
			{"to": "pos_sekuriti"},
			{"to": "koridor_cincin"},
			{"to": "ruang_sidang_paripurna"},
			{"to": "gudang_barat_daya"},
		],
	},
	"koridor_timur": {
		"exits": [
			{"to": "pos_sekuriti"},
			{"to": "koridor_cincin"},
			{"to": "fraksi_timur"},
			{"to": "lounge_timur_laut"},
		],
	},
	"fraksi_timur": {
		"exits": [{"to": "koridor_timur"}],
	},
	"lounge_timur_laut": {
		"exits": [{"to": "koridor_timur"}],
	},
	"koridor_cincin": {
		"exits": [
			{"to": "lobi_garuda"},
			{"to": "koridor_timur"},
			{"to": "koridor_barat"},
			{"to": "ruang_sidang_paripurna"},
			{"to": "pimpinan_utara"},
		],
	},
	"ruang_sidang_paripurna": {
		"exits": [
			{"to": "lobi_garuda"},
			{"to": "koridor_cincin"},
			{"to": "pimpinan_utara"},
		],
	},
	"pimpinan_utara": {
		"exits": [
			{"to": "koridor_cincin"},
			{"to": "ruang_sidang_paripurna"},
		],
	},
	"gudang_barat_daya": {
		"exits": [
			{"to": "lobi_garuda"},
			{"to": "koridor_barat"},
		],
		"grants": "spare_battery",
	},
	"koridor_barat": {
		"exits": [
			{"to": "koridor_cincin"},
			{"to": "gudang_barat_daya"},
			{"to": "fraksi_barat"},
			{"to": "server_generator_nw", "needs": "cctv_access"},
		],
	},
	"fraksi_barat": {
		"exits": [{"to": "koridor_barat"}],
	},
	"server_generator_nw": {
		"exits": [{"to": "koridor_barat"}],
		"grants": "emergency_power",
	},
}

const BEATS := [
	{"room": "pos_sekuriti",           "type": "teach",  "intensity": 0.15},
	{"room": "lobi_garuda",            "type": "combat", "intensity": 0.52},
	{"room": "gudang_barat_daya",      "type": "rest",   "intensity": 0.22},
	{"room": "ruang_sidang_paripurna", "type": "combat", "intensity": 0.82},
	{"room": "fraksi_barat",           "type": "rest",   "intensity": 0.25},
	{"room": "server_generator_nw",    "type": "climax", "intensity": 0.96},
]


static func goal_reachable(rooms: Dictionary, start: String, goal: String) -> bool:
	var pending: Array[Dictionary] = [{"room": start, "keys": {}}]
	var visited := {}
	while not pending.is_empty():
		var state: Dictionary = pending.pop_back()
		var room: String = state["room"]
		var have: Dictionary = state["keys"].duplicate()
		var info: Dictionary = rooms.get(room, {})
		var grant = info.get("grants")
		if grant != null:
			have[grant] = true
		var names := PackedStringArray(have.keys())
		names.sort()
		var id := room + "|" + ",".join(names)
		if visited.has(id):
			continue
		visited[id] = true
		if room == goal:
			return true
		for exit in info.get("exits", []):
			var open: bool = not exit.has("needs") or have.has(exit["needs"])
			if open:
				pending.append({"room": exit["to"], "keys": have})
	return false


static func pacing_problems(beats: Array, high := 0.7, max_high_run := 2) -> PackedStringArray:
	var problems := PackedStringArray()
	var run := 0
	for i in beats.size():
		var beat: Dictionary = beats[i]
		run = run + 1 if float(beat["intensity"]) >= high else 0
		if run > max_high_run:
			problems.append("%s: %d high-intensity beats in a row" % [beat["room"], run])
		if beat["type"] == "climax" and (i == 0 or beats[i - 1]["type"] != "rest"):
			problems.append("%s: no rest beat right before the climax" % beat["room"])
	if not beats.is_empty() and beats[0]["type"] != "teach":
		problems.append("%s: the level does not open with a teach beat" % beats[0]["room"])
	return problems
