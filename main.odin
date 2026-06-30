package game

import "core:math"

import rl "vendor:raylib"

active_cam := &player_cam
dev_mode := false

main :: proc() {
	rl.SetConfigFlags({ .MSAA_4X_HINT })
	rl.InitWindow(1920, 1080, "Game")

	world := create_world()

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

		rl.BeginDrawing()
			rl.ClearBackground(rl.SKYBLUE)
			rl.BeginMode3D(active_cam^)
				draw_world(&world)
			rl.EndMode3D()

			rl.DrawFPS(10, 10)

			if dev_mode {
				rl.DrawText("DEV", 10, 40, 20, rl.BLACK)
			}

		rl.EndDrawing()
	}

	unload_world(&world)
	rl.CloseWindow()
}
