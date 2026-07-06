package texture

import "core:math"

import rl "vendor:raylib"

// Bark swatch: assorted browns coloured by a vertically stretched Voronoi
// pattern, so each tall, thin cell reads as a streak of wood grain. The sample
// grid has many cells across (BARK_CELLS_X) but few down (BARK_CELLS_Y), which
// is what stretches the cells vertically. See gen_bark_swatch.
BARK_SEED    :: 31
BARK_CELLS_X :: 80 // thin cells across -> fine grain lines
BARK_CELLS_Y :: 10  // few tall cells down -> grain runs vertically

BARK_BROWNS :: [?]rl.Color{
	{  58, 40, 24, 255 },
	{  82, 55, 33, 255 },
	{ 101, 67, 33, 255 },
	{ 120, 85, 52, 255 },
}

// Bakes the bark swatch: assorted browns laid down by a vertically stretched
// Voronoi pattern. The sample grid has many cells across but few down, so each
// Voronoi cell is a tall, thin column; colouring the cells from a few browns
// turns those columns into vertical wood-grain streaks. Cell indices wrap, so
// the swatch tiles seamlessly. `seed` makes the grain deterministic.
@(private)
gen_bark_swatch :: proc(seed: i64) -> rl.Texture2D {
	img := rl.GenImageColor(SWATCH_RES, SWATCH_RES, rl.BLANK)
	browns := BARK_BROWNS

	for py in 0..<SWATCH_RES {
		for px in 0..<SWATCH_RES {
			// Cell-space point, stretched so cells are tall and thin: a unit cell
			// spans 1/BARK_CELLS_X of the width but 1/BARK_CELLS_Y of the height.
			cx := f32(px) / f32(SWATCH_RES) * BARK_CELLS_X
			cy := f32(py) / f32(SWATCH_RES) * BARK_CELLS_Y

			id := _bark_cell(seed, cx, cy, BARK_CELLS_X, BARK_CELLS_Y)
			rl.ImageDrawPixel(&img, i32(px), i32(py), browns[id %% len(browns)])
		}
	}

	tex := rl.LoadTextureFromImage(img)

	rl.UnloadImage(img)
	rl.SetTextureFilter(tex, .POINT)
	rl.SetTextureWrap(tex, .REPEAT)

	return tex
}

// Colour index of the nearest Voronoi feature point's cell at (x,y) in cell
// space. Cells wrap on cells_x/cells_y so the pattern tiles seamlessly. Each
// cell's feature point is jittered inside it by a hash, and the winning cell's
// hash also selects the colour.
@(private="file")
_bark_cell :: proc(seed: i64, x: f32, y: f32, cells_x: int, cells_y: int) -> int {
	ix := int(math.floor(x))
	iy := int(math.floor(y))

	best    := f32(1e30)
	best_id := 0

	for dy in -1..=1 {
		for dx in -1..=1 {
			cxi := ix + dx
			cyi := iy + dy

			// Wrap the cell index so feature points match across swatch edges.
			h := _hash(seed, cxi %% cells_x, cyi %% cells_y)

			// Feature point: cell origin + hashed [0,1) jitter.
			fx := f32(cxi) + f32(h & 0xFFFF) / 65536.0
			fy := f32(cyi) + f32((h >> 16) & 0xFFFF) / 65536.0

			d := (fx - x) * (fx - x) + (fy - y) * (fy - y)
			if d < best {
				best = d
				best_id = int(h >> 8) // decorrelate the colour from the jitter bits
			}
		}
	}

	return best_id
}

// Small deterministic integer hash -> u32, keyed by (seed, a, b).
@(private="file")
_hash :: proc(seed: i64, a: int, b: int) -> u32 {
	h := u32(seed) + u32(a) * 374761393 + u32(b) * 668265263
	h = (h ~ (h >> 13)) * 1274126177
	h = h ~ (h >> 16)
	return h
}
