package texture

import rl "vendor:raylib"

import "../island"

// Global texture resources: every swatch the game bakes, loaded once at launch
// (load_textures) and unloaded once at shutdown (unload_textures). Reach them
// anywhere as texture.textures.
textures : Textures

Textures :: struct {
	grass: rl.Texture,
	dirt:  rl.Texture,
	stone: rl.Texture,
	bark:  rl.Texture,
	leaf:  rl.Texture
}

// Each swatch is a small tileable texture sampled either by the triplanar
// ground shader (by world position) or by UVs the island package bakes at
// constant world texel size, so everything is baked at the shared
// island.SWATCH_RES resolution.
SWATCH_RES :: island.SWATCH_RES // swatch resolution (px), tiled across the world

// Call once after InitWindow (the GL context must exist).
load_textures :: proc() {
	textures = Textures {
		grass = gen_palette_swatch(GRASS, GRASS_SEED),
		dirt  = gen_palette_swatch(DIRT,  DIRT_SEED),
		stone = gen_palette_swatch(STONE, STONE_SEED),
		bark  = gen_bark_swatch(BARK_SEED),
		leaf  = gen_leaf_swatch(LEAF_SEED),
	}
}

unload_textures :: proc() {
	rl.UnloadTexture(textures.grass)
	rl.UnloadTexture(textures.dirt)
	rl.UnloadTexture(textures.stone)
	rl.UnloadTexture(textures.bark)
	rl.UnloadTexture(textures.leaf)
}
