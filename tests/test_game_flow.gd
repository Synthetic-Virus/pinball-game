extends GutTest
## Test matrix entry: GAME FLOW state machine (scoring, balls, drain, game over, restart).
## Owner: test-builder + gameplay-programmer.
##
## Pure-logic tests: drive GameFlow via its public methods/signals; no physics frames needed.
## This is the cheapest, most reliable coverage and should be filled first.
##
## HOW THESE TESTS WORK (for a non-expert reader):
##   - We create a real GameFlow node (no mocks) and call its public methods directly.
##   - Signals are captured by connecting them to a local helper that appends to an Array.
##   - Assertions check the captured array contents and the current_state() return value.
##
## NOTE ON THE LAUNCHING STATE (SLICE "Playtest fixes 2", soft-lock fix):
##   on_ball_launched() now enters LAUNCHING (not directly BALL_IN_PLAY). Tests that need the
##   ball to be in play use _promote_to_ball_in_play(), which feeds a single tick_launch_watch
##   call with a clearly in-play Z, exactly as table.gd does in the real game. Tests that
##   exercise the LAUNCHING state and recovery are in tests/test_soft_lock_recovery.gd.

var flow: Node

## Collected signal payloads. Each helper below appends to the matching list so tests can
## assert what was emitted, in order, without needing a coroutine or frame advance.
var _score_events: Array = []
var _balls_events: Array = []
var _messages: Array = []
var _game_over_events: Array = []
var _new_ball_requests: int = 0

func before_each() -> void:
	flow = preload("res://scripts/game_flow.gd").new()
	add_child_autofree(flow)

	# Reset capture arrays.
	_score_events = []
	_balls_events = []
	_messages = []
	_game_over_events = []
	_new_ball_requests = 0

	# Wire signal captures. Lambda syntax keeps each handler in-line for readability.
	flow.score_changed.connect(func(s: int) -> void: _score_events.append(s))
	flow.balls_changed.connect(func(b: int) -> void: _balls_events.append(b))
	flow.message.connect(func(m: String) -> void: _messages.append(m))
	flow.game_over.connect(func(fs: int) -> void: _game_over_events.append(fs))
	flow.request_new_ball.connect(func() -> void: _new_ball_requests += 1)


## Promote the state machine from LAUNCHING to BALL_IN_PLAY by feeding one tick_launch_watch
## call with a Z clearly in-play (0.0 is at the table center, well past the flipper row).
## This mirrors exactly what table.gd does each physics frame in real gameplay: the ball's
## measured Z is fed to the watchdog, and once it crosses LAUNCH_REACHED_PLAY_Z the machine
## promotes. WHY 0.0: it is the table center, unambiguously up-table of LAUNCH_REACHED_PLAY_Z
## (= FLIPPER_PIVOT_Z - 3.5 = 16.5 in world scale after the QA BUG-031 hardening). Tests that are
## not about the LAUNCHING state call this immediately after on_ball_launched() to reach
## BALL_IN_PLAY cleanly.
func _promote_to_ball_in_play() -> void:
	flow.tick_launch_watch(0.0, 1.0 / 240.0)

# ---------------------------------------------------------------------------
# start_game
# ---------------------------------------------------------------------------

func test_starts_with_zero_score_and_three_balls() -> void:
	flow.start_game()
	# Score should be announced as 0 on start.
	assert_true(_score_events.size() > 0, "score_changed should fire on start_game")
	assert_eq(_score_events[0], 0, "initial score should be 0")
	# Balls should be announced as 3 on start.
	assert_true(_balls_events.size() > 0, "balls_changed should fire on start_game")
	assert_eq(_balls_events[0], 3, "initial ball count should be 3")

func test_start_game_requests_new_ball() -> void:
	flow.start_game()
	assert_eq(_new_ball_requests, 1, "start_game should emit request_new_ball once")

func test_start_game_state_is_ready_to_launch() -> void:
	flow.start_game()
	assert_eq(flow.current_state(), flow.State.READY_TO_LAUNCH,
		"state after start_game should be READY_TO_LAUNCH")

# ---------------------------------------------------------------------------
# scoring
# ---------------------------------------------------------------------------

func test_target_scores_only_in_play() -> void:
	flow.start_game()
	# Still in READY_TO_LAUNCH - a target hit should be ignored.
	flow.on_target_scored(100)
	assert_eq(_score_events[-1], 0, "score must not change while READY_TO_LAUNCH")

	# Move to BALL_IN_PLAY (on_ball_launched -> LAUNCHING, then promote via watchdog).
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	var count_before: int = _score_events.size()
	flow.on_target_scored(100)
	assert_true(_score_events.size() > count_before, "score_changed must fire during BALL_IN_PLAY")
	assert_eq(_score_events[-1], 100, "score should be 100 after one 100-point target hit")

func test_multiple_target_hits_accumulate() -> void:
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_target_scored(100)
	flow.on_target_scored(100)
	flow.on_target_scored(100)
	assert_eq(_score_events[-1], 300, "three 100-point hits should total 300")

func test_scoring_during_game_over_is_ignored() -> void:
	# Drain three balls to reach GAME_OVER. Each ball must reach play first (BALL_IN_PLAY) before
	# the drain guard accepts the drain signal.
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_ball_drained()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_ball_drained()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_ball_drained()
	assert_eq(flow.current_state(), flow.State.GAME_OVER, "should be GAME_OVER after 3 drains")
	var score_before_size: int = _score_events.size()
	flow.on_target_scored(100)
	assert_eq(_score_events.size(), score_before_size,
		"score_changed must not fire in GAME_OVER state")

