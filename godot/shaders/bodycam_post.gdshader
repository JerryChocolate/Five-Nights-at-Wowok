shader_type canvas_item;

// Lensa Analog Found-Footage / VHS Sinematik (Gaya Kane Pixels / Hi8 Camcorder 1998)
// Hemat GPU (maks 5 pembacaan tekstur + hardware mipmap LOD):
// 1. Tengah layar JERNIH & TAJAM dengan kontras S-curve pekat (mudah membaca ruangan gelap).
// 2. Pinggir lensa wide-angle optik asli: aberasi kromatik radial, keburaman tepi kaca, & halation hangat di lampu terang.
// 3. Autofocus hunt mulus saat zoom optik camcorder (tanpa Gaussian loop berat).
// 4. Gangguan pita magnetik VHS (head-switching bar bawah, sinkronisasi horizontal, & pita tracking)
//    tenang saat AMAN, dan menggila secara organik saat Wowok dekat / mengejar!

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float zoom_amount : hint_range(0.0, 1.0) = 0.0;
uniform float focus_blur : hint_range(0.0, 1.0) = 0.0;
uniform float base_distortion : hint_range(0.0, 0.35) = 0.115;
uniform float base_aberration : hint_range(0.0, 0.02) = 0.0042;
uniform float vignette_strength : hint_range(0.0, 1.2) = 0.44;
uniform float scanline_strength : hint_range(0.0, 0.35) = 0.048;
uniform float vhs_bleed : hint_range(0.0, 0.02) = 0.0024;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec2 barrel_uv(vec2 uv, float k) {
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	return 0.5 + c * (1.0 + k * r2) * (1.0 - k * 0.245);
}

