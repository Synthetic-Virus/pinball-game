# QA Backlog (independent)
Owner: gamedev-qa-lead. QA is an INDEPENDENT team. It is never blocked waiting for a coding handoff.
It pulls work from this backlog and runs in parallel with development. Tests EXECUTE headless on the
homelab runner via CI (the laptop has no Godot); CI results are the source of truth. Three streams:

## Stream 1 - Test debt (automated GUT tests to write, often BEFORE the code exists)
- [x] Physics: the ball never tunnels through a wall across many high-speed collisions.
      Written: tests/test_ball_tunneling.gd. FAILS until physics-programmer sets
      continuous_cd = true in ball.gd _ready(). That is the correct pre-impl state.
- [x] Scoring: hitting a target adds exactly the expected points.
      Written: tests/test_game_flow.gd (test_target_scores_only_in_play,
      test_multiple_target_hits_accumulate). FAILS until gameplay-programmer fills
      game_flow.gd on_target_scored(). Correct pre-impl state.
- [x] Drain: losing the ball decrements ball count; the game ends at zero balls.
      Written: tests/test_game_flow.gd (test_drain_decrements_balls_and_requests_new_ball,
      test_game_over_at_zero_balls, test_no_new_ball_request_at_game_over). FAILS until
      gameplay-programmer fills on_ball_drained(). Correct pre-impl state.

## Stream 2 - Bug repros (found defects, reproduced and logged)

---

### BUG-001 [CRITICAL] Right flipper bat extends in the wrong direction - inverted-V impossible

Severity: CRITICAL - the right flipper cannot catch or strike the ball; the core loop is broken.

Suspected files/lines:
- /home/virus/pinball-game/scripts/flipper.gd lines 127-132 (_build_flipper, shape offset)
- /home/virus/pinball-game/scripts/flipper.gd lines 167-190 (_apply_handedness)

Repro (trace):
1. table.gd places left flipper at local position (-FLIPPER_PIVOT_SPREAD, 0, FLIPPER_PIVOT_Z) = (-5, 0, 20)
   and right flipper at (+5, 0, 20), calling configure("right_flipper", mirrored=true).
2. _apply_handedness() sets rest_angle = FLIPPER_REST_ANGLE * -1 = +0.55 for the right flipper.
3. _body.transform = Transform3D(Basis(Vector3(0,1,0), +0.55), Vector3.ZERO).
   Using right-hand Y-rotation: bat local +X maps to world direction (cos(0.55), 0, -sin(0.55)) = (0.853, 0, -0.523).
4. The CollisionShape3D offset is always shape.position = Vector3(FLIPPER_LENGTH * 0.5, 0.0, 0.0)
   (line 131). This is in body-local space along +X regardless of mirror state.
5. Right flipper tip world position: pivot(+5,0,20) + FLIPPER_LENGTH*(0.853, 0, -0.523)
   = (+10.97, 0, +16.34). The tip is 10.97 units to the RIGHT (outside the playfield near
   HALF_WIDTH=12) and 3.66 units toward the ARCH (wrong side of pivot).

Expected: right flipper tip at approximately (-0.97, 0, 23.66) -- the mirror of the left tip,
pointing toward center from the right side and toward the drain.

Actual: right flipper tip at (+10.97, 0, 16.34) -- pointing away from center and toward the arch.
The bat is on the arch side of the pivot, not the drain side. It cannot intercept a ball falling
toward the drain from the upper playfield.

Root cause: The mirroring logic inverts the hinge angle sign but does NOT invert the bat's
extension direction. The shape is always offset at +X from the body origin. For the right flipper
the bat arm must extend in the -X direction (world), which requires either:
  (a) Placing the shape at (-FLIPPER_LENGTH * 0.5, 0, 0) when _mirrored == true, AND
      rotating the mesh instance to match, OR
  (b) Having table.gd rotate the right Flipper node 180 degrees about Y before calling configure().

The test test_flippers_do_not_overlap_at_pivots in tests/test_world_scale.gd WILL FAIL on this
geometry: gap = 2*FLIPPER_PIVOT_SPREAD - 2*FLIPPER_LENGTH*cos(|REST_ANGLE|) = 10 - 11.935 = -1.935 < 0.

Suggested GUT test to lock the fix:
  Assert that after configure("right_flipper", true), the right flipper bat tip world X is
  less than 0 (left of center) and world Z is greater than FLIPPER_PIVOT_Z (drain side).
  Specifically: tip_x < 0.0 and tip_z > TableConfig.FLIPPER_PIVOT_Z.

---

