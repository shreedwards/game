package texture

import "core:math"
import noise "core:math/noise"

import rl "vendor:raylib"

// Ground biome swatches (grass/dirt/stone): per-texel color variation from a
// fractal-noise palette -> broad patches + fine mottling.

SWATCH_FREQ :: 6.0 // noise patches per swatch; higher = finer mottle

GRASS_SEED        :: 11
DIRT_SEED         :: 13
STONE_SEED        :: 29
PALETTE_OCTAVES   :: 3     // more = more layered detail
PALETTE_LACUNARITY :: 2.0
PALETTE_GAIN      :: 0.5   // lower = smoother (less fine speckle)

GRASS :: [3]rl.Color{ {60,110,40,255}, {80,140,55,255}, {105,160,70,255} }
DIRT  :: [3]rl.Color{ {70,52,34,255},  {96,70,44,255},  {120,90,58,255}  }
STONE :: [3]rl.Color{ {72,70,78,255},  {104,102,110,255}, {138,136,146,255} }

// Bakes one seamlessly-tileable biome swatch (fractal palette mottle) for the
// triplanar shader to sample by world position. Tileability comes from
// evaluating the noise on a 4D torus, so opposite edges of the swatch match.
@(private)
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
