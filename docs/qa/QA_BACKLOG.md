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

### BUG-012 [HIGH] test_plunger.gd simulates at 120 Hz but the game runs at 240 Hz - power curve timing is wrong in tests

Severity: HIGH (test quality / latent gameplay bug) - the plunger test drives `_physics_process`
manually at FRAME_DELTA = 1/120 s, but project.godot sets physics_ticks_per_second = 240. The
in-game oscillation timing is therefore TWICE as fast as the test assumes. A player who expects
a 0.8 s sweep (from the comment "CHARGE_RATE 2.5 -> 0.8 s") actually gets a 0.8 s sweep, because
the real game calls _physics_process 240 times per second with delta = 1/240. BUT the test uses
delta = 1/120, meaning one simulated second is achieved in half as many test "frames". The
test_higher_power_maps_to_higher_speed test drives 4 frames for "low power" and 48 frames for
"high power" using delta=1/120. In the real game at 240 Hz, those same durations are 0.033 s and
0.4 s (same wall-clock time). This is actually consistent because the test is using real time
(frame_count * delta), not frame count. The issue is subtler: test comments say "48 frames at 120
Hz" but the game runs at 240 Hz, so any test that reasons about FRAME COUNTS (not time) will be
wrong.

Specifically: the frame-count reasoning in test comments ("48 frames = 0.4 s -> phase 1.0") is
correct for the test's own manually-driven 120 Hz loop but WRONG for reasoning about the live game.
If a future test asserts a specific frame count from a CI-run scene (not manually driven), it will
be off by a factor of 2x.

Suspected files/lines:
- /home/virus/pinball-game/tests/test_plunger.gd line 39:
  const FRAME_DELTA: float = 1.0 / 120.0

Repro:
1. Read test_plunger.gd FRAME_DELTA = 1.0 / 120.0.
2. Read project.godot: common/physics_ticks_per_second = 240.
3. The test uses half the project tick rate when driving _physics_process manually.
4. test_higher_power_maps_to_higher_speed: "4 frames * (1/120) = 0.033 s" and "48 frames *
   (1/120) = 0.4 s". The wall-clock math is correct. But the frame-count-based comment in
   test_meter_oscillates_between_zero_and_one says "160 frames (~1.33 s)" - at 120 Hz that is
   1.33 s. In the real 240 Hz game, 1.33 s = 320 frames. This mismatch means the test is not
   a faithful simulation of the real game's frame budget.
5. Any future physics integration test that imports the 120 Hz FRAME_DELTA constant (or its
   reasoning) for a scene-based test will produce timing assertions off by 2x.

Expected: FRAME_DELTA should match the real game's tick: 1.0 / 240.0. Frame-count comments
should reflect the 240 Hz baseline so the test is a faithful simulation and future tests can
copy the constant without surprise.

Suggested fix:
  const FRAME_DELTA: float = 1.0 / 240.0
  Update all frame-count comments accordingly (160 frames at 120 Hz -> 320 frames at 240 Hz,
  but wall-clock durations are the same so test_higher_power_maps_to_higher_speed logic is unaffected
  once FRAME_DELTA is corrected - just recalculate frame counts to keep same durations).

Suggested GUT test to lock the fix:
  Add a constant consistency check: assert FRAME_DELTA == 1.0 /
  ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 240).

---

### BUG-013 [HIGH] The flipper return-spring displacement is measured relative to THIS NODE's +X but the rest angle is in the HINGE frame - coordinate mismatch may cause wrong spring direction

Severity: HIGH - the return spring may push the bat in the wrong direction (toward the up-stop
instead of back to rest), causing the bat to be energized when it should relax, and introducing
a jitter or self-oscillation when the flip action is released.

Suspected files/lines:
- /home/virus/pinball-game/scripts/flipper.gd lines 231-235 (_physics_process return spring block)
- /home/virus/pinball-game/scripts/flipper.gd lines 248-254 (_current_hinge_angle)

