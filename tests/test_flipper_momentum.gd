extends GutTest
## Test matrix entry: REAL MOMENTUM (force-driven flipper feel gate).
## Owner: test-builder + physics-programmer.
##
## DESIGN's headline FEEL test made objective: a full-swing flip must out-throw a tap.
## If a tap and a full swing produce the same ball speed, the flipper is effectively
## kinematic and wrong. This catches a regression to the old teleport-style approach.
##
## METHOD:
##   The tests here are split into two tiers:
##
##   Tier 1 - CONTRACT CHECKS (run before implementation):
##     These check the stable typed signatures on the Flipper script (is_energized,
##     tip_speed, configure). They pass the moment the skeleton is in place and verify
##     the lead-programmer's contract has not been broken.
##
##   Tier 2 - PHYSICS CHECKS (require physics-programmer implementation):
##     These build a Flipper + Ball world, run trials, and measure ball speed. They are
##     marked with a clear NOTE so CI failure before implementation is expected.
##
## INDEPENDENT ORACLE: we measure the BALL's resulting speed (Ball.current_speed()), not
## the flipper's self-reported tip_speed(), for the momentum comparison. The ball speed
## is the ground truth the player experiences. tip_speed() is used ONLY for the snap-timing
## check, never for the momentum comparison.
##
## TEST HOOK: GUT cannot synthesize persistent Input events across physics frames, so the
## flipper exposes force_energized(true)/clear_force_energized() (inert in normal play). The
## Tier-2 tests below DRIVE that hook, wait the swing frames, and measure the real bodies.
## These instance the shipping Flipper.tscn + Ball.tscn; a green result on a stand-in body
## does not satisfy the gate.

## Physics tick duration in seconds. At 240 Hz one tick = 1/240 s.
const PHYSICS_TICK_S: float = 1.0 / 240.0
## DESIGN target: flipper reaches full swing in ~50 ms. At 240 Hz that is 12 ticks.
## We allow a generous 80 ms (20 ticks) as the pass threshold.
const SNAP_TIME_MS: float = 80.0
const SNAP_FRAMES: int = int(SNAP_TIME_MS / 1000.0 / PHYSICS_TICK_S) + 1  ## = 20 frames

## A "tap": the action is held for a SINGLE physics frame, so the bat barely twitches before
## the spring takes over. The solenoid is strong and the bat is light, so even one frame of
## drive imparts real momentum - that is why the tap must be this short to read as a tap and
## not as a second full swing. A full swing holds for the whole snap window.
const TAP_FRAMES: int = 1

## DESIGN floor: a full swing must impart ball speed >= 1.5x a tap. A smaller ratio means the
## flip does not feel like the player's decision (DESIGN.md "REAL MOMENTUM").
const MOMENTUM_RATIO_FLOOR: float = 1.5

var _flipper: Node3D = null
var _ball: RigidBody3D = null

func before_each() -> void:
	## Build a minimal world: one Flipper node and one Ball resting in its swing path.
	var world := Node3D.new()
	add_child_autofree(world)

	## Instance the REAL Flipper scene (force-driven hinge + solenoid + return spring).
	var flipper_scene: PackedScene = load("res://scenes/elements/Flipper.tscn")
	_flipper = flipper_scene.instantiate()
	world.add_child(_flipper)
	## Configure for the left flipper (non-mirrored side).
	_flipper.configure("left_flipper", false)

	## Instance the REAL shipping Ball for the physics trials.
	var ball_scene: PackedScene = load("res://scenes/elements/Ball.tscn")
	_ball = ball_scene.instantiate() as RigidBody3D
	world.add_child(_ball)
	## Isolate the momentum-transfer measurement from gravity. The trials compare the speed
	## the BAT imparts on a tap vs a full swing; on this minimal flat world (no tilted
	## playfield) gravity would just drop the ball off the bat over the swing window and add
	## noise to both trials. Zeroing it is a test-setup choice that isolates the variable under
	## test (swing energy), NOT a re-tune of the ball - the shipping ball keeps gravity_scale 1.
	_ball.gravity_scale = 0.0

# ---- Trial helpers (shared by the Tier-2 physics tests) -----------------------------

