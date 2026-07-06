package shader

import rl "vendor:raylib"

// General-purpose Blinn-Phong shader for ordinary meshes (spheres, props,
// anything with real vertex normals and UVs). It uses raylib's standard vertex
// attributes and auto-bound uniforms (mvp, matModel, matNormal, colDiffuse,
// texture0) plus the shared sun uniforms, so lit props match the terrain.

LIT_VS :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
in vec2 vertexTexCoord;
in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;

out vec3 fragPosition;
out vec3 fragNormal;
out vec2 fragTexCoord;
out vec4 fragColor;

void main() {
	fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
	fragNormal   = normalize(vec3(matNormal * vec4(vertexNormal, 1.0)));
	fragTexCoord = vertexTexCoord;
	fragColor    = vertexColor;
	gl_Position  = mvp * vec4(vertexPosition, 1.0);
}
`

LIT_FS :: `#version 330
in vec3 fragPosition;
in vec3 fragNormal;
in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0; // ALBEDO map; raylib binds a white 1x1 if unset
uniform vec4 colDiffuse;    // per-draw tint (the rl.DrawModel colour)

uniform vec3 sunDir;
uniform vec3 sunColor;
uniform vec3 ambient;
uniform vec3 viewPos;

out vec4 finalColor;

void main() {
	vec4 albedo = texture(texture0, fragTexCoord) * colDiffuse * fragColor;

	// Flat / faceted shading: use the true per-face normal from screen-space
	// derivatives of world position, aligned to the smooth normal for outward
	// facing, instead of the interpolated vertex normal.
	vec3 fn = normalize(cross(dFdx(fragPosition), dFdy(fragPosition)));
	vec3 N = dot(fn, fragNormal) < 0.0 ? -fn : fn;
	vec3 L = normalize(-sunDir);              // fragment -> sun
	float diff = max(dot(N, L), 0.0);

	vec3 V = normalize(viewPos - fragPosition);
	vec3 H = normalize(L + V);
	float spec = pow(max(dot(N, H), 0.0), 32.0) * 0.25;

	vec3 lit = albedo.rgb * (ambient + sunColor * diff) + sunColor * spec;
	finalColor = vec4(lit, albedo.a);
}
`

@(private)
load_lit_shader :: proc() -> rl.Shader {
	shader := rl.LoadShaderFromMemory(LIT_VS, LIT_FS)
	bind_lighting(shader)
	return shader
}
