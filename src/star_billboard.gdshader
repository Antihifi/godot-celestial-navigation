// Procedural star billboard.
//
// Renders a soft circular star (tight core + wider halo) as an additive
// unshaded quad that always faces the camera. No texture required — the
// shape is generated in the fragment shader from UV distance, so you get
// crisp results at any resolution and you can animate per-star brightness
// by driving the `brightness` uniform.
//
// Designed to render in front of Sky3D's background starmap without
// fighting it. Because it's additive, a star on top of a dark sky just
// adds brightness; on top of a bright sky it quietly vanishes — which is
// exactly what real stars do at dawn.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 star_color : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform float brightness : hint_range(0.0, 10.0) = 1.0;

// Tight bright center of the star.
uniform float core_radius : hint_range(0.0, 0.5) = 0.08;
uniform float core_softness : hint_range(0.001, 0.5) = 0.05;

// Wider soft halo around the core. This is what makes stars read as
// *stars* rather than pixels — don't skip it.
uniform float glow_radius : hint_range(0.0, 1.0) = 0.5;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.35;

// Optional 4-point diffraction spike (set to 0 for clean disc).
uniform float spike_strength : hint_range(0.0, 2.0) = 0.0;
uniform float spike_width : hint_range(0.001, 0.1) = 0.015;


void vertex() {
	// Billboard: lock the quad's orientation to the camera so it always
	// faces us, while keeping its world-space position intact.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	// Preserve per-instance scale from the MODEL_MATRIX so you can pulse
	// highlighted stars by scaling the node.
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(centered);

	// Core: hard bright center with a soft edge.
	float core = 1.0 - smoothstep(core_radius, core_radius + core_softness, dist);

	// Glow: wide soft falloff. Using a squared falloff reads more like
	// a real point-spread function than linear smoothstep.
	float glow = 1.0 - smoothstep(0.0, glow_radius, dist);
	glow = glow * glow * glow_strength;

	// Optional cross-shaped diffraction spikes for beacon stars.
	float spikes = 0.0;
	if (spike_strength > 0.0) {
		float h = 1.0 - smoothstep(0.0, spike_width, abs(centered.y)) * smoothstep(1.0, 0.2, abs(centered.x));
		float v = 1.0 - smoothstep(0.0, spike_width, abs(centered.x)) * smoothstep(1.0, 0.2, abs(centered.y));
		spikes = max(h, v) * spike_strength * (1.0 - smoothstep(0.0, 1.0, dist));
	}

	float intensity = (core + glow + spikes) * brightness;
	ALBEDO = star_color.rgb * intensity;
	ALPHA = clamp(intensity, 0.0, 1.0) * star_color.a;
}
