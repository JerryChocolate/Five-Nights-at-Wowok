shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, ambient_light_disabled;

// Pengganti VolumetricFog super ringan (< 0.05 ms): berkas cahaya lembut (God-rays / Light Cone)
// dengan pudar vertikal + pudar tepi Fresnel + pudar jarak kamera agar tidak terlihat tepi kasar.

uniform vec4 shaft_color : source_color = vec4(0.85, 0.92, 1.0, 0.085);
uniform float fade_power : hint_range(0.5, 4.0) = 1.8;
uniform float rim_softness : hint_range(0.5, 5.0) = 2.2;

varying float v_height01;
varying float v_cam_dist;

void vertex() {
	// CylinderMesh standar Godot memiliki tinggi berpusat di Y=0: atas = +0.5*h, bawah = -0.5*h -> UV.y
	v_height01 = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_dist = distance(wp, CAMERA_POSITION_WORLD);
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), rim_softness);
	float vert = pow(v_height01, fade_power) * smoothstep(0.0, 0.14, 1.0 - v_height01);
	float near_fade = smoothstep(1.2, 3.8, v_cam_dist);
	float far_fade = 1.0 - smoothstep(26.0, 38.0, v_cam_dist);
	float intensity = shaft_color.a * edge * vert * near_fade * far_fade;
	ALBEDO = shaft_color.rgb * intensity;
}
