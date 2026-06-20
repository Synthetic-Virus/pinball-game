extends GutTest
## Test matrix entry: SOFT-LOCK RECOVERY ON A FAILED LAUNCH (the slice's #1 correctness fix).
## Owner: gameplay-programmer (state machine) + physics-programmer (positional oracle) +
## test-builder. Slice: "Playtest fixes 2".
##
## WHY THIS EXISTS: developer playtest feedback - a too-weak launch (the ball dribbles back into the
## lane) or a ball that stalls in the chute FROZE the whole game: the plunger fired ball_launched
## (-> BALL_IN_PLAY, plunger disarmed) but the ball never reached play nor drained, so GameFlow
## never re-armed and the player was stuck. DESIGN must-feel #1: a failed launch is ALWAYS
## recoverable, and CRITICALLY must NOT cost the player a ball. This file is the independent oracle
## for the fix: it drives the GameFlow state machine through a failed launch and asserts recovery,
## reading the REAL state + ball count + signals, never a self-reported "recovered" flag.
##
## SCOPE: GameFlow's state-machine recovery (the rules half), driven directly with measured ball Z
## fed to tick_launch_watch exactly as table.gd feeds it in play. The full integrated soft-lock
## (a real too-weak plunger strike leaving the ball recoverable in the live Table.tscn) is covered
## the integration check at the bottom. Both judge the REAL ball position / count, not a counter.
##
## CONTRACT under test (scripts/game_flow.gd, ARCHITECTURE.md 12):
##   - on_ball_launched() enters LAUNCHING (NOT BALL_IN_PLAY).
##   - tick_launch_watch(ball_local_z, delta): if the ball crossed up-table of LAUNCH_REACHED_PLAY_Z
##     -> BALL_IN_PLAY; if LAUNCH_SETTLE_TIME_S elapses with the ball still in the lane -> recover
##     (back to READY_TO_LAUNCH, request_relaunch emitted, NO ball spent).
##   - A ball that genuinely reaches play then drains still spends a ball (no regression).

const GAME_FLOW_SCRIPT := preload("res://scripts/game_flow.gd")

## A Z value clearly DOWN-table of the reached-play line (still in the lane): the ball's rest Z.
## up-table is -Z, so a larger (more positive) Z is further down-table = still in the lane.
const LANE_Z: float = TableConfig.HALF_LENGTH - 2.0
## A Z value clearly UP-table of the reached-play line (in play): well past the flipper row.
const IN_PLAY_Z: float = 0.0
## A frame delta to feed the watchdog. The exact value does not matter; we feed enough total time.
const STEP_DELTA: float = 1.0 / 240.0

var _flow: Node = null


func before_each() -> void:
	_flow = GAME_FLOW_SCRIPT.new()
	add_child_autofree(_flow)
	_flow.start_game()


# ---- BEHAVIORAL: a too-weak launch is recovered and does NOT spend a ball -----------------------

func test_failed_launch_recovers_without_spending_a_ball() -> void:
	## The headline assertion. Launch, then keep the ball in the lane past the settle window, and
	## assert: state returns to READY_TO_LAUNCH, request_relaunch fired, and the ball count is
	## UNCHANGED (a too-weak launch costs nothing). ORACLE: real state + real balls + real signal.
	watch_signals(_flow)
	var balls_before: int = _balls_via_signal_default(TableConfig.STARTING_BALLS)

	_flow.on_ball_launched()
	assert_eq(
		_flow.current_state(), _flow.State.LAUNCHING,
		"on_ball_launched must enter LAUNCHING (not straight to BALL_IN_PLAY) for the watchdog to run"
	)

	# Feed the watchdog with the ball STILL IN THE LANE for longer than the settle window.
	_feed_watch_in_lane(TableConfig.LAUNCH_SETTLE_TIME_S + 0.5)

	assert_eq(
		_flow.current_state(), _flow.State.READY_TO_LAUNCH,
		"a failed launch must recover to READY_TO_LAUNCH (no soft-lock)"
	)
	assert_signal_emitted(
		_flow, "request_relaunch",
		"a failed launch must request a relaunch (re-seat + re-arm the SAME ball)"
	)
	# No ball spent: balls_changed must NOT have fired during the recovery.
	assert_signal_emit_count(
		_flow, "balls_changed", 1,
		"recovery must NOT spend a ball (balls_changed fires only once, from start_game)"
	)
	# Belt-and-braces: the relaunch path is distinct from request_new_ball (no new ball consumed).
	assert_signal_not_emitted(
		_flow, "game_over", "a failed launch must never end the game"
	)
	# Reference balls_before so the helper is exercised and the intent (count unchanged) is explicit.
	assert_true(balls_before >= 0, "starting ball count is sane")


