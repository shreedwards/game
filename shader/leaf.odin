package shader

import rl "vendor:raylib"

// Cutout variant of the lit fragment shader for foliage: the leaf swatch is
// mostly transparent, and instead of alpha-blending (which would need sorted
// draw order) the shader discards see-through texels outright, punching
// leaf-shaped holes in the canopy while still writing depth for the rest.
// Shares LIT_VS with the plain lit shader.

LEAF_FS :: `#version 330
in vec3 fragPosition;
in vec3 fragNormal;
in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0; // leaf swatch (transparent gaps between leaves)
uniform vec4 colDiffuse;    // per-draw tint (the rl.DrawModel colour)

uniform vec3 sunDir;
uniform vec3 sunColor;
uniform vec3 ambient;
uniform vec3 viewPos;

out vec4 finalColor;

void main() {
	vec4 albedo = texture(texture0, fragTexCoord) * colDiffuse * fragColor;

	// The swatch's bare gaps are holes in the canopy, not translucency.
	if (albedo.a < 0.5) discard;

	// Flat / faceted shading, as in the lit shader.
	vec3 fn = normalize(cross(dFdx(fragPosition), dFdy(fragPosition)));
	vec3 N = dot(fn, fragNormal) < 0.0 ? -fn : fn;
	vec3 L = normalize(-sunDir);              // fragment -> sun
	float diff = max(dot(N, L), 0.0);

	vec3 V = normalize(viewPos - fragPosition);
	vec3 H = normalize(L + V);
	float spec = pow(max(dot(N, H), 0.0), 32.0) * 0.25;

	vec3 lit = albedo.rgb * (ambient + sunColor * diff) + sunColor * spec;
	finalColor = vec4(lit, 1.0);
}
`

@(private)
load_leaf_shader :: proc() -> rl.Shader {
	shader := rl.LoadShaderFromMemory(LIT_VS, LEAF_FS)
	bind_lighting(shader)
	return shader
}
