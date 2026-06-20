extends Node
## GameFlow - the game state machine: balls, score, new-ball arming, game over, restart.
##
## OWNERSHIP: gameplay-programmer. This is the rules brain. It owns NO physics and NO UI widgets; it
## receives events (target scored, ball drained, ball launched) and emits state changes the HUD and
## the ball/plunger react to. table.gd wires every connection (see its header).
##
## STATE MACHINE (keep it small and explicit - one responsibility):
##   READY_TO_LAUNCH : a ball sits in the lane, plunger armed. -> on_ball_launched -> LAUNCHING.
##   LAUNCHING       : the player released the plunger; the ball is leaving the lane but has NOT yet
##                     been confirmed to have reached play. A positional watchdog (fed measured ball
##                     Z by table.gd via tick_launch_watch) decides:
##                       - the ball crossed into play (up-table of LAUNCH_REACHED_PLAY_Z)
##                         -> notify_ball_reached_play -> BALL_IN_PLAY (normal play);
##                       - the settle timer expired and the ball is STILL in the lane (a too-weak
##                         launch / a stall) -> on_launch_failed -> RE-ARM the SAME ball, do NOT
##                         spend a ball, back to READY_TO_LAUNCH. This is the SOFT-LOCK FIX: a weak
##                         launch is always recoverable, never a dead state.
##   BALL_IN_PLAY    : ball is live; targets score. -> on_ball_drained -> spend a ball.
##   (spend a ball) : balls_left -= 1; if > 0 -> request_new_ball -> READY_TO_LAUNCH;
##     else GAME_OVER.
##   GAME_OVER       : show final score; "launch"/restart action resets to READY_TO_LAUNCH ball 3.
##
## WHY THE LAUNCHING STATE (SLICE "Playtest fixes 2", soft-lock fix, ARCHITECTURE.md 12): the old
## machine went straight READY_TO_LAUNCH -> BALL_IN_PLAY on ball_launched and disarmed the plunger.
## A ball that never reached play and never drained left the machine stuck in BALL_IN_PLAY forever
## with a dead plunger - the reported soft-lock. The LAUNCHING state is the "in flight, not yet
## confirmed" gap where the watchdog can recover a failed launch WITHOUT spending a ball. A ball
## genuinely reaches play promotes to BALL_IN_PLAY and the drain/spend path is UNCHANGED.
##
## DESIGN scope: score from 0, +points per target, 3 balls, drain decrements + re-arms, game over at
## 0 shows final score + restart. No ball-save, multipliers, combos, persistence (DESIGN cut list).
## The failed-launch recovery is NOT a ball-save: it only recovers a ball that NEVER reached play.
##
## STABLE CONTRACT (table.gd / HUD / tests depend on these):
##   signal score_changed(score: int)
##   signal balls_changed(balls: int)
##   signal message(text: String)
##   signal game_over(final_score: int)
##   signal request_new_ball()        # ask table.gd to reset the ball + arm the plunger (new ball).
##   signal request_relaunch()        # SOFT-LOCK FIX: re-seat the ball + re-arm the plunger for the
##                                     # SAME ball (no ball spent). table.gd wires this to the same
##                                     # reset+arm path as request_new_ball; the difference is just
##                                     # that no balls_changed fired (no ball was spent).
##   func start_game() -> void
##   func on_target_scored(points: int) -> void
##   func on_ball_launched() -> void
##   func on_ball_drained() -> void
##   func restart() -> void
##   func current_state() -> int      # one of the State enum values (for tests/diagnostics).
##   func tick_launch_watch(ball_local_z: float, delta: float) -> void
##       # SOFT-LOCK FIX: table.gd calls this each physics frame with the ball's MEASURED playfield-
##       # local Z (independent oracle - the real ball position, never a self-reported flag) and the
##       # frame delta. Only acts in LAUNCHING. Promotes to BALL_IN_PLAY when the ball crosses
##       # LAUNCH_REACHED_PLAY_Z; recovers (request_relaunch) when LAUNCH_SETTLE_TIME_S elapses with
##       # the ball still in the lane. A no-op in every other state.

signal score_changed(score: int)
signal balls_changed(balls: int)
signal message(text: String)
signal game_over(final_score: int)
signal request_new_ball()
signal request_relaunch()

enum State { READY_TO_LAUNCH, LAUNCHING, BALL_IN_PLAY, GAME_OVER }

const STARTING_BALLS: int = 3

