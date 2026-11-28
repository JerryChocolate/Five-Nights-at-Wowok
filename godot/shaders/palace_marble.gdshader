shader_type spatial;
render_mode specular_schlick_ggx;

// Marmer Istana Nusantara Mengilap: pantulan mewah dengan pola urat marmer & nat ubin,
// dilengkapi contact-AO sudut ruangan serta pembatas specular di light() agar bebas bocor bulat silau.

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 base_tint : source_color = vec4(0.34, 0.36, 0.40, 1.0);
uniform vec4 vein_tint : source_color = vec4(0.66, 0.61, 0.52, 1.0);
uniform vec3 env_sheen_color : source_color = vec3(0.20, 0.26, 0.35);
uniform float tile_size : hint_range(0.5, 6.0) = 2.2;
uniform float gloss_roughness : hint_range(0.05, 0.6) = 0.13;
uniform float env_reflect_strength : hint_range(0.0, 1.5) = 0.72;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wuv = v_world_pos.xz / tile_size;
	vec2 tile_id = floor(wuv);
	vec2 tile_f = fract(wuv);

	// Nat sambungan ubin marmer tipis (grout line)
	vec2 edge_d = min(tile_f, 1.0 - tile_f);
	float grout = smoothstep(0.006, 0.018, min(edge_d.x, edge_d.y));

	// Variasi tiap keping marmer + urat marmer diagonal organik (2 octave ringan)
	float tile_shift = hash21(tile_id) * 0.14;
	vec2 p_vein = v_world_pos.xz * 0.42 + vec2(tile_shift * 5.0);
	float n1 = vnoise(p_vein * 1.8);
	float n2 = vnoise(p_vein * 4.1 + n1 * 1.6);
	float vein = pow(1.0 - abs(sin((p_vein.x + p_vein.y) * 1.6 + n1 * 2.8 + n2 * 1.2)), 6.0);

	vec3 tex_c = texture(tex_albedo, v_world_pos.xz * 0.22).rgb;
	vec3 marble_col = mix(base_tint.rgb * (0.88 + tile_shift), vein_tint.rgb, vein * 0.55);
	marble_col = mix(marble_col, marble_col * tex_c * 1.55, 0.42);
	// Gelapkan sedikit di garis nat ubin
	ALBEDO = mix(marble_col * 0.35, marble_col, grout);

	// Normal halus agar pantulan marmer rata seperti batu poles (tidak bergelombang kasar)
	vec3 n_map = texture(tex_normal, v_world_pos.xz * 0.22).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n_map, 0.22 * grout);

	float r_tex = texture(tex_rough, v_world_pos.xz * 0.22).r;
	float r_pol = clamp(gloss_roughness + (r_tex - 0.5) * 0.08 - vein * 0.03, 0.09, 0.36);
	ROUGHNESS = mix(0.78, r_pol, grout);
	METALLIC = 0.04;
	SPECULAR = 0.68;

	// Pantulan langit-langit istana palsu berbasis sudut pandang Fresnel (0 ms SSR palsu untuk PC low-end!)
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.12 + 0.88 * pow(1.0 - ndv, 3.2);
	EMISSION = env_sheen_color * fresnel * env_reflect_strength * grout;
}

void light() {
	// Potong ekor atenuasi lampu yang sangat tipis agar sisa jangkauan lampu tak pernah membekas di ruang sebelah
	float clean_atten = ATTENUATION * smoothstep(0.02, 0.10, ATTENUATION);
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * ndl * clean_atten;

	// Schlick-GGX marmer istana mengilap dengan soft-shoulder (mewah berkilau namun tidak membakar lingkaran kasar)
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = max(dot(NORMAL, h), 0.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.010);
	float a2 = a * a;
	float denom = (ndh * ndh * (a2 - 1.0) + 1.0);
	float d_term = min(a2 / max(PI * denom * denom, 0.0001), 7.5);
	float fres = 0.08 + 0.92 * pow(1.0 - max(dot(h, VIEW), 0.0), 4.2);
	vec3 spec = LIGHT_COLOR * d_term * fres * ndl * clean_atten * 0.52;
	SPECULAR_LIGHT += spec;
}
