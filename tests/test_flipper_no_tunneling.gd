extends GutTest
## Test matrix entry: NO TUNNELING through the FLIPPER BAT (the headline physics gate this slice).
## Owner: physics-programmer + qa-lead. Slice: "Table reshape + playtest fixes".
##
## WHY THIS EXISTS (the slice's COVERAGE GAP, producer SEND_BACK): the flipper bat collider was
## reshaped this slice from a BoxShape3D plank to a tapered rounded CONVEX-HULL stadium (flipper.gd,
## test_flipper_shape.gd). A new collision shape is a NEW tunneling risk: a convex hull has angled
## faces and a thin rounded tip a small fast ball could clip past between solver steps. The only
## existing ball-vs-flipper test (test_flipper_rubber.gd) fires at only ~50 u/s - far below the
## worst-case. The the project docs non-negotiable and DESIGN.md "NOTHING TUNNELS, EVER" require a
## stress test that fires a >= 2x LAUNCH_SPEED_MAX ball at the REAL instanced bat and proves it
## never passes through, at BOTH the resting bat AND a bat in MID-SWING (the worst case: a fast bat
## face sweeping into a fast ball, the highest closing speed in the game).
##
## INDEPENDENT-ORACLE RULE: every assertion reads the REAL ball's measured POSITION relative to the
## REAL bat (its live world transform), never a collision-count the body self-reports. Position
## cannot lie about whether the sphere exited through the solid bat.
##
## STRUCTURE: instance the REAL Flipper.tscn (so the bat's convex-hull shape, KINEMATIC_OBSTACLES
## layer, CCD flag, and rubber PhysicsMaterial are the exact shipping ones) and the REAL Ball.tscn
## (CCD/mass/material/shape from ball.gd). A hand-built stand-in passing here would be a false green
## on the gate that matters most.

## Fire the worst-case shot many times. Matches the flat-wall and target stress loops (100 / 60).
const TEST_ITERATIONS: int = 80
## At 240 Hz, 30 frames = 125 ms. A ball at 2*LAUNCH_SPEED_MAX (220 u/s after the "Fix the launch"
## slice raised MAX to 110) travels 27.5 units in that span, far past a bat a few units away, so a
## missed contact shows up as the ball behind the bat. _test_speed reads the live config.
const STEP_FRAMES: int = 30
## How far in front of the bat face (along the face normal) the ball starts each shot.
const START_OFFSET: float = 4.0
## Frames to let the forced swing build up before firing the mid-swing shot, so the bat face is
## moving at speed when the ball arrives (the highest closing speed: fast bat + fast ball).
const SWING_SPINUP_FRAMES: int = 2

const FLIPPER_SCENE: PackedScene = preload("res://scenes/elements/Flipper.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _flipper: Node3D = null
var _ball: RigidBody3D = null
## The test speed: 2x LAUNCH_SPEED_MAX. Strictly harder than anything gameplay produces.
var _test_speed: float = 0.0


func before_all() -> void:
	_test_speed = 2.0 * TableConfig.LAUNCH_SPEED_MAX


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)

	# A real LEFT flipper at the world origin, configured exactly like table.gd, so we fire at the
	# shipping bat geometry (the new convex-hull stadium), not a stand-in.
	_flipper = FLIPPER_SCENE.instantiate() as Node3D
	_flipper.position = Vector3.ZERO
	_world.add_child(_flipper)
	if _flipper.has_method("configure"):
		_flipper.configure("left_flipper", false)

	# The REAL shipping ball: ball.gd._ready() sets continuous_cd, layers, mass, shape, material.
	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(_ball)
	# Zero gravity for the stress loop so the straight head-on shot stays on the face normal across
	# frames; the tunneling check is about CCD + the solver catching the contact, gravity is noise.
	_ball.gravity_scale = 0.0
	await wait_frames(2)  # let _ready / configure build the bat + body


# ---- Bat geometry helpers (read LIVE from the instanced bat, never hardcoded) -------------------

## The FlipperBody RigidBody3D (the swinging bat). Resolved by the agreed child name.
func _bat() -> Node3D:
	return _flipper.find_child("FlipperBody", true, false) as Node3D


## The bat's direction (pivot -> tip) in WORLD space, read LIVE from the bat basis. The bat is
## angled on the surface (rest angle, plus it rotates while swinging), so we read it live - a fixed
## direction would aim at empty space and the ball would sail past, faking a pass (see the same live
## technique in test_flipper_rubber.gd).
func _bat_dir() -> Vector3:
	return _bat().global_transform.basis.x.normalized()


## The bat's long-face normal on the surface plane, pointing UP-TABLE (-Z), the side a ball strikes
## from. Perpendicular to the live bat direction about the surface normal (+Y).
func _face_normal() -> Vector3:
	var bat_dir: Vector3 = _bat_dir()
	var n: Vector3 = Vector3(bat_dir.z, 0.0, -bat_dir.x).normalized()
	# Choose the perpendicular pointing up-table (-Z) so we fire down the normal into the face the way
	# a real ball strikes the flipper.
	return n if n.z < 0.0 else -n


## The mid-bat contact point in WORLD space (half the bat length along the live direction from the
## pivot, which is this Flipper node's origin). Firing at mid-bat hits the long face, not a cap.
func _bat_mid() -> Vector3:
	return _flipper.global_position + _bat_dir() * (TableConfig.FLIPPER_LENGTH * 0.5)


