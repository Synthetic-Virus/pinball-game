extends GutTest
## Test matrix entry: PLUNGER power meter + launch mapping.
## Owner: test-builder + gameplay-programmer.
##
## SCOPE OF THIS FILE (the plunger-side CONTRACT, not the ball's resulting speed):
##   This file owns the gameplay contract that the plunger honors regardless of HOW the ball is
##   thrown: the oscillating meter, arm/disarm gating, the release-before-charge rule (BUG-008),
##   and that a release fires ball_launched exactly once and disarms. It exercises plunger.gd with
##   manually-stepped _physics_process frames and a lightweight stub ball, so it needs NO physics
##   server and NO scene tree.
##
##   The PHYSICAL strike (the ball's resulting velocity from the AnimatableBody3D face contact, the
##   power->speed mapping landing in the design range, no tunneling) is the physics half of the slice
##   and is proven against the REAL instanced Ball.tscn in tests/test_plunger_launch.gd, which drives
##   a real physics world. Asserting ball speed HERE is impossible without that physics world, so this
##   file deliberately does NOT - it asserts the launch CONTRACT (signal/disarm/stroke begun + a
##   monotonic power->stroke-speed mapping), and leaves the measured-ball-speed oracle to that file.
##
## WHAT CHANGED (QA BUG-015): the plunger no longer calls ball.launch() (it became a physical strike
##   in this slice). The four tests that asserted launch_call_count / last_launch_speed /
##   last_launch_direction on a stub were testing a path that no longer exists and would be RED in CI.
##   They are rewritten below to assert the plunger-side contract the physical strike DOES honor
##   (ball_launched once, disarm, stroke begun, and power -> stroke_speed monotonic via the test hook).
##
## HOW THESE TESTS WORK (for a non-expert reader):
##   - We create a real Plunger node and a lightweight stub ball (FakeBall) so set_ball() has a
##     RigidBody3D to hold. The plunger never calls anything on it now; it is just a valid handle so
##     the null-guard in _physics_process passes. This is NOT a mock of game infrastructure.
##   - _physics_process is called manually (simulate frames) so we do not need a running scene tree.
##   - All power_changed values are collected via signal connection.

# ---------------------------------------------------------------------------
# FakeBall: a minimal RigidBody3D handle so plunger.set_ball() has a valid ball to track. The
# physical plunger does NOT call any method on it (the strike is a collision, not a code call), so
# this stub records nothing; it only needs to exist and to expose sleeping (set by _do_launch).
# ---------------------------------------------------------------------------
class FakeBall extends RigidBody3D:
	pass

# ---------------------------------------------------------------------------
# Shared test state
# ---------------------------------------------------------------------------

var plunger: Node
var fake_ball: FakeBall

var _power_values: Array = []     # Collects every power_changed emission.
var _launched_count: int = 0       # Counts ball_launched signal firings.

## Step size used when we want to simulate a meaningful number of physics frames.
## Matches project.godot physics/common/physics_ticks_per_second = 120.
const FRAME_DELTA: float = 1.0 / 120.0

func before_each() -> void:
	plunger = preload("res://scripts/plunger.gd").new()
	add_child_autofree(plunger)

	fake_ball = FakeBall.new()
	add_child_autofree(fake_ball)
	plunger.set_ball(fake_ball)

	_power_values = []
	_launched_count = 0

	plunger.power_changed.connect(func(p: float) -> void: _power_values.append(p))
	plunger.ball_launched.connect(func() -> void: _launched_count += 1)

# ---------------------------------------------------------------------------
# Helper: simulate N physics frames with the "launch" action in a given state.
## We use Input.action_press / Input.action_release to toggle the action without needing
## a real window or InputEvent. These are the standard GUT-compatible input helpers.
# ---------------------------------------------------------------------------

func _simulate_frames(n: int, hold_launch: bool) -> void:
	if hold_launch:
		Input.action_press("launch")
	else:
		Input.action_release("launch")
	for _i: int in range(n):
		plunger._physics_process(FRAME_DELTA)

func _release_launch() -> void:
	Input.action_release("launch")
	plunger._physics_process(FRAME_DELTA)

func after_each() -> void:
	# Always release the action after each test so state does not bleed between tests.
	Input.action_release("launch")

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_only_charges_when_armed() -> void:
	# Without arm(): holding launch must produce no power_changed emissions and no launch.
	_simulate_frames(30, true)
	_release_launch()
	assert_eq(_launched_count, 0, "unarmed plunger must not launch")
	assert_eq(_power_values.size(), 0,
		"unarmed plunger must not emit power_changed while button is held")

func test_arm_emits_zero_power() -> void:
	plunger.arm()
	assert_true(_power_values.size() > 0, "arm() should emit power_changed")
	assert_eq(_power_values[-1], 0.0, "arm() should emit power of 0.0")

