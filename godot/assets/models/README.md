# Panduan Pemasangan Model 3D Gratis (`godot/assets/models/`)

Folder ini disiapkan untuk menampung aset model 3D gratis (format **`.glb`** atau **`.gltf`** paling direkomendasikan di Godot 4.7 karena material & tekstur langsung terbaca otomatis).

## Spesifikasi Teknis Aset yang Cocok
- **Format**: `.glb` (prioritas utama) atau `.gltf` + tekstur.
- **Skala Dunia**: `1 unit = 1 meter` (tinggi pintu `2.6 m`, tinggi plafon `3.2 m`, tinggi karakter `~1.85 m`).
- **Orientasi Godot**: `-Z` menghadap depan, `+Y` ke atas, titik tumpu (*pivot*) di bagian alas/kaki (`y = 0`) untuk karakter & perabot lantai.
- **Gaya Visual**: Low-poly / PSX retro horror atau PBR industrial grimy.

## Cara Memasang Lewat Godot Editor (Tanpa Ubah Kode)
1. Taruh file `.glb` ke dalam folder `godot/assets/models/`.
2. **Untuk Pintu, Loker, Terminal CCTV, Baterai, atau Generator**:
   - Buka scene terkait di `res://scenes/props/` (mis. `locker.tscn` atau `generator.tscn`), **atau** pilih instance-nya langsung di `res://scenes/world.tscn`.
   - Di panel **Inspector** → bagian **Interactable**, tarik file `.glb` ke slot **`Custom Model`**. Mesh kotak bawaan otomatis disembunyikan saat game berjalan.
3. **Untuk Sosok Musuh (Wowok)**:
   - Buka `res://scenes/enemy.tscn` → di **Inspector** → **Enemy Config & Custom Model**, isi **`Custom Body Model`** dengan model karakter/jas `.glb`. Centang **`Hide Photo Face When Custom`** bila model sudah memiliki kepala sendiri, atau biarkan tidak dicentang untuk tetap mempertahankan wajah ikonik `prabowo.jpg`.
4. **Untuk Perabot Ruangan (`R1_Kantor` s.d. `R6_Keamanan`)**:
   - Buka `res://scenes/world.tscn`, bentangkan node `Rooms/<NamaRuangan>`, lalu tarik `.glb` meja, kursi, rak server, sofa, atau lampu plafon langsung ke viewport 3D.
