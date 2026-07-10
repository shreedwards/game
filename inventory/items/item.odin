package items

import rl "vendor:raylib"

import "../../entity"

g_items : map[Item_Id]Item

register_all_items :: proc() {
	register_rock()
}

// Unloads every registered item's GPU model and empties the registry. Call at
// shutdown, before CloseWindow.
unload_all_items :: proc() {
	for _, item in g_items {
		rl.UnloadModel(item.model)
	}

	delete(g_items)
	g_items = nil
}

Item_Id :: enum {
	NOTHING,
	ROCK
}

Action_Handler :: proc(entity:^entity.Entity, point:rl.Vector3)

Item :: struct {
	model: rl.Model,
	held_rot: rl.Vector3,
	placed_rot: rl.Vector3,
	primary: Action_Handler,
	secondary: Action_Handler
}
