package game

import rl "vendor:raylib"

Body :: struct {
	position:  rl.Vector3,
	velocity:  rl.Vector3,
	direction: rl.Vector3,
	grounded:  bool,
}

move_and_collide :: proc(body:^Body, radius:f32, tris:[]Triangle, delta:f32) {
	body.position += body.velocity * delta
	body.grounded = false

	for _ in 0..<4 {
		center := body.position + rl.Vector3 { 0, radius, 0 }

		for t in tris {
			closest := _closest_point_on_triangle(center, t.a, t.b, t.c)
			diff := center - closest
			dist := rl.Vector3Length(diff)

			if dist < PLAYER_RADIUS && dist > 0.00001 {
				n := diff / dist
				push := PLAYER_RADIUS - dist

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


// Derived from Ericson's Real-Time Collision Detection
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
