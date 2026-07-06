package game

import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "collision"
import "island"
import "shader"
import "texture"

// The world's islands: one entry per island, generated from its seed and
// floated at its position. The same seed always generates the same island -
// same ground, same number of trees, at the same spots. Trees live in
// island-local space, so a tree's world position is island + tree.
Island_Spawn :: struct {
	seed:     i64,
	position: rl.Vector3
}

ISLAND_SPAWNS :: [?]Island_Spawn {
	{ seed = 0, position = {  0.0, 0.0,  0.0 } },
	{ seed = 1, position = { 65.0, 6.0, 10.0 } },
}

World :: struct {
	islands: [dynamic]island.Island,

	tris: [dynamic]collision.Triangle
}

create_world :: proc() -> World {
	world: World

	for spawn in ISLAND_SPAWNS {
		isle := island.create_island(spawn.seed)
		isle.position = spawn.position

		// Triplanar shader samples three tileable biome swatches by world position.
		ground := &isle.ground
		ground.materials[0].shader = shader.shaders.ground
		rl.SetMaterialTexture(&ground.materials[0], .ALBEDO,    texture.textures.grass) // texture0
		rl.SetMaterialTexture(&ground.materials[0], .METALNESS, texture.textures.dirt)  // texture1
		rl.SetMaterialTexture(&ground.materials[0], .NORMAL,    texture.textures.stone) // texture2

		collision.append_mesh_tris(&world.tris, ground.meshes[0], isle.position)

		// Bark tubes are opaque and use the plain lit shader; the leaf domes use
		// the cutout variant so the leaf swatch's transparent gaps become holes in
		// the canopy. Both sample their generated swatch as the albedo map, with
		// UVs baked into the meshes at constant world texel size.
		for tree in isle.trees {
			shader.apply_shader(tree.trunk,  shader.shaders.lit)
			shader.apply_shader(tree.leaves, shader.shaders.leaf)
			rl.SetMaterialTexture(&tree.trunk.materials[0],  .ALBEDO, texture.textures.bark)
			rl.SetMaterialTexture(&tree.leaves.materials[0], .ALBEDO, texture.textures.leaf)

			collision.append_tris(&world.tris, tree.tris[:], isle.position + tree.position)
		}

		append(&world.islands, isle)
	}

	return world
}

draw_world :: proc(world: ^World) {

	shader.update_lighting(active_cam.position)

	for isle in world.islands {
		rl.DrawModel(isle.ground, isle.position, 1.0, rl.WHITE)
	}

	// Trees are hollow, open-ended meshes: render both faces so they don't cull
	// away where we see their insides. Bark/leaf colour comes from the sampled
	// swatches, so tint white to leave them untouched.
	rlgl.DisableBackfaceCulling()
	for isle in world.islands {
		for tree in isle.trees {
			rl.DrawModel(tree.trunk,  isle.position + tree.position, 1.0, rl.WHITE)
			rl.DrawModel(tree.leaves, isle.position + tree.position, 1.0, rl.WHITE)
		}
	}
	rlgl.EnableBackfaceCulling()

	if dev_mode {
		for isle in world.islands {
			rl.DrawModelWires(isle.ground, isle.position, 1.0, rl.DARKGRAY)

			for tree in isle.trees {
				rl.DrawModelWires(tree.trunk,  isle.position + tree.position, 1.0, rl.DARKGRAY)
				rl.DrawModelWires(tree.leaves, isle.position + tree.position, 1.0, rl.DARKGRAY)
			}
		}
	}
}

unload_world :: proc(world: ^World) {
	for &isle in world.islands {
		island.unload_island(&isle)
	}

	delete(world.islands)
	delete(world.tris)
}
