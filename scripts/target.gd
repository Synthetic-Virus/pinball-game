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

## Knock-back speed ADDED outward on a hit. Tuned to be clearly legible at this world scale
## (gravity 200, LAUNCH_SPEED_MAX 90) without being so strong it breaks the physics solver. This is
## the bumper "pop", added to the ball's redirected momentum rather than replacing it (see below).
const KICK_SPEED: float = 25.0

## Floor speed after a hit. A ball that crawls into a target should still pop off legibly, so the
## outgoing speed is at least this. A fast ball keeps (most of) its speed; a slow one gets a boost.
const MIN_OUTGOING_SPEED: float = 25.0

## Minimum squared distance between ball and target before we fall back to a default kick direction.
## Prevents a divide-by-zero if the ball is centred exactly on the target origin.
const MIN_KICK_DIST_SQ: float = 0.001

## Re-trigger cooldown (seconds). After a hit, this target ignores further contacts briefly so a ball
## resting/grinding against it on the tilted plane cannot score every physics frame (QA BUG-007 score
## farm). One legible hit, then a short dead time, matches how a real bumper behaves.
const RETRIGGER_COOLDOWN_S: float = 0.20

var _ball: RigidBody3D = null
## Time (seconds, from Time.get_ticks_msec) before which contacts are ignored. 0 = ready.
var _cooldown_until_ms: float = 0.0

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

	# Cooldown guard: a ball grinding against the target on the tilted plane re-fires body_entered
	# every time it dips out and back in. Without this it would score every frame (QA BUG-007). One
	# hit, then a short dead time before this target can score again.
	var now_ms: float = float(Time.get_ticks_msec())
	if now_ms < _cooldown_until_ms:
		return
	_cooldown_until_ms = now_ms + RETRIGGER_COOLDOWN_S * 1000.0

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

	# REDIRECT while PRESERVING MOMENTUM (QA BUG-007 / DESIGN "REAL MOMENTUM").
	# The old code OVERWROTE linear_velocity with a fixed 25 u/s, which slowed a 90 u/s ball to a
	# crawl on every hit and discarded the player's speed - the opposite of the momentum pillar. We
	# instead keep the ball's incoming SPEED (flattened to the playfield plane), send it outward along
	# kick_dir, and ADD the bumper pop on top. A floor speed guarantees even a slow ball pops legibly.
	var incoming: Vector3 = _ball.linear_velocity
	incoming.y = 0.0
	var outgoing_speed: float = maxf(incoming.length() + KICK_SPEED, MIN_OUTGOING_SPEED)
	# Preserve the original Y velocity so the kick does not fight gravity / the tilted surface.
	var new_velocity: Vector3 = kick_dir * outgoing_speed
	new_velocity.y = _ball.linear_velocity.y
	_ball.linear_velocity = new_velocity
