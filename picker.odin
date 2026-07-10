package game

import rl "vendor:raylib"

import "entity"
import "inventory"

// Result of a pick: the entity under the cursor, where the ray hit it, the
// surface normal of the triangle it hit, and whether anything was hit at all.
Pick :: struct {
	entity: ^entity.Entity,
	point:  rl.Vector3,
	normal: rl.Vector3,
	hit:    bool,
}

// Casts a ray from the crosshair into the world and returns the nearest entity
// it hits. World triangles are the single source of truth and already carry an
// owner pointer, so we test the ray against them directly and follow the
// winning triangle back to its entity. The nearest hit (smallest distance) is
// the one actually under the crosshair - a ray pierces everything behind it too.
//
// The ray comes from the exact screen center, not GetMousePosition: the cursor
// is disabled (we drive the look with mouse *delta*), so the reported cursor
// position drifts and would send the ray off from where the player is aiming.
pick_world :: proc(world: ^World, cam: rl.Camera) -> Pick {
	center := rl.Vector2 {
		f32(rl.GetScreenWidth())  / 2.0,
		f32(rl.GetScreenHeight()) / 2.0
	}

	ray := rl.GetScreenToWorldRay(center, cam)

	best: Pick
	best_dist := max(f32)

	for t in world.tris {
		hit := rl.GetRayCollisionTriangle(ray, t.a, t.b, t.c)

		if hit.hit && hit.distance < best_dist {
			best_dist   = hit.distance
			best.entity = t.owner
			best.point  = hit.point
			best.normal = t.normal
			best.hit    = true
		}
	}

	// Placed items live outside world.tris (the inventory package can't reach into
	// the World), so test their tris here too. They carry the same owner pointers,
	// so a hit resolves to a PLACED_ITEM entity just like a ground or tree.
	for placed in inventory.g_placed_items {
		for &t in placed.tris {
			hit := rl.GetRayCollisionTriangle(ray, t.a, t.b, t.c)

			if hit.hit && hit.distance < best_dist {
				best_dist   = hit.distance
				best.entity = t.owner
				best.point  = hit.point
				best.normal = t.normal
				best.hit    = true
			}
		}
	}

	return best
}