## Place the ball in front of the bat face (along +face_normal) and fire it straight DOWN the normal
## into the face at the worst-case speed. Returns the face normal used, so the no-tunnel check can
## measure the ball's signed distance across the face plane afterward.
func _fire_head_on() -> Vector3:
	var face_normal: Vector3 = _face_normal()
	var bat_mid: Vector3 = _bat_mid()
	# Stand off by half the bat width + ball radius + the approach gap so the ball starts clearly in
	# front of the solid bat, then sweeps into it under CCD.
	var standoff: float = TableConfig.FLIPPER_WIDTH * 0.5 + TableConfig.BALL_RADIUS + START_OFFSET
	_ball.position = bat_mid + face_normal * standoff
	_ball.linear_velocity = -face_normal * _test_speed
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false
	return face_normal


## Signed distance of the ball CENTER across the bat face plane, measured along +face_normal from
## the mid-bat point. POSITIVE = the ball is on the up-table (front) side it was fired from; deeply
## NEGATIVE = it has crossed to the far (down-table) side of the bat: a tunnel. We allow a small
## penetration epsilon (half a ball radius) for solver contact depth, exactly like the flat-wall and
## target stress tests.
func _signed_distance_in_front(face_normal: Vector3) -> float:
	return (_ball.global_position - _bat_mid()).dot(face_normal)


# ---- STRESS 1: the RESTING bat is never tunneled ------------------------------------------------

func test_full_speed_ball_never_tunnels_resting_bat() -> void:
	## Fire the worst-case ball head-on at the bat held at REST, TEST_ITERATIONS times, and assert the
	## ball NEVER crosses to the far side of the bat face. ORACLE: the ball's measured signed distance
	## across the live face plane. The resting bat is the most common contact in play; this is the
	## convex-hull analogue of the flat-wall gate in test_ball_tunneling.gd.
	if _flipper.has_method("force_energized"):
		_flipper.force_energized(false)  # hold at rest for the whole loop (inert test hook)
	# Half a ball radius of penetration tolerance, matching the flat-wall / target thresholds.
	var tunnel_floor: float = -TableConfig.BALL_RADIUS * 0.5

	for i in range(TEST_ITERATIONS):
		var face_normal: Vector3 = _fire_head_on()
		await wait_physics_frames(STEP_FRAMES)
		var dist: float = _signed_distance_in_front(face_normal)
		assert_gt(
			dist,
			tunnel_floor,
			"iter %d: ball tunneled the RESTING bat. signed-distance-in-front=%f, floor=%f, speed=%f"
			% [i, dist, tunnel_floor, _test_speed]
		)


# ---- STRESS 2: the bat in MID-SWING is never tunneled (highest closing speed) -------------------

func test_full_speed_ball_never_tunnels_mid_swing_bat() -> void:
	## The worst case the slice introduced: a fast convex-hull bat face SWEEPING into a fast ball. We
	## force the flipper energized (the inert test hook), let the swing spin up a couple of frames so
	## the bat is moving at speed, then fire the worst-case ball head-on into it. The bat may launch
	## the ball back hard (that is the point of a flipper), but the ball must NEVER end up behind the
	## bat. ORACLE: the ball's measured signed distance across the live (moving) face plane.
	## We re-read the face normal AFTER spin-up each iteration because the swinging bat's angle - and
	## therefore its face normal - has changed from the rest pose.
	var tunnel_floor: float = -TableConfig.BALL_RADIUS * 0.5

	for i in range(TEST_ITERATIONS):
		# Seat the bat at rest, then drive it.
		if _flipper.has_method("force_energized"):
			_flipper.force_energized(false)
		await wait_physics_frames(2)  # settle back to rest between iterations
		if _flipper.has_method("force_energized"):
			_flipper.force_energized(true)  # solenoid drive: the bat starts swinging up
		await wait_physics_frames(SWING_SPINUP_FRAMES)  # let the bat reach swing speed

		# Fire head-on at the bat at its CURRENT (mid-swing) pose.
		var face_normal: Vector3 = _fire_head_on()
		await wait_physics_frames(STEP_FRAMES)

		# Measure against the bat's pose now (it kept swinging / settled at the up-stop). The far-side
		# test uses the CURRENT live face normal and mid point, so it is valid wherever the bat ended.
		var current_normal: Vector3 = _face_normal()
		var dist: float = _signed_distance_in_front(current_normal)
		assert_gt(
			dist,
			tunnel_floor,
			"iter %d: ball tunneled the MID-SWING bat. signed-distance-in-front=%f, floor=%f, speed=%f"
			% [i, dist, tunnel_floor, _test_speed]
		)


# ---- GUARD: the bat itself carries CCD (belt-and-braces with the ball's CCD) --------------------

func test_bat_has_continuous_cd() -> void:
	## The bat tip moves fast (a long lever at high angular velocity), so the bat carries its OWN CCD
	## in addition to the ball's (flipper.gd). If that regresses, a fast bat could sweep through a slow
	## ball between steps. Cheap structural guard so a regression is caught immediately, not only
	## statistically through the position loops above.
	var bat: Node = _bat()
	assert_not_null(bat, "the flipper must build a FlipperBody RigidBody3D bat")
	if bat != null and bat is RigidBody3D:
		assert_true(
			(bat as RigidBody3D).continuous_cd,
			"the flipper bat must have continuous_cd == true (its tip moves fast - flipper.gd)"
		)
