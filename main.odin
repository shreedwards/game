package game

import "core:math"

import rl "vendor:raylib"

sensitivity := rl.Vector2 { 0.001, 0.001 }

player := Body { }
look_rotation := rl.Vector2 { }
head_lerp := STAND_HEIGHT

main :: proc() {
	rl.SetConfigFlags({ .MSAA_4X_HINT })
	rl.InitWindow(1920, 1080, "Game")

	world := create_world()

	camera := rl.Camera3D { }
	camera.up = { 0.0, 1.0, 0.0 }
	camera.fovy = 60.0
	camera.projection = .PERSPECTIVE
	camera.position = {
		player.position.x,
		player.position.y + (BOTTOM_HEIGHT + head_lerp),
		player.position.z
	}

	update_camera(&camera, &look_rotation)

	rl.DisableCursor()
	rl.SetTargetFPS(120)

	for !rl.WindowShouldClose() {
		mouse_delta := rl.GetMouseDelta()
		look_rotation.x -= mouse_delta.x * sensitivity.x
		look_rotation.y += mouse_delta.y * sensitivity.y

		sideways := i8(rl.IsKeyDown(.D)) - i8(rl.IsKeyDown(.A))
		forwards := i8(rl.IsKeyDown(.W)) - i8(rl.IsKeyDown(.S))
		crouching := rl.IsKeyDown(.LEFT_CONTROL)
		jumping := rl.IsKeyPressed(.SPACE)

		update_body(&player, world.tris[:], look_rotation.x, sideways, forwards, jumping, crouching)

		delta := rl.GetFrameTime()
		head_lerp = math.lerp(
			head_lerp,
			crouching ? CROUCH_HEIGHT : STAND_HEIGHT,
			20.0 * delta
		)

		camera.position = {
			player.position.x,
			player.position.y + (BOTTOM_HEIGHT + head_lerp),
			player.position.z
		}

		update_camera(&camera, &look_rotation)

		rl.BeginDrawing()
			rl.ClearBackground(rl.RAYWHITE)
			rl.DrawFPS(10, 10)

			rl.BeginMode3D(camera)
				draw_world(&world)
			rl.EndMode3D()
		rl.EndDrawing()
	}

	unload_world(&world)
	rl.CloseWindow()
}
