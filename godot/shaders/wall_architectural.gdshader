shader_type spatial;

// Shader Dinding & Panel Kayu Gedung Paripurna dengan Procedural Contact Ambient Occlusion:
// menghadirkan gradasi bayangan kaki lantai & sudut plafon secara analitik (0 ms tanpa SSAO berat!).

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 wall_tint : source_color = vec4(0.56, 0.53, 0.48, 1.0);
uniform vec4 wainscoting_tint : source_color = vec4(0.24, 0.15, 0.09, 1.0);
uniform float uv_scale : hint_range(0.05, 1.0) = 0.26;
uniform float ceiling_height : hint_range(3.0, 12.0) = 4.4;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.58;
uniform float use_wainscoting : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_world_pos;
varying vec3 v_world_nrm;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Triplanar ringan berbasis sumbu dominan normal dunia (hanya 1x sample tekstur, bukan 3x!)
	vec2 uv_proj = abs(v_world_nrm.x) > 0.5 ? v_world_pos.zy : (abs(v_world_nrm.y) > 0.5 ? v_world_pos.xz : v_world_pos.xy);
	uv_proj *= uv_scale;

	vec3 tex_c = texture(tex_albedo, uv_proj).rgb;
	vec3 n_map = texture(tex_normal, uv_proj).rgb;
	float r_tex = texture(tex_rough, uv_proj).r;

	// Panel kayu bawah dinding (wainscoting khas gedung parlemen setinggi 1.05m) + lis emas tipis
	float h = v_world_pos.y;
	float is_vertical_wall = 1.0 - step(0.6, abs(v_world_nrm.y));
	float lower_panel = (1.0 - smoothstep(1.02, 1.06, h)) * use_wainscoting * is_vertical_wall;
	float gold_trim = (smoothstep(1.00, 1.025, h) * (1.0 - smoothstep(1.055, 1.08, h))) * use_wainscoting * is_vertical_wall;

	// Analytic Contact AO di kaki lantai (y=0) dan batas plafon (y=ceiling_height)
	float ao_floor = smoothstep(0.0, 0.62, h);
	float ao_ceil = smoothstep(0.0, 0.72, max(ceiling_height - h, 0.0));
	float contact_ao = mix(1.0, ao_floor * ao_ceil, ao_strength * is_vertical_wall);

	vec3 col = mix(wall_tint.rgb, wainscoting_tint.rgb, lower_panel) * tex_c * 1.45;
	col = mix(col, vec3(0.78, 0.62, 0.22), gold_trim * 0.85);

	ALBEDO = col * contact_ao;
	AO = contact_ao;
	AO_LIGHT_AFFECT = 0.75;
	NORMAL_MAP = n_map;
	ROUGHNESS = mix(clamp(r_tex * 0.92, 0.42, 0.92), 0.34, lower_panel * 0.6 + gold_trim);
	METALLIC = gold_trim * 0.65;
	SPECULAR = mix(0.32, 0.55, lower_panel);
}
