package inventory

import "core:math"

import rl "vendor:raylib"

import "items"
import "../collision"
import "../entity"

// Items dropped into the world. Held by pointer so their addresses stay stable:
// each placed item owns its collision tris (whose `owner` points back at the
// item's entity) and is wrapped by an entity whose `actual` points at the item.
// A value array's reallocation on append would leave both dangling - the same
// reason the entity registry holds pointers (see the entity package).
g_placed_items : [dynamic]^Placed_Item

Placed_Item :: struct {
	id:       items.Item_Id,
	position: rl.Vector3,
	tris:     [dynamic]collision.Triangle,
	ent:      ^entity.Entity, // the PLACED_ITEM entity wrapping this item

	// Full model->world transform: the item's local up rotated onto the surface
	// normal, its placed_rot offset applied first, then translated to position.
	// Drawing and the collision tris are both derived from this one matrix so
	// they always agree.
	transform: rl.Matrix,
}

// Drops one of the currently held item into the world at `pos`, seated flat on
// the surface whose `normal` was hit: the model's local up is rotated onto that
// normal (with the item's placed_rot applied as a local offset). Registers it as
// a PLACED_ITEM entity so the picker can find it and empties the held hotbar
// slot. No-op when that slot is empty.
place_item :: proc(pos: rl.Vector3, normal: rl.Vector3) {
	id := g_hotbar[g_hb_index]
	if id == .NOTHING {
		return
	}

	placed := new(Placed_Item)
	placed.id = id
	placed.position = pos
	placed.transform = _placement_transform(pos, normal, items.g_items[id].placed_rot)

	// Build the tris in the model's local space, then push them through the same
	// transform used to draw, so they are the world-space source of truth the
	// picker reads and they line up exactly with the rendered mesh.
	model := items.g_items[id].model
	for i in 0..<int(model.meshCount) {
		collision.append_mesh_tris(&placed.tris, model.meshes[i], rl.Vector3 {})
	}
	collision.transform_tris(placed.tris[:], placed.transform)

	e := entity.add(.PLACED_ITEM, placed)
	placed.ent = e
	for &t in placed.tris {
		t.owner = e
	}

	append(&g_placed_items, placed)

	// The held item left the hand for the world: empty its slot.
	g_hotbar[g_hb_index] = .NOTHING
}

// Builds the model->world matrix for an item seated at `pos` on a surface with
// unit `normal`. In apply-order: the placed_rot euler offset (Z, then X, then Y
// to match the viewmodel's local pose convention), then the rotation that
// carries local up (+Y) onto `normal`, then the translation to `pos`.
@(private="file")
_placement_transform :: proc(pos: rl.Vector3, normal: rl.Vector3, placed_rot: rl.Vector3) -> rl.Matrix {
	// Applied to a local vertex right-to-left (Vector3Transform computes m * v):
	// the placed_rot offset first (Z, then X, then Y), then the up->normal
	// alignment, then the translation - so the offset and alignment rotate the
	// mesh but leave `pos` itself untranslated.
	euler := rl.MatrixRotateY(placed_rot.y * rl.DEG2RAD) *
	         rl.MatrixRotateX(placed_rot.x * rl.DEG2RAD) *
	         rl.MatrixRotateZ(placed_rot.z * rl.DEG2RAD)

	align := _align_up_to(rl.Vector3Normalize(normal))

	translate := rl.MatrixTranslate(pos.x, pos.y, pos.z)

	return translate * align * euler
}

// The minimal rotation carrying local up (+Y) onto unit `n`.
@(private="file")
_align_up_to :: proc(n: rl.Vector3) -> rl.Matrix {
	up := rl.Vector3 { 0, 1, 0 }
	d := clamp(rl.Vector3DotProduct(up, n), -1, 1)

	if d > 0.9999 {
		return rl.Matrix(1) // already pointing along the normal
	}
	if d < -0.9999 {
		return rl.MatrixRotate({ 1, 0, 0 }, math.PI) // antiparallel: flip about any axis
	}

	axis := rl.Vector3Normalize(rl.Vector3CrossProduct(up, n))
	return rl.MatrixRotate(axis, math.acos(d))
}

// Picks `placed` back up: returns one of its item to the hotbar and removes it
// from the world - its entity (so it stops being pickable), its slot in the
// placed list, and its own allocation and tris.
pickup_item :: proc(placed: ^Placed_Item) {
	add_to_hotbar(placed.id)

	entity.remove(placed.ent)

	for p, i in g_placed_items {
		if p == placed {
			unordered_remove(&g_placed_items, i)
			break
		}
	}

	delete(placed.tris)
	free(placed)
}

// Draws every placed item through its stored transform (orientation + position),
// so the rendered mesh lines up with its collision tris. Pass `wires` (dev mode)
// to overlay the collision wireframe. The model is copied by value first so
// setting its transform never touches the shared item model the viewmodel draws.
draw_placed :: proc(wires: bool) {
	for placed in g_placed_items {
		model := items.g_items[placed.id].model
		model.transform = placed.transform

		rl.DrawModel(model, {}, 1.0, rl.WHITE)

		if wires {
			rl.DrawModelWires(model, {}, 1.0, rl.DARKGRAY)
		}
	}
}

// Frees every placed item's tris and allocation at shutdown. Their entities are
// owned by the entity registry and cleared separately (entity.clear).
unload_placed :: proc() {
	for placed in g_placed_items {
		delete(placed.tris)
		free(placed)
	}

	delete(g_placed_items)
	g_placed_items = nil
}
