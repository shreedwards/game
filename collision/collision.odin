package collision

import rl "vendor:raylib"

import "../entity"

Body :: struct {
	position:  rl.Vector3,
	velocity:  rl.Vector3,
	direction: rl.Vector3,
	grounded:  bool,
}

Triangle :: struct {
	a: rl.Vector3,
	b: rl.Vector3,
	c: rl.Vector3,
	normal: rl.Vector3,

	// The entity this triangle belongs to (see the entity package). Nil until the
	// owning entity exists - set once, after the tris are in their final world
	// buffers.
	owner: ^entity.Entity
}

move_and_collide :: proc(body:^Body, radius:f32, tris:[]^Triangle, delta:f32) {
	body.position += body.velocity * delta
	body.grounded = false

	for _ in 0..<4 {
		center := body.position + rl.Vector3 { 0, radius, 0 }

		for t in tris {
			closest := _closest_point_on_triangle(center, t.a, t.b, t.c)
			diff := center - closest
			dist := rl.Vector3Length(diff)

			if dist < radius && dist > 0.00001 {
				n := diff / dist
				push := radius - dist

				body.position += n * push

				into := rl.Vector3DotProduct(body.velocity, n)

				if into < 0 {
					body.velocity -=  n * into
				}

				if n.y > 0.7 {
					body.grounded = true
				}
			}
		}
	}
}

append_mesh_tris :: proc(
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

		return Triangle { a = a, b = b, c = c, normal = n }
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

// Shifts every triangle in `tris` by `offset`, in place. Used to move a model's
// local-space collision tris to its final world position, once that position is
// known - the tris stay the single source of truth the world points into.
translate_tris :: proc(tris: []Triangle, offset: rl.Vector3) {
	for &t in tris {
		t.a += offset
		t.b += offset
		t.c += offset
	}
}


// Derived from Ericson's Real-Time Collision Detection
@(private="file")
_closest_point_on_triangle :: proc(p, a, b, c: rl.Vector3) -> rl.Vector3 {
	ab := b - a
	ac := c - a
	ap := p - a

	d1 := rl.Vector3DotProduct(ab, ap)
	d2 := rl.Vector3DotProduct(ac, ap)
	if d1 <= 0 && d2 <= 0 do return a // vertex A

	bp := p - b
	d3 := rl.Vector3DotProduct(ab, bp)
	d4 := rl.Vector3DotProduct(ac, bp)
	if d3 >= 0 && d4 <= d3 do return b // vertex B

	vc := d1 * d4 - d3 * d2
	if vc <= 0 && d1 >= 0 && d3 <= 0 {
		v := d1 / (d1 - d3)
		return a + ab * v // edge AB
	}

	cp := p - c
	d5 := rl.Vector3DotProduct(ab, cp)
	d6 := rl.Vector3DotProduct(ac, cp)
	if d6 >= 0 && d5 <= d6 do return c // vertex C

	vb := d5 * d2 - d1 * d6
	if vb <= 0 && d2 >= 0 && d6 <= 0 {
		w := d2 / (d2 - d6)
		return a + ac * w // edge AC
	}

	va := d3 * d6 - d5 * d4
	if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
		w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return b + (c - b) * w // edge BC
	}

	denom := 1.0 / (va + vb + vc) // face
	v := vb * denom
	w := vc * denom
	return a + ab * v + ac * w
}
