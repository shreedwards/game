package game

import "core:math"
import "core:math/linalg"

import rl "vendor:raylib"

GRAVITY : f32 : 32.0
MAX_SPEED : f32 : 20.0
CROUCH_SPEED : f32 : 5.0
JUMP_FORCE : f32 : 12.0
MAX_ACCEL : f32 : 150.0
FRICION : f32 : 0.86
AIR_DRAG : f32 : 0.98
CONTROL : f32 : 15.0
CROUCH_HEIGHT : f32 : 0.0
STAND_HEIGHT : f32 : 1.0
BOTTOM_HEIGHT : f32 : 0.5
PLAYER_RADIUS : f32 : 0.5

update_body :: proc(body:^Body, tris:[]Triangle, rot:f32, side:i8, forward:i8, jump:bool, crouch:bool) {
	input := rl.Vector2 { f32(side), f32(-forward) }

	if side != 0 && forward != 0 {
		input = rl.Vector2Normalize(input)
	}

	delta := rl.GetFrameTime()

	if (!body.grounded) {
		body.velocity.y -= GRAVITY * delta
	}

	if (body.grounded && jump) {
		body.velocity.y = JUMP_FORCE
		body.grounded = false
	}

	front := rl.Vector3 { math.sin(rot), 0.0, math.cos(rot) }
	right := rl.Vector3 { math.cos(-rot), 0.0, math.sin(-rot) }

	desired := rl.Vector3 {
		input.x * right.x + input.y * front.x,
		0.0,
		input.x * right.z + input.y * front.z
	}

	body.direction = linalg.lerp(body.direction, desired, CONTROL * delta)

	decel := body.grounded ? FRICION : AIR_DRAG
	hvelo := rl.Vector3 { body.velocity.x * decel, 0.0, body.velocity.z * decel }

	hvelo_length := rl.Vector3Length(hvelo)

	if (hvelo_length < MAX_SPEED * 0.01) {
		hvelo = rl.Vector3 { }
	}

	speed := rl.Vector3DotProduct(hvelo, body.direction)

	max_speed := crouch ? CROUCH_SPEED : MAX_SPEED
	accel := math.clamp(max_speed - speed, 0.0, MAX_ACCEL * delta)

	hvelo.x += body.direction.x * accel
	hvelo.z += body.direction.z * accel

	body.velocity.x = hvelo.x
	body.velocity.z = hvelo.z

	move_and_collide(body, PLAYER_RADIUS, tris, delta)
}
