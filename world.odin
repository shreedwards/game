package game

import "core:c"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

Triangle :: struct {
	a: rl.Vector3,
	b: rl.Vector3,
	c: rl.Vector3,
	normal: rl.Vector3
}

World :: struct {
	island: rl.Model,

	tree_bark:   rl.Model, // trunk + branch tubes (opaque bark swatch)
	tree_leaves: rl.Model, // canopy domes (cutout leaf swatch)

	shader:      rl.Shader, // triplanar terrain shader (island only)
	lit:         rl.Shader, // reusable Blinn-Phong shader for ordinary props
	leaf:        rl.Shader, // lit + alpha cutout for the leaf swatch's gaps

	grass_tex: rl.Texture,
	dirt_tex:  rl.Texture,
	stone_tex: rl.Texture,
	bark_tex:  rl.Texture,
	leaf_tex:  rl.Texture,

	tris: [dynamic]Triangle
}

create_world :: proc() -> World {
	world: World

	island_mesh := gen_island()
	world.island = rl.LoadModelFromMesh(island_mesh)

	// Triplanar shader samples three tileable biome swatches by world position.
	world.shader = load_island_shader()

	// Reusable lit shader for props. Apply it to any model to have it lit by the
	// shared sun, e.g.:
	//   sphere := rl.LoadModelFromMesh(rl.GenMeshSphere(1, 16, 16))
	//   apply_shader(sphere, world.lit)
	world.lit = load_lit_shader()
	world.grass_tex = gen_palette_swatch(GRASS, GRASS_SEED)
	world.dirt_tex  = gen_palette_swatch(DIRT,  DIRT_SEED)
	world.stone_tex = gen_palette_swatch(STONE, STONE_SEED)

	world.island.materials[0].shader = world.shader
	rl.SetMaterialTexture(&world.island.materials[0], .ALBEDO,    world.grass_tex) // texture0
	rl.SetMaterialTexture(&world.island.materials[0], .METALNESS, world.dirt_tex)  // texture1
	rl.SetMaterialTexture(&world.island.materials[0], .NORMAL,    world.stone_tex) // texture2

	_append_mesh_tris(&world.tris, island_mesh, rl.Vector3 { })

	bark_mesh, leaf_mesh := create_tree(TREE_SEED)
	world.tree_bark   = rl.LoadModelFromMesh(bark_mesh)
	world.tree_leaves = rl.LoadModelFromMesh(leaf_mesh)

	// Bark tubes are opaque and use the plain lit shader; the leaf domes use
	// the cutout variant so the leaf swatch's transparent gaps become holes in
	// the canopy. Both sample their generated swatch as the albedo map, with
	// UVs baked into the meshes at constant world texel size.
	world.leaf     = load_leaf_shader()
	world.bark_tex = gen_bark_swatch(BARK_SEED)
	world.leaf_tex = gen_leaf_swatch(LEAF_SEED)

	apply_shader(world.tree_bark,   world.lit)
	apply_shader(world.tree_leaves, world.leaf)
	rl.SetMaterialTexture(&world.tree_bark.materials[0],   .ALBEDO, world.bark_tex)
	rl.SetMaterialTexture(&world.tree_leaves.materials[0], .ALBEDO, world.leaf_tex)

	_append_mesh_tris(&world.tris, bark_mesh, rl.Vector3 { 20.0, 0.0, 20.0 })
	_append_mesh_tris(&world.tris, leaf_mesh, rl.Vector3 { 20.0, 0.0, 20.0 })

	return world
}

draw_world :: proc(world: ^World) {

	update_lighting(world.shader, active_cam.position)
	update_lighting(world.lit,    active_cam.position)
	update_lighting(world.leaf,   active_cam.position)

	rl.DrawModel(world.island, rl.Vector3 { }, 1.0, rl.WHITE)

	// Tree is a hollow, open-ended mesh: render both faces so it doesn't cull
	// away where we see its inside. Bark/leaf colour comes from the sampled
	// swatches, so tint white to leave them untouched.
	rlgl.DisableBackfaceCulling()
	rl.DrawModel(world.tree_bark,   rl.Vector3 { 20.0, -1.0, 20.0 }, 1.0, rl.WHITE)
	rl.DrawModel(world.tree_leaves, rl.Vector3 { 20.0, -1.0, 20.0 }, 1.0, rl.WHITE)
	rlgl.EnableBackfaceCulling()

	if dev_mode {
		rl.DrawModelWires(world.island,      rl.Vector3 { }, 1.0, rl.DARKGRAY)
		rl.DrawModelWires(world.tree_bark,   rl.Vector3 { 20.0, -1.0, 20.0 }, 1.0, rl.DARKGRAY)
		rl.DrawModelWires(world.tree_leaves, rl.Vector3 { 20.0, -1.0, 20.0 }, 1.0, rl.DARKGRAY)
	}
}

unload_world :: proc(world: ^World) {
	rl.UnloadModel(world.island)
	rl.UnloadModel(world.tree_bark)
	rl.UnloadModel(world.tree_leaves)
	rl.UnloadShader(world.shader)
	rl.UnloadShader(world.lit)
	rl.UnloadShader(world.leaf)
	rl.UnloadTexture(world.grass_tex)
	rl.UnloadTexture(world.dirt_tex)
	rl.UnloadTexture(world.stone_tex)
	rl.UnloadTexture(world.bark_tex)
	rl.UnloadTexture(world.leaf_tex)
	delete(world.tris)
}

_append_mesh_tris :: proc(
	tris: ^[dynamic]Triangle,
	mesh: rl.Mesh,
	offset: rl.Vector3
) {
	v := mesh.vertices

	vert :: proc(v:[^]f32, i:int, offset:rl.Vector3) -> rl.Vector3 {
		return rl.Vector3 { v[i*3], v[i*3 + 1], v[i*3 + 2] } + offset
	}

	make_tri :: proc(a, b, c: rl.Vector3) -> Triangle {
		n := rl.Vector3Normalize(rl.Vector3CrossProduct(b - a, c -a))

		return Triangle { a, b, c, n }
	}

	if mesh.indices != nil {
		idx := mesh.indices

		for t in 0..<int(mesh.triangleCount) {
			a := vert(v, int(idx[t*3 + 0]), offset)
			b := vert(v, int(idx[t*3 + 1]), offset)
			c := vert(v, int(idx[t*3 + 2]), offset)

			append(tris, make_tri(a, b, c))
		}
	} else {
		for t in 0..<int(mesh.triangleCount) {
			a := vert(v, t*3 + 0, offset)
			b := vert(v, t*3 + 1, offset)
			c := vert(v, t*3 + 2, offset)

			append(tris, make_tri(a, b, c))
		}
	}
}
