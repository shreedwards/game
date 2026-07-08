package shader

import "core:c"

import rl "vendor:raylib"

// Global shader resources, loaded once at launch (load_shaders) and unloaded
// once at shutdown (unload_shaders). Reach them anywhere as shader.shaders.
g_shaders : Shaders

Shaders :: struct {
	ground:      rl.Shader, // triplanar terrain shader (island ground only)
	lit:         rl.Shader, // reusable Blinn-Phong shader for ordinary props
	leaf:        rl.Shader, // lit + alpha cutout for the leaf swatch's gaps
}

// Call once after InitWindow (the GL context must exist).
load_shaders :: proc() {
	g_shaders = Shaders {
		ground = load_ground_shader(),
		lit    = load_lit_shader(),
		leaf   = load_leaf_shader(),
	}
}

unload_shaders :: proc() {
	rl.UnloadShader(g_shaders.ground)
	rl.UnloadShader(g_shaders.lit)
	rl.UnloadShader(g_shaders.leaf)
}

// Assign a shader to every material on a model so the whole model renders with
// it. Use to make any rl.Model (LoadModelFromMesh, GenMeshSphere, etc.) lit by
// the shared sun, e.g.:
//   sphere := rl.LoadModelFromMesh(rl.GenMeshSphere(1, 16, 16))
//   shader.apply_shader(sphere, shader.shaders.lit)
apply_shader :: proc(model: rl.Model, shader: rl.Shader) {
	for i in 0 ..< c.int(model.materialCount) {
		model.materials[i].shader = shader
	}
}
