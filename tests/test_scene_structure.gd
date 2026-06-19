extends GutTest
## RENDER-CONTRACT structure tests - the game's analog of a web app asserting its required
## DOM nodes exist. Headless GUT cannot see pixels, so instead of eyeballing we instantiate the
## REAL Table scene and assert it BUILDS the parts that make it viewable: a CURRENT Camera3D, a
## light, an environment, and a visible MeshInstance3D on the ball. This is the gate the original
## camera-less "empty gray table" build would have FAILED. See game-testing-strategy.

const TableScene := preload("res://scenes/Table.tscn")

var table: Node3D


func before_each() -> void:
	table = TableScene.instantiate()
	add_child_autofree(table)
	await wait_frames(2)  # let _ready() build the whole tree


## Depth-first search for the first descendant of the given class. Returns null if none.
func _find(type_name: String, root: Node = null) -> Node:
	var start: Node = root if root != null else table
	for child in start.get_children():
		if child.is_class(type_name):
			return child
		var found: Node = _find(type_name, child)
		if found != null:
			return found
	return null


func test_builds_a_current_camera() -> void:
	var cam: Node = _find("Camera3D")
	assert_not_null(cam, "Table must build a Camera3D, else the viewport renders only the clear color")
	if cam != null:
		assert_true((cam as Camera3D).current, "the Camera3D must be current so the viewport uses it")


func test_builds_a_light() -> void:
	assert_not_null(_find("DirectionalLight3D"), "Table must build a light, else meshes are invisible")


func test_builds_an_environment() -> void:
	assert_not_null(_find("WorldEnvironment"), "WorldEnvironment expected for ambient + bg")


func test_ball_has_a_visible_mesh() -> void:
	## A body with a collision shape but no MeshInstance3D is invisible even when lit (Ball.tscn gap).
	var ball: Node = _find("RigidBody3D")
	assert_not_null(ball, "expected a ball RigidBody3D in the built scene")
	if ball != null:
		assert_not_null(_find("MeshInstance3D", ball), "ball needs a MeshInstance3D to be visible")


func test_camera_frames_the_whole_table() -> void:
	## FRAMING gate: the auto-frame must put every table corner inside the camera frustum, or the
	## table renders off-screen / jammed in a corner (the "table at the bottom" bug). Verified via the
	## engine's own projection, so it holds for whatever viewport size CI runs at.
	await wait_frames(3)  # let the deferred _frame_camera run after _ready
	var cam: Camera3D = _find("Camera3D") as Camera3D
	assert_not_null(cam, "need a Camera3D to test framing")
	if cam == null:
		return
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(TableConfig.TILT_DEG))
	var hw: float = TableConfig.HALF_WIDTH
	var hl: float = TableConfig.HALF_LENGTH
	var ht: float = TableConfig.WALL_HEIGHT
	for sx in [-hw, hw]:
		for sy in [0.0, ht]:
			for sz in [-hl, hl]:
				var corner: Vector3 = tilt * Vector3(sx, sy, sz)
				assert_true(cam.is_position_in_frustum(corner),
					"table corner %s must be framed by the camera" % corner)
