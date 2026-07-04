package game

import "core:math/rand"

import rl "vendor:raylib"

// Fine film grain post-process. The scene is rendered into an off-screen target
// (needed so the grain can be a full-screen pass), then blitted to the screen
// through the grain shader.
//
// SSAA_SCALE supersamples the scene for anti-aliasing (a plain render target has
// no MSAA), downsampling with a bilinear average on present. 2x keeps geometry
// edges smooth; 1x is a crisp 1:1 blit but leaves edges aliased.
//
// The grain itself is a static, screen-sized noise texture baked once at start
// (not procedural per-frame): it maps 1:1 onto screen pixels and never changes,
// so there's no animation, no drift, and no precision artifacts. GRAIN_INTENSITY
// is the main knob

GRAIN_INTENSITY :: 0.03 // 0 = off
GRAIN_SEED      :: 1234 // seed for the one-time noise bake
SSAA_SCALE      :: 2    // supersample factor; 2 = smoother edges, 1 = crisp but aliased

GRAIN_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0; // the rendered scene
uniform sampler2D texture1; // static grain, screen-sized, sampled 1:1
uniform vec4 colDiffuse;

uniform float intensity;    // grain strength

out vec4 finalColor;

void main() {
	vec3 scene = texture(texture0, fragTexCoord).rgb;

	// Static per-pixel noise. Signed (- 0.5) so it both darkens and brightens,
	// leaving average brightness unchanged.
	float n = texture(texture1, fragTexCoord).r;
	float g = (n - 0.5) * intensity;

	finalColor = vec4(scene + g, 1.0);
}
`

Grain :: struct {
	target: rl.RenderTexture2D,
	noise:  rl.Texture2D,
	shader: rl.Shader,
}

// Creates the render target (SSAA_SCALE x the screen), bakes the static noise
// texture, and loads the grain shader. Call after InitWindow so the GL context
// exists.
create_grain :: proc(screen_w: i32, screen_h: i32) -> Grain {
	g: Grain

	g.target = rl.LoadRenderTexture(screen_w * SSAA_SCALE, screen_h * SSAA_SCALE)
	// POINT for a crisp 1:1 blit when SSAA is off; BILINEAR to average the
	// downsample when supersampling.
	rl.SetTextureFilter(g.target.texture, SSAA_SCALE > 1 ? .BILINEAR : .POINT)

	g.noise  = _bake_grain(screen_w, screen_h, GRAIN_SEED)
	g.shader = rl.LoadShaderFromMemory(nil, GRAIN_FS) // nil vs -> raylib's default

	inten := f32(GRAIN_INTENSITY)
	rl.SetShaderValue(g.shader, rl.GetShaderLocation(g.shader, "intensity"), &inten, .FLOAT)

	return g
}

// Bakes a screen-sized grayscale noise texture: one random value per pixel, so
// it aligns 1:1 with the screen when presented. Sampled with POINT filtering to
// keep the grain crisp per pixel.
@(private="file")
_bake_grain :: proc(w: i32, h: i32, seed: u64) -> rl.Texture2D {
	state := rand.create_u64(seed)
	context.random_generator = rand.default_random_generator(&state)

	count := int(w) * int(h)
	pixels := make([]u8, count * 4)
	defer delete(pixels)

	for i in 0..<count {
		v := u8(rand.int31_max(256))
		pixels[i*4 + 0] = v
		pixels[i*4 + 1] = v
		pixels[i*4 + 2] = v
		pixels[i*4 + 3] = 255
	}

	img := rl.Image {
		data    = raw_data(pixels),
		width   = w,
		height  = h,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}

	tex := rl.LoadTextureFromImage(img) // copies to the GPU; pixels freed on return

	rl.SetTextureFilter(tex, .POINT)
	rl.SetTextureWrap(tex, .REPEAT)

	return tex
}

// Begin capturing the scene into the supersampled target. Pair with end_grain,
// then present_grain inside BeginDrawing/EndDrawing.
begin_grain :: proc(g: ^Grain) {
	rl.BeginTextureMode(g.target)
}

end_grain :: proc(g: ^Grain) {
	rl.EndTextureMode()
}

// Blit the captured scene to the screen through the grain shader. Anything drawn
// after this (HUD, debug text) is not grained.
present_grain :: proc(g: ^Grain) {
	// Render textures are stored bottom-up: flip V with a negative source height.
	// Source is the full 2x target; destination is the screen, so this scales it
	// down 2x (bilinear) = the supersample resolve.
	src := rl.Rectangle{ 0, 0, f32(g.target.texture.width), -f32(g.target.texture.height) }
	dst := rl.Rectangle{ 0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }

	rl.BeginShaderMode(g.shader)
		// Bind the static noise as texture1 (texture0 is the drawn scene target).
		rl.SetShaderValueTexture(g.shader, rl.GetShaderLocation(g.shader, "texture1"), g.noise)
		rl.DrawTexturePro(g.target.texture, src, dst, rl.Vector2{}, 0, rl.WHITE)
	rl.EndShaderMode()
}

unload_grain :: proc(g: ^Grain) {
	rl.UnloadRenderTexture(g.target)
	rl.UnloadTexture(g.noise)
	rl.UnloadShader(g.shader)
}
