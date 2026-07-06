package island

import "core:math/rand"

import rl "vendor:raylib"

// Resolution (px) of the baked swatch textures. It lives here because the
// meshers bake UVs sized in swatch repeats (SWATCH_RES texels at a constant
// world texel size); the game's texture baking must match it.
SWATCH_RES :: 256

// Tree placement: how many trees an island grows and how they may stand.
MIN_TREES    :: 1
MAX_TREES    :: 2
TREE_SPACING :: 10.0 // minimum world distance between two trees
TREE_SINK    :: 1.0  // trunk base is sunk this far below the surface
PLACE_SEED   :: 101  // seed offset for the placement RNG (tree count + spots)

Island :: struct {
	position: rl.Vector3, // where the island floats, chosen by the caller

	ground: rl.Model,
	trees: [dynamic]Tree
}

// Generates the whole island for `seed`: the floating ground mesh plus 1-2
// trees placed at random flat spots on the top surface, each tree carrying its
// models, position and local-space collision tris. Every random draw (noise
// layers, tree count, spots, tree growth) is derived from `seed`, so the same
// seed always yields the same island with the same trees at the same spots.
// Materials (shaders, swatch textures) are the caller's job.
create_island :: proc(seed: i64) -> Island {
	isle: Island

	ground_mesh, top := gen_ground(seed)
	defer delete(top)

	isle.ground = rl.LoadModelFromMesh(ground_mesh)

	// Where a tree may stand: flat, fully-on-land patches of the top surface.
	spots := flat_land_spots(seed, top[:])
	defer delete(spots)

	// Placement RNG, seeded off the island seed: draws the tree count, then a
	// random order of the candidate spots (shuffle) that placement walks,
	// greedily keeping spots far enough from the trees already placed.
	state := rand.create_u64(u64(seed) + PLACE_SEED)
	context.random_generator = rand.default_random_generator(&state)

	count := MIN_TREES + int(rand.int31_max(MAX_TREES - MIN_TREES + 1))

	rand.shuffle(spots[:])

	for spot in spots {
		if len(isle.trees) >= count {
			break
		}

		spaced := true
		for tree in isle.trees {
			if rl.Vector3Distance(tree.position, spot) < TREE_SPACING {
				spaced = false
				break
			}
		}

		if !spaced {
			continue
		}

		// Each tree draws its own seed (offset by its index) so a two-tree
		// island grows two different trees, still determined by `seed`.
		tree := create_tree(u64(seed) + TREE_SEED + u64(len(isle.trees)))
		tree.position = spot - rl.Vector3 { 0.0, TREE_SINK, 0.0 }

		append(&isle.trees, tree)
	}

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
