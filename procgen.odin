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

// Island shape: radial falloff that pulls the terrain down toward the grid
// edges so the landmass forms a blob instead of filling the square. The
// coastline radius is perturbed by noise so the edge meanders organically.
// This is a *floating* island: cells past SEA_CUTOFF are culled entirely
// (no mesh, no collision) rather than flattened into an ocean.
ISLAND_RADIUS   :: 0.62  // base land radius (normalized, 0=center .. 1=edge midpoint)
ISLAND_FALLOFF  :: 0.30  // width of the land->edge transition band
ISLAND_DEPTH    :: 2.0   // how far (noise space) the rim is pushed down before the cut
AIR_CUTOFF      :: 0.5   // mask value (0 inland .. 1 outside) past which cells don't exist
COAST_SEED      :: 17
COAST_FREQ      :: 2.5   // coastline wiggle scale; lower = larger bays/capes
COAST_OCTAVES   :: 3
COAST_LACUNARITY :: 2.0
COAST_GAIN      :: 0.5
COAST_STRENGTH  :: 0.22  // how far the coastline radius wanders

// Floating underside: a second, flipped surface hung below the top. It is
// thin (WALL_MIN) at the rim and bulges deepest (BOTTOM_DEPTH) at the center,
// with high-frequency ridged noise carving downward stalactite spikes. The
// top, the bottom, and a connecting wall are merged into one mesh.
WALL_MIN          :: 0.06  // minimum island thickness at the rim (noise units)
BOTTOM_DEPTH      :: 1.30  // extra hang toward the center (noise units)
STALAC_SEED       :: 23
STALAC_FREQ       :: 9.0   // higher than the surface -> smaller, spikier features
STALAC_OCTAVES    :: 4
STALAC_LACUNARITY :: 2.0
STALAC_GAIN       :: 0.5
STALAC_STRENGTH   :: 0.85  // stalactite spike length (noise units)

// Texturing: each biome is a small tileable swatch the triplanar shader
// samples by world position (see island.fs). No per-location baking anymore;
// grass/dirt/stone are chosen in-shader from the world normal.
SWATCH_RES :: 256          // swatch resolution (px), tiled across the world
SWATCH_FREQ :: 6.0         // noise patches per swatch; higher = finer mottle

// Per-texel color variation (fractal noise -> broad patches + fine mottling)
GRASS_SEED        :: 11
DIRT_SEED         :: 13
STONE_SEED        :: 29
PALETTE_OCTAVES   :: 3     // more = more layered detail
PALETTE_LACUNARITY :: 2.0
PALETTE_GAIN      :: 0.5   // lower = smoother (less fine speckle)

GRASS :: [3]rl.Color{ {60,110,40,255}, {80,140,55,255}, {105,160,70,255} }
DIRT  :: [3]rl.Color{ {70,52,34,255},  {96,70,44,255},  {120,90,58,255}  }
STONE :: [3]rl.Color{ {72,70,78,255},  {104,102,110,255}, {138,136,146,255} }

