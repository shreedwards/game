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

gen_island :: proc(width:int, length:int, amplitude:f32) -> rl.Mesh {
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

	return _gen_mesh(raw_data(vals), width, length, 1.0)
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

@(private="file")
_gen_mesh :: proc(heights:[^]f32, width:int, length:int, scale:f32) -> rl.Mesh {
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
_height_at :: proc(heights:[^]f32, width:int, length:int, x:int, z:int) -> f32 {
	cx := clamp(x, 0, width - 1)
	cz := clamp(z, 0, width - 1)

	return heights[cx * length + cz]
}
