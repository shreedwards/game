package shader

import rl "vendor:raylib"

// Shared scene lighting. Any shader that declares the uniforms
//   uniform vec3 sunDir, sunColor, ambient, viewPos;
// can be wired up with bind_lighting (once) + update_lighting (per frame),
// so the terrain and every other lit object share one consistent sun.

// SUN_DIR is the direction the light TRAVELS, so a negative Y means the sun is
// up in the sky pointing down at the scene.
SUN_DIR   :: rl.Vector3 { -0.55, -1.0, -0.35 }
SUN_COLOR :: rl.Vector3 { 1.0, 0.96, 0.86 }
AMBIENT   :: rl.Vector3 { 0.30, 0.34, 0.42 }

// Bind the static sun uniforms and route "viewPos" through raylib's standard
// view-location slot so it can be refreshed each frame without a name lookup.
// Call once, right after loading a shader.
@(private)
bind_lighting :: proc(shader: rl.Shader) {
	shader.locs[int(rl.ShaderLocationIndex.VECTOR_VIEW)] =
		rl.GetShaderLocation(shader, "viewPos")

	dir := rl.Vector3Normalize(SUN_DIR)
	sun := SUN_COLOR
	amb := AMBIENT
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "sunDir"),   &dir, .VEC3)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "sunColor"), &sun, .VEC3)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "ambient"),  &amb, .VEC3)
}

// Feed the current camera position to every loaded shader (needed for
// specular). Call each frame before drawing anything lit.
update_lighting :: proc(view_pos: rl.Vector3) {
	pos := view_pos
	all := [?]rl.Shader{ g_shaders.ground, g_shaders.lit, g_shaders.leaf }

	for s in all {
		rl.SetShaderValue(s, s.locs[int(rl.ShaderLocationIndex.VECTOR_VIEW)], &pos, .VEC3)
	}
}