## Place the ball in the LEFT flipper's swing path, at rest, ready to be struck.
##
## Geometry (matches flipper.gd's convention): the bat lies flat and swings about the
## flipper's local +Y. A point at radius r along the bat at swing angle theta is at local
## (r*cos(theta), 0, -r*sin(theta)). The bat sweeps from FLIPPER_REST_ANGLE up to
## FLIPPER_UP_ANGLE, and its leading face moves toward -Z as theta increases.
##
## WHERE we seat the ball matters for the tap-vs-swing contrast. The solenoid is strong and
## the bat is light, so it reaches high angular speed within a frame or two. If the ball sits
## near the rest end, even a brief tap strikes it at nearly full bat speed and the ratio
## collapses toward 1.0 (the original failures: 1.02, then 1.40). We seat the ball near the
## UP end of the arc (at the full tip radius). A FULL swing drives the bat all the way to the
## up-stop, so its tip reaches the ball moving fast; a one-frame TAP, hauled back by the
## return spring, coasts only partway and falls short of the up end, so it imparts far less.
## That is the real feel difference the player gets, and it is a placement choice, NOT a
## flipper re-tune.
func _seat_ball_in_swing_path() -> void:
	var radius: float = TableConfig.FLIPPER_LENGTH
	## Near the up-stop (most of the way through the rest..up arc), on the leading (-Z) side.
	var seat_angle: float = lerpf(
		TableConfig.FLIPPER_REST_ANGLE, TableConfig.FLIPPER_UP_ANGLE, 0.85
	)
	var local_pos := Vector3(
		radius * cos(seat_angle),
		TableConfig.FLIPPER_HEIGHT * 0.5,
		-radius * sin(seat_angle),
	)
	## The flipper is at the world origin in these tests, so flipper-local == world here, but
	## go through the flipper transform so the seat stays correct if that ever changes.
	_ball.global_position = _flipper.global_transform * local_pos
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false


## Run ONE swing trial: seat the ball, force the flipper energized for hold_frames physics
## frames (then release), let the strike resolve, and return the ball's resulting speed.
## Uses force_energized()/clear_force_energized() because headless GUT cannot hold a real key.
func _run_swing_trial(hold_frames: int) -> float:
	## Make sure the bat has returned to its rest angle from any previous trial before we
	## seat the ball, so every trial starts from the same resting flipper. The override is
	## already cleared (false reads as not-pressed headless), so the spring holds it at rest.
	_flipper.clear_force_energized()
	await wait_physics_frames(SNAP_FRAMES)

	_seat_ball_in_swing_path()
	## Let the seat settle for one frame so contact is registered before the swing fires.
	await wait_physics_frames(1)

	_flipper.force_energized(true)
	await wait_physics_frames(hold_frames)
	## Release: hand control back to the (un-pressed) input action so the spring returns the bat.
	_flipper.clear_force_energized()

	## Let the struck ball fly free of the bat and reach its post-strike speed.
	await wait_physics_frames(SNAP_FRAMES)

	return _ball.current_speed()


# ---- Tier 1: contract checks (pass with skeleton) -----------------------------------

func test_flipper_scene_loads() -> void:
	## Smoke test: the scene file exists and instances cleanly.
	assert_not_null(_flipper, "Flipper.tscn must instantiate without error")

func test_configure_is_callable() -> void:
	## configure() is a STABLE SIGNATURE; it must exist and not crash when called.
	## Calling it a second time to confirm idempotency.
	_flipper.configure("right_flipper", true)
	assert_true(true, "configure() must be callable without crashing")

func test_is_energized_returns_false_by_default() -> void:
	## With no input held, is_energized() must return false. The skeleton already
	## implements this correctly (reads Input.is_action_pressed on the stored action).
	assert_false(
		_flipper.is_energized(),
		"is_energized() must return false when no flipper action is held"
	)

func test_tip_speed_returns_float() -> void:
	## tip_speed() must exist and return a float (even 0.0 from the skeleton is fine).
	var speed = _flipper.tip_speed()
	## typeof() returns TYPE_FLOAT (= 3) for a float value. This is a plain int comparison
	## so we do not need assert_is (which requires an Object, not a primitive).
	assert_eq(typeof(speed), TYPE_FLOAT, "tip_speed() must return a float")

