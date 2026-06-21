extends "res://scripts/active_kicker.gd"
## PopBumper - an active round "bell thingy" that fires the ball radially outward on contact.
##
## A pop bumper is an ActiveKicker (shared base owns the cap/cooldown/score) whose KICK DIRECTION is
## RADIALLY OUTWARD from its own center along the ball's contact normal: wherever the ball touches,
## it
## is fired straight away from the bumper. That is the classic "pop": a ball entering the cluster
## bounces off one bumper toward another, racking up little jolts of action and score (DESIGN
## must-feel
## #1 "active kick, not a limp bounce").
##
## GEOMETRY (TableConfig): a round solid post of POP_BUMPER_RADIUS, POP_BUMPER_HEIGHT tall. The base
## class builds the solid StaticBody3D (physics half) and the detector; this subclass only supplies
## the round shape and the radial kick direction.
##
## OWNERSHIP: lead scaffolds; physics-programmer fills _build_body/_apply_kick in the BASE (shared);
## this file's _kick_direction_for + geometry setup are small and stable.
##
## STABLE CONTRACT: inherits scored(points), kicked(direction), set_ball, points from ActiveKicker.
##   func configure() -> void   # pull radius/height/score from TableConfig (called by table.gd).

## The solid post radius and height, pulled from TableConfig in configure() so the base _build_body
## and _build_detector_and_mesh can read a single resolved value. The detector is built one
## BALL_RADIUS
## larger than this so body_entered fires as the ball arrives.
var _radius: float = TableConfig.POP_BUMPER_RADIUS
var _height: float = TableConfig.POP_BUMPER_HEIGHT


## Pull this bumper's geometry + score from TableConfig. table.gd calls this after instancing,
## before
## the bumper is added to the tree (so _ready/_build_body see the resolved values). STABLE
## SIGNATURE.
func configure() -> void:
	_radius = TableConfig.POP_BUMPER_RADIUS
	_height = TableConfig.POP_BUMPER_HEIGHT
	points = TableConfig.POP_BUMPER_SCORE


## RADIAL kick: the unit vector FROM the bumper center TO the ball, flattened onto the surface plane
## (Y = 0) so the kick stays in-plane (a pop bumper bats the ball across the table, not into the
## air).
## ball_pos is the ball's GLOBAL position; the bumper's global_position is its center. If the ball
## is
## (degenerately) exactly on center, fall back to up-table so the kick is never a zero vector.
func _kick_direction_for(ball_pos: Vector3) -> Vector3:
	var to_ball: Vector3 = ball_pos - global_position
	to_ball.y = 0.0  # keep the kick on the playfield plane (no vertical pop)
	if to_ball.length() < 0.0001:
		return TableConfig.up_table_local()
	return to_ball.normalized()


## Round solid post. The base _build_body reads this for the StaticBody3D collision shape.
func _make_body_shape() -> Shape3D:
	var shape := CylinderShape3D.new()
	shape.radius = _radius
	shape.height = _height
	return shape


## Detector one BALL_RADIUS larger so body_entered fires as the ball arrives, before center contact.
func _make_detector_shape() -> Shape3D:
	var shape := CylinderShape3D.new()
	shape.radius = _radius + TableConfig.BALL_RADIUS
	shape.height = _height
	return shape


## Visible mesh: a ROUND cylinder matching the collision post (the base _make_mesh returns a tiny
## 1x1 box - the "little squares" the developer saw). A red cap-coloured cylinder of the real radius
## so the bumper reads as a chunky round bumper, not a dot.
func _make_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _radius
	cyl.bottom_radius = _radius
	cyl.height = _height
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.18, 0.18)
	cyl.material = mat
	mesh_instance.mesh = cyl
	return mesh_instance
