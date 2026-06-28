package game

import "core:math"
import "core:math/linalg"

import rl "vendor:raylib"

@(private="file")
GRAVITY : f32 : 32.0

@(private="file")
MAX_SPEED : f32 : 20.0

@(private="file")
CROUCH_SPEED : f32 : 5.0

@(private="file")
JUMP_FORCE : f32 : 12.0

@(private="file")
MAX_ACCEL : f32 : 150.0

@(private="file")
FRICION : f32 : 0.86

@(private="file")
AIR_DRAG : f32 : 0.98

@(private="file")
CONTROL : f32 : 15.0

@(private="file")
CROUCH_HEIGHT : f32 : 0.0

@(private="file")
STAND_HEIGHT : f32 : 1.0

@(private="file")
BOTTOM_HEIGHT : f32 : 0.5

@(private="file")
PLAYER_RADIUS : f32 : 0.5

player_cam := rl.Camera3D { }

player_body := Body { }

@(private="file")
_look := rl.Vector2 { }

@(private="file")
_head_lerp := STAND_HEIGHT

@(private="file")
_sensitivity := rl.Vector2 { 0.001, 0.001 }

setup_player :: proc() {
	player_cam.up = { 0.0, 1.0, 0.0 }
	player_cam.fovy = 60.0
	player_cam.projection = .PERSPECTIVE
	player_cam.position = {
		player_body.position.x,
		player_body.position.y + (BOTTOM_HEIGHT + _head_lerp),
		player_body.position.z
	}

	_update_camera()
}

update_player :: proc(world:^World) {
	mouse_delta := rl.GetMouseDelta()
	_look.x -= mouse_delta.x * _sensitivity.x
	_look.y += mouse_delta.y * _sensitivity.y

	sideways := i8(rl.IsKeyDown(.D)) - i8(rl.IsKeyDown(.A))
	forwards := i8(rl.IsKeyDown(.W)) - i8(rl.IsKeyDown(.S))
	crouching := rl.IsKeyDown(.LEFT_CONTROL)
	jumping := rl.IsKeyPressed(.SPACE)

	_update_body(world.tris[:], _look.x, sideways, forwards, jumping, crouching)

	delta := rl.GetFrameTime()
	_head_lerp = math.lerp(
		_head_lerp,
		crouching ? CROUCH_HEIGHT : STAND_HEIGHT,
		20.0 * delta
	)

	player_cam.position = {
		player_body.position.x,
		player_body.position.y + (BOTTOM_HEIGHT + _head_lerp),
		player_body.position.z
	}

	_update_camera()
}

@(private="file")
_update_body :: proc(tris:[]Triangle, rot:f32, side:i8, forward:i8, jump:bool, crouch:bool) {
	input := rl.Vector2 { f32(side), f32(-forward) }

	if side != 0 && forward != 0 {
		input = rl.Vector2Normalize(input)
	}

	delta := rl.GetFrameTime()

	if (!player_body.grounded) {
		player_body.velocity.y -= GRAVITY * delta
	}

	if (player_body.grounded && jump) {
		player_body.velocity.y = JUMP_FORCE
		player_body.grounded = false
	}

	front := rl.Vector3 { math.sin(rot), 0.0, math.cos(rot) }
	right := rl.Vector3 { math.cos(-rot), 0.0, math.sin(-rot) }

	desired := rl.Vector3 {
		input.x * right.x + input.y * front.x,
		0.0,
		input.x * right.z + input.y * front.z
	}

	player_body.direction = linalg.lerp(player_body.direction, desired, CONTROL * delta)

	decel := player_body.grounded ? FRICION : AIR_DRAG
	hvelo := rl.Vector3 { player_body.velocity.x * decel, 0.0, player_body.velocity.z * decel }

	hvelo_length := rl.Vector3Length(hvelo)

	if (hvelo_length < MAX_SPEED * 0.01) {
		hvelo = rl.Vector3 { }
	}

	speed := rl.Vector3DotProduct(hvelo, player_body.direction)

	max_speed := crouch ? CROUCH_SPEED : MAX_SPEED
	accel := math.clamp(max_speed - speed, 0.0, MAX_ACCEL * delta)

	hvelo.x += player_body.direction.x * accel
	hvelo.z += player_body.direction.z * accel

	player_body.velocity.x = hvelo.x
	player_body.velocity.z = hvelo.z

	move_and_collide(&player_body, PLAYER_RADIUS, tris, delta)
}

@(private="file")
_update_camera :: proc() {
	UP :: rl.Vector3 { 0.0, 1.0, 0.0 }
	TARGET_OFFSET :: rl.Vector3 { 0.0, 0.0, -1.0 }

	yaw := rl.Vector3RotateByAxisAngle(TARGET_OFFSET, UP, _look.x)

	max_angle_up := rl.Vector3Angle(UP, yaw) - 0.001

	if -_look.y > max_angle_up {
		_look.y = -max_angle_up
	}

	max_angle_down := rl.Vector3Angle(-UP, yaw) * -1.0 + 0.001

	if -_look.y < max_angle_down {
		_look.y = -max_angle_down
	}

	right := rl.Vector3Normalize(rl.Vector3CrossProduct(yaw, UP))

	pitch_angle := -_look.y
	pitch_angle = math.clamp(pitch_angle, -math.PI/2 + 0.0001, math.PI/2 - 0.0001)
	pitch := rl.Vector3RotateByAxisAngle(yaw, right, pitch_angle)

	player_cam.target = player_cam.position + pitch
}
