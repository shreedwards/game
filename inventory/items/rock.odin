package items

import "core:fmt"

import rl "vendor:raylib"

import "../../entity"

register_rock :: proc() {
	mesh := rl.GenMeshCube(2.0, 2.0, 2.0)
	model := rl.LoadModelFromMesh(mesh)

	g_items[.ROCK] = Item {
		model = model,
		primary = _on_primary,
		secondary = _on_secondary
	}
}

@(private="file")
_on_primary :: proc(target:^entity.Entity) {
	fmt.println("Rock primary!")
}

@(private="file")
_on_secondary :: proc(target:^entity.Entity) {
	fmt.println("Rock secondary!")
}
