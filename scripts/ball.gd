extends RigidBody3D
## Ball - the pinball. A continuous-CD RigidBody on the BALLS physics layer.
##
## OWNERSHIP: physics-programmer. Geometry/scale comes from TableConfig; YOU own mass tuning,
## damping, the PhysicsMaterial, and (critically) the no-tunneling guarantee.
##
## NON-NEGOTIABLE (from .claude/CLAUDE.md and DESIGN.md "NO TUNNELING, EVER"):
##   - continuous_cd MUST be true. This is the single most important correctness property in the
##     project. The GUT stress test (tests/test_ball_tunneling.gd) asserts a full-flip-speed ball
##     never passes through a wall/flipper. Do not ship this with CCD off.
##   - collision_layer = PhysicsLayers.BALLS, collision_mask = PhysicsLayers.BALL_COLLISION_MASK.
##
## STABLE CONTRACT (tests and table.gd depend on these; keep the signatures):
##   func reset_to_start() -> void           # zero velocity, return to TableConfig.BALL_START.
##   func reset_to(pos: Vector3) -> void      # zero velocity, place at an arbitrary local position.
##   func current_speed() -> float            # |linear_velocity|, for tests/HUD/diagnostics.
##
## NOT a launch path any more (QA BUG-017): launch(direction, speed) below is RETAINED only as a
## low-level velocity helper for diagnostics/future tooling. After the physics-based-interactions
## slice, NO production code calls it: the ball is launched by the PHYSICAL plunger strike (the
## AnimatableBody3D face in scripts/plunger.gd colliding with the resting ball), never by setting the
## ball's velocity in code. Do NOT re-wire the plunger to call this; that would reintroduce the fake
## non-physics launch the slice deliberately removed.

## --- TUNING (physics-programmer owns these) -----------------------------------------------------
## Linear damping. A real steel ball loses little energy in flight; keep this very low so a launched
## ball carries up the lane and a flipped ball travels. A touch above zero stops the ball drifting
## forever on the near-frictionless surface and helps it settle into a cradle.
const LINEAR_DAMP: float = 0.05
## Angular damping. Slightly higher than linear so the ball is not perpetually spinning, but low
## enough that it still rolls. Pinballs scrub spin against the playfield felt; this approximates it.
const ANGULAR_DAMP: float = 0.6

## A cradled ball must be allowed to fall asleep so it sits still in a flipper cradle without jitter,
## but Jolt's sleep threshold (project.godot jolt_3d/sleep/velocity_threshold) is already very low,
## so sleeping never swallows a real movement. We force the ball AWAKE on every reset/launch so a
## new or relaunched ball never starts asleep (a stuck-asleep ball at launch would be a dead ball).

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	# --- The headline correctness gate: continuous collision detection. ---------------------------
	# The ball is small (radius 0.6) and fast (launch up to 90 u/s, flips faster). At 240 Hz a ball
	# at 90 u/s moves 0.375 u/step, comparable to its own radius, and a flipper tip moves faster
	# still. Without CCD it would tunnel thin walls/flippers between solver steps. This single line
	# is the most important in the project; the GUT stress test fails loudly if it regresses.
	continuous_cd = true

	# --- Collision routing (named layers, never raw bits). ----------------------------------------
	collision_layer = PhysicsLayers.BALLS
	collision_mask = PhysicsLayers.BALL_COLLISION_MASK

	# --- Mass and damping from the world-scale contract. ------------------------------------------
	mass = TableConfig.BALL_MASS
	gravity_scale = 1.0  # Uses project default_gravity (200); the table tilt is the Playfield node.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = LINEAR_DAMP
	angular_damp = ANGULAR_DAMP

	# Allow sleep so a cradled ball settles without jitter; we always wake it on reset/launch.
	can_sleep = true

	# --- Physics material (bounce + friction) from the contract. ----------------------------------
	# A steel ball is heavy and not very bouncy; low restitution keeps bounces tight and readable.
	var material := PhysicsMaterial.new()
	material.bounce = TableConfig.BALL_BOUNCE
	material.friction = TableConfig.BALL_FRICTION
	physics_material_override = material

	# --- Shape: keep it in sync with the scale contract. ------------------------------------------
	# The scene ships a SphereShape3D; enforce the radius from TableConfig so the body never drifts
	# out of scale if the contract radius changes (one edit in TableConfig re-scales the ball).
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		var sphere: SphereShape3D = _collision_shape.shape
		sphere.radius = TableConfig.BALL_RADIUS

	_ensure_mesh()

	# Start the ball at the launch-lane rest position so a freshly-loaded scene is in a sane state.
	reset_to_start()


## Provide a gray-box sphere mesh of the correct radius if the scene did not author one, so the ball
## is visible without depending on art. Idempotent: does nothing if a MeshInstance3D already exists.
func _ensure_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BallMesh"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = TableConfig.BALL_RADIUS
	sphere_mesh.height = TableConfig.BALL_RADIUS * 2.0
	mesh_instance.mesh = sphere_mesh
	add_child(mesh_instance)


## Zero motion and return the ball to the launch-lane start position. Called by GameFlow/Plunger on
## new ball. STABLE SIGNATURE.
func reset_to_start() -> void:
	reset_to(TableConfig.BALL_START)


## Zero motion and place the ball at a given LOCAL (playfield-space) position. STABLE SIGNATURE.
## Uses the physics-safe path: we stop the body, place it, and clear sleep so the next physics step
## sees a stationary, awake ball at the new spot (never a teleport with leftover velocity).
func reset_to(pos: Vector3) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# position is the local transform origin; table.gd parents the ball under the tilted Playfield,
	# so a local position is the playfield-space coordinate the contract (BALL_START) is written in.
	position = pos
	# Wake the body so a reset never lands it stuck-asleep mid-air (which would be a dead ball).
	sleeping = false


## Low-level helper: set a velocity along a unit direction at a given speed. NOT called by production
## code after the physics-based-interactions slice (the physical plunger strike launches the ball by
## collision now - see the class header / QA BUG-017). Retained as a deterministic velocity setter
## for diagnostics and possible future tooling; do NOT re-wire the plunger to call it.
func launch(direction: Vector3, speed: float) -> void:
	sleeping = false
	var dir := direction
	if dir.length() < 0.0001:
		# Degenerate direction: fall back to "up the table" so a launch is never a no-op.
		dir = TableConfig.up_table_local()
	linear_velocity = dir.normalized() * speed


## Current scalar speed. STABLE SIGNATURE - the tunneling test reads this.
func current_speed() -> float:
	return linear_velocity.length()