### BUG-002 [CRITICAL] Game-over screen is a permanent soft-lock - restart action is never wired

Severity: CRITICAL - the game cannot be replayed; player is permanently stuck on game-over screen.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table.gd lines 85-86 (_wire_signals is pass/TODO)
- /home/virus/pinball-game/scripts/hud.gd (no _input or _unhandled_input handler)
- /home/virus/pinball-game/scripts/game_flow.gd line 99 (restart() exists but is never called)

Repro:
1. Run the game. Drain all 3 balls.
2. GameFlow transitions to GAME_OVER state. HUD shows "press LAUNCH to restart".
3. Press Space (the "launch" action). Nothing happens.
4. Press any other key. Nothing happens.
5. The game-over panel stays visible permanently. The game cannot be restarted.

Expected: pressing the "launch" action in GAME_OVER state calls GameFlow.restart(), which calls
start_game(), resets score/balls to 0/3, emits request_new_ball, and returns to READY_TO_LAUNCH.
HUD hides the game-over panel (hide_game_over()) and resets score and ball display.

Actual: GameFlow.restart() is never triggered. No code polls the "launch" action in GAME_OVER state.
table.gd._wire_signals() is a stub (pass). hud.gd has no input handling.

Additional issue: hide_game_over() on hud.gd is never called anywhere in any connected path.
Even if restart() is triggered, the panel will remain visible.

Suggested GUT test to lock the fix:
  test_game_flow.gd already covers restart() logic. Add an integration test: confirm that
  after GameFlow.game_over fires, calling GameFlow.restart() emits score_changed(0),
  balls_changed(3), and request_new_ball; and that hud.hide_game_over() is called.

---

### BUG-003 [CRITICAL] Entire table scene is empty at runtime - all _build_* methods are stubs

Severity: CRITICAL - the playable game does not exist; nothing renders or simulates.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table.gd lines 69-86 (_build_static_geometry, _build_dynamic_elements,
  _build_flow_and_hud, _wire_signals are all pass/TODO)
- /home/virus/pinball-game/scripts/table_geometry.gd line 16 (build() is pass/TODO)

Repro:
1. Run scenes/Table.tscn.
2. Table._ready() executes: _build_playfield() creates a tilted Node3D named "Playfield".
3. _build_static_geometry() -> pass. No surface, no walls, no arch, no lane divider created.
4. _build_dynamic_elements() -> pass. No Ball, no Flippers, no Plunger, no Targets, no Drain.
5. _build_flow_and_hud() -> pass. game_flow is null, hud is null.
6. _wire_signals() -> pass. No signals connected.
7. if game_flow != null: is false, start_game() never called.
8. Scene loads as a single tilted empty Node3D. No interaction is possible.

Expected: a playable gray-box pinball table with ball, two flippers, plunger, targets, drain, HUD,
and wired signals as documented in table.gd header.

Actual: blank tilted Node3D. This is the expected state for this task (lead-programmer TODO), but
it is the root blocker for all integration testing. Noted here so the QA backlog reflects it.

Note for test-builder: this defect means all physics and gameplay integration tests that require
a running scene will produce no output. Unit tests on isolated scripts (game_flow.gd, plunger.gd,
drain.gd, target.gd) are still valid and should be the current test focus.

---

### BUG-004 [HIGH] Drain trigger is behind the playfield bottom edge - perimeter wall will block it

Severity: HIGH - when walls are built, the drain will be permanently unreachable; balls accumulate
in play with no drain, no ball count decrement, no game-over condition. Soft-lock on first ball.

Suspected files/lines:
- /home/virus/pinball-game/scripts/config/table_config.gd line 72:
  const DRAIN_Z: float = HALF_LENGTH + 2.0
- /home/virus/pinball-game/scripts/table_geometry.gd (TODO - will build perimeter walls)
- /home/virus/pinball-game/scripts/drain.gd line 47 (positions drain at DRAIN_Z)

Repro:
1. Evaluate DRAIN_Z = HALF_LENGTH + 2.0 = 25.0 + 2.0 = 27.0 (world units past playfield bottom).
2. The playfield bottom edge is at local Z = HALF_LENGTH = 25.0.
3. If table_geometry._build_perimeter_walls() builds a continuous bottom wall at Z = 25.0,
   the drain Area3D at Z = 27.0 is positioned BEHIND that wall.
4. A ball draining past the flippers hits the bottom wall at Z = 25.0 and stops there.
   It never enters the drain Area3D at Z = 27.0. ball_drained never fires.
