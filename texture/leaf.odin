package texture

import "core:math/rand"

import rl "vendor:raylib"

// The leaf swatch isn't a smooth palette like bark; it's spattered foliage.
// Small, same-sized rects of assorted greens are stamped at random over a
// transparent swatch, so overlaps clump into leaf clusters and the bare gaps
// read as holes in the canopy (the leaf shader discards them). See
// gen_leaf_swatch.
LEAF_SEED     :: 37
LEAF_RECT_W   :: 7
LEAF_RECT_H   :: 12
LEAF_COVERAGE :: 5 // total rect area as a multiple of the swatch (overlaps + gaps)

LEAF_GREENS :: [?]rl.Color{
	{ 40,  90, 38, 255 },
	{ 56, 120, 46, 255 },
	{ 74, 140, 58, 255 },
	{ 96, 160, 72, 255 },
}

// Bakes the leaf swatch: a transparent texture spattered with many small,
// same-sized rects of random greens. Overlaps build up denser leaf clusters and
// the gaps stay transparent, so sampled onto the leaf hemispheres (with the leaf
// shader discarding transparent texels) it reads as ragged foliage rather than a
// solid dome. `seed` makes the spatter deterministic.
@(private)
gen_leaf_swatch :: proc(seed: i64) -> rl.Texture2D {
	img := rl.GenImageColor(SWATCH_RES, SWATCH_RES, rl.BLANK) // fully transparent

	// Local seeded RNG so the spatter is deterministic and doesn't disturb the
	// program-wide default generator.
	state := rand.create_u64(u64(seed))
	context.random_generator = rand.default_random_generator(&state)

	area    := f32(SWATCH_RES * SWATCH_RES) * LEAF_COVERAGE / f32(LEAF_RECT_W * LEAF_RECT_H)
	count   := int(area)
	greens  := LEAF_GREENS

	for _ in 0..<count {
		x := rand.int31_max(SWATCH_RES)
		y := rand.int31_max(SWATCH_RES)
		col := greens[rand.int31_max(len(greens))]

		rl.ImageDrawRectangle(&img, x, y, LEAF_RECT_W, LEAF_RECT_H, col)
	}

	tex := rl.LoadTextureFromImage(img)

	rl.UnloadImage(img)
	rl.SetTextureFilter(tex, .POINT)
	rl.SetTextureWrap(tex, .REPEAT)

	return tex
}
