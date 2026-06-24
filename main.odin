package game

import "core:c"
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

Body :: struct {
	position:  rl.Vector3,
	velocity:  rl.Vector3,
	direction: rl.Vector3,
	grounded:  bool,
}

sensitivity := rl.Vector2 { 0.001, 0.001 }

player := Body { }
look_rotation := rl.Vector2 { }
head_lerp := STAND_HEIGHT

main :: proc() {
	rl.SetConfigFlags({ .MSAA_4X_HINT })
	rl.InitWindow(1920, 1080, "Game")

	camera := rl.Camera3D {}
	camera.up = { 0.0, 1.0, 0.0 }
	camera.fovy = 60.0
	camera.projection = .PERSPECTIVE
	camera.position = {
		player.position.x,
		player.position.y + (BOTTOM_HEIGHT + head_lerp),
		player.position.z
	}

	update_camera(&camera)

	rl.DisableCursor()
	rl.SetTargetFPS(120)

	for !rl.WindowShouldClose() {
		mouse_delta := rl.GetMouseDelta()
		look_rotation.x -= mouse_delta.x * sensitivity.x
		look_rotation.y += mouse_delta.y * sensitivity.y

		sideways := i8(rl.IsKeyDown(.D)) - i8(rl.IsKeyDown(.A))
		forwards := i8(rl.IsKeyDown(.W)) - i8(rl.IsKeyDown(.S))
		crouching := rl.IsKeyDown(.LEFT_CONTROL)
		jumping := rl.IsKeyPressed(.SPACE)

		update_body(&player, look_rotation.x, sideways, forwards, jumping, crouching)

		delta := rl.GetFrameTime()
		head_lerp = math.lerp(
			head_lerp,
			crouching ? CROUCH_HEIGHT : STAND_HEIGHT,
			20.0 * delta
		)

		camera.position = {
			player.position.x,
			player.position.y + (BOTTOM_HEIGHT + head_lerp),
			player.position.z
		}

		update_camera(&camera)

		rl.BeginDrawing()
			rl.ClearBackground(rl.RAYWHITE)
			rl.DrawFPS(10, 10)

			rl.BeginMode3D(camera)
				draw_level()
			rl.EndMode3D()
		rl.EndDrawing()
	}

	rl.CloseWindow()
}

update_body :: proc(body:^Body, rot:f32, side:i8, forward:i8, jump:bool, crouch:bool) {
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

	body.position.x += body.velocity.x * delta
	body.position.y += body.velocity.y * delta
	body.position.z += body.velocity.z * delta

	if (body.position.y <= 0.0) {
		body.position.y = 0.0;
		body.velocity.y = 0.0;
		body.grounded = true;
	}
}

update_camera :: proc(camera:^rl.Camera) {
	UP :: rl.Vector3 { 0.0, 1.0, 0.0 }
	TARGET_OFFSET :: rl.Vector3 { 0.0, 0.0, -1.0 }

	yaw := rl.Vector3RotateByAxisAngle(TARGET_OFFSET, UP, look_rotation.x)

	max_angle_up := rl.Vector3Angle(UP, yaw) - 0.001

	if -look_rotation.y > max_angle_up {
		look_rotation.y = -max_angle_up
	}

	max_angle_down := rl.Vector3Angle(-UP, yaw) * -1.0 + 0.001

	if -look_rotation.y < max_angle_down {
		look_rotation.y = -max_angle_down
	}

	right := rl.Vector3Normalize(rl.Vector3CrossProduct(yaw, UP))

	pitch_angle := -look_rotation.y
	pitch_angle = math.clamp(pitch_angle, -math.PI/2 + 0.0001, math.PI/2 - 0.0001)
	pitch := rl.Vector3RotateByAxisAngle(yaw, right, pitch_angle)

	camera.target = camera.position + pitch
}

draw_level :: proc() {
	FLOOR_EXTENT :: 25
	TILE_SIZE :: 5.0
	TILE_COLOR :: rl.RED

	for y := -FLOOR_EXTENT; y < FLOOR_EXTENT; y += 1 {
		for x := -FLOOR_EXTENT; x < FLOOR_EXTENT; x += 1 {
			color : rl.Color

			switch {
				case (y & 1) == 1 && (x & 1) == 1:
					color = TILE_COLOR
				case (y & 1) == 0 && (x & 1) == 0:
					color = rl.LIGHTGRAY
				case:
					continue
			}

			rl.DrawPlane(
				{ f32(x) * TILE_SIZE, 0.0, f32(y) * TILE_SIZE },
				{ TILE_SIZE, TILE_SIZE },
				color
			)
		}
	}

	rl.DrawSphere(
		{ 300.0, 300.0, 0.0 },
		100.0,
		rl.RED
	)
}
