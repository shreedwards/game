package entity

// Every interactable thing in the world (a ground, a tree, ...). Entities are
// heap-allocated and held by pointer so their addresses stay stable: collision
// triangles point back at their owning entity (collision.Triangle.owner), and
// the picker walks from a hit triangle to its entity. Those pointers must
// survive g_entities growing, which a value array's reallocation would break.
//
// This package sits at the bottom of the dependency graph (it imports nothing),
// so both collision and game can name Entity without an import cycle - which is
// what lets a triangle carry a real typed owner pointer.
g_entities: [dynamic]^Entity

Entity :: struct {
	kind:   Kind,
	actual: rawptr, // the concrete object: ^island.Ground, ^island.Tree, ...
}

Kind :: enum {
	GROUND,
	TREE,
	PLACED_ITEM
}

// Creates an entity of `kind` wrapping `actual` and returns a stable pointer to
// it - the value stored in each of the object's collision triangles as `owner`.
add :: proc(kind: Kind, actual: rawptr) -> ^Entity {
	e := new(Entity)
	e^ = Entity { kind, actual }

	append(&g_entities, e)

	return e
}

// Removes `e` from the registry and frees it. Used when a placed item is picked
// back up: its entity should no longer be reachable by the picker. The caller
// must ensure no collision triangles still point at `e` before calling.
remove :: proc(e: ^Entity) {
	for other, i in g_entities {
		if other == e {
			ordered_remove(&g_entities, i)
			break
		}
	}

	free(e)
}

// Frees every entity and empties the registry. Call at shutdown, after the
// triangles that reference these entities are gone.
clear :: proc() {
	for e in g_entities {
		free(e)
	}

	delete(g_entities)
	g_entities = nil
}
