extends GutTest
## Test matrix entry: RUBBER-WRAPPED FLIPPER (a ball rebounds off the flipper face keeping
## momentum).
## Owner: physics-programmer + test-builder. Slice: "real pinball furniture".
##
## WHY THIS EXISTS: DESIGN must-feel #3 "rubber flipper rebound that keeps momentum": a ball
## striking
## a flipper FACE (with the flipper at rest, not being swung) must rebound off it like a real
## rubber-sleeved flipper - a live, slightly springy contact that PRESERVES the ball's momentum (a
## fast ball stays fast), not a dead thud and not an energy-adding trampoline. The rubber feel is
## added
## via the flipper collider's PhysicsMaterial / a rubber edge WITHOUT touching the
## force/hinge/return-
## spring drive (DESIGN constraint "rubber is a surface, not a redesign").
##
## INDEPENDENT-ORACLE RULE: assert the REAL ball's measured velocity DIRECTION (it bounced back) and
## SPEED (momentum kept), with the flipper held at REST via the force_energized(false) test hook so
## the
## measurement is of the SURFACE rebound, not a swing. A green that only checks the material
## constant
## without firing a real ball is a FAIL.
##
## REGRESSION GUARD: test_flipper_momentum.gd and test_flipper_no_overlap.gd (if present) must stay
## GREEN unchanged - the rubber surface must not change the drive, the snap, or the cradle. That
## guard
## lives in those files; this file only proves the new rubber rebound behavior.

const APPROACH_FRAMES: int = 30
## Incoming speed of the ball at the flipper face. A mid-game speed, well below the tunneling band.
const FIRE_SPEED: float = 50.0
## The rebound must keep at least this fraction of the incoming speed (live rubber, not a dead
## thud).
## A dead bounce (bounce ~0.05) would drop well below this; a rubber surface keeps the ball lively.
const MIN_REBOUND_FRACTION: float = 0.35
## The rebound must NOT exceed the incoming speed by more than this (no energy-adding trampoline).
const MAX_REBOUND_FRACTION: float = 1.15

const FLIPPER_SCENE: PackedScene = preload("res://scenes/elements/Flipper.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _flipper: Node3D = null
var _ball: RigidBody3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)

	# A single LEFT flipper at the origin, held at rest (no swing) so we measure the SURFACE rebound.
	_flipper = FLIPPER_SCENE.instantiate() as Node3D
	_flipper.position = Vector3.ZERO
	_world.add_child(_flipper)
	if _flipper.has_method("configure"):
		_flipper.configure("left_flipper", false)
	# Hold the flipper RELEASED (at rest) for the whole test so the bat is not driving the ball; we
	# are testing the rubber surface, not a swing. force_energized(false) is the inert test hook.
	if _flipper.has_method("force_energized"):
		_flipper.force_energized(false)

	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(_ball)
	_ball.gravity_scale = 0.0
	await wait_frames(2)


## Fire the ball at the flipper bat face. The bat at rest extends from the pivot (origin) toward
## center along +X (left flipper), lying flat on the surface. We aim the ball at a point partway
## down
## the bat from the side (-Z) so it strikes the long face and rebounds back along +Z.
func _fire_at_face() -> void:
	var along_bat: float = TableConfig.FLIPPER_LENGTH * 0.5
	var face_offset: float = TableConfig.FLIPPER_WIDTH * 0.5 + TableConfig.BALL_RADIUS + 2.0
	_ball.position = Vector3(along_bat, 0.0, -face_offset)
	_ball.linear_velocity = Vector3(0.0, 0.0, FIRE_SPEED)  # toward the face (+Z)
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false


func test_flipper_face_has_rubber_material() -> void:
	## Structural: the bat must carry a PhysicsMaterial with a rubber-feeling bounce (the load-bearing
	## surface change). We resolve the FlipperBody and read its physics_material_override.bounce. The
	## physics-programmer sets the exact value; we assert it is springy enough to read as rubber (a
	## clearly-above-dead-thud bounce), not the old near-zero BAT_BOUNCE.
	var bat: Node = _flipper.find_child("FlipperBody", true, false)
	assert_not_null(bat, "flipper must have a FlipperBody RigidBody3D")
	if bat != null and bat is RigidBody3D:
		var mat: PhysicsMaterial = (bat as RigidBody3D).physics_material_override
		assert_not_null(mat, "the flipper bat must carry a PhysicsMaterial (the rubber surface)")
		if mat != null:
			assert_gt(
				mat.bounce, 0.25,
				"the flipper rubber surface must be springy (bounce > 0.25 reads as rubber, not a "
				+ "dead thud). bounce=%f" % mat.bounce
			)


func test_ball_rebounds_off_resting_flipper_face() -> void:
	## A ball fired at the resting bat face must bounce back (-z), proving a real surface contact, not
	## a pass-through. ORACLE: _ball.linear_velocity.z after contact.
	_fire_at_face()
	await wait_physics_frames(APPROACH_FRAMES)
	assert_lt(
		_ball.linear_velocity.z, 0.0,
		"ball must rebound off the resting flipper face (-z), not pass through. vz=%f"
		% _ball.linear_velocity.z
	)


func test_rubber_rebound_preserves_momentum() -> void:
	## The rebound must keep a substantial fraction of the incoming speed (live rubber), and must NOT
	## exceed it (no trampoline). With the flipper at REST this isolates the surface from any swing.
	## ORACLE: _ball.current_speed() after the bounce vs the incoming FIRE_SPEED.
	_fire_at_face()
	await wait_physics_frames(APPROACH_FRAMES)

	var speed: float = _ball.current_speed()
	assert_gt(
		speed, FIRE_SPEED * MIN_REBOUND_FRACTION,
		"rubber rebound must keep momentum (>= %.0f%% of incoming). speed=%f, incoming=%f"
		% [MIN_REBOUND_FRACTION * 100.0, speed, FIRE_SPEED]
	)
	assert_lt(
		speed, FIRE_SPEED * MAX_REBOUND_FRACTION,
		"rubber rebound must NOT add energy (no trampoline, < %.0f%% of incoming). speed=%f"
		% [MAX_REBOUND_FRACTION * 100.0, speed]
	)