Repro (trace):
1. When the flip action is released, _physics_process enters the spring branch.
2. current_angle = _current_hinge_angle(axis_world).
3. _current_hinge_angle computes: ref_dir = global_transform.basis * Vector3.RIGHT (the Flipper
   NODE's local +X in world). bat_dir = _body.global_transform.basis * Vector3.RIGHT (the bat
   body's local +X in world).
4. signed_angle_to(bat_dir, axis_world) returns the angle from the Flipper node's +X to the
   bat body's +X about the hinge axis.
5. At rest angle _rest_angle = -0.55, the bat was placed by:
   _body.transform = Transform3D(Basis(_HINGE_AXIS_LOCAL, _rest_angle), Vector3.ZERO)
   So the bat's +X is rotated _rest_angle radians from the Flipper node's +X.
   Therefore current_angle at rest = _rest_angle. displacement = _rest_angle - _rest_angle = 0.
   Spring torque = 0. Correct.
6. When the player holds the flipper to up_angle (-0.15 for the left flipper, but wait:
   LEFT: _rest_angle = -0.55, _up_angle = 0.15. hand_sign = +1. drive_dir = signf(0.15 - (-0.55)) = +1.
   When released mid-swing (current_angle > _rest_angle, say 0.0), displacement = 0.0 - (-0.55) = +0.55.
   Spring torque = -RETURN_SPRING_STIFFNESS * 0.55 = -660 Nm. This is NEGATIVE (clockwise / down).
   axis_world for the left flipper (on tilted playfield, Y pointing up from surface) is a world vector.
   apply_torque(axis_world * (-660)) drives the bat back toward negative angles (toward _rest_angle).
   This IS the correct direction. The math appears consistent for the left flipper.

7. For the RIGHT flipper: _rest_angle = +0.55, _up_angle = -0.15. When released at mid-swing
   (current_angle < _rest_angle, say 0.0), displacement = 0.0 - 0.55 = -0.55.
   Spring torque = -RETURN_SPRING_STIFFNESS * (-0.55) = +660 Nm.
   apply_torque(axis_world * 660) drives the bat toward more positive angles (back toward +0.55 rest).
   This is also correct.

HOWEVER: the hinge's angular_limit/lower and angular_limit/upper are set to
  lower = min(_rest_angle, _up_angle), upper = max(_rest_angle, _up_angle).
For the LEFT flipper: lower = min(-0.55, 0.15) = -0.55, upper = max(-0.55, 0.15) = 0.15.
For the RIGHT flipper: lower = min(0.55, -0.15) = -0.15, upper = max(0.55, -0.15) = 0.55.

The hinge limit is set in the JOINT's local frame. Since the joint's Z axis is the hinge axis
(per the comment "local Z == hinge axis == surface normal"), the HingeJoint3D angular limits
refer to rotation about the joint's Z axis. But _current_hinge_angle measures rotation of the
BAT's body about axis_world (the playfield surface normal in world space). If the joint's local
Z and axis_world are not the same direction (sign), the limit signs are inverted relative to the
spring-angle convention, and the bat hits the WRONG stop as its hard limit.

Specifically: the joint transform is:
  Transform3D(
    Vector3(1,0,0),    # joint local X = world X
    Vector3(0,0,-1),   # joint local Y = world -Z
    Vector3(0,1,0),    # joint local Z = world Y (the surface normal)
    Vector3.ZERO
  )
The joint's local Z = world Y = playfield surface normal = axis_world. Signs match. So the
limits ARE in the same direction as the angle convention. The spring math is consistent.

REVISED VERDICT: the spring direction logic is geometrically consistent. The suspected mismatch
does not manifest if the joint Z is confirmed to point the same direction as axis_world (both
are +Y local of the Flipper parent node). This bug is marked PROBABLE CONCERN but not confirmed
as a definite defect; it requires a CI physics run to observe the bat's actual at-rest position.

The key TESTABLE question is: after releasing the flipper and waiting SNAP_FRAMES, does
current_hinge_angle(axis_world) converge to _rest_angle (within epsilon), or overshoot to the
wrong stop? If the bat ends up at _up_angle instead of _rest_angle, the spring direction is wrong.

Suggested GUT test to confirm or close:
  After a full swing (force_energized(true) for SNAP_FRAMES), call clear_force_energized(), wait
  SNAP_FRAMES, then assert abs(_flipper._current_hinge_angle(axis_world) - _flipper._rest_angle)
  < 0.1 rad (bat returned to rest, not stuck at up-stop). This is a regression-lock test for
  the spring direction regardless of the analysis above.

---

### BUG-014 [HIGH] Lane divider bottom edge terminates exactly at DRAIN_Z creating a ball-trap corner

Severity: HIGH - a ball rolling slowly along the right gutter (between the right wall and the lane
divider) can become trapped in the corner where the lane divider's bottom end meets the drain volume,
bouncing between the divider end and the drain trigger without draining or being playable.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table_geometry.gd lines 122-128 (_build_lane_divider)
- /home/virus/pinball-game/scripts/config/table_config.gd line 86:
  const DRAIN_Z: float = HALF_LENGTH - 1.0  (= 24.0)

Repro (trace):
1. _build_lane_divider sets bottom_z = hl - 1.0 = 24.0.
2. TableConfig.DRAIN_Z = HALF_LENGTH - 1.0 = 24.0.
3. The lane divider's bottom face is at Z = 24.0. The drain trigger volume CENTER is at Z = 24.0
   with DRAIN_DEPTH = 6.0, spanning Z = 21.0 to Z = 27.0. So the drain trigger starts at Z = 21.
4. The lane divider occupies LANE_INNER_X = 8.0 in X, from Z = top_z to Z = 24.0. It has
   WALL_THICKNESS = 0.8, so its right face is at X = 8.0 + 0.4 = 8.4 and its left face at X = 7.6.
5. A ball rolling down the right gutter (X near 10.0, between X=8.0 and X=12.0) at slow speed
   reaches the lane divider bottom at Z = 24.0. The drain width is DRAIN_WIDTH = HALF_WIDTH * 2 = 24
   (the full table width), so it catches the ball anywhere in X.
6. At slow ball speeds (~0 u/s along Z) the ball enters the drain normally. This is the INTENDED
   path.
7. EDGE CASE: a ball rolling along the inside face of the lane divider (X near 8.0) at moderate
   speed reaches Z = 24.0, the divider ends, and the ball deflects around the corner of the
   divider end. The sharp right-angle corner of the box geometry can trap a slow ball in a narrow
   corridor between the divider end-face and the drain trigger. The ball may oscillate without
   quite having enough velocity to clear the corner and reach the open drain mouth.
8. If the drain trigger fires here, the ball drains correctly. If the corner geometry deflects the
   ball back up before the drain triggers (ball never enters the volume at rest), the ball is stuck.

Severity rationale: a ball trapped in the gutter-corner is a soft-lock (game stuck in BALL_IN_PLAY
if it is not moving enough to trigger the drain volume). The OOB failsafe at Y = -20.0 would not
help since the ball is on the playfield surface. If this corner-trap occurs before the drain Z, the
game can only be rescued by tilting (nudge), which may or may not dislodge it given the geometry.

Suggested fix contract: extend the lane divider's bottom edge 1-2 units PAST the drain center
(bottom_z = hl + 1.0) or taper the bottom corner with an angled face. Alternatively, move the
lane divider terminus to Z = FLIPPER_PIVOT_Z so the ball exits the lane mouth above the flippers
rather than beside the drain trigger.

Suggested GUT test to lock the fix:
  In a scene-level integration test, give a ball zero velocity at position (LANE_INNER_X, BALL_RADIUS,
  DRAIN_Z - 0.5). After 60 frames, assert either: ball position.z >= DRAIN_Z (it drained normally)
  or ball current_speed() > 0 (it was not trapped at rest). A trapped ball at rest at this position
  is the failure condition.

---

### BUG-015 [MEDIUM] The OOB failsafe drain fires for the wrong body type if a future non-ball physics body enters its volume

Severity: MEDIUM - the OOB catch-plane (`oob_drain`) is a plain Area3D with no `set_ball` guard,
wired to `_on_oob_body_entered` which only filters for `body == ball`. This is correct for single-
ball play. However, the flipper body (RigidBody3D on KINEMATIC_OBSTACLES layer) is NOT in the OOB
drain's mask (mask = PhysicsLayers.BALLS = 8). So flippers cannot trigger it. This is safe.

BUT: if a future implementation adds a physics-based debris object or a multiball ball on the BALLS
layer without calling `table.gd`'s set_ball equivalent, the OOB drain would SILENTLY IGNORE that
ball (body != ball is true, so the drain fires nothing). The result is the same stuck-in-BALL_IN_PLAY
soft-lock that BUG-006 describes.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table.gd lines 222-226 (_on_oob_body_entered)

Repro:
1. A future multiball implementation adds a second Ball instance to the playfield without calling
   oob_drain.set_ball (because oob_drain is a plain Area3D with no set_ball method).
2. The second ball escapes through the table geometry.
3. oob_drain.body_entered fires with the escaped ball as `body`.
4. _on_oob_body_entered checks `body != ball` - this is TRUE (it is the second ball, not the
   tracked first ball). The condition returns early.
5. game_flow.on_ball_drained() is never called for the escaped ball. Soft-lock.

Severity rationale: non-blocking for the single-ball slice (this slice is explicitly single-ball),
but is a latent multiball trap. Noted here so the multiball implementation knows to extend the
failsafe or add per-ball drain tracking.

Suggested fix for the multiball extension:
  Replace the `body != ball` identity check with a layer-based check:
  `if not (body is RigidBody3D and (body.collision_layer & PhysicsLayers.BALLS) != 0): return`
  This drains ANY ball-layer body that falls out of bounds, regardless of which ball object it is.

Suggested GUT test:
  When multiball is implemented, assert that if a second ball (on BALLS layer) exits the playfield
  (Y < OOB_DRAIN_Y), a ball_drained event fires (even if it is not the "primary" tracked ball).

---

### BUG-016 [MEDIUM] The test_full_swing_outthrows_a_tap momentum ratio is satisfiable if tap_speed is near zero, masking a broken flipper

Severity: MEDIUM (test quality / correctness gap) - the tap trial may return near-zero ball speed
(the ball slips off the bat tip without meaningful contact), making the 1.5x ratio gate trivially
satisfiable. The min_meaningful_speed guard is applied only to the FULL SWING speed, not the tap.

Suspected files/lines:
- /home/virus/pinball-game/tests/test_flipper_momentum.gd lines 193-225 (test_full_swing_outthrows_a_tap)

Repro (trace):
1. Trial A (tap): TAP_FRAMES = 1 frame of solenoid drive. The bat barely twitches; if the ball
   is seated at the up-stop (seat_angle near _up_angle, ~0.85 of the arc), the 1-frame drive
   may not reach the ball before the spring pulls the bat back. tap_speed could be 0.0.
2. Trial B (full swing): SNAP_FRAMES = 20 frames of drive. The bat sweeps to the up-stop and
   strikes the ball. swing_speed should be significant.
3. Assert: swing_speed >= MOMENTUM_RATIO_FLOOR * tap_speed = 1.5 * 0.0 = 0.0.
4. Any positive swing_speed satisfies this. The test passes even if the tap was a complete miss.
5. The min_meaningful_speed guard checks: swing_speed > LAUNCH_SPEED_MIN / 5.0 = 6.0. This
   catches a missing FULL SWING but does not catch a missing tap.
6. A broken flipper that does nothing on a tap but does strike the ball on a full swing would
   pass both guards, reporting a "correct" momentum ratio despite the tap being a miss.

Expected behavior: the test should also assert that tap_speed > some_minimum (the tap actually
struck the ball, not that it missed). This ensures the RATIO is measured between two real contact
events, not between a real strike and a missed contact.

Suggested fix:
  After tap_speed = await _run_swing_trial(TAP_FRAMES), add:
  assert_gt(tap_speed, 0.1, "Tap trial must actually strike the ball (tap_speed > 0.1); "
    "if this fails, the ball seat is too far from the bat tip to be reached in one frame")
  This minimum is intentionally low (the tap should be a real but weak hit). Adjust the seat
  angle in _seat_ball_in_swing_path if needed so a one-frame drive reliably reaches it.

---

### BUG-017 [LOW] The flipper bat is placed on KINEMATIC_OBSTACLES layer but its collision_mask only checks BALLS - flipper-vs-wall collisions are silently skipped

Severity: LOW - flippers cannot collide with the arch or perimeter walls. In normal play this is
by design: the hinge joint constrains the bat, and the hinge limits stop it before it reaches a
wall. But if the physics solver's hinge limits slip (Jolt constraint solver tolerance) or the
solenoid drive overshoots under high load, the bat tip could penetrate a wall without a collision
response. No bounce-back occurs; the bat clips through.

Suspected files/lines:
- /home/virus/pinball-game/scripts/config/physics_layers.gd line 28:
  const KINEMATIC_COLLISION_MASK: int = BALLS
- /home/virus/pinball-game/scripts/flipper.gd line 116:
  _body.collision_mask = PhysicsLayers.KINEMATIC_COLLISION_MASK

Repro:
1. KINEMATIC_COLLISION_MASK = BALLS (bit 8 only).
2. The flipper bat's collision_mask = 8.
3. The perimeter walls are on STATIC_OBSTACLES (bit 2).
4. Ball mask (BALL_COLLISION_MASK) includes KINEMATIC_OBSTACLES (bit 4). Ball detects flippers.
5. Flipper mask (KINEMATIC_COLLISION_MASK = BALLS, bit 8). Flipper ONLY detects balls.
6. Flipper body cannot register a collision with a wall (bit 2 not in its mask).
7. If the hinge limit fails to stop the bat at the up-stop (constraint slip), the tip passes
   through the arch or perimeter wall. No collision force is applied to the wall; the bat
   passes through without a physics response.

Severity rationale: the hinge angular limits are the primary stop. Adding wall-collision to the
flipper mask would cause redundant collision pairs (flipper-vs-wall) every frame, adding solver
cost. The design choice (hinge-limit only) is intentional and documented. Flagged here as a LOW
severity known limitation so the physics-programmer is aware that the hinge limits are the single
failure point for bat-over-extension.

Suggested monitoring: in the integration stress test, assert that after 100 full-swing cycles
the bat tip position remains within the table bounds (tip X within [-HALF_WIDTH, HALF_WIDTH]).

---

### BUG-018 [LOW] The HUD score label "BALLS" can display negative values if on_ball_drained fires twice for the same ball

Severity: LOW - if two drain signals fire for the same lost ball (e.g. ball passes through both
the center drain and the OOB failsafe in the same frame), GameFlow.on_ball_drained() is called
twice. The second call passes the BALL_IN_PLAY guard only if the state has not yet transitioned.
Since state transitions happen synchronously inside on_ball_drained, the second call arrives when
state is READY_TO_LAUNCH (or GAME_OVER), and the guard returns early. This IS safe as written.

HOWEVER, there is a race if signals are processed in a different order. In Godot 4, signal
connections fire in connection order (first-connected first). Both drain.ball_drained and
oob_drain.body_entered are wired in _wire_signals. If they somehow both fire in the same physics
frame (e.g. ball enters both volumes simultaneously), they are dispatched in connection order:
drain.ball_drained -> game_flow.on_ball_drained (state goes READY_TO_LAUNCH or GAME_OVER).
Then oob_drain.body_entered -> _on_oob_body_entered -> game_flow.on_ball_drained, which is
guarded (state != BALL_IN_PLAY) and returns. So double-spend is prevented.

The actual risk is a deferred-signal scenario: if one signal fires in one physics frame and the
other fires in the next (before the ball is reset), both could pass the guard. This depends on
exact ball trajectory. The OOB drain at Y = -20 is far enough from the center drain (Z = 24)
that simultaneous triggering is geometrically implausible unless the ball is falling diagonally.
This bug is THEORETICAL but the design is correct for the single-ball case.

Suggested GUT test to prove the guard holds:
  Call game_flow.on_ball_drained() twice in the same frame while in BALL_IN_PLAY. Assert that
  balls_changed fires only once and the final ball count is (starting - 1), not (starting - 2).
  This test locks the guard against regression.

---

## Stream 3 - Regression sweeps (re-verify after changes)

### SWEEP 2026-06-18 - integrated slice review (qa-lead). CI run 27794688808 GREEN on the runner.
Independent-oracle verified from the runner log (not the summary line): Godot 4.6.3 + Jolt,
test_ball_tunneling 3/3 (incl. test_full_speed_ball_never_tunnels_a_wall), test_flipper_momentum
7/7 (incl. test_full_swing_outthrows_a_tap + test_flipper_reaches_full_swing_quickly, NO
pending/risky), Totals "All tests passed!". BOTH producer-blocking CI gates are now green.

Status of the BUG-001..011 backlog after the integration/polish pass (re-read of shipping code):
- BUG-001 (right flipper mirror): FIXED in flipper.gd _apply_handedness (bat offset sign flips with
  hand_sign). Spread 5->7 in table_config.gd leaves a positive drain mouth. CLOSED.
  -> test debt: test_flipper_no_overlap.gd still owed to lock it (see Stream 1).
- BUG-002 (game-over soft-lock): FIXED. table.gd _physics_process polls just_pressed "launch" in
  GAME_OVER -> restart(); _on_request_new_ball calls hud.hide_game_over(). CLOSED.
- BUG-003 (empty table): FIXED. table.gd builds surface/walls/arch/lane + ball/flippers/plunger/
  targets/drain/oob and wires every signal. CLOSED.
- BUG-004 (drain behind bottom wall): FIXED. DRAIN_Z = HALF_LENGTH-1.0 (inside field); geometry
  leaves bottom OPEN. CLOSED.
- BUG-005 (no surface): FIXED. TableGeometry._build_surface builds PLAYFIELD-layer surface, top at Y=0.
- BUG-006 (sideways escape): MITIGATED. Full-length side+top walls; OOB failsafe Area3D at Y=-20
  routes to on_ball_drained. CLOSED as designed.
- BUG-007 (target momentum/score-farm): FIXED. target.gd preserves incoming speed + adds KICK_SPEED,
  RETRIGGER_COOLDOWN_S 0.20 dead time. CLOSED. -> test debt: test_target_no_double_score.gd owed.
- BUG-008 (auto-launch on held key): FIXED. plunger.gd _release_seen latch. CLOSED.
- BUG-009 (bounce test strict threshold): NOT YET RELAXED. test_ball_tunneling.gd line 155 still
  asserts `position.z <= WALL_Z` (no epsilon). It is GREEN today, but it is a latent flaky gate.
  Non-blocking (deferred to Stream 1); see findings NB-1.
- BUG-010 (tip_speed off-axis): FIXED. tip_speed() projects angular_velocity onto hinge axis. CLOSED.
- BUG-011 (restart test coincidental path): test quality, non-blocking. Still owed.

## Stream 1 additions (test debt owed, NON-blocking for this slice - deferred by producer ruling)
- [ ] test_flipper_no_overlap.gd - assert right-flipper tip_x < 0 and tip_z > FLIPPER_PIVOT_Z after
      configure("right_flipper", true); locks BUG-001. (test-builder)
- [ ] test_target_no_double_score.gd - a single dwell on a target scores once within the cooldown;
      locks BUG-007. (test-builder)
- [ ] test_table_integration.gd - boot Table.tscn headless; assert ball rests on surface (BUG-005),
      a full-power launch never leaves [-HALF_WIDTH, HALF_WIDTH] (BUG-006), drain fires -> ball
      decrements, restart hides the game-over panel (BUG-002). (test-builder)
- [ ] Relax test_ball_tunneling bounce threshold to WALL_Z + BALL_RADIUS*0.5 (BUG-009). (test-builder)
- [ ] Restructure test_restart_resets_score_and_balls so each loop iteration launches then drains
      (BUG-011). (test-builder)

## How QA stays unblocked (the independence rule in practice)
When there is no new code to test, QA does NOT idle. It (a) writes tests against agreed function
signatures and contracts before the code exists, (b) hardens existing coverage and adds edge cases,
and (c) audits DESIGN.md and the code for testability gaps. There is always test-debt to pull.
