package island

import rl "vendor:raylib"

// Resolution (px) of the baked swatch textures. It lives here because the
// meshers bake UVs sized in swatch repeats (SWATCH_RES texels at a constant
// world texel size); the game's texture baking must match it.
SWATCH_RES :: 256

Island :: struct {
	ground: rl.Model,
	trees: [dynamic]Tree
}

// Generates the whole island for `seed`: the floating ground mesh plus its
// trees, each tree carrying its models and local-space collision tris. Every
// random draw (noise layers, tree growth) is derived from `seed`, so the same
// seed always yields the same island. Materials (shaders, swatch textures) are
// the caller's job, as is placing the trees in the world.
create_island :: proc(seed: i64) -> Island {
	isle: Island

	isle.ground = rl.LoadModelFromMesh(gen_ground(seed))

	append(&isle.trees, create_tree(u64(seed) + TREE_SEED))

	return isle
}

unload_island :: proc(isle: ^Island) {
	rl.UnloadModel(isle.ground)

	for tree in isle.trees {
		rl.UnloadModel(tree.trunk)
		rl.UnloadModel(tree.leaves)
		delete(tree.tris)
	}

	delete(isle.trees)
}
