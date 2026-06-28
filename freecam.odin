package game

import rl "vendor:raylib"

free_cam := rl.Camera3D {
	up = { 0.0, 1.0, 0.0 },
	fovy = 60.0,
	projection = .PERSPECTIVE,
	target= { 0.0, 0.0, 0.0 }
}

@(private="file")
_look := rl.Vector2 { }

setup_free_cam :: proc() {
	free_cam.position = {
		player_body.position.x,
		player_body.position.y + 1.0,
		player_body.position.z
	}
}

update_free_cam :: proc() {
	rl.UpdateCamera(&free_cam, .FREE)
}