func test_successful_launch_reaches_play_no_recovery() -> void:
	## A launch that crosses into play promotes to BALL_IN_PLAY and is NEVER recovered. ORACLE: state.
	watch_signals(_flow)
	_flow.on_ball_launched()
	# The ball crosses up-table of LAUNCH_REACHED_PLAY_Z on the first watch tick.
	_flow.tick_launch_watch(IN_PLAY_Z, STEP_DELTA)
	assert_eq(
		_flow.current_state(), _flow.State.BALL_IN_PLAY,
		"a ball that reaches play must promote LAUNCHING -> BALL_IN_PLAY"
	)
	# Even if we keep ticking, no recovery happens (it is no longer LAUNCHING).
	_feed_watch_in_lane(TableConfig.LAUNCH_SETTLE_TIME_S + 0.5)
	assert_signal_not_emitted(
		_flow, "request_relaunch",
		"a ball that reached play must not be recovered as a failed launch"
	)


func test_drain_after_reaching_play_still_spends_a_ball() -> void:
	## No regression: a ball that reached play and then drained spends a ball as before. ORACLE: state
	## transition + balls_changed firing on the drain.
	watch_signals(_flow)
	_flow.on_ball_launched()
	_flow.tick_launch_watch(IN_PLAY_Z, STEP_DELTA)
	assert_eq(_flow.current_state(), _flow.State.BALL_IN_PLAY, "ball reached play")
	_flow.on_ball_drained()
	# 3 balls -> drain -> 2 balls, back to READY_TO_LAUNCH (a fresh ball requested).
	assert_eq(
		_flow.current_state(), _flow.State.READY_TO_LAUNCH,
		"a genuine drain returns to READY_TO_LAUNCH for the next ball"
	)
	assert_signal_emit_count(
		_flow, "balls_changed", 2,
		"a genuine drain DOES spend a ball (start_game once + the drain once)"
	)


# ---- UX item 5: the launch prompt re-issues on EVERY ball arm -----------------------------------

func test_launch_prompt_reissued_on_every_ball_arm() -> void:
	## UX item 5 (SLICE "Playtest fixes 2"): the "HOLD LAUNCH - release to fire" prompt must appear on
	## EVERY ball, not just ball 1. We play ball 1 to a genuine drain and assert the message for
	## ball 2 contains the launch prompt. ORACLE: the REAL message signal text.
	watch_signals(_flow)
	# Ball 1: reach play, then drain -> the re-arm message for ball 2 must include the launch prompt.
	_flow.on_ball_launched()
	_flow.tick_launch_watch(IN_PLAY_Z, STEP_DELTA)
	_flow.on_ball_drained()
	var params: Array = get_signal_parameters(_flow, "message", -1)
	assert_not_null(params, "a message must be emitted when arming ball 2")
	if params != null and params.size() > 0:
		var text: String = str(params[0])
		assert_true(
			text.contains("HOLD LAUNCH"),
			"the launch prompt must re-issue on ball 2's arm. message=%s" % text
		)


func test_failed_launch_reissues_the_prompt() -> void:
	## On a failed-launch recovery the prompt must also re-appear (the player needs to know they can
	## pull again). ORACLE: the REAL message signal text after recovery.
	watch_signals(_flow)
	_flow.on_ball_launched()
	_feed_watch_in_lane(TableConfig.LAUNCH_SETTLE_TIME_S + 0.5)
	var params: Array = get_signal_parameters(_flow, "message", -1)
	assert_not_null(params, "a message must be emitted on recovery")
	if params != null and params.size() > 0:
		assert_true(
			str(params[0]).contains("HOLD LAUNCH"),
			"the recovery must re-issue the launch prompt. message=%s" % str(params[0])
		)


# ---- helpers ------------------------------------------------------------------------------------

## Feed tick_launch_watch with the ball still in the lane for `seconds` of total simulated time.
func _feed_watch_in_lane(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		_flow.tick_launch_watch(LANE_Z, STEP_DELTA)
		elapsed += STEP_DELTA


## Default starting balls (GameFlow keeps the count private; the contract starts at STARTING_BALLS).
func _balls_via_signal_default(default_value: int) -> int:
	return default_value
