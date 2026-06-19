extends "res://scripts/active_kicker.gd"
## Slingshot - an active angled kicker above a flipper that fires the ball UP-table and toward
## center.
##
## A slingshot is an ActiveKicker (shared base owns the cap/cooldown/score) whose KICK DIRECTION is
## FIXED: its face normal, pointing into play. A ball dropping down the side and grazing the sling
## is
## kicked back UP and toward center (DESIGN must-feel: "saved by the slings"), NEVER down toward the
## drain. Unlike the pop bumper (radial), the direction is constant so the ball always returns into
## play regardless of exactly where it touched the angled face.
##
## GEOMETRY (TableConfig): a flat angled wall (BoxShape3D) of SLINGSHOT_LENGTH x
## SLINGSHOT_THICKNESS,
## SLINGSHOT_HEIGHT tall. The base builds the solid StaticBody3D + detector; this subclass supplies
## the
## box shape and the fixed kick direction. The kick direction comes from TableConfig per side
## (SLINGSHOT_LEFT_KICK_DIR / SLINGSHOT_RIGHT_KICK_DIR) and is set via configure(mirrored).
##
## OWNERSHIP: lead scaffolds; physics-programmer fills _build_body/_apply_kick in the BASE (shared);
## this file's _kick_direction_for + configure are small and stable.
##
## STABLE CONTRACT: inherits scored(points), kicked(direction), set_ball, points from ActiveKicker.
##   func configure(mirrored: bool) -> void   # mirrored = true builds the RIGHT slingshot.

## Box dimensions of the kicker face, from TableConfig (resolved in configure()).
var _length: float = TableConfig.SLINGSHOT_LENGTH
var _thickness: float = TableConfig.SLINGSHOT_THICKNESS
var _height: float = TableConfig.SLINGSHOT_HEIGHT
## The FIXED kick direction (unit, playfield-local XZ). Set per side in configure(): the left sling
## kicks toward +X/-Z, the right toward -X/-Z. Both point INTO play (positive up-table component).
var _kick_dir: Vector3 = TableConfig.SLINGSHOT_LEFT_KICK_DIR
## Handedness, for the face angle and the kick direction. table.gd sets it via configure().
var _mirrored: bool = false


## Configure this slingshot's side. table.gd calls configure(false) for the left, configure(true)
## for
## the right, after instancing and before adding to the tree. STABLE SIGNATURE.
func configure(mirrored: bool) -> void:
	_mirrored = mirrored
	_length = TableConfig.SLINGSHOT_LENGTH
	_thickness = TableConfig.SLINGSHOT_THICKNESS
	_height = TableConfig.SLINGSHOT_HEIGHT
	points = TableConfig.SLINGSHOT_SCORE
	# The kick direction is the load-bearing "into play, never the drain" guarantee. Pick per side.
	_kick_dir = (
		TableConfig.SLINGSHOT_RIGHT_KICK_DIR if _mirrored
		else TableConfig.SLINGSHOT_LEFT_KICK_DIR
	).normalized()


## FIXED kick: always the face normal into play, independent of the contact point (ball_pos unused).
## This is why a slingshot reliably returns the ball into play: the direction never depends on where
## the ball hit the angled face. The vector is validated by table_viz to have a positive up-table
## component and a toward-center X sign (never aimed at the drain or the side wall).
func _kick_direction_for(_ball_pos: Vector3) -> Vector3:
	return _kick_dir


## Flat angled wall. The base _build_body reads this for the StaticBody3D collision shape; long axis
## is local X, rotated by _body_yaw so the face angles into play.
func _make_body_shape() -> Shape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(_length, _height, _thickness)
	return shape


## Detector box, padded by one BALL_RADIUS on the thin axis so body_entered fires as the ball
## arrives.
func _make_detector_shape() -> Shape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(_length, _height, _thickness + TableConfig.BALL_RADIUS * 2.0)
	return shape


## Yaw the box so its flat face normal aligns with the kick direction (the face kicks the ball along
## its normal). The kick direction is in XZ; the face normal of an unrotated box (thin in Z) is
## +/-Z,
## so the yaw is the angle from -Z to the kick direction about Y. This keeps the visible angled wall
## consistent with where the ball is actually fired.
func _body_yaw() -> float:
	# atan2(x, -z): heading of the kick direction measured from the up-table (-Z) axis about +Y.
	return atan2(_kick_dir.x, -_kick_dir.z)
