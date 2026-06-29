package game

import "core:math"
import noise "core:math/noise"

import rl "vendor:raylib"

// Domain warp
WARP_SEED     :: 1
WARP_FREQ     :: 2.0
WARP_STRENGTH :: 0.05

// Base fractal noise
NOISE_SEED      :: 0
BASE_OCTAVES    :: 4
BASE_FREQ       :: 1.5
BASE_LACUNARITY :: 2.0
BASE_GAIN       :: 0.25

// Detail noise (post-terrace)
DETAIL_OCTAVES    :: 3
DETAIL_FREQ       :: 12.0
DETAIL_LACUNARITY :: 2.0
DETAIL_GAIN       :: 0.25
DETAIL_STRENGTH   :: 0.025

// Terracing
TERRACE_STEPS :: 2.0
STEP_HEIGHT   :: 0.2

// Biased "base plane": collapse a band of noise values around GROUND_LEVEL
// into one flat terrace, giving the player a large level area to stand on.
GROUND_LEVEL :: 0.0   // target value in noise space [-1,1]
GROUND_WIDTH :: 0.15  // half-width of the collapsed band (bigger = wider plane)

// Texturing
TEX_RES :: 2048            // baked albedo resolution (px)
SLOPE_THRESHOLD :: 0.75    // ~half a terrace step (STEP_HEIGHT*amplitude); above detail-noise slope, below a riser

// Grass/dirt boundary warp: offsets the slope-sample position (fractal noise)
// so the edge meanders instead of snapping to grid cells.
JITTER_SEED       :: 7
JITTER_FREQ       :: 0.03   // base wiggle scale; lower = larger, smoother
JITTER_STRENGTH   :: 0.5    // displacement in grid cells
JITTER_OCTAVES    :: 3      // more = more ragged, multi-scale edge
JITTER_LACUNARITY :: 2.0
JITTER_GAIN       :: 0.5

// Per-texel color variation (fractal noise -> broad patches + fine mottling)
GRASS_SEED        :: 11
DIRT_SEED         :: 13
PALETTE_FREQ      :: 0.1   // base noise step per texel; lower = larger color patches
PALETTE_OCTAVES   :: 3     // more = more layered detail
PALETTE_LACUNARITY :: 2.0
PALETTE_GAIN      :: 0.5   // lower = smoother (less fine speckle)

GRASS :: [3]rl.Color{ {60,110,40,255}, {80,140,55,255}, {105,160,70,255} }
DIRT  :: [3]rl.Color{ {70,52,34,255},  {96,70,44,255},  {120,90,58,255}  }

gen_island_heights :: proc(width:int, length:int, amplitude:f32) -> [dynamic]f32 {
	vals : [dynamic]f32

	for x in 0..<width {
		for z in 0..<length {
			x_ := f64(x) / f64(width)
			z_ := f64(z) / f64(length)

			wx := x_ + f64(noise.noise_2d(WARP_SEED, { x_*WARP_FREQ, z_*WARP_FREQ })) * WARP_STRENGTH
			wz := z_ + f64(noise.noise_2d(WARP_SEED, { x_*WARP_FREQ, z_*WARP_FREQ })) * WARP_STRENGTH

			base := _fbm(NOISE_SEED, wx, wz, BASE_OCTAVES, BASE_FREQ, BASE_LACUNARITY, BASE_GAIN)

			// Bias: collapse a band around GROUND_LEVEL flat, then close the
			// gap so terraces above/below stay contiguous.
			biased := base
			if abs(biased - GROUND_LEVEL) < GROUND_WIDTH {
				biased = GROUND_LEVEL
			} else if biased > GROUND_LEVEL {
				biased -= GROUND_WIDTH
			} else {
				biased += GROUND_WIDTH
			}

			level := math.floor(biased * TERRACE_STEPS)
			h := f32(level) * STEP_HEIGHT
			detail := _fbm(NOISE_SEED, x_, z_, DETAIL_OCTAVES, DETAIL_FREQ, DETAIL_LACUNARITY, DETAIL_GAIN) * DETAIL_STRENGTH

			append(&vals, (h + detail) * amplitude)
		}
	}

	return vals
}

gen_island_texture :: proc(heights:[^]f32, width:int, length:int) -> rl.Texture2D {
	img := rl.GenImageColor(TEX_RES, TEX_RES, rl.BLANK)

	for py in 0..<TEX_RES {
		for px in 0..<TEX_RES {
			fx := f32(px) / f32(TEX_RES) * f32(width  - 1)
			fz := f32(py) / f32(TEX_RES) * f32(length - 1)

			// warp the sample position (fractal) so the edge meanders
			ox := _fbm(JITTER_SEED,     f64(px), f64(py), JITTER_OCTAVES, JITTER_FREQ, JITTER_LACUNARITY, JITTER_GAIN) * JITTER_STRENGTH
			oz := _fbm(JITTER_SEED + 1, f64(px), f64(py), JITTER_OCTAVES, JITTER_FREQ, JITTER_LACUNARITY, JITTER_GAIN) * JITTER_STRENGTH

			slope := _slope_at(heights, width, length, fx + ox, fz + oz)
			grass := slope < SLOPE_THRESHOLD

			col := grass ? _palette_color(GRASS, GRASS_SEED, px, py) : _palette_color(DIRT, DIRT_SEED, px, py)

			rl.ImageDrawPixel(&img, i32(px), i32(py), col)
		}
	}

	tex := rl.LoadTextureFromImage(img)

	rl.UnloadImage(img)
	rl.SetTextureFilter(tex, .POINT)

	return tex
}