5. GameFlow stays in BALL_IN_PLAY permanently. The ball sits against the bottom wall.

Expected: the drain trigger is positioned so a ball rolling past the flipper gap enters it
without obstruction. The DESIGN mandates an OPEN center drain (no bottom wall blocking the gap).

Actual (latent): DRAIN_Z is past the playfield boundary. If the bottom perimeter wall is built
without an explicit gap, the drain is unreachable. This is a design-time latent defect that becomes
a runtime bug the moment table_geometry is implemented naively.

Note: the drain.gd comment "just past the flipper pivots" is also inaccurate - DRAIN_Z is 7 units
past the flipper pivot row (20.0) and 2 units past the playfield bottom (25.0).

Suggested fix contract for lead-programmer: table_geometry._build_perimeter_walls() MUST NOT build
a wall segment at the bottom center (the drain gap). Only build left and right gutter walls that
terminate at or above Z = FLIPPER_PIVOT_Z. Alternatively, lower DRAIN_Z to HALF_LENGTH - 1.0 so
it is inside the playfield below the flipper pivot.

Suggested GUT test to lock the fix:
  Assert DRAIN_Z < HALF_LENGTH (drain is inside playfield bounds, no perimeter wall blocks it),
  OR confirm the perimeter wall geometry has a gap >= DRAIN_WIDTH at z = DRAIN_Z.

---

### BUG-005 [HIGH] Ball has no playfield surface to rest on - falls into void immediately

Severity: HIGH - when dynamic elements are built (table.gd TODO), the ball will fall through the
scene immediately after creation because no static surface exists.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table_geometry.gd line 16 (TableGeometry.build() is pass/TODO)
- /home/virus/pinball-game/scripts/ball.gd line 97 (reset_to_start calls reset_to(BALL_START))

Repro:
1. table.gd _build_static_geometry() calls TableGeometry.build(playfield) which is pass/TODO.
2. No StaticBody3D surface exists on the PLAYFIELD layer.
3. Ball is instantiated and placed at BALL_START = (10.0, BALL_RADIUS+0.2, 23.0) = (10, 0.8, 23).
4. Ball has mass=0.6, gravity_scale=1.0. Gravity = 200 downward.
5. The ball is parented under the tilted Playfield (7 deg tilt). Gravity pulls it down and
   along the table toward the drain. No surface exists to support it.
6. Ball accelerates freely, exits the scene volume, and never reaches the drain.
7. GameFlow stays in BALL_IN_PLAY. Game hangs.

Expected: the ball rests at BALL_START on the playfield surface (BALL_RADIUS above the surface).

Actual (latent): ball falls into the void. Blocked by BUG-003 (table is entirely empty), so
currently moot, but will manifest the moment table_geometry is partially implemented without the
surface builder.

Suggested GUT test to lock the fix:
  Once table_geometry is implemented, assert the ball's Y position remains >= BALL_RADIUS
  after 60 physics frames with zero initial velocity (ball rests on surface, does not fall).

---

### BUG-006 [HIGH] Ball can exit the playfield sideways causing an unresolvable stuck-ball state

Severity: HIGH - when the table has partial or missing walls, the ball can leave the playfield
laterally; the drain never fires; GameFlow hangs in BALL_IN_PLAY indefinitely.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table_geometry.gd (TODO - side walls not built yet)
- /home/virus/pinball-game/scripts/drain.gd lines 27 (DRAIN_WIDTH covers only table width,
  not sideways escapes)

Repro:
1. Ball receives a lateral velocity (e.g. after bouncing off a target at angle, or a glancing
   flipper hit) that exceeds TableConfig.HALF_WIDTH = 12.0 in the X direction.
2. Side perimeter walls are missing (table_geometry is TODO) or have a gap.
3. Ball exits the playfield laterally. Its Z never reaches DRAIN_Z = 27.0.
4. The drain Area3D at z=27 never fires body_entered.
5. GameFlow.on_ball_drained() is never called. State stays BALL_IN_PLAY.
6. The game is hung. The ball is gone. No balls, no drain, no game over.

Expected: perimeter side walls prevent lateral exit; the ball must drain through the flipper gap.

Actual (latent): perimeter walls are a TODO. Any non-zero lateral impulse risks a sideways escape.

Mitigation needed: a failsafe drain that triggers if the ball falls more than N units below the
table surface (Y < -some_threshold) in world space, regardless of X/Z position. This acts as a
safety net for any ball that leaves the play volume by any path.

