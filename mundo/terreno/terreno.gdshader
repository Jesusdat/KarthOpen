shader_type spatial;
// Terreno de prueba: colores de Karth según altura y pendiente, con variación de ruido.
// Más adelante el editor de terreno pintará capas (splat map) y esto mezclará texturas.

uniform vec3 color_pasto : source_color = vec3(0.32, 0.33, 0.18);
uniform vec3 color_pasto_seco : source_color = vec3(0.45, 0.40, 0.25);
uniform vec3 color_ceniza : source_color = vec3(0.38, 0.36, 0.34);
uniform vec3 color_roca : source_color = vec3(0.20, 0.19, 0.19);
uniform vec3 color_cumbre : source_color = vec3(0.62, 0.60, 0.57);
uniform float altura_ceniza = 18.0;
uniform float altura_cumbre = 42.0;
uniform float pendiente_roca : hint_range(0.0, 1.0) = 0.62;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * ruido(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n_grande = fbm(pos_mundo.xz * 0.02);
	float n_fino = fbm(pos_mundo.xz * 0.35);
	float h = pos_mundo.y + (n_grande - 0.5) * 8.0;

	vec3 base = mix(color_pasto, color_pasto_seco, smoothstep(0.35, 0.7, n_grande));
	base = mix(base, color_ceniza, smoothstep(altura_ceniza - 4.0, altura_ceniza + 4.0, h));
	base = mix(base, color_cumbre, smoothstep(altura_cumbre - 3.0, altura_cumbre + 5.0, h));

	float pendiente = 1.0 - normal_mundo.y;          // 0 = plano
	float roca = smoothstep(pendiente_roca * 0.35, pendiente_roca * 0.55, pendiente + (n_fino - 0.5) * 0.08);
	base = mix(base, color_roca * (0.8 + n_fino * 0.4), roca);

	ALBEDO = base * (0.85 + n_fino * 0.3);
	ROUGHNESS = mix(0.95, 0.8, roca);
}