var _state: int = State.READY_TO_LAUNCH
var _score: int = 0
var _balls: int = STARTING_BALLS
## SOFT-LOCK FIX: seconds since on_ball_launched while in LAUNCHING. tick_launch_watch advances it;
## when it passes TableConfig.LAUNCH_SETTLE_TIME_S with the ball still in the lane, the launch is
## judged FAILED and the ball is recovered (re-armed for the same ball, no ball spent).
var _launch_watch_elapsed: float = 0.0

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

## The plunger launched the ball: move from READY_TO_LAUNCH to LAUNCHING and start the soft-lock
## watchdog. We do NOT go straight to BALL_IN_PLAY any more (that is the soft-lock fix): the ball is
## "in flight, not yet confirmed in play" until the watchdog (tick_launch_watch) sees it cross into
## play. The prompt clears here because the player has committed the launch. STABLE SIGNATURE.
func on_ball_launched() -> void:
	# Ignore if we somehow receive this in the wrong state (defensive guard).
	if _state != State.READY_TO_LAUNCH:
		return
	_state = State.LAUNCHING
	# Reset the watchdog timer so each launch is judged from its own start.
	_launch_watch_elapsed = 0.0
	# Clear the launch prompt so HUD message area is clean during/after the launch.
	message.emit("")


## SOFT-LOCK FIX: the positional watchdog, driven each physics frame by table.gd with the ball's
## MEASURED playfield-local Z (independent oracle) and the frame delta. Only acts while LAUNCHING.
##
## Two branches:
##   1. REACHED PLAY: if ball_local_z < TableConfig.LAUNCH_REACHED_PLAY_Z (the ball crossed the
##      flipper-pivot row up-table, so it is unambiguously in play) -> notify_ball_reached_play()
##      promotes to BALL_IN_PLAY and returns. No further timer work needed.
##   2. FAILED LAUNCH: ball is still down-table in the lane. Advance the settle timer; once it
##      exceeds LAUNCH_SETTLE_TIME_S without the ball reaching play, the launch is judged FAILED
##      and on_launch_failed() recovers: re-arms the plunger for the SAME ball, no ball spent.
## A no-op in every state other than LAUNCHING. Judges ONLY the passed-in measured Z.
## STABLE SIGNATURE.
func tick_launch_watch(ball_local_z: float, delta: float) -> void:
	if _state != State.LAUNCHING:
		return
	# Branch 1: the ball reached play (crossed up-table of the reached-play line).
	if ball_local_z < TableConfig.LAUNCH_REACHED_PLAY_Z:
		notify_ball_reached_play()
		return
	# Branch 2: still in the lane - tick the settle timer; recover once it expires.
	_launch_watch_elapsed += delta
	if _launch_watch_elapsed >= TableConfig.LAUNCH_SETTLE_TIME_S:
		on_launch_failed()


## SOFT-LOCK FIX: the launch succeeded (the ball crossed into play). Promote to BALL_IN_PLAY
## so the normal drain/spend path takes over. Idempotent guard: only acts from LAUNCHING.
## STABLE SIGNATURE.
func notify_ball_reached_play() -> void:
	if _state != State.LAUNCHING:
		return
	_state = State.BALL_IN_PLAY


## SOFT-LOCK FIX: the launch FAILED (the ball never reached play within the settle window). Recover:
## return to READY_TO_LAUNCH and request a RELAUNCH (re-seat the ball at the cradle + re-arm the
## plunger) for the SAME ball. CRITICAL: do NOT decrement the ball count - a weak launch must not
## cost the player a ball. Only acts from LAUNCHING. STABLE SIGNATURE.
func on_launch_failed() -> void:
	if _state != State.LAUNCHING:
		return
	_state = State.READY_TO_LAUNCH
	# Re-issue the launch prompt so the player knows they can pull again (also satisfies UX item 5:
	# the prompt re-appears on this re-arm, not only on a brand-new ball).
	message.emit("HOLD LAUNCH - release to fire")
	# Ask table.gd to re-seat the ball at the cradle and re-arm the plunger. NO balls_changed emitted
	# (no ball spent) - that is the whole point of recovering a launch that never reached play.
	request_relaunch.emit()

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
		# UX item 5 (SLICE "Playtest fixes 2"): re-issue the launch prompt on EVERY ball arm, not just
		# ball 1. Before this, ball 1 got the prompt (from start_game) but balls 2 and 3 only saw "BALL
		# DRAINED" and no instruction, so a player could be left not knowing how to launch the next
		# ball. We show the drain notice AND the launch prompt: a two-line message keeps the loss
		# legible (DESIGN "LEGIBLE DRAIN") while telling the player what to do next.
		message.emit("BALL DRAINED\nHOLD LAUNCH - release to fire")
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
