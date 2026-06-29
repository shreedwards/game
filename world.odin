package game

import "core:c"
import rl "vendor:raylib"

Triangle :: struct {
	a: rl.Vector3,
	b: rl.Vector3,
	c: rl.Vector3,
	normal: rl.Vector3
}

World :: struct {
	island: rl.Model,

	tris: [dynamic]Triangle
}

create_world :: proc() -> World {
	world: World

	island_mesh := gen_island(45, 45, 7.5)
	world.island = rl.LoadModelFromMesh(island_mesh)

	_append_mesh_tris(&world.tris, island_mesh, rl.Vector3 { })

	return world
}

draw_world :: proc(world: ^World) {

	rl.DrawModel(world.island, rl.Vector3 { }, 1.0, rl.LIGHTGRAY)
	rl.DrawModelWires(world.island, rl.Vector3 { }, 1.0, rl.DARKGRAY)

	rl.DrawSphere(
		{ 300.0, 300.0, 0.0 },
		100.0,
		rl.RED
	)
}

unload_world :: proc(world: ^World) {
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