Suggested GUT test to lock the fix:
  Assert that after N physics frames with any starting velocity, ball position.x remains within
  [-HALF_WIDTH, HALF_WIDTH] (side walls hold). Also assert: a ball at (20, 0, 23) with velocity
  (100, 0, 0) is brought back within bounds within 10 frames (wall collision).

---

### BUG-007 [MEDIUM] Target velocity override cancels incoming ball momentum - score exploit possible between two aligned targets

Severity: MEDIUM - ball speed is non-conserved at targets; a fast shot is slowed to 25 u/s which
violates "REAL MOMENTUM" feel expectations. Also enables a theoretical infinite-score loop.

Suspected files/lines:
- /home/virus/pinball-game/scripts/target.gd line 93:
  _ball.linear_velocity = kick_dir * KICK_SPEED
  (sets velocity, does not add to or preserve incoming speed)

Repro A (momentum loss):
1. Ball is launched at LAUNCH_SPEED_MAX = 90 u/s and strikes a target.
2. target.gd sets _ball.linear_velocity = kick_dir * 25.0.
3. The ball's speed drops from ~90 u/s to 25 u/s instantly. Energy is not conserved.
4. DESIGN requirement "REAL MOMENTUM" states different ball speeds produce visibly different
   results. A fast shot into a target produces the SAME exit speed as a slow shot.

Repro B (score loop, theoretical):
1. Two targets are placed at positions A and B such that the kick direction from A points toward B
   and vice versa (e.g. A at (0, 0, -5), B at (0, 0, -15), each kicking straight up/down table).
2. Ball enters target A: scored, kicked toward B at 25 u/s.
3. Ball enters target B: scored, kicked toward A at 25 u/s.
4. If KICK_SPEED exceeds the gravity deceleration over the distance, the ball oscillates and
   scores repeatedly. KICK_SPEED = 25 u/s, gravity along table ~ 24.4 u/s^2; this is a near-miss.
5. Whether this loops depends on exact target placement; it is table.gd's responsibility to
   avoid this layout, but there is no code-level guard.

Expected: target kick preserves or adds to incoming ball speed proportionally, or adds a capped
velocity component rather than overriding the full linear_velocity.

Suggested GUT test:
  Fire the ball at LAUNCH_SPEED_MAX into a target. Assert ball speed after kick is >= KICK_SPEED
  (speed not below the kick value) OR that speed is within a reasonable range of the incoming speed.

---

### BUG-008 [MEDIUM] Auto-launch-on-drain: holding the launch key through a drain fires ball at minimal power

Severity: MEDIUM - player holding Space during a drain event gets a nearly-zero-power auto-launch
on the very next physics frame, bypassing the intentional plunger skill mechanic.

Suspected files/lines:
- /home/virus/pinball-game/scripts/plunger.gd lines 70-92 (_physics_process)
- /home/virus/pinball-game/scripts/plunger.gd lines 89-91 (launch triggered on holding -> releasing transition)

Repro:
1. Ball is in play. Player holds the Space key (launch action) - this has no effect during
   BALL_IN_PLAY (plunger is disarmed).
2. Ball drains. GameFlow transitions to READY_TO_LAUNCH and emits request_new_ball.
3. table.gd handles request_new_ball: calls ball.reset_to_start() and plunger.arm().
4. plunger._armed becomes true.
5. SAME OR NEXT physics frame: plunger._physics_process runs. holding = true (Space still held).
   _charging = true, _charge_phase increments by delta * 2.5 (tiny value, ~0.004).
   _power = pingpong(0.004, 1.0) ~= 0.004. power_changed emitted.
6. Player releases Space. _charging is true, holding is false: _do_launch() fires.
7. speed = lerpf(30, 90, 0.004) ~= 30.2 u/s. Ball launches at barely-above-minimum power.
8. The player did not intend to launch; the ball was fired without deliberate aiming.

Expected: the plunger arm() should reset to a state where the player must make a new press-and-hold
gesture to charge. If the launch key was already held when arm() fires, the plunger should not
start charging until the key is released and re-pressed.

Suggested fix: record whether the key was held at arm() time; require a full release + re-press
before charging begins.

Suggested GUT test:
  Simulate: arm plunger while "launch" action is already pressed. Verify that _launched_count == 0
  until the action is released and re-pressed.

---

### BUG-009 [MEDIUM] test_ball_stays_in_front_of_wall_after_bounce uses too strict a threshold - will produce false failures

Severity: MEDIUM (test quality) - a spurious test failure will block CI and waste investigation
time; the underlying game may be correct while the test reports a failure.

Suspected files/lines:
- /home/virus/pinball-game/tests/test_ball_tunneling.gd lines 146-162