void fragment() {
	float t = mod(TIME, 180.0);
	float pulse = sin(TIME * 7.2) * 0.5 + 0.5;

	// Saat zoom optik masuk (telephoto), distorsi barrel lensa wide sedikit merata seperti lensa camcorder asli
	float zoom_flat = mix(1.0, 0.52, zoom_amount);
	float dyn_k = base_distortion * zoom_flat + intensity * (0.055 + 0.022 * pulse);
	float dyn_ca = base_aberration * mix(1.0, 1.35, zoom_amount) + intensity * (0.0065 + 0.0025 * pulse);

	vec2 centered = SCREEN_UV - 0.5;
	vec2 aspect_c = centered * vec2(1.18, 1.0);
	float r = length(aspect_c);
	float r2 = dot(centered, centered);

	vec2 uv_g = barrel_uv(SCREEN_UV, dyn_k);

	// 1. VHS Head-Switching Noise tipis di bibir paling bawah frame (khas rekaman kaset Hi8/VHS asli)
	float head_switch = smoothstep(0.955 - intensity * 0.025, 0.995, uv_g.y);
	float hs_shift = head_switch * (0.0045 + intensity * 0.012) * sin(t * 43.0 + uv_g.y * 90.0);

	// 2. Gangguan Pita Tracking & Glitch Horizontal — HANYA aktif saat tegang / Wowok dekat (intensity > 0.05)
	float row_id = floor(uv_g.y * 300.0);
	float line_rng = hash11(row_id + floor(t * 25.0) * 19.7) - 0.5;
	float scroll_y = fract(uv_g.y + t * (0.14 + intensity * 0.22));
	float track_band = smoothstep(0.055, 0.0, abs(scroll_y - 0.5)) * smoothstep(0.06, 0.45, intensity);
	float tear_gate = step(0.996 - intensity * 0.065, hash11(floor(t * 15.0) * 7.3 + floor(uv_g.y * 16.0))) * smoothstep(0.04, 0.35, intensity);

	// Saat AMAN hanya ada micro-flutter pita analog super halus (0.00022) agar gambar tetap tajam
	float h_jitter = line_rng * (0.00022 + track_band * (0.008 + intensity * 0.014) + tear_gate * (0.009 + intensity * 0.018)) + hs_shift;
	uv_g.x += h_jitter;

	// 3. Aberasi Kromatik & Keburaman Tepi Optik (Tajam di tengah layar, organik di pinggir kaca lensa)
	float edge_mask = smoothstep(0.16, 0.82, r);
	float af_lod = focus_blur * 2.15 + zoom_amount * edge_mask * 0.55 + intensity * track_band * 1.25;
	float chroma_lod = 0.85 + edge_mask * 0.85 + focus_blur * 1.8;

	vec2 ca_vec = centered * dyn_ca * (0.18 + r2 * 3.8) + vec2(vhs_bleed * (0.35 + edge_mask * 0.85 + intensity * 1.6), 0.0);
	vec2 uv_r = clamp(uv_g + ca_vec, vec2(0.001), vec2(0.999));
	vec2 uv_b = clamp(uv_g - ca_vec, vec2(0.001), vec2(0.999));
	uv_g = clamp(uv_g, vec2(0.001), vec2(0.999));

	vec3 sharp_center = textureLod(screen_tex, uv_g, af_lod).rgb;
	float chr_r = textureLod(screen_tex, uv_r, chroma_lod).r;
	float chr_b = textureLod(screen_tex, uv_b, chroma_lod).b;
	vec3 glow_tap = textureLod(screen_tex, uv_g, 2.35).rgb;

	// Pertahankan ketajaman penuh di pusat pandangan; campurkan karakter pita kromatik di tepi & saat dikejar
	float luma = dot(sharp_center, vec3(0.299, 0.587, 0.114));
	vec3 analog_rgb = vec3(chr_r, sharp_center.g, chr_b);
	float chroma_mix = clamp(0.24 + edge_mask * 0.62 + intensity * 0.25 + focus_blur * 0.35, 0.0, 0.94);
	vec3 col = mix(sharp_center, analog_rgb, chroma_mix);

	// Micro-sharpening tipis di tengah lensa camcorder CCD (agar objek di ruang gelap tegas terbaca)
	vec3 detail_boost = sharp_center - glow_tap;
	col += detail_boost * (0.16 * (1.0 - edge_mask) * (1.0 - focus_blur));

	// 4. Analog Halation / Phosphor Bloom lembut khusus di sumber lampu terang & pantulan senter
	float glow_luma = dot(glow_tap, vec3(0.299, 0.587, 0.114));
	float halation_mask = smoothstep(0.46, 0.95, glow_luma);
	col += glow_tap * vec3(1.08, 0.88, 0.68) * halation_mask * (0.22 + zoom_amount * 0.08);

	// 5. Color Grading VHS Sinematik Kontras Pekat (Hitam dalam tidak kusam, highlight hangat sedikit organik)
	vec3 s_curve = col * col * (3.0 - 2.0 * col);
	col = mix(col, s_curve, 0.28);
	float post_luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(post_luma), 0.06);
	col *= mix(vec3(0.97, 0.99, 1.03), vec3(1.04, 1.00, 0.92), smoothstep(0.08, 0.65, post_luma));

	// Bintik putih dropout kaset HANYA pada pita glitch saat dikejar / ancaman aktif
	float dropout = step(0.92 - intensity * 0.10, hash12(vec2(floor(FRAGCOORD.x * 0.25), row_id + floor(t * 60.0)))) * (track_band + head_switch * 0.35 * intensity);
	col += vec3(0.28, 0.27, 0.24) * dropout * (0.35 + intensity * 0.85);

	// Scanline 480i super halus (terlihat terutama di area midtone/pinggir, tidak menggelapkan ruangan gelap)
	float scan = sin(uv_g.y * 480.0 * 3.14159265) * 0.5 + 0.5;
	col *= 1.0 - scanline_strength * (0.35 + 0.65 * scan) * smoothstep(0.02, 0.35, post_luma);

	// Denyut stres merah gelap sinematik di tepi lensa saat dikejar Wowok
	float vig = smoothstep(0.32 - zoom_amount * 0.05, 0.86, r);
	col = mix(col, col * vec3(1.12, 0.22, 0.18), intensity * vig * 0.56);

	// Vignette optik lensa camcorder + sudut bingkai tabung halus
	float bezel = 1.0 - smoothstep(0.78, 0.90, length(pow(abs(centered * 2.0), vec2(3.6))));
	float eff_vig = vignette_strength + zoom_amount * 0.10 + intensity * 0.20;
	float lens_dark = 1.0 - vig * eff_vig;
	col *= clamp(lens_dark * bezel, 0.0, 1.0);

	// Sensor Low-Light CCD Grain (lebih terasa halus di bayangan gelap untuk mencegah color banding, tetap jernih di terang)
	float grain = hash12(FRAGCOORD.xy + vec2(t * 71.7, t * 37.3)) - 0.5;
	float shadow_weight = mix(1.25, 0.55, smoothstep(0.02, 0.45, post_luma));
	col += grain * (0.024 * shadow_weight + intensity * 0.028);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
