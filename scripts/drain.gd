extends Area3D
## Drain - the open center drain trigger. A ball entering this volume is lost.
##
## OWNERSHIP: gameplay-programmer. A simple Area3D below/between the flippers. It does not
## change the ball; it only DETECTS the loss and announces it so GameFlow can decrement the count.
##
## DESIGN ("LEGIBLE DRAIN"): draining is obviously the player's loss. This node's only job is the
## clean signal; GameFlow + HUD make it legible (message + ball-count tick). Geometry: TableConfig.
##
## COLLISION SETUP: this Area3D detects bodies on the BALLS layer by setting its collision_mask.
## The CollisionShape3D is sized from TableConfig.DRAIN_WIDTH / DRAIN_DEPTH and positioned at
## TableConfig.DRAIN_Z. Only the tracked ball triggers the signal; other bodies (e.g. debris from
## physics objects or future multiball extras not yet tracked) are silently ignored.
##
## STABLE CONTRACT:
##   signal ball_drained()            # emitted once when the live ball enters the drain volume.
##   func set_ball(ball: RigidBody3D) -> void   # only this body triggers the drain.

signal ball_drained()

var _ball: RigidBody3D = null

func _ready() -> void:
	# Set collision mask so this Area3D only monitors bodies on the BALLS physics layer.
	# Using the named constant (PhysicsLayers.BALLS) instead of a raw bit so a future layer
	# renumber is one edit in physics_layers.gd, not a search across the codebase.
	collision_mask = PhysicsLayers.BALLS

	# Build and place a BoxShape3D that covers the full drain opening.
	# Width spans the whole table so a ball rolling along either gutter is still caught.
	# Depth gives enough vertical travel that even a slow-rolling ball triggers before it comes
	# to rest at the edge. Height is generous so the trigger volume is not a razor-thin plane.
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		TableConfig.DRAIN_WIDTH,   # x: full table width
		TableConfig.WALL_HEIGHT,   # y: tall enough to catch a ball regardless of bounce height
		TableConfig.DRAIN_DEPTH    # z: deep enough for a slow or bouncing ball
	)

	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	# Position the Area3D at the drain centre in local (playfield) space.
	# DRAIN_Z is defined as HALF_LENGTH + 2.0 - just past the flipper pivots toward the bottom edge.
	# X = 0 (centred), Y = 0 (on the playfield surface).
	position = Vector3(0.0, 0.0, TableConfig.DRAIN_Z)

	# Connect the body-entered signal. Using Callable so the connection is explicit and
	# an IDE or GUT test can verify it exists.
	body_entered.connect(_on_body_entered)

## Register the live ball. Only this body triggers ball_drained; everything else is ignored.
## Called by table.gd after _build_dynamic_elements creates the Ball instance. STABLE SIGNATURE.
func set_ball(ball: RigidBody3D) -> void:
	_ball = ball

func _on_body_entered(body: Node) -> void:
	# Guard: only the tracked ball matters. Any other physics body (future multiball, debris) is
	# silently ignored rather than causing a spurious drain event.
	if body != _ball:
		return
	ball_drained.emit()