@(private="file")
_fbm :: proc(seed:i64, x:f64, z:f64, octs:int, freq:f64, lac:f64, gain:f64) -> f32 {
	sum := 0.0
	amp := 1.0
	f := freq
	norm := 0.0

	for i in 0..<octs {
		sum += amp * f64(noise.noise_2d(seed, { x*f, z*f }))
		norm += amp
		f *= lac
		amp *= gain
	}

	return f32(sum / norm)
}

gen_island_mesh :: proc(heights:[^]f32, width:int, length:int, scale:f32) -> rl.Mesh {
	vertices : [dynamic]f32
	texcoords : [dynamic]f32
	normals : [dynamic]f32
	indices : [dynamic]u16

	for x in 0..<width {
		for z in 0..<length {
			h := heights[x * length + z]

			append(&vertices, f32(x) * scale)
			append(&vertices, h)
			append(&vertices, f32(z) * scale)

			append(&texcoords, f32(x) / (f32(width) - 1.0))
			append(&texcoords, f32(z) / (f32(length) - 1.0))

			hl := _height_at(heights, width, length, x-1, z)
			hr := _height_at(heights, width, length, x+1, z)
			hd := _height_at(heights, width, length, x, z-1)
			hu := _height_at(heights, width, length, x, z+1)

			dhdx := (hr - hl) / (2 * scale)
			dhdz := (hu - hd) / (2 * scale)

			n := rl.Vector3Normalize({ -dhdx, 1.0, -dhdz })

			append(&normals, n.x)
			append(&normals, n.y)
			append(&normals, n.z)
		}
	}

	for x in 0..<(width - 1) {
		for z in 0..<(length - 1) {
			row1 := x * length + z
			row2 := (x + 1) * length + z

			append(&indices, u16(row1))
			append(&indices, u16(row1 + 1))
			append(&indices, u16(row2))

			append(&indices, u16(row1 + 1))
			append(&indices, u16(row2 + 1))
			append(&indices, u16(row2))
		}
	}

	mesh := rl.Mesh {
		vertexCount = i32(len(vertices) / 3),
		triangleCount = i32(len(indices) / 3),

		vertices = raw_data(vertices),
		texcoords = raw_data(texcoords),
		normals = raw_data(normals),
		indices = raw_data(indices)
	}

	rl.UploadMesh(&mesh, false)

	return mesh
}

@(private="file")
_palette_color :: proc(pal:[3]rl.Color, seed:i64, px:int, py:int) -> rl.Color {
	n := _fbm(seed, f64(px), f64(py), PALETTE_OCTAVES, PALETTE_FREQ, PALETTE_LACUNARITY, PALETTE_GAIN)
	t := (n + 1) * 0.5
	idx := clamp(int(t * f32(len(pal))), 0, len(pal) - 1)

	return pal[idx]
}

@(private="file")
_height_at :: proc(heights:[^]f32, width:int, length:int, x:int, z:int) -> f32 {
	cx := clamp(x, 0, width - 1)
	cz := clamp(z, 0, length - 1)

	return heights[cx * length + cz]
}

@(private="file")
_sample_height :: proc(heights:[^]f32, width:int, length:int, fx:f32, fz:f32) -> f32 {
	cfx := clamp(fx, 0, f32(width  - 1))
	cfz := clamp(fz, 0, f32(length - 1))

	x0 := int(cfx); z0 := int(cfz)
	x1 := min(x0 + 1, width  - 1)
	z1 := min(z0 + 1, length - 1)
	tx := cfx - f32(x0)
	tz := cfz - f32(z0)

	h00 := heights[x0*length + z0]
	h10 := heights[x1*length + z0]
	h01 := heights[x0*length + z1]
	h11 := heights[x1*length + z1]

	return math.lerp(math.lerp(h00, h10, tx), math.lerp(h01, h11, tx), tz)
}

@(private="file")
_slope_at :: proc(heights:[^]f32, width:int, length:int, fx:f32, fz:f32) -> f32 {
	D :: f32(0.75)   // central-difference offset in grid cells

	dhdx := _sample_height(heights, width, length, fx+D, fz) - _sample_height(heights, width, length, fx-D, fz)
	dhdz := _sample_height(heights, width, length, fx, fz+D) - _sample_height(heights, width, length, fx, fz-D)

	return math.sqrt(dhdx*dhdx + dhdz*dhdz)
}
