extends Node3D
## Plunger - the launch control: hold to charge an OSCILLATING power meter, release to launch.
##
## OWNERSHIP: gameplay-programmer. You own the charge/oscillation logic and the power->speed mapping.
## You do NOT own the ball physics: to launch, call ball.launch(direction, speed) on the Ball handle
## table.gd hands you. Geometry/speeds come from TableConfig.
##
## FEEL TARGET (DESIGN.md "LAUNCH SKILL"): the meter sweeps fast enough to matter, slow enough to
## aim - a full 0..1..0 sweep on the order of 0.5-1.0 s. Released power visibly maps to launch
## strength (LAUNCH_SPEED_MIN..MAX). Input.is_action_pressed("launch") polled each physics frame
## (same pattern as flipper input, zero lag).
##
## OSCILLATION MATH: _charge_phase advances by delta * CHARGE_RATE each frame while the button is
## held. pingpong(_charge_phase, 1.0) maps the unbounded phase to a 0..1..0 triangle wave. One full
## triangle (0->1->0) completes when phase crosses 2.0, which takes 2.0 / CHARGE_RATE seconds.
## At CHARGE_RATE = 2.5: full sweep = 2.0/2.5 = 0.8 s. This sits in the 0.5-1.0 s target range.
##
## STATE: the plunger is only active when ARMED (a fresh ball is waiting in the lane). GameFlow arms
## it via arm(); a successful launch disarms it and emits ball_launched.
##
## STABLE CONTRACT (table.gd / GameFlow / tests depend on these):
##   signal power_changed(power: float)   # 0..1 each frame while charging, for the HUD meter.
##   signal ball_launched()               # emitted the frame the ball is launched.
##   func arm() -> void                    # enable charging for the waiting ball.
##   func disarm() -> void                 # disable (e.g. on drain mid-charge).
##   func set_ball(ball: RigidBody3D) -> void  # the ball this plunger launches.
##   func is_armed() -> bool

signal power_changed(power: float)
signal ball_launched()

var _armed: bool = false
var _charging: bool = false
var _charge_phase: float = 0.0
var _power: float = 0.0
var _ball: RigidBody3D = null
## Release latch (QA BUG-008): when a ball arms while the player still happens to be holding "launch"
## (e.g. they held it through the previous ball draining), we must NOT start charging on a held key
## the player never pressed for THIS ball. We require a release first: charging is blocked until the
## action has been seen released at least once since arm(). Set false by arm(), set true on release.
var _release_seen: bool = false

## How fast the meter oscillates. CHARGE_RATE of 2.5 makes a full 0->1->0 sweep take 0.8 s,
## which sits comfortably in the DESIGN feel target of 0.5-1.0 s.
## Formula: sweep_time = 2.0 / CHARGE_RATE.
const CHARGE_RATE: float = 2.5

## Register the ball that this plunger will launch. Called by table.gd when it builds the scene.
## STABLE SIGNATURE.
func set_ball(ball: RigidBody3D) -> void:
	_ball = ball

## Arm for a fresh ball. Resets oscillation so every launch starts from the same baseline.
## Called by GameFlow via table.gd when request_new_ball fires. STABLE SIGNATURE.
func arm() -> void:
	_armed = true
	_charging = false
	_charge_phase = 0.0
	_power = 0.0
	# Require the player to RELEASE before this ball can charge. If "launch" is already held at arm
	# time (held through the previous drain), _physics_process will wait for a release rather than
	# auto-charging a key the player never pressed for this ball (QA BUG-008). A press from a clean
	# released state is allowed immediately.
	_release_seen = not Input.is_action_pressed("launch")
	# Emit immediately so the HUD meter resets to zero on the same frame the ball resets.
	power_changed.emit(0.0)

## Disarm the plunger. Called if the ball drains before it was launched (rare but possible if a
## stray ball reaches the drain during a charge), or on game over. STABLE SIGNATURE.
func disarm() -> void:
	_armed = false
	_charging = false
	# Zero the meter so the HUD bar does not freeze at its last power reading.
	power_changed.emit(0.0)

## True when a ball is waiting and the player can charge. STABLE SIGNATURE.
func is_armed() -> bool:
	return _armed

func _physics_process(delta: float) -> void:
	# Only handle input when a ball is actually waiting in the lane.
	if not _armed:
		return

	# Null guard: if table.gd has not called set_ball() yet, do nothing rather than crashing.
	if _ball == null:
		return

	var holding: bool = Input.is_action_pressed("launch")

	# Latch the first release after arm(). Until we have seen the key released once, a held key is
	# stale input from before this ball armed and must not charge (QA BUG-008).
	if not holding:
		_release_seen = true

	if holding and _release_seen:
		# Build up the oscillating charge phase each physics frame.
		# pingpong maps the unbounded _charge_phase to a triangle wave on [0, 1].
		_charging = true
		_charge_phase += delta * CHARGE_RATE
		_power = pingpong(_charge_phase, 1.0)
		# Emit every frame so the HUD meter animates smoothly.
		power_changed.emit(_power)
	elif _charging:
		# The player just released (was holding last frame, no longer holding this frame).
		# This is the launch moment: use whatever power the meter is at right now.
		_do_launch()

## Map the current power level to a launch speed and fire the ball.
## Called on the frame the player releases the launch button. STABLE behaviour.
func _do_launch() -> void:
	# Clamp _power to [0,1] defensively; pingpong should never exceed this but clamp is cheap.
	var clamped_power: float = clampf(_power, 0.0, 1.0)

	# Linear interpolation: 0.0 -> LAUNCH_SPEED_MIN (dribble), 1.0 -> LAUNCH_SPEED_MAX (full power).
	var speed: float = lerpf(TableConfig.LAUNCH_SPEED_MIN, TableConfig.LAUNCH_SPEED_MAX, clamped_power)

	# TableConfig.up_table_local() returns Vector3(0,0,-1) - toward the arch in playfield local space.
	# The ball script's launch() sets linear_velocity = direction * speed.
	_ball.launch(TableConfig.up_table_local(), speed)

	# Disarm before emitting so any listener that checks is_armed() sees the correct state.
	_armed = false
	_charging = false
	_charge_phase = 0.0
	_power = 0.0

	# Zero the meter bar immediately on launch.
	power_changed.emit(0.0)

	# Notify GameFlow (-> BALL_IN_PLAY) and any other listener.
	ball_launched.emit()
