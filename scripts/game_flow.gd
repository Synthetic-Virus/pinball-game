extends Node
## GameFlow - the game state machine: balls, score, new-ball arming, game over, restart.
##
## OWNERSHIP: gameplay-programmer. This is the rules brain. It owns NO physics and NO UI widgets; it
## receives events (target scored, ball drained, ball launched) and emits state changes the HUD and
## the ball/plunger react to. table.gd wires every connection (see its header).
##
## STATE MACHINE (keep it small and explicit - one responsibility):
##   READY_TO_LAUNCH : a ball sits in the lane, plunger armed. -> on_ball_launched -> BALL_IN_PLAY.
##   BALL_IN_PLAY    : ball is live; targets score. -> on_ball_drained -> spend a ball.
##   (spend a ball) : balls_left -= 1; if > 0 -> request_new_ball -> READY_TO_LAUNCH;
##     else GAME_OVER.
##   GAME_OVER       : show final score; "launch"/restart action resets to READY_TO_LAUNCH ball 3.
##
## DESIGN scope: score from 0, +points per target, 3 balls, drain decrements + re-arms, game over at
## 0 shows final score + restart. No ball-save, multipliers, combos, persistence (DESIGN cut list).
##
## STABLE CONTRACT (table.gd / HUD / tests depend on these):
##   signal score_changed(score: int)
##   signal balls_changed(balls: int)
##   signal message(text: String)
##   signal game_over(final_score: int)
##   signal request_new_ball()        # ask table.gd to reset the ball + arm the plunger.
##   func start_game() -> void
##   func on_target_scored(points: int) -> void
##   func on_ball_launched() -> void
##   func on_ball_drained() -> void
##   func restart() -> void
##   func current_state() -> int      # one of the State enum values (for tests/diagnostics).

signal score_changed(score: int)
signal balls_changed(balls: int)
signal message(text: String)
signal game_over(final_score: int)
signal request_new_ball()

enum State { READY_TO_LAUNCH, BALL_IN_PLAY, GAME_OVER }

const STARTING_BALLS: int = 3

var _state: int = State.READY_TO_LAUNCH
var _score: int = 0
var _balls: int = STARTING_BALLS

## Begin a fresh game: reset score and ball count, emit initial state, and request the first ball.
## Called by table.gd _ready() to kick off gameplay. STABLE SIGNATURE.
func start_game() -> void:
	_score = 0
	_balls = STARTING_BALLS
	_state = State.READY_TO_LAUNCH
	# Announce the clean slate so HUD reflects the initial values immediately.
	score_changed.emit(0)
	balls_changed.emit(_balls)
	# Prompt the player so they know what to do on their very first launch.
	message.emit("HOLD LAUNCH - release to fire")
	# Ask table.gd to position the ball and arm the plunger.
	request_new_ball.emit()

## A target was hit. Only scores during BALL_IN_PLAY - guard prevents phantom scores during launch
## or after game over (e.g. a slow ball still rolling when the state has already changed).
## STABLE SIGNATURE.
func on_target_scored(points: int) -> void:
	if _state != State.BALL_IN_PLAY:
		return
	_score += points
	score_changed.emit(_score)

## The plunger launched the ball: move from READY_TO_LAUNCH to BALL_IN_PLAY and clear the prompt.
## STABLE SIGNATURE.
func on_ball_launched() -> void:
	# Ignore if we somehow receive this in the wrong state (defensive guard).
	if _state != State.READY_TO_LAUNCH:
		return
	_state = State.BALL_IN_PLAY
	# Clear the launch prompt so HUD message area is clean during play.
	message.emit("")

## The ball entered the drain. Spends a ball; re-arms for the next one or declares game over.
## Only acts while BALL_IN_PLAY - guards against duplicate drain signals or late-arriving bodies.
## STABLE SIGNATURE.
func on_ball_drained() -> void:
	if _state != State.BALL_IN_PLAY:
		return
	_balls -= 1
	balls_changed.emit(_balls)

	if _balls > 0:
		# More balls remain: return to launch state and ask for a fresh ball.
		_state = State.READY_TO_LAUNCH
		message.emit("BALL DRAINED")
		request_new_ball.emit()
	else:
		# All balls spent: game is over.
		_state = State.GAME_OVER
		# game_over carries the final score so the HUD can display it without keeping its own score.
		game_over.emit(_score)

## Restart the game from the GAME_OVER screen. Only meaningful in GAME_OVER state.
## The HUD "press LAUNCH to restart" prompt should call this (wired via table.gd or the HUD button).
## STABLE SIGNATURE.
func restart() -> void:
	# Silently ignore restarts when the game is still running - prevents accidental resets.
	if _state != State.GAME_OVER:
		return
	start_game()

## Current state value exposed for tests and diagnostics. STABLE SIGNATURE.
func current_state() -> int:
	return _state