# ---------------------------------------------------------------------------
# ball launched
# ---------------------------------------------------------------------------

func test_launch_transitions_to_launching() -> void:
	## on_ball_launched() now enters LAUNCHING (not straight to BALL_IN_PLAY). The watchdog
	## (tick_launch_watch) promotes to BALL_IN_PLAY once the ball crosses into play (see
	## test_soft_lock_recovery.gd for the full watchdog suite). This test pins the direct transition.
	flow.start_game()
	flow.on_ball_launched()
	assert_eq(flow.current_state(), flow.State.LAUNCHING,
		"on_ball_launched must enter LAUNCHING (the watchdog confirms play before BALL_IN_PLAY)")


func test_launch_then_promote_transitions_to_ball_in_play() -> void:
	## Confirm the full happy path: launch -> LAUNCHING -> watchdog sees in-play Z -> BALL_IN_PLAY.
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	assert_eq(flow.current_state(), flow.State.BALL_IN_PLAY,
		"after a ball reaches play the state must be BALL_IN_PLAY")


func test_launch_clears_message() -> void:
	flow.start_game()
	# The start message is already set; launching should clear it (empty string).
	flow.on_ball_launched()
	assert_true(_messages.size() > 0, "message signal should have fired")
	assert_eq(_messages[-1], "", "on_ball_launched should emit an empty message to clear the HUD")

# ---------------------------------------------------------------------------
# drain
# ---------------------------------------------------------------------------

func test_drain_decrements_balls_and_requests_new_ball() -> void:
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	_new_ball_requests = 0  # Reset after start_game's initial request.
	flow.on_ball_drained()
	assert_true(_balls_events.size() > 0, "balls_changed should fire on drain")
	assert_eq(_balls_events[-1], 2, "balls should be 2 after first drain")
	assert_eq(_new_ball_requests, 1, "request_new_ball should fire after a non-final drain")

func test_drain_posts_ball_drained_message() -> void:
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_ball_drained()
	# The drain message now includes the re-issue of the launch prompt (UX item 5).
	assert_true(_messages.size() > 0, "a message should be emitted after a drain")
	var found_drain_text: bool = false
	for msg: String in _messages:
		if "BALL DRAINED" in msg:
			found_drain_text = true
			break
	assert_true(found_drain_text,
		"a message containing 'BALL DRAINED' should be emitted after a drain when balls remain")

func test_drain_ignored_when_not_in_play() -> void:
	# Drain without launching (while READY_TO_LAUNCH) should be silently ignored.
	# With the new LAUNCHING state, draining during LAUNCHING is also ignored (the soft-lock
	# recovery path handles that via the watchdog, not a drain signal from that state).
	flow.start_game()
	var balls_before: int = _balls_events.size()
	flow.on_ball_drained()
	assert_eq(_balls_events.size(), balls_before,
		"drain while READY_TO_LAUNCH should emit no balls_changed")

# ---------------------------------------------------------------------------
# game over
# ---------------------------------------------------------------------------

func test_game_over_at_zero_balls() -> void:
	flow.start_game()
	# Drain all three balls. Each must reach play (BALL_IN_PLAY) before the drain guard accepts it.
	for _i: int in range(3):
		flow.on_ball_launched()
		_promote_to_ball_in_play()
		flow.on_ball_drained()
	assert_eq(flow.current_state(), flow.State.GAME_OVER,
		"state should be GAME_OVER after draining all balls")
	assert_eq(_game_over_events.size(), 1, "game_over signal should fire exactly once")

func test_game_over_carries_final_score() -> void:
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_target_scored(250)  # Score some points before game over.
	flow.on_ball_drained()
	for _i: int in range(2):
		flow.on_ball_launched()
		_promote_to_ball_in_play()
		flow.on_ball_drained()
	assert_eq(_game_over_events[-1], 250,
		"game_over signal should carry the accumulated score as the argument")

func test_no_new_ball_request_at_game_over() -> void:
	flow.start_game()
	_new_ball_requests = 0
	for _i: int in range(3):
		flow.on_ball_launched()
		_promote_to_ball_in_play()
		flow.on_ball_drained()
	# Only the two mid-game drains should have requested a new ball (not the game-over drain).
	assert_eq(_new_ball_requests, 2,
		"request_new_ball should not fire on the final drain that triggers game over")

# ---------------------------------------------------------------------------
# restart
# ---------------------------------------------------------------------------

func test_restart_resets_score_and_balls() -> void:
	flow.start_game()
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	flow.on_target_scored(500)
	# Drain ball 1 first (already in BALL_IN_PLAY), then drain balls 2 and 3.
	flow.on_ball_drained()
	for _i: int in range(2):
		flow.on_ball_launched()
		_promote_to_ball_in_play()
		flow.on_ball_drained()
	# Now in GAME_OVER; call restart.
	flow.restart()
	assert_eq(flow.current_state(), flow.State.READY_TO_LAUNCH,
		"restart should return state to READY_TO_LAUNCH")
	assert_eq(_score_events[-1], 0, "restart should reset score to 0")
	assert_eq(_balls_events[-1], 3, "restart should reset ball count to 3")

func test_restart_ignored_when_not_game_over() -> void:
	flow.start_game()
	# After launch + promote the state is BALL_IN_PLAY; restart must not fire.
	flow.on_ball_launched()
	_promote_to_ball_in_play()
	var state_before: int = flow.current_state()
	flow.restart()
	assert_eq(flow.current_state(), state_before,
		"restart called during BALL_IN_PLAY should have no effect")
