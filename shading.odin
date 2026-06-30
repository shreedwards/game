package game

import rl "vendor:raylib"

// Triplanar terrain shader. The island mesh has no usable UVs for steep faces
// (terrace risers, walls), so instead of mesh UVs the fragment shader samples
// three tileable biome swatches by WORLD POSITION. Two normals are used, and
// keeping them separate is the whole trick:
//
//   * GEOMETRIC normal (from screen-space derivatives of world position) is the
//     true per-face orientation. We pick ONE projection axis from it (uniplanar,
//     hard pick) so every face samples a single clean texel grid aligned to a
//     cardinal plane -> square texels, no stretching, no overlapping grids.
//
//   * SMOOTH normal (interpolated vertex normal) drives the biome choice, but it
//     is sampled at the TEXEL-CELL CENTRE, reconstructed via derivatives. That
//     makes the grass/dirt/stone decision constant across each whole texel (no
//     half/half split) while still following the real smooth slope (no
//     triangle-aligned lines).
//
// raylib auto-binds: mvp, matModel, matNormal, colDiffuse, and the material
// maps ALBEDO/METALNESS/NORMAL as texture0/texture1/texture2 (grass/dirt/stone).

ISLAND_VS :: `#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;

out vec3 fragPosition;
out vec3 fragNormal;
out vec4 fragColor;

void main() {
	fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
	fragNormal   = normalize(vec3(matNormal * vec4(vertexNormal, 1.0)));
	fragColor    = vertexColor;
	gl_Position  = mvp * vec4(vertexPosition, 1.0);
}
`

ISLAND_FS :: `#version 330
in vec3 fragPosition;
in vec3 fragNormal;
in vec4 fragColor;

uniform sampler2D texture0; // grass
uniform sampler2D texture1; // dirt
uniform sampler2D texture2; // stone
uniform vec4 colDiffuse;

out vec4 finalColor;

const float SCALE   = 0.12;  // texture tiles per world unit
const float TEX_RES = 256.0; // swatch resolution (must match SWATCH_RES)

const float EDGE_SCALE  = 6.0;  // ragged-edge noise frequency (higher = smaller chunks)
const float EDGE_JITTER = 0.18; // how far the noise breaks up the biome boundary
const float GRASS_LEVEL = 0.90; // slope above this (after jitter) is grass, below is dirt
const float STONE_LEVEL = 0.10; // slope below this (after jitter) is stone

// Hard single-axis (uniplanar) sample: project the world point onto whichever
// cardinal plane the face most faces. One face -> one grid -> square texels.
vec3 uniplanar(sampler2D tex, vec3 p, vec3 an) {
	vec2 uv;
	if (an.x >= an.y && an.x >= an.z)      uv = p.zy; // face points along X -> ZY plane
	else if (an.y >= an.x && an.y >= an.z)  uv = p.xz; // face points along Y -> XZ plane
	else                                    uv = p.xy; // face points along Z -> XY plane
	return texture(tex, uv * SCALE).rgb;
}

// Cheap hash-based value noise in [0,1], for breaking up the biome boundary.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	               mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	               mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void main() {
	// World-position screen-space basis on the surface.
	vec3 dPx = dFdx(fragPosition);
	vec3 dPy = dFdy(fragPosition);

	// True geometric face normal -> projection axis (square texels, no stretch).
	vec3 gn = normalize(cross(dPx, dPy));
	vec3 an = abs(gn);

	vec3 grass = uniplanar(texture0, fragPosition, an);
	vec3 dirt  = uniplanar(texture1, fragPosition, an);
	vec3 stone = uniplanar(texture2, fragPosition, an);

	// Biome from the SMOOTH slope, but evaluated at the texel-cell centre so the
	// decision is constant per texel. Reconstruct slope at the cell by projecting
	// the world displacement (cell - frag) onto the screen basis and stepping the
	// slope's screen-space gradient.
	float texel = 1.0 / (SCALE * TEX_RES);
	vec3  cell  = (floor(fragPosition / texel) + 0.5) * texel;

	float s   = fragNormal.y;     // smooth slope at this fragment
	float dsx = dFdx(s);
	float dsy = dFdy(s);
	vec3  d   = cell - fragPosition;

	float m00 = dot(dPx, dPx);
	float m01 = dot(dPx, dPy);
	float m11 = dot(dPy, dPy);
	float r0  = dot(dPx, d);
	float r1  = dot(dPy, d);
	float det = m00 * m11 - m01 * m01;

	float sCell = s;
	if (abs(det) > 1e-12) {
		float a = (r0 * m11 - r1 * m01) / det;
		float b = (r1 * m00 - r0 * m01) / det;
		sCell = s + a * dsx + b * dsy;
	}

	// Jitter (also per-texel) breaks the boundary into ragged texel-sized chunks.
	float jitter = (vnoise(cell * EDGE_SCALE) - 0.5) * EDGE_JITTER;
	float ny = sCell + jitter;

	float grassW = step(GRASS_LEVEL, ny);       // 1 = grass, 0 = dirt
	float stoneW = 1.0 - step(STONE_LEVEL, ny); // 1 = stone (down / sideways)

	vec3 top = mix(dirt, grass, grassW);
	vec3 col = mix(top, stone, stoneW);

	finalColor = vec4(col, 1.0) * colDiffuse * fragColor;
}
`

load_island_shader :: proc() -> rl.Shader {
	return rl.LoadShaderFromMemory(ISLAND_VS, ISLAND_FS)
}
