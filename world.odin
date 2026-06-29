package game

import "core:c"
import rl "vendor:raylib"

FLOOR_EXTENT :: 25
TILE_SIZE :: 5.0
TILE_COLOR :: rl.GREEN
TOWER_SIZE :: rl.Vector3 { 16.0, 32.0, 16.0 }
TOWER_COLOR :: rl.GRAY
FLOOR_SIZE :: f32(FLOOR_EXTENT) * TILE_SIZE * 2.0

Triangle :: struct {
	a: rl.Vector3,
	b: rl.Vector3,
	c: rl.Vector3,
	normal: rl.Vector3
}

World :: struct {
	floor: rl.Model,
	tower: rl.Model,
	spots: [4]rl.Vector3,
	island: rl.Model,

	tris: [dynamic]Triangle
}

create_world :: proc() -> World {
	world: World

	floor_mesh := rl.GenMeshPlane(FLOOR_SIZE, FLOOR_SIZE, 4, 4)
	world.floor = rl.LoadModelFromMesh(floor_mesh)

	tower_mesh := rl.GenMeshCube(TOWER_SIZE.x, TOWER_SIZE.y, TOWER_SIZE.z)
	world.tower = rl.LoadModelFromMesh(tower_mesh)

	island_mesh := gen_island(45, 45, 7.5)
	world.island = rl.LoadModelFromMesh(island_mesh)

	world.spots = {
		{  16.0, 16.0,  16.0 },
		{ -16.0, 16.0,  16.0 },
		{ -16.0, 16.0, -16.0 },
		{  16.0, 16.0, -16.0 }
	}

	_append_mesh_tris(&world.tris, floor_mesh, rl.Vector3 { })
	_append_mesh_tris(&world.tris, island_mesh, rl.Vector3 { 125.0, 1.0, 0.0 })

	for spot in world.spots {
		_append_mesh_tris(&world.tris, tower_mesh, spot)
	}

	return world
}

draw_world :: proc(world: ^World) {
	rl.DrawModel(world.floor, rl.Vector3 { }, 1.0, TILE_COLOR)
	rl.DrawModelWires(world.floor, rl.Vector3 { }, 1.0, rl.DARKGRAY)

	rl.DrawModel(world.island, rl.Vector3 { 125.0, 1.0, 0.0 }, 1.0, rl.LIGHTGRAY)
	rl.DrawModelWires(world.island, rl.Vector3 { 125.0, 1.0, 0.0 }, 1.0, rl.DARKGRAY)

	for spot in world.spots {
		rl.DrawModel(world.tower, spot, 1.0, TOWER_COLOR)
		rl.DrawModelWires(world.tower, spot, 1.0, rl.DARKGRAY)
	}

	rl.DrawSphere(
		{ 300.0, 300.0, 0.0 },
		100.0,
		rl.RED
	)
}

unload_world :: proc(world: ^World) {
	rl.UnloadModel(world.floor)
	rl.UnloadModel(world.tower)
	rl.UnloadModel(world.island)
	delete(world.tris)
}

_append_mesh_tris :: proc(
	tris: ^[dynamic]Triangle,
	mesh: rl.Mesh,
	offset: rl.Vector3
) {
	v := mesh.vertices

	vert :: proc(v:[^]f32, i:int, offset:rl.Vector3) -> rl.Vector3 {
		return rl.Vector3 { v[i*3], v[i*3 + 1], v[i*3 + 2] } + offset
	}

	make_tri :: proc(a, b, c: rl.Vector3) -> Triangle {
		n := rl.Vector3Normalize(rl.Vector3CrossProduct(b - a, c -a))

		return Triangle { a, b, c, n }
	}

	if mesh.indices != nil {
		idx := mesh.indices

		for t in 0..<int(mesh.triangleCount) {
			a := vert(v, int(idx[t*3 + 0]), offset)
			b := vert(v, int(idx[t*3 + 1]), offset)
			c := vert(v, int(idx[t*3 + 2]), offset)

			append(tris, make_tri(a, b, c))
		}
	} else {
		for t in 0..<int(mesh.triangleCount) {
			a := vert(v, t*3 + 0, offset)
			b := vert(v, t*3 + 1, offset)
			c := vert(v, t*3 + 2, offset)

			append(tris, make_tri(a, b, c))
		}
	}
}