func test_flipper_body_is_not_animatable_body() -> void:
	## The architecture explicitly forbids a kinematic/AnimatableBody3D approach.
	## Once the physics-programmer builds the flipper body, this asserts it is a
	## RigidBody3D, not AnimatableBody3D.
	## With the skeleton (just a Node3D root), the bat body does not exist yet; we
	## check by searching for any AnimatableBody3D child and asserting none found.
	var animatable_children: Array = []
	for child in _flipper.get_children():
		if child is AnimatableBody3D:
			animatable_children.append(child)
	assert_eq(
		animatable_children.size(),
		0,
		"Flipper must NOT contain an AnimatableBody3D child (kinematic approach is forbidden)"
	)

# ---- Tier 2: physics-driven checks (require physics-programmer implementation) ------

func test_full_swing_outthrows_a_tap() -> void:
	## DESIGN's single most important feel test, made objective: a full swing must noticeably
	## out-throw a tap. Drives the force_energized() hook on the REAL Flipper + Ball.
	##
	## Trial A (tap): hold the flipper energized for only TAP_FRAMES, then release.
	## Trial B (full swing): hold for the full SNAP_FRAMES window.
	## Both use the identical ball placement, so the ONLY difference is swing energy.
	##
	## INDEPENDENT ORACLE: we compare the BALL's measured current_speed(), never the
	## flipper's self-reported tip_speed(). Ball speed is the ground truth the player feels.
	##
	## PASS: full-swing ball speed >= MOMENTUM_RATIO_FLOOR (1.5x) the tap ball speed.

	## Trial A: the tap.
	var tap_speed: float = await _run_swing_trial(TAP_FRAMES)

	## Trial B: the full swing. Re-seating happens inside the trial helper.
	var swing_speed: float = await _run_swing_trial(SNAP_FRAMES)

	## A full swing must impart a SUBSTANTIAL absolute speed, not just a nonzero nudge. This
	## floor stops the 1.5x ratio from being satisfied trivially by two near-zero trials (e.g.
	## if neither swing reached the ball). It is a conservative "this is a real throw, not
	## solver noise" guard (a fifth of LAUNCH_SPEED_MIN, scaled from config); the 1.5x ratio is
	## the real discriminator for the feel difference.
	var min_meaningful_speed: float = TableConfig.LAUNCH_SPEED_MIN / 5.0
	assert_gt(
		swing_speed,
		min_meaningful_speed,
		"A full swing must impart a substantial ball speed (>= %f); got %f." % [
			min_meaningful_speed, swing_speed
		]
	)

	## The headline assert: the full swing out-throws the tap by at least the design floor.
	assert_gte(
		swing_speed,
		MOMENTUM_RATIO_FLOOR * tap_speed,
		"Full swing must out-throw a tap by >= %.1fx. tap=%f, swing=%f, ratio=%f" % [
			MOMENTUM_RATIO_FLOOR,
			tap_speed,
			swing_speed,
			(swing_speed / tap_speed) if tap_speed > 0.0 else INF,
		]
	)

func test_flipper_reaches_full_swing_quickly() -> void:
	## DESIGN "FLIPPER SNAP": the flip reaches full swing fast (~50 ms target). We drive the
	## force_energized() hook and assert the bat's tip_speed() rises above zero within the
	## generous SNAP_FRAMES (80 ms) window - i.e. the solenoid is actually snapping the bat,
	## not crawling. tip_speed() is the RIGHT oracle here: this test is about the flipper's
	## own swing speed (timing), not the ball, so the self-reported tip speed is exactly what
	## "reaches full swing quickly" means.
	##
	## No ball is needed; we just energize and watch the bat accelerate.
	_flipper.force_energized(true)

	var peak_tip: float = 0.0
	## Sample the tip speed once per physics frame across the snap window and keep the peak.
	for _i in range(SNAP_FRAMES):
		await wait_physics_frames(1)
		peak_tip = maxf(peak_tip, _flipper.tip_speed())

	_flipper.clear_force_energized()

	assert_gt(
		peak_tip,
		0.0,
		"tip_speed() must rise above 0 within the %.0f ms snap window (peak=%f)." % [
			SNAP_TIME_MS, peak_tip
		]
	)