Repro:
1. test_ball_stays_in_front_of_wall_after_bounce fires ball at 180 u/s toward wall at z=0.
2. After 60 physics frames (0.25s) asserts ball.position.z <= WALL_Z (= 0.0).
3. With BALL_BOUNCE = 0.15, ball bounces back at ~27 u/s. After 0.25s the ball should be well
   behind the wall. So the test should pass in practice.
4. BUT: if any floating-point penetration leaves the ball center at z = 0.001 to 0.3 (inside
   the wall thickness, between front face at 0 and back face at 0.8), the test fails with:
   "Ball should be at or in front of wall after bounce. ball.z=0.05"
5. This is a false failure: the ball bounced, CCD is working, but microscopic solver penetration
   trips the exact threshold.

Expected: the bounce test uses a small positive epsilon (e.g. BALL_RADIUS * 0.5 = 0.3) as the
pass threshold, consistent with the tunneling test's tunnel_threshold.

Actual: the threshold is exactly WALL_Z = 0.0 with no tolerance.

Suggested fix:
  Change assertion to: ball.position.z <= WALL_Z + TableConfig.BALL_RADIUS * 0.5

---

### BUG-010 [LOW] tip_speed() uses angular_velocity.length() instead of hinge-axis projection - inflates reading if body picks up spurious off-axis spin

Severity: LOW - tip_speed() may read slightly higher than the true hinge rotation speed; the
momentum test (full > tap) still passes because both measurements are equally inflated. Could
cause a false pass if the bat has large off-axis angular velocity rather than true hinge rotation.

Suspected files/lines:
- /home/virus/pinball-game/scripts/flipper.gd lines 271-274 (tip_speed)

Repro:
1. Flipper body receives an off-axis angular velocity (e.g. from a Jolt constraint impulse
   or a ball strike that imparts torque on the X or Z axis of the hinge).
2. _body.angular_velocity.length() includes all three components of angular velocity.
3. The true hinge rotation speed is only the Y component (hinge axis).
4. tip_speed() returns a value larger than the actual tip sweep speed.
5. A test asserting tip_speed() > some_threshold could pass even if the flipper is barely
   rotating about the hinge but is spinning about another axis.

Expected: tip_speed = |angular_velocity.dot(hinge_axis_world)| * FLIPPER_LENGTH
(project angular velocity onto the hinge axis before computing magnitude).

Suggested GUT test:
  Force-energize a flipper. After SNAP_FRAMES, assert that _body.angular_velocity.dot(hinge_axis)
  accounts for > 90% of _body.angular_velocity.length() (hinge is dominant rotation axis).

---

### BUG-011 [LOW] test_restart_resets_score_and_balls has a silent ignored on_ball_launched() call making setup fragile

Severity: LOW (test quality) - the test produces the correct outcome via a coincidental path,
but the setup intention differs from what executes. If game_flow state logic changes, the test
may silently stop covering the intended scenario.

Suspected files/lines:
- /home/virus/pinball-game/tests/test_game_flow.gd lines 186-199

Repro:
1. Test calls: start_game(), on_ball_launched(), on_target_scored(500).
   State is now BALL_IN_PLAY, score=500.
2. Loop (3 iterations): on_ball_launched() + on_ball_drained().
   - Iteration 1: on_ball_launched() is called while in BALL_IN_PLAY -> silently IGNORED.
     on_ball_drained() -> READY_TO_LAUNCH (balls=2).
   - Iteration 2: on_ball_launched() -> BALL_IN_PLAY. on_ball_drained() -> READY_TO_LAUNCH (balls=1).
   - Iteration 3: on_ball_launched() -> BALL_IN_PLAY. on_ball_drained() -> GAME_OVER (balls=0).
3. restart() is called. Test passes.

The intent appears to be: drain all 3 balls (one per loop iteration). But iteration 1's
on_ball_launched() is a no-op. The first drain actually happens from the pre-loop launch.
The test passes for the right reason (3 drains -> GAME_OVER -> restart) but via an unintended path.

Suggested fix: remove the pre-loop on_ball_launched() + on_target_scored() and instead score
during the loop, or restructure so each iteration explicitly launches then drains.

---

## Stream 3 - Regression sweeps (re-verify after changes)
(none yet)

## How QA stays unblocked (the independence rule in practice)
When there is no new code to test, QA does NOT idle. It (a) writes tests against agreed function
signatures and contracts before the code exists, (b) hardens existing coverage and adds edge cases,
and (c) audits DESIGN.md and the code for testability gaps. There is always test-debt to pull.
