package game

import "core:fmt"

import rl "vendor:raylib"

import "entity"
import "shader"
import "texture"

active_cam := &player_cam
dev_mode := false

main :: proc() {
	rl.SetConfigFlags({ .MSAA_4X_HINT })
	rl.InitWindow(1600, 900, "Game")

	// Global resources: shaders and textures are loaded once at launch and
	// unloaded once at shutdown.
	shader.load_shaders()
	texture.load_textures()

	world := create_world()

	grain := create_grain(rl.GetScreenWidth(), rl.GetScreenHeight())

	setup_player()

	rl.DisableCursor()
	rl.SetTargetFPS(120)

	// Left-click picking: the kind of the last-hit entity, shown for a few
	// seconds after the click.
	pick_kind:  entity.Kind
	pick_timer: f32 = 0.0

	for !rl.WindowShouldClose() {
		if dev_mode {
			update_free_cam()
		} else {
			update_player(&world)
		}

		if rl.IsMouseButtonPressed(.LEFT) {
			pick := pick_world(&world, active_cam^)
			if pick.hit {
				pick_kind  = pick.entity.kind
				pick_timer = 3.0
			}
		}

		pick_timer = max(0.0, pick_timer - rl.GetFrameTime())

		if rl.IsKeyPressed(.GRAVE) {
			if dev_mode {
				active_cam = &player_cam
			} else {
				setup_free_cam()
				active_cam = &free_cam
			}

			dev_mode = !dev_mode
		}

		// Render the scene into the supersampled off-screen target...
		begin_grain(&grain)
			rl.ClearBackground(rl.LIGHTGRAY)
			rl.BeginMode3D(active_cam^)
				draw_world(&world)
			rl.EndMode3D()
		end_grain(&grain)

		// ...then present it to the screen through the film-grain shader. HUD is
		// drawn afterwards so it stays crisp and grain-free.
		rl.BeginDrawing()
			present_grain(&grain)

			rl.DrawFPS(10, 10)

			if dev_mode {
				rl.DrawText("DEV", 10, 40, 20, rl.BLACK)
			}

			// Crosshair: a small circle in the dead center of the screen, where
			// the pick ray is cast from.
			cx := rl.GetScreenWidth()  / 2
			cy := rl.GetScreenHeight() / 2
			rl.DrawCircleLines(cx, cy, 4, rl.WHITE)

			if pick_timer > 0.0 {
				rl.DrawText(fmt.ctprintf("%v", pick_kind), 10, 70, 20, rl.BLACK)
			}

		rl.EndDrawing()
	}

	unload_grain(&grain)
	unload_world(&world)
	texture.unload_textures()
	shader.unload_shaders()
	rl.CloseWindow()
}
