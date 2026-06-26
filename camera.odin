package game

import "core:math"

import rl "vendor:raylib"

update_camera :: proc(camera:^rl.Camera, look:^rl.Vector2) {
	UP :: rl.Vector3 { 0.0, 1.0, 0.0 }
	TARGET_OFFSET :: rl.Vector3 { 0.0, 0.0, -1.0 }

	yaw := rl.Vector3RotateByAxisAngle(TARGET_OFFSET, UP, look.x)

	max_angle_up := rl.Vector3Angle(UP, yaw) - 0.001

	if -look.y > max_angle_up {
		look.y = -max_angle_up
	}

	max_angle_down := rl.Vector3Angle(-UP, yaw) * -1.0 + 0.001

	if -look.y < max_angle_down {
		look.y = -max_angle_down
	}

	right := rl.Vector3Normalize(rl.Vector3CrossProduct(yaw, UP))

	pitch_angle := -look.y
	pitch_angle = math.clamp(pitch_angle, -math.PI/2 + 0.0001, math.PI/2 - 0.0001)
	pitch := rl.Vector3RotateByAxisAngle(yaw, right, pitch_angle)

	camera.target = camera.position + pitch
}
