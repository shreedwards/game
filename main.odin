package game

import rl "vendor:raylib"

import "shader"
import "texture"

active_cam := &player_cam
dev_mode := false

main :: proc() {
	rl.SetConfigFlags({ .MSAA_4X_HINT })
	rl.InitWindow(1920, 1080, "Game")

	// Global resources: shaders and textures are loaded once at launch and
	// unloaded once at shutdown.
	shader.load_shaders()
	texture.load_textures()

	world := create_world()

	grain := create_grain(rl.GetScreenWidth(), rl.GetScreenHeight())

	setup_player()

	rl.DisableCursor()
	rl.SetTargetFPS(120)

	for !rl.WindowShouldClose() {
		if dev_mode {
			update_free_cam()
		} else {
			update_player(&world)
		}

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

		rl.EndDrawing()
	}

	unload_grain(&grain)
	unload_world(&world)
	texture.unload_textures()
	shader.unload_shaders()
	rl.CloseWindow()
}
