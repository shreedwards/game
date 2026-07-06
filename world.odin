package game

import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "collision"
import "island"
import "shader"
import "texture"

// The world's island seed: the same seed always generates the same island
// (ground and trees alike). 0 reproduces the island from before generation
// was seeded. Change it for a different island.
ISLAND_SEED :: 0

// Where the island's trees sit in the world: models and collision tris alike,
// with the trunk base sunk one unit into the terrain.
TREE_POSITION :: rl.Vector3 { 20.0, -1.0, 20.0 }

World :: struct {
	island: island.Island,

	tris: [dynamic]collision.Triangle
}

create_world :: proc() -> World {
	world: World

	world.island = island.create_island(ISLAND_SEED)

	// Triplanar shader samples three tileable biome swatches by world position.
	ground := &world.island.ground
	ground.materials[0].shader = shader.shaders.ground
	rl.SetMaterialTexture(&ground.materials[0], .ALBEDO,    texture.textures.grass) // texture0
	rl.SetMaterialTexture(&ground.materials[0], .METALNESS, texture.textures.dirt)  // texture1
	rl.SetMaterialTexture(&ground.materials[0], .NORMAL,    texture.textures.stone) // texture2

	collision.append_mesh_tris(&world.tris, ground.meshes[0], rl.Vector3 { })

	// Bark tubes are opaque and use the plain lit shader; the leaf domes use
	// the cutout variant so the leaf swatch's transparent gaps become holes in
	// the canopy. Both sample their generated swatch as the albedo map, with
	// UVs baked into the meshes at constant world texel size.
	for tree in world.island.trees {
		shader.apply_shader(tree.trunk,  shader.shaders.lit)
		shader.apply_shader(tree.leaves, shader.shaders.leaf)
		rl.SetMaterialTexture(&tree.trunk.materials[0],  .ALBEDO, texture.textures.bark)
		rl.SetMaterialTexture(&tree.leaves.materials[0], .ALBEDO, texture.textures.leaf)

		collision.append_tris(&world.tris, tree.tris[:], TREE_POSITION)
	}

	return world
}

draw_world :: proc(world: ^World) {

	shader.update_lighting(active_cam.position)

	rl.DrawModel(world.island.ground, rl.Vector3 { }, 1.0, rl.WHITE)

	// Tree is a hollow, open-ended mesh: render both faces so it doesn't cull
	// away where we see its inside. Bark/leaf colour comes from the sampled
	// swatches, so tint white to leave them untouched.
	rlgl.DisableBackfaceCulling()
	for tree in world.island.trees {
		rl.DrawModel(tree.trunk,  TREE_POSITION, 1.0, rl.WHITE)
		rl.DrawModel(tree.leaves, TREE_POSITION, 1.0, rl.WHITE)
	}
	rlgl.EnableBackfaceCulling()

	if dev_mode {
		rl.DrawModelWires(world.island.ground, rl.Vector3 { }, 1.0, rl.DARKGRAY)

		for tree in world.island.trees {
			rl.DrawModelWires(tree.trunk,  TREE_POSITION, 1.0, rl.DARKGRAY)
			rl.DrawModelWires(tree.leaves, TREE_POSITION, 1.0, rl.DARKGRAY)
		}
	}
}

unload_world :: proc(world: ^World) {
	island.unload_island(&world.island)
	delete(world.tris)
}
