package items

import "core:fmt"

import rl "vendor:raylib"

import "../../entity"

register_rock :: proc() {
	model := rl.LoadModel("assets/models/rock.gltf")

	g_items[.ROCK] = Item {
		model = model,
		held_rot = { 0.0, 0.0, 0.0 },
		placed_rot = { 0.0, 0.0, 0.0 },
		primary = _on_primary,
		secondary = _on_secondary
	}
}

@(private="file")
_on_primary :: proc(entity:^entity.Entity, point:rl.Vector3) {
	fmt.println("Rock primary!")
}

@(private="file")
_on_secondary :: proc(entity:^entity.Entity, point:rl.Vector3) {
	fmt.println("Rock secondary!")
}
