extends GutTest
## Test matrix entry: PLUNGER power meter + launch mapping.
## Owner: test-builder + gameplay-programmer.
##
## HOW THESE TESTS WORK (for a non-expert reader):
##   - We create a real Plunger node and a lightweight stub ball (FakeBall) that records the
##     speed passed to launch() without doing any physics. This is NOT a mock of game infrastructure;
##     it is a minimal stand-in for the physics-programmer's ball.gd, which does not run without
##     Godot's physics server being driven by frames. Using a stub here is the right boundary.
##   - _physics_process is called manually (simulate frames) so we do not need a running scene tree.
##   - All power_changed values are collected via signal connection.

# ---------------------------------------------------------------------------
# FakeBall: minimal stand-in so plunger.gd can call _ball.launch(direction, speed)
# without needing real ball physics. Records the last launch arguments for assertions.
# ---------------------------------------------------------------------------
class FakeBall extends RigidBody3D:
	var last_launch_direction: Vector3 = Vector3.ZERO
	var last_launch_speed: float = 0.0
	var launch_call_count: int = 0

	func launch(direction: Vector3, speed: float) -> void:
		last_launch_direction = direction
		last_launch_speed = speed
		launch_call_count += 1

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
	assert_eq(fake_ball.launch_call_count, 1, "ball.launch() should be called exactly once")

func test_release_speed_within_bounds() -> void:
	plunger.arm()
	_simulate_frames(30, true)
	_release_launch()

	var speed: float = fake_ball.last_launch_speed
	assert_true(
		speed >= TableConfig.LAUNCH_SPEED_MIN and speed <= TableConfig.LAUNCH_SPEED_MAX,
		"launch speed %f must be within [LAUNCH_SPEED_MIN, LAUNCH_SPEED_MAX]" % speed
	)

func test_higher_power_maps_to_higher_speed() -> void:
	# Launch at low power (hold briefly - charge stays near the low end of the wave).
	# CHARGE_RATE = 2.5, so after just a few frames the phase is small and power is near 0.
	plunger.arm()
	_simulate_frames(4, true)   # Very brief hold -> low power (phase ~= 4/120 * 2.5 ~= 0.083)
	_release_launch()
	var low_speed: float = fake_ball.last_launch_speed

	# Reset and launch at higher power (hold long enough to climb toward the peak).
	plunger.arm()
	# 48 frames = 0.4 s -> phase ~= 0.4 * 2.5 = 1.0 -> pingpong(1.0,1.0) = 1.0 (the peak)
	_simulate_frames(48, true)
	_release_launch()
	var high_speed: float = fake_ball.last_launch_speed

	assert_true(high_speed > low_speed,
		"higher power (speed %f) must produce a higher launch speed than lower power (speed %f)" % [
			high_speed, low_speed
		])

func test_launch_direction_is_up_table() -> void:
	plunger.arm()
	_simulate_frames(20, true)
	_release_launch()
	# TableConfig.up_table_local() returns Vector3(0, 0, -1).
	var expected: Vector3 = TableConfig.up_table_local()
	assert_true(
		fake_ball.last_launch_direction.is_equal_approx(expected),
		"launch direction should be TableConfig.up_table_local() = %s, got %s" % [
			str(expected), str(fake_ball.last_launch_direction)
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