func test_meter_oscillates_between_zero_and_one() -> void:
	plunger.arm()
	_power_values.clear()

	# Hold the launch button for enough frames to complete at least one full oscillation.
	# CHARGE_RATE = 2.5 -> sweep time = 0.8 s -> 96 frames at 120 Hz.
	# We run 160 frames (~1.33 s) to guarantee at least one full triangle cycle.
	_simulate_frames(160, true)

	assert_true(_power_values.size() > 0, "power_changed should fire every frame while charging")

	# Every value must stay in [0, 1].
	for pv: float in _power_values:
		assert_true(pv >= 0.0 and pv <= 1.0,
			"power_changed value %f is outside [0, 1]" % pv)

	# The meter must both rise and fall (triangle oscillation, not a monotonic ramp).
	var saw_rise: bool = false
	var saw_fall: bool = false
	for i: int in range(1, _power_values.size()):
		if _power_values[i] > _power_values[i - 1]:
			saw_rise = true
		elif _power_values[i] < _power_values[i - 1]:
			saw_fall = true
		if saw_rise and saw_fall:
			break
	assert_true(saw_rise, "power should increase at some point (oscillation, not flat)")
	assert_true(saw_fall, "power should decrease at some point (oscillation, not capped at 1)")

func test_release_launches_and_disarms() -> void:
	plunger.arm()
	# Hold for a quarter sweep to build some charge.
	_simulate_frames(30, true)
	# Release.
	_release_launch()

	assert_eq(_launched_count, 1, "ball_launched should fire exactly once on release")
	assert_false(plunger.is_armed(), "plunger should be disarmed after launch")
	# The release must BEGIN the physical strike stroke (the contract replacing ball.launch()): the
	# face is now driving up-table. We assert the stroke is in progress rather than a ball.launch()
	# call. The ball's resulting speed is verified against the real ball in test_plunger_launch.gd.
	assert_true(plunger.is_stroking(), "release should begin the physical strike stroke")

func test_release_stroke_speed_within_bounds() -> void:
	# The forward STROKE speed (the plunger-side knob that, via the contact, throws the ball) must map
	# into the configured stroke band. The resulting BALL speed is verified against the real ball in
	# test_plunger_launch.gd; here we assert the mapping the plunger itself controls.
	plunger.arm()
	_simulate_frames(30, true)
	_release_launch()

	var speed: float = plunger.stroke_speed()
	assert_true(
		speed >= TableConfig.PLUNGER_STROKE_SPEED_MIN and speed <= TableConfig.PLUNGER_STROKE_SPEED_MAX,
		"stroke speed %f must be within [PLUNGER_STROKE_SPEED_MIN, PLUNGER_STROKE_SPEED_MAX]" % speed
	)

func test_higher_power_maps_to_higher_stroke_speed() -> void:
	# Strike at low power (hold briefly - charge stays near the low end of the wave).
	# CHARGE_RATE = 2.5, so after just a few frames the phase is small and power is near 0.
	plunger.arm()
	_simulate_frames(4, true)   # Very brief hold -> low power (phase ~= 4/120 * 2.5 ~= 0.083)
	_release_launch()
	var low_speed: float = plunger.stroke_speed()

	# Reset and strike at higher power (hold long enough to climb toward the peak).
	plunger.arm()
	# 48 frames = 0.4 s -> phase ~= 0.4 * 2.5 = 1.0 -> pingpong(1.0,1.0) = 1.0 (the peak)
	_simulate_frames(48, true)
	_release_launch()
	var high_speed: float = plunger.stroke_speed()

	assert_true(high_speed > low_speed,
		"higher power (stroke %f) must produce a higher stroke speed than lower power (stroke %f)" % [
			high_speed, low_speed
		])

func test_strike_drives_face_up_table() -> void:
	# The physical strike drives the face UP-TABLE (local -Z) into the ball. After a release, the face
	# has begun moving and its z must be at or below (more up-table than) its rest z. This replaces the
	# old ball.launch() direction assertion: the launch direction is now expressed by the face's motion.
	plunger.arm()
	_simulate_frames(20, true)
	_release_launch()
	# Step a few frames so the forward stroke has visibly advanced the face up-table.
	_simulate_frames(4, false)

	var rest_z: float = TableConfig.PLUNGER_REST_POS.z
	assert_lt(
		plunger.face_position().z,
		rest_z,
		"strike must drive the face up-table (-Z) from rest z=%f; got %f" % [
			rest_z, plunger.face_position().z
		]
	)

func test_meter_resets_to_zero_after_launch() -> void:
	plunger.arm()
	_simulate_frames(30, true)
	_power_values.clear()
	_release_launch()
	# The last power_changed emission after launch must be 0.0.
	assert_true(_power_values.size() > 0, "power_changed should fire on launch to reset the meter")
	assert_eq(_power_values[-1], 0.0, "power should be 0.0 after launch")

func test_disarm_resets_meter_to_zero() -> void:
	plunger.arm()
	_simulate_frames(30, true)  # Build some charge.
	_power_values.clear()
	# Release action first so next _physics_process does not interpret it as a launch.
	Input.action_release("launch")
	plunger.disarm()
	assert_true(_power_values.size() > 0, "disarm() should emit power_changed")
	assert_eq(_power_values[-1], 0.0, "disarm() should emit power 0.0")
	assert_false(plunger.is_armed(), "plunger should be unarmed after disarm()")

func test_no_double_launch_after_disarm() -> void:
	# Arm, build charge, disarm, then release the button and simulate frames.
	# The ball should NOT be launched because the plunger was disarmed.
	plunger.arm()
	_simulate_frames(20, true)
	Input.action_release("launch")
	plunger.disarm()
	_launched_count = 0
	_simulate_frames(10, false)  # No button held, already disarmed.
	assert_eq(_launched_count, 0, "disarmed plunger must not launch even if release is detected")
