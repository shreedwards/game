package game

import "vendor:stb/rect_pack"
import "core:fmt"

import rl "vendor:raylib"

import "entity"
import "shader"
import "texture"
import "inventory"
import "inventory/items"

active_cam := &player_cam
dev_mode := false

main :: proc() {
	rl.SetConfigFlags({ .MSAA_4X_HINT })
	rl.InitWindow(1600, 900, "Game")

	items.register_all_items()
	inventory.setup_hotbar()

	// Global resources: shaders and textures are loaded once at launch and
	// unloaded once at shutdown.
	shader.load_shaders()
	texture.load_textures()

	world := create_world()

	grain := create_grain(rl.GetScreenWidth(), rl.GetScreenHeight())

	// The held item, drawn in hand. Created after load_shaders so the item
	// models can be wired to the shared sun.
	viewmodel := create_viewmodel(rl.GetScreenWidth(), rl.GetScreenHeight())

	setup_player()

	rl.DisableCursor()
	rl.SetTargetFPS(120)
	for !rl.WindowShouldClose() {
		if dev_mode {
			update_free_cam()
		} else {
			update_player(&world)
		}

		update_viewmodel(&viewmodel)

		// The hand swings on every use, hit or miss; the item action only fires
		// on a hit.
		if rl.IsMouseButtonPressed(.LEFT) {
			swing_viewmodel(&viewmodel)

			pick := pick_world(&world, active_cam^)
			if pick.hit {
				held := inventory.g_hotbar[inventory.g_hb_index]

				if held != .NOTHING {
					items.g_items[held].primary(pick.entity, pick.point)
				}
			}
		}

		if rl.IsMouseButtonPressed(.RIGHT) {
			swing_viewmodel(&viewmodel)

			pick := pick_world(&world, active_cam^)
			if pick.hit {
				held := inventory.g_hotbar[inventory.g_hb_index]

				if held != .NOTHING {
					items.g_items[held].secondary(pick.entity, pick.point)
				}
			}
		}

		if rl.IsKeyPressed(.Q) {
			pick := pick_world(&world, active_cam^)

			if pick.hit {
				if pick.entity.kind == .GROUND {
					inventory.place_item(pick.point, pick.normal)
				}
			}
		}

		if rl.IsKeyPressed(.E) {
			pick := pick_world(&world, active_cam^)

			if pick.hit {
				if pick.entity.kind == .PLACED_ITEM {
					item := cast(^inventory.Placed_Item) pick.entity.actual

					inventory.pickup_item(item)
				}
			}
		}

		// Number keys 1-9 select hotbar slots 0-8.
		for i in 0..<9 {
			if rl.IsKeyPressed(rl.KeyboardKey(int(rl.KeyboardKey.ONE) + i)) {
				inventory.select_slot(i)
			}
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

		// The held item renders into its own target first (texture modes can't
		// nest), then composites into the grain pass below.
		render_viewmodel(&viewmodel)

		// Render the scene into the supersampled off-screen target...
		begin_grain(&grain)
			rl.ClearBackground(rl.LIGHTGRAY)
			rl.BeginMode3D(active_cam^)
				draw_world(&world)
			rl.EndMode3D()

			// The held item goes over the world but inside the grain target, so
			// it picks up the film grain and supersample resolve too.
			composite_viewmodel(&viewmodel)
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

		rl.EndDrawing()
	}

	unload_viewmodel(&viewmodel)
	unload_grain(&grain)
	inventory.unload_placed()
	unload_world(&world)
	items.unload_all_items()
	texture.unload_textures()
	shader.unload_shaders()
	rl.CloseWindow()
}
