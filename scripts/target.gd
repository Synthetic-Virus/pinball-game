extends Area3D
## Target - one rewarding upper-playfield scoring obstacle (gray-box bumper/target).
##
## OWNERSHIP: gameplay-programmer. When the ball hits it, it scores a flat value and gives an
## immediate legible response (a knock-back kick + score tick). DESIGN requires at least one target
## a skilled flip can hit on purpose; table.gd places a small number of these in the upper-middle.
##
## NOTE on layer: implemented as an Area3D that DETECTS the ball and applies a kick, mirroring the
## old Main.gd bumpers. If the physics-programmer later prefers a solid StaticBody bumper with a
## restitution kick, that is a coordinated change; for this slice the Area3D + manual kick is the
## contract so scoring is deterministic and testable.
##
## KICK DIRECTION: the ball is kicked away from the target centre, flattened to the playfield XZ
## plane (Y component zeroed out). This gives a natural "bounce off a bumper" feel without fighting
## gravity. A minimum kick distance guard prevents a zero-vector divide when the ball is exactly
## centred on the target (edge case, but crashes without the guard).
##
## STABLE CONTRACT:
##   signal scored(points: int)       # emitted when the ball strikes this target.
##   func set_ball(ball: RigidBody3D) -> void
##   var points: int                  # flat score value (default 100, placeholder per DESIGN).

signal scored(points: int)

@export var points: int = 100  ## Flat value per hit (placeholder, DESIGN.md scoring).

## Knock-back speed applied to the ball on a hit. Tuned to be clearly legible at this world scale
## (gravity 200, LAUNCH_SPEED_MAX 90) without being so strong it breaks the physics solver.
const KICK_SPEED: float = 25.0

## Minimum squared distance between ball and target before we fall back to a default kick direction.
## Prevents a divide-by-zero if the ball is centred exactly on the target origin.
const MIN_KICK_DIST_SQ: float = 0.001

var _ball: RigidBody3D = null

func _ready() -> void:
	# Monitor bodies on the BALLS layer only. This Area3D does not need to be on a layer itself
	# for detection (monitoring does not require layer membership), but setting collision_mask
	# to BALLS ensures Godot's broadphase only wakes the Area3D for relevant bodies.
	collision_mask = PhysicsLayers.BALLS

	# Gray-box cylinder: small enough that hitting it takes skill, large enough to be a real target.
	# CylinderShape3D stands upright (axis Y) so its round profile faces the ball correctly.
	var shape := CylinderShape3D.new()
	shape.radius = 1.5   # ~2.5 ball diameters wide - clearly visible and hittable.
	shape.height = TableConfig.WALL_HEIGHT  # Same height as walls so it is a solid obstacle.

	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	# Gray-box visual mesh (matches the collision shape so the player can aim at what they see).
	var mesh_instance := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = shape.radius
	cylinder_mesh.bottom_radius = shape.radius
	cylinder_mesh.height = shape.height
	mesh_instance.mesh = cylinder_mesh
	add_child(mesh_instance)

	body_entered.connect(_on_body_entered)

## Register the live ball. Only this body triggers the score and kick. STABLE SIGNATURE.
func set_ball(ball: RigidBody3D) -> void:
	_ball = ball

func _on_body_entered(body: Node) -> void:
	# Guard: ignore any body that is not the tracked ball.
	if body != _ball:
		return

	# Announce the score immediately so HUD ticks the instant the ball touches the target.
	scored.emit(points)

	# Compute the kick direction: away from the target centre, on the playfield XZ plane only.
	# We zero out Y so the kick does not fight gravity by adding an upward or downward component.
	var delta: Vector3 = _ball.global_position - global_position
	delta.y = 0.0

	var kick_dir: Vector3
	if delta.length_squared() > MIN_KICK_DIST_SQ:
		kick_dir = delta.normalized()
	else:
		# Ball is exactly centred (should not happen in play but guards the math).
		# Default kick: straight up-table (away from the drain), which is a safe fallback.
		kick_dir = Vector3(0.0, 0.0, -1.0)

	# Apply the kick by setting linear_velocity directly.
	# We do not add to the existing velocity because the ball may be travelling INTO the target
	# at an oblique angle; we want the kick to REDIRECT it, not just add to the incoming speed.
	# This gives the same clear snap the old Main.gd bumper produced.
	_ball.linear_velocity = kick_dir * KICK_SPEED
