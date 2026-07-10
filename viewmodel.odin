package game

import "core:math"

import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "inventory"
import "inventory/items"
import "shader"

// The held-item viewmodel: the active hotbar item, rendered fully 3D in the
// bottom-right corner so it reads as "in hand", with a swing animation on use.
//
// It draws with a fixed camera at the origin looking down -Z, so the item sits
// at a constant screen position no matter where the player looks, and camera
// space reads as right/up/forward offsets.
//
// The item is rendered into its own transparent render target rather than
// straight into the grain target's 3D pass: the grain target's depth buffer
// holds world depths from the player camera, so nearby terrain would clip
// chunks out of the item (and raylib has no depth-only clear). An off-screen
// target gives the item its own depth buffer - it self-occludes correctly and
// can never be cut by world geometry. Compositing that target onto the grain
// target (composite_viewmodel, inside the grain pass) puts the item through
// the same grain + supersample resolve as the rest of the scene.

// Rest transform in camera space: nudged right and down so the item pokes in
// from the corner, angled so more than one face catches the light.
VM_REST_POS :: rl.Vector3{ 0.70, -0.45, -1.40 }
VM_REST_YAW :: f32(-35) // degrees around Y
VM_SCALE    :: f32(1.0)

// The swing: a timer counts down from SWING_DURATION and sin(pi * progress)
// turns it into a smooth out-and-back arc (0 at rest, 1 mid-swing, 0 again),
// which drives a forward dip and a down-left push.
SWING_DURATION :: f32(0.25)                          // seconds
SWING_ARC_DIP  :: f32(65)                            // degrees forward at the arc's peak
SWING_ARC_POS  :: rl.Vector3{ -0.25, -0.20, -0.15 }  // offset at the arc's peak

@(private="file")
VIEWMODEL_CAM :: rl.Camera3D {
	position   = { 0, 0,  0 },
	target     = { 0, 0, -1 },
	up         = { 0, 1,  0 },
	fovy       = 45,
	projection = .PERSPECTIVE,
}

Viewmodel :: struct {
	target: rl.RenderTexture2D,
	swing:  f32, // seconds left in the current swing; 0 = at rest
}

// Creates the off-screen target (grain-target sized, so it composites 1:1)
// and wires every registered item's model to the shared sun. Call after
// InitWindow, register_all_items, and load_shaders.
create_viewmodel :: proc(screen_w: i32, screen_h: i32) -> Viewmodel {
	vm: Viewmodel

	vm.target = rl.LoadRenderTexture(screen_w * SSAA_SCALE, screen_h * SSAA_SCALE)
	// POINT: the composite onto the grain target is 1:1, never resampled.
	rl.SetTextureFilter(vm.target.texture, .POINT)

	// Items render with the same lit shader as the world's props, so the hand
	// matches the scene's sun.
	for _, item in items.g_items {
		shader.apply_shader(item.model, shader.g_shaders.lit)
	}

	return vm
}

// Kick off (or restart) a swing; call on item use, hit or miss.
swing_viewmodel :: proc(vm: ^Viewmodel) {
	vm.swing = SWING_DURATION
}

update_viewmodel :: proc(vm: ^Viewmodel) {
	vm.swing = max(vm.swing - rl.GetFrameTime(), 0)
}

// Renders the held item into the viewmodel's own target. Call before
// begin_grain - texture modes can't nest, so this pass must run outside the
// grain capture.
render_viewmodel :: proc(vm: ^Viewmodel) {
	hand := inventory.g_hotbar[inventory.g_hb_index]

	rl.BeginTextureMode(vm.target)
		rl.ClearBackground(rl.BLANK) // transparent: only the item composites over the world

		if hand != .NOTHING {
			item := items.g_items[hand]

			// 0 at rest and at the swing's end, 1 mid-swing.
			arc := math.sin(math.PI * (1 - vm.swing / SWING_DURATION))

			pos := VM_REST_POS + SWING_ARC_POS * arc

			rl.BeginMode3D(VIEWMODEL_CAM)
				rlgl.PushMatrix()
					rlgl.Translatef(pos.x, pos.y, pos.z)
					rlgl.Rotatef(-SWING_ARC_DIP * arc, 1, 0, 0) // dip forward through the arc
					rlgl.Rotatef(VM_REST_YAW, 0, 1, 0)          // angled rest pose
					// per-item pose fixup (Y, X, Z), applied in the model's local space
					rlgl.Rotatef(item.held_rot.y, 0, 1, 0)
					rlgl.Rotatef(item.held_rot.x, 1, 0, 0)
					rlgl.Rotatef(item.held_rot.z, 0, 0, 1)
					rl.DrawModel(item.model, {}, VM_SCALE, rl.WHITE)
				rlgl.PopMatrix()
			rl.EndMode3D()
		}
	rl.EndTextureMode()
}

// Alpha-blends the rendered item over the scene. Call inside the grain pass
// (between begin_grain and end_grain, after the world), so the item gets the
// film grain and the supersample resolve like everything else.
composite_viewmodel :: proc(vm: ^Viewmodel) {
	// Render textures are stored bottom-up: flip V with a negative source height.
	src := rl.Rectangle{ 0, 0, f32(vm.target.texture.width), -f32(vm.target.texture.height) }
	rl.DrawTextureRec(vm.target.texture, src, {}, rl.WHITE)
}

unload_viewmodel :: proc(vm: ^Viewmodel) {
	rl.UnloadRenderTexture(vm.target)
}