gen_island_heights :: proc(width:int, length:int, amplitude:f32) -> [dynamic]f32 {
	vals : [dynamic]f32

	for x in 0..<width {
		for z in 0..<length {
			x_ := f64(x) / f64(width)
			z_ := f64(z) / f64(length)

			wx := x_ + f64(noise.noise_2d(WARP_SEED, { x_*WARP_FREQ, z_*WARP_FREQ })) * WARP_STRENGTH
			wz := z_ + f64(noise.noise_2d(WARP_SEED, { x_*WARP_FREQ, z_*WARP_FREQ })) * WARP_STRENGTH

			base := _fbm(NOISE_SEED, wx, wz, BASE_OCTAVES, BASE_FREQ, BASE_LACUNARITY, BASE_GAIN)

			// Island falloff: a noise-perturbed radial mask shapes the rim
			// into a meandering blob. Cells fully past the coast are culled
			// in gen_island_mesh; here we just slope the rim down a bit.
			base -= f32(_island_mask(x_, z_)) * ISLAND_DEPTH

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

// Underside of the floating island: hung below the top surface, thin at the
// rim and bulging deepest at the center, with ridged noise carving downward
// stalactite spikes. Returned y-values are absolute (already below `top`).
gen_island_underside :: proc(top:[^]f32, width:int, length:int, amplitude:f32) -> [dynamic]f32 {
	vals : [dynamic]f32

	for x in 0..<width {
		for z in 0..<length {
			x_ := f64(x) / f64(width)
			z_ := f64(z) / f64(length)

			// 1 deep inland, 0 at the coastline: drives how far the
			// underside hangs and fades the spikes out toward the rim.
			profile := clamp(1.0 - _island_mask(x_, z_) / AIR_CUTOFF, 0.0, 1.0)

			ridge := f64(_ridged(STALAC_SEED, x_, z_, STALAC_OCTAVES, STALAC_FREQ, STALAC_LACUNARITY, STALAC_GAIN))

			hang   := profile * BOTTOM_DEPTH
			stalac := profile * ridge * STALAC_STRENGTH
			drop   := f32((WALL_MIN + hang + stalac) * f64(amplitude))

			append(&vals, top[x * length + z] - drop)
		}
	}

	return vals
}

// Bakes one seamlessly-tileable biome swatch (fractal palette mottle) for the
// triplanar shader to sample by world position. Tileability comes from
// evaluating the noise on a 4D torus, so opposite edges of the swatch match.
gen_palette_swatch :: proc(pal:[3]rl.Color, seed:i64) -> rl.Texture2D {
	img := rl.GenImageColor(SWATCH_RES, SWATCH_RES, rl.BLANK)

	for py in 0..<SWATCH_RES {
		for px in 0..<SWATCH_RES {
			u := f64(px) / f64(SWATCH_RES)
			v := f64(py) / f64(SWATCH_RES)

			n := _tile_fbm(seed, u, v, PALETTE_OCTAVES, SWATCH_FREQ, PALETTE_LACUNARITY, PALETTE_GAIN)
			t := (n + 1) * 0.5
			idx := clamp(int(t * f32(len(pal))), 0, len(pal) - 1)

			rl.ImageDrawPixel(&img, i32(px), i32(py), pal[idx])
		}
	}

	tex := rl.LoadTextureFromImage(img)

	rl.UnloadImage(img)
	rl.SetTextureFilter(tex, .POINT)
	rl.SetTextureWrap(tex, .REPEAT)

	return tex
}

@(private="file")
_smoothstep :: proc(e0:f64, e1:f64, x:f64) -> f64 {
	t := clamp((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
}

// Radial island mask in normalized grid space: 0 deep inland, 1 out at sea.
// The coastline radius is perturbed by fractal noise so the edge meanders.
@(private="file")
_island_mask :: proc(x_:f64, z_:f64) -> f64 {
	nx := x_*2 - 1
	nz := z_*2 - 1
	dist := math.sqrt(nx*nx + nz*nz) // 0 center .. 1 edge midpoint .. ~1.41 corner

	coast := f64(_fbm(COAST_SEED, x_, z_, COAST_OCTAVES, COAST_FREQ, COAST_LACUNARITY, COAST_GAIN)) * COAST_STRENGTH
	edge  := ISLAND_RADIUS + coast

	return _smoothstep(edge, edge + ISLAND_FALLOFF, dist)
}

// Whether a grid cell is part of the floating island (inside the coastline).
@(private="file")
_is_land :: proc(x:int, z:int, width:int, length:int) -> bool {
	x_ := f64(x) / f64(width)
	z_ := f64(z) / f64(length)

	return _island_mask(x_, z_) < AIR_CUTOFF
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

// Seamlessly-tileable fractal noise over the unit square. (u,v) are mapped onto
// a 4D torus (two circles), so the noise is periodic in both axes and opposite
// swatch edges line up when the texture is tiled by the triplanar shader.
@(private="file")
_tile_fbm :: proc(seed:i64, u:f64, v:f64, octs:int, freq:f64, lac:f64, gain:f64) -> f32 {
	TAU :: 2.0 * math.PI

	sum := 0.0
	amp := 1.0
	f := freq
	norm := 0.0

	a := u * TAU
	b := v * TAU

	for i in 0..<octs {
		r := f / TAU
		p := noise.Vec4{ math.cos(a) * r, math.sin(a) * r, math.cos(b) * r, math.sin(b) * r }

		sum += amp * f64(noise.noise_4d_fallback(seed, p))
		norm += amp
		f *= lac
		amp *= gain
	}

	return f32(sum / norm)
}

// Ridged fractal noise in [0,1]: crests (near 1) where the base noise crosses
// zero. Used to carve sharp downward stalactite spikes on the underside.
@(private="file")
_ridged :: proc(seed:i64, x:f64, z:f64, octs:int, freq:f64, lac:f64, gain:f64) -> f32 {
	sum := 0.0
	amp := 1.0
	f := freq
	norm := 0.0

	for i in 0..<octs {
		n := f64(noise.noise_2d(seed, { x*f, z*f }))
		r := 1.0 - abs(n)
		sum += amp * r * r   // squared -> sharper, spikier ridges
		norm += amp
		f *= lac
		amp *= gain
	}

	return f32(sum / norm)
}

// Central-difference surface normal of a heightfield cell (points up).
@(private="file")
_grid_normal :: proc(heights:[^]f32, width:int, length:int, x:int, z:int, scale:f32) -> rl.Vector3 {
	hl := _height_at(heights, width, length, x-1, z)
	hr := _height_at(heights, width, length, x+1, z)
	hd := _height_at(heights, width, length, x, z-1)
	hu := _height_at(heights, width, length, x, z+1)

	dhdx := (hr - hl) / (2 * scale)
	dhdz := (hu - hd) / (2 * scale)

	return rl.Vector3Normalize({ -dhdx, 1.0, -dhdz })
}

// Whether the whole quad cell at (x,z) is land (all four corners inside).
@(private="file")
_cell_land :: proc(x:int, z:int, width:int, length:int) -> bool {
	if x < 0 || z < 0 || x >= width - 1 || z >= length - 1 do return false

	return _is_land(x, z, width, length)     &&
	       _is_land(x+1, z, width, length)   &&
	       _is_land(x, z+1, width, length)   &&
	       _is_land(x+1, z+1, width, length)
}

@(private="file")
_vert :: proc(v:[dynamic]f32, i:u16) -> rl.Vector3 {
	j := int(i) * 3
	return { v[j], v[j+1], v[j+2] }
}

@(private="file")
_push_vert :: proc(vertices:^[dynamic]f32, texcoords:^[dynamic]f32, normals:^[dynamic]f32, p:rl.Vector3, u:f32, v:f32, n:rl.Vector3) {
	append(vertices, p.x, p.y, p.z)
	append(texcoords, u, v)
	append(normals, n.x, n.y, n.z)
}

// Emit a vertical wall quad closing the rim between a top boundary edge
// (ta->tb) and its matching bottom edge. Walls get their own vertices so they
// carry a single horizontal normal (the triplanar shader picks the biome and
// projection from that normal), rather than inheriting the surfaces' up/down
// normals. The quad is wound so its front face points away from `center`.
@(private="file")
_wall :: proc(vertices:^[dynamic]f32, texcoords:^[dynamic]f32, normals:^[dynamic]f32, indices:^[dynamic]u16, base:u16, ta:u16, tb:u16, center:rl.Vector3) {
	pa  := _vert(vertices^, ta)
	pb  := _vert(vertices^, tb)
	pba := _vert(vertices^, ta + base)
	pbb := _vert(vertices^, tb + base)

	// Outward-facing winding + normal (away from the cell center, horizontally).
	g := rl.Vector3CrossProduct(pb - pa, pbb - pa)
	outward := (pa + pb) * 0.5 - center
	outward.y = 0
	flip := rl.Vector3DotProduct(g, outward) < 0
	n := rl.Vector3Normalize(flip ? -g : g)

	b := u16(len(vertices^) / 3)

	// Texcoords are unused by the triplanar shader; keep the buffer aligned.
	_push_vert(vertices, texcoords, normals, pa,  0, 0, n)
	_push_vert(vertices, texcoords, normals, pb,  0, 0, n)
	_push_vert(vertices, texcoords, normals, pbb, 0, 0, n)
	_push_vert(vertices, texcoords, normals, pba, 0, 0, n)

	if flip {
		append(indices, b, b + 2, b + 1)
		append(indices, b, b + 3, b + 2)
	} else {
		append(indices, b, b + 1, b + 2)
		append(indices, b, b + 2, b + 3)
	}
}

// Builds one merged mesh: the top surface, the flipped underside, and the
// vertical walls that close the rim between them. `top` and `bottom` share the
// same width x length grid; bottom vertices are stored after all top vertices
// (offset N), so index `i` on top maps to `i + N` on the bottom.
gen_island_mesh :: proc(top:[^]f32, bottom:[^]f32, width:int, length:int, scale:f32) -> rl.Mesh {
	vertices : [dynamic]f32
	texcoords : [dynamic]f32
	normals : [dynamic]f32
	indices : [dynamic]u16

	N := u16(width * length) // top index -> matching bottom index offset

	// Vertices: the whole top grid first, then the whole bottom grid. The
	// underside reuses the top's x,z layout; its normals are flipped to face
	// down/out. Texcoords are unused by the triplanar shader (which samples by
	// world position), but the buffer is kept for raylib's vertex layout.
	surfaces := [2][^]f32{ top, bottom }
	for surface, s in surfaces {
		down := s == 1

		for x in 0..<width {
			for z in 0..<length {
				h := surface[x * length + z]

				append(&vertices, f32(x) * scale, h, f32(z) * scale)
				append(&texcoords, f32(x) / (f32(width) - 1.0), f32(z) / (f32(length) - 1.0))

				n := _grid_normal(surface, width, length, x, z, scale)
				if down do n = -n

				append(&normals, n.x, n.y, n.z)
			}
		}
	}

	for x in 0..<(width - 1) {
		for z in 0..<(length - 1) {
			// Floating island: only emit a cell when all four corners are
			// land, so the off-island area is empty space rather than mesh.
			if !_cell_land(x, z, width, length) do continue

			r1 := u16(x * length + z)
			r2 := u16((x + 1) * length + z)

			// top surface (faces up)
			append(&indices, r1, r1 + 1, r2)
			append(&indices, r1 + 1, r2 + 1, r2)

			// underside (same cell, reversed winding, bottom vertices)
			append(&indices, r2 + N, r1 + 1 + N, r1 + N)
			append(&indices, r2 + N, r2 + 1 + N, r1 + 1 + N)

			// close the side wherever a neighbouring cell is absent
			center := rl.Vector3{ (f32(x) + 0.5) * scale, 0, (f32(z) + 0.5) * scale }

			if !_cell_land(x - 1, z, width, length) do _wall(&vertices, &texcoords, &normals, &indices, N, r1,     r1 + 1, center)
			if !_cell_land(x + 1, z, width, length) do _wall(&vertices, &texcoords, &normals, &indices, N, r2,     r2 + 1, center)
			if !_cell_land(x, z - 1, width, length) do _wall(&vertices, &texcoords, &normals, &indices, N, r1,     r2,     center)
			if !_cell_land(x, z + 1, width, length) do _wall(&vertices, &texcoords, &normals, &indices, N, r1 + 1, r2 + 1, center)
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
	cz := clamp(z, 0, length - 1)

	return heights[cx * length + cz]
}
