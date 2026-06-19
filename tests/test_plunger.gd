extends GutTest
## Test matrix entry: PLUNGER power meter + the physical-strike CONTRACT.
## Owner: test-builder + gameplay-programmer + physics-programmer.
##
## WHAT THIS COVERS (unit tier): the charge/oscillation logic and the stable contract
## (arm/disarm/is_armed, power_changed/ball_launched, the release-latch). These run by calling
## _physics_process manually so we do not need a running scene tree.
##
## WHAT MOVED OUT: the plunger no longer SETS the ball's velocity via ball.launch(); it now STRIKES
## the ball with a physical AnimatableBody3D face and the momentum comes from the contact. The
## velocity-transfer assertions (a strike imparts speed, full out-throws weak, no tunneling) need a
## real physics world and live in tests/test_plunger_launch.gd. Here we only assert that a release
## BEGINS a stroke and keeps the meter/arm contract.
##
## HOW THESE TESTS WORK (for a non-expert reader):
##   - We create a real Plunger node and a lightweight stub ball (FakeBall). The plunger no longer
##     calls anything on the ball (it strikes it physically), so the stub just stands in as the
##     RigidBody3D handle set_ball() expects. It is NOT a mock of game infrastructure.
##   - _physics_process is called manually (simulate frames) so we do not need a running scene tree.
##   - All power_changed values are collected via signal connection.

# ---------------------------------------------------------------------------
# FakeBall: minimal RigidBody3D stand-in so set_ball() has a typed handle. The physical plunger does
# not call back into the ball, so this records nothing; it just exists to satisfy the contract.
# ---------------------------------------------------------------------------
class FakeBall extends RigidBody3D:
	## Marker so the class body is non-empty; the physical plunger never reads it.
	const IS_FAKE_BALL: bool = true

# ---------------------------------------------------------------------------
# Shared test state
# ---------------------------------------------------------------------------

var plunger: Node
var fake_ball: FakeBall

var _power_values: Array = []     # Collects every power_changed emission.
var _launched_count: int = 0       # Counts ball_launched signal firings.

## Step size used when we want to simulate a meaningful number of physics frames.
## Matches project.godot physics/common/physics_ticks_per_second = 240.
const FRAME_DELTA: float = 1.0 / 240.0

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
	# CHARGE_RATE = 2.5 -> sweep time = 0.8 s -> 192 frames at 240 Hz.
	# We run 320 frames (~1.33 s) to guarantee at least one full triangle cycle.
	_simulate_frames(320, true)

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
	assert_true(plunger.is_stroking(),
		"release must BEGIN a physical stroke (is_stroking() true right after release)")

func test_launch_direction_is_up_table() -> void:
	# The physical face is driven UP-TABLE (local -Z). After a release, the face must have moved to a
	# SMALLER z than its rest position (toward the arch), confirming the stroke direction.
	var rest_z: float = TableConfig.PLUNGER_REST_POS.z
	plunger.arm()
	_simulate_frames(20, true)
	_release_launch()
	# Step a few frames so the forward stroke advances measurably.
	_simulate_frames(5, false)
	assert_lt(
		plunger.face_position().z,
		rest_z,
		"plunger face must drive up-table (smaller z) on a strike; rest z=%f, now=%f" % [
			rest_z, plunger.face_position().z
		]
	)

func test_face_returns_to_rest_after_stroke() -> void:
	# After the full forward + return stroke the face must come back to its rest position so it is
	# ready for the next ball and does not sit blocking the lane.
	plunger.arm()
	_simulate_frames(20, true)
	_release_launch()
	# Step generously: forward stroke (PLUNGER_STROKE_LENGTH at >=30 u/s) + return at RETURN_SPEED.
	# At 240 Hz, 240 frames = 1.0 s, far longer than the whole stroke needs.
	_simulate_frames(240, false)
	assert_false(plunger.is_stroking(), "stroke should have finished after 1 s of frames")
	assert_true(
		plunger.face_position().is_equal_approx(TableConfig.PLUNGER_REST_POS),
		"face should return to PLUNGER_REST_POS %s, got %s" % [
			str(TableConfig.PLUNGER_REST_POS), str(plunger.face_position())
		]
	)

func test_higher_power_strokes_faster() -> void:
	# The power->stroke mapping must be monotonic: a higher charge produces a faster forward stroke,
	# which is what makes a full strike out-throw a weak one. We measure the face's forward speed by
	# how far it travels in a fixed number of frames right after release.
	var rest_z: float = TableConfig.PLUNGER_REST_POS.z

	# Low power: brief hold (phase ~= 4/240 * 2.5 ~= 0.042 -> power near 0).
	plunger.arm()
	_simulate_frames(4, true)
	_release_launch()
	_simulate_frames(3, false)
	var low_travel: float = rest_z - plunger.face_position().z
	# Let the low stroke finish so it does not bleed into the next measurement.
	_simulate_frames(240, false)

	# High power: hold to the peak (96 frames = 0.4 s -> phase 1.0 -> pingpong = 1.0).
	plunger.arm()
	_simulate_frames(96, true)
	_release_launch()
	_simulate_frames(3, false)
	var high_travel: float = rest_z - plunger.face_position().z

	assert_gt(
		high_travel,
		low_travel,
		"higher power must drive the face faster (more travel in 3 frames): high=%f, low=%f" % [
			high_travel, low_travel
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
