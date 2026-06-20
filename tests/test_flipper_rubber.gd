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


## Fire the ball at the flipper bat face HEAD-ON (along the face normal), so we measure the PURE
## surface restitution the rubber sleeve provides, not a glancing contact.
##
## WHY HEAD-ON, NOT STRAIGHT +Z (QA BUG-019 / B1 root cause): the bat at rest is held at
## FLIPPER_REST_ANGLE (-0.55 rad), so it lies at an ANGLE on the surface, not along +Z. Firing the
## ball straight +Z therefore struck the bat at ~31 deg off-normal, a glancing blow: the normal
## component (which the bounce acts on) was only cos(31 deg) ~= 0.85 of the speed, while the
## tangential component was gripped/bled by friction. At BAT_BOUNCE=0.45 that glancing geometry
## cannot retain 35% of the incoming speed - which is exactly why the old test measured 24.8% and
## failed, NOT because the rubber material is too dead. The fix is the TEST geometry, not the
## material: aim the ball ALONG the bat's face normal so the contact is head-on and the measurement
## is of the surface restitution the test docstring claims to measure. (Do NOT raise BAT_BOUNCE to
## paper over a glancing-hit test - that would make a real glancing rebound a trampoline.)
##
## The bat extends from the pivot (origin) along the bat direction; its long FACE normal is
## perpendicular to that direction, on the surface plane. We place the ball off the mid-bat point
## along the +face-normal side and fire it back DOWN the normal into the face; it rebounds out along
## the same normal.
## The resting bat's direction (pivot -> tip) in WORLD space, read from the LIVE FlipperBody basis.
##
## WHY read it live instead of computing Vector3(cos(rest), 0, sin(rest)) (QA BUG-019 follow-up):
## the hand-computed version had the WRONG Z sign for Godot's +Y rotation convention AND assumed the
## bat sits exactly at FLIPPER_REST_ANGLE. In practice the bat SETTLES to a slightly different angle
## (the return spring/hinge balance), so the hardcoded direction pointed at empty space and the
## ball sailed PAST the bat without ever touching it - the test then "passed" the momentum check
## trivially (the ball kept ~98% of its speed because it never collided) while the direction check
## failed. The bat's own basis.x IS its true direction at the instant we fire, so deriving the face
## geometry from it guarantees a real head-on contact at whatever angle the bat actually rests at.
func _bat_dir() -> Vector3:
	var bat: Node = _flipper.find_child("FlipperBody", true, false)
	return (bat as Node3D).global_transform.basis.x.normalized()


## The bat's long-face normal on the surface plane, pointing toward the side a ball approaches from
## (negative Z, up-table). Perpendicular to the live bat direction, about the surface normal (+Y).
func _face_normal() -> Vector3:
	var bat_dir: Vector3 = _bat_dir()
	var n: Vector3 = Vector3(bat_dir.z, 0.0, -bat_dir.x).normalized()
	# Two perpendiculars exist; choose the one pointing up-table (-Z) so the ball is fired down-table
	# into the face the way a real ball strikes a resting flipper.
	return n if n.z < 0.0 else -n


func _fire_at_face() -> void:
	var bat_dir: Vector3 = _bat_dir()
	var face_normal: Vector3 = _face_normal()
	# Aim at the mid-bat point so we hit the long face, not an end cap. The FlipperBody sits at the
	# pivot (this Flipper node's origin), so the mid-face is half the length along the live bat dir.
	var bat_mid: Vector3 = _flipper.global_position + bat_dir * (TableConfig.FLIPPER_LENGTH * 0.5)
	# Stand the ball off the face by half the bat width + the ball radius + a small approach gap.
	var standoff: float = TableConfig.FLIPPER_WIDTH * 0.5 + TableConfig.BALL_RADIUS + 2.0
	_ball.position = bat_mid + face_normal * standoff
	# Fire straight DOWN the normal into the face (head-on); it rebounds back out along +face_normal.
	_ball.linear_velocity = -face_normal * FIRE_SPEED
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
	## A ball fired HEAD-ON at the resting bat face must bounce back OUT along the face normal, proving
	## a real surface contact, not a pass-through. We fired the ball IN along -face_normal, so a true
	## rebound has a POSITIVE component along +face_normal. ORACLE: the dot of the ball's measured
	## velocity with the face normal (geometry-correct for the angled bat, not a bare +/-z check).
	## The face normal is read from the LIVE bat (see _face_normal) so it matches where _fire_at_face
	## actually aimed, even though the resting bat settles a little off FLIPPER_REST_ANGLE.
	var face_normal: Vector3 = _face_normal()
	_fire_at_face()
	await wait_physics_frames(APPROACH_FRAMES)
	var rebound_along_normal: float = _ball.linear_velocity.dot(face_normal)
	assert_gt(
		rebound_along_normal, 0.0,
		"ball must rebound OUT along the face normal, not pass through. v.n=%f"
		% rebound_along_normal
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
