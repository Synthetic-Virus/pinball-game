# QA Backlog (independent)
Owner: gamedev-qa-lead. QA is an INDEPENDENT team. It is never blocked waiting for a coding handoff.
It pulls work from this backlog and runs in parallel with development. Tests EXECUTE headless on the
homelab runner via CI (the laptop has no Godot); CI results are the source of truth. Three streams:

## Stream 1 - Test debt (automated GUT tests to write, often BEFORE the code exists)
- [x] SLICE/real-pinball-furniture: six GUT test files written and pushed (CI run 27850857532,
      sha a25a6f4, 119/120 passing). Files:
      tests/test_pop_bumper.gd (structural + behavioral: slow ball leaves fast, outward, capped,
        scores once, cooldown bounds farming),
      tests/test_slingshot.gd (structural + behavioral: both sides kick up-table + toward center,
        min outgoing speed, scores once),
      tests/test_active_kicker_no_tunneling.gd (stress: 60-iteration loop at 2x LAUNCH_SPEED_MAX
        against REAL PopBumper.tscn and Slingshot.tscn; position oracle + cap check),
      tests/test_flipper_rubber.gd (structural: bat PhysicsMaterial bounce > 0.25; behavioral:
        ball rebounds off resting bat face, momentum preserved >= 35%, no trampoline < 115%),
      tests/test_furniture_layout.gd (integration: REAL Table.tscn instances bumpers/slings/
        standup-bank/lane-guides on correct layers and in correct regions),
      tests/test_shot_geometry.gd (CAD geometry: standup bank in makeable window, bumpers clear
        of walls, sling kicks never at drain, kick bounds inside CCD-safe band).
      GUT addon confirmed installed: addons/gut present (vendored v9.4.0).
      REMAINING RED: test_rubber_rebound_preserves_momentum - fails because BAT_BOUNCE=0.45 at
      the glancing test geometry achieves only 24.8% rebound vs the 35% floor. Blocked on
      physics-programmer raising BAT_BOUNCE or confirming the geometry angle. All other behavioral
      and stress tests for active kickers are RED by design until physics fills _build_body() and
      _apply_kick() with the solid body and capped impulse. Structural and geometry tests are GREEN.
- [x] Physics: the ball never tunnels through a wall across many high-speed collisions.
      Written: tests/test_ball_tunneling.gd. FAILS until physics-programmer sets
      continuous_cd = true in ball.gd _ready(). That is the correct pre-impl state.
- [x] SLICE/physical-launch: lane pocket stops ball without closing center drain.
      Written: tests/test_lane_pocket_drain.gd (branch: slice/core-interactions-physics).
      Structural: LanePocket on STATIC_OBSTACLES, -X face does not reach center drain region.
      Behavioral: resting ball stays in lane; center-X ball reaches real Drain.ball_drained.
      FAILS until physics-programmer builds TableGeometry._build_lane_pocket and adds
      TableConfig.LANE_POCKET_FACE_Z. Correct pre-impl state.
- [x] SLICE/physical-launch: plunger strike physically imparts velocity (no ball.launch() call).
      Written: tests/test_plunger_launch.gd (branch: slice/core-interactions-physics, adopted
      from prototype/physical-plunger). Structural: PlungerFace on KINEMATIC_OBSTACLES,
      contract (power_changed/ball_launched/arm/disarm/set_ball/is_armed/test_strike_at_power).
      Behavioral: strike imparts speed, full >= 1.5x weak, speed in LAUNCH_SPEED_MIN..MAX.
      Stress: 20 iterations at full power - ball never tunnels lane pocket (position oracle).
      FAILS until physics-programmer implements the AnimatableBody3D face + stroke machine.
- [x] SLICE/physical-targets: target has solid deflector, bounces ball, scores on contact.
      Written: tests/test_target_physical.gd (branch: slice/core-interactions-physics).
      Structural: Deflector child on STATIC_OBSTACLES, Area3D monitors BALLS, contract intact.
      Behavioral: direction reversal, >= 40% momentum kept, ball never passes post far face,
      scored fires exactly once per hit, cooldown bounds farming to <= 5 emits in 120 frames.
      FAILS until gameplay-programmer deletes the velocity kick + physics-programmer adds
      the StaticBody3D Deflector child with near-elastic PhysicsMaterial.
- [x] SLICE/physical-targets: no tunneling through the target deflector (stress gate).
      Written: tests/test_target_no_tunneling.gd (branch: slice/core-interactions-physics).
      100-iteration stress loop at 2x LAUNCH_SPEED_MAX. Position oracle: ball never ends up
      past POST_RADIUS + BALL_RADIUS*0.5 on the far side of the deflector cylinder. Bonus
      test confirms POST_RADIUS constant matches the actual CylinderShape3D radius.
      FAILS until the Deflector body exists in target.gd.
- [x] Scoring: hitting a target adds exactly the expected points.
      Written: tests/test_game_flow.gd (test_target_scores_only_in_play,
      test_multiple_target_hits_accumulate). FAILS until gameplay-programmer fills
      game_flow.gd on_target_scored(). Correct pre-impl state.
- [x] Drain: losing the ball decrements ball count; the game ends at zero balls.
      Written: tests/test_game_flow.gd (test_drain_decrements_balls_and_requests_new_ball,
      test_game_over_at_zero_balls, test_no_new_ball_request_at_game_over). FAILS until
      gameplay-programmer fills on_ball_drained(). Correct pre-impl state.
- [ ] TEST DEBT (locks BUG-023): drain trigger volume must not overlap the flipper-bat catch zone.
      TWO assertions: (1) a CONFIG/structural assert DRAIN_Z - DRAIN_DEPTH/2 > max flipper-bat z
      (the drain's up-table edge clears the bat sweep) - the cheap machine-check the existing
      center-only assert is missing; (2) a BEHAVIORAL integration test that seats the REAL Ball
      cradled on a REAL flipper (left, then right) held energized, watches Drain.ball_drained for
      the full settle, asserts ZERO emissions (independent oracle). Goes in test_world_scale.gd +
      test_table_integration.gd. Write it RED now (the current geometry overlaps), green after fix.
      Owner: gamedev-test-builder + gamedev-qa-lead.

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

Suggested GUT test to lock the fix (NOTE: see BUG-016 for why tip_x < 0 is the wrong predicate):
  Assert that after configure("right_flipper", true), the right flipper bat tip world X is
  LESS than FLIPPER_PIVOT_SPREAD (tip is left of the right pivot, pointing toward center),
  and world Z is greater than FLIPPER_PIVOT_Z (drain side). Also assert the gap between
  the two tips = 2*pivot_spread - 2*reach > BALL_RADIUS*2 (drain mouth is wider than the ball).

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

### BUG-012 [BLOCKING] Lane pocket is NOT built - the whole "ball rests in the lane" mechanic is missing

Severity: BLOCKING - one of the three slice conversions does not exist in production. Slice review.

Slice: core-interactions-physics. Found by QA review 2026-06-19 on branch slice/core-interactions-physics.

Files:
- /home/virus/pinball-game/scripts/table_geometry.gd lines 22-27 (build() does NOT call _build_lane_pocket)
- /home/virus/pinball-game/scripts/table_geometry.gd (no _build_lane_pocket method exists at all)

Evidence:
1. TableConfig has LANE_POCKET_FACE_Z / LANE_POCKET_THICKNESS (table_config.gd 107-108) and a
   BALL_START tuned to rest against the pocket, but NO body is ever created from them.
2. TableGeometry.build() calls _build_surface / _build_perimeter_walls / _build_lane_divider /
   _build_arch only. There is no _build_lane_pocket method and no call to one.
3. The prototype/physical-plunger branch DOES have _build_lane_pocket and calls it in build()
   (verified: git show prototype/physical-plunger:scripts/table_geometry.gd). The BACKLOG LEAD task
   said to ADOPT it; the geometry half of the adoption was dropped during integration onto the slice.

Consequence: the ball placed at BALL_START rolls down the tilted lane and falls off the open bottom
edge (the exact bug the slice exists to fix). The launch mechanic cannot work because there is no
resting ball to strike. This also re-opens the pre-existing "ball falls out the lane" report.

CI status: NOT green. test_lane_pocket_drain.gd::test_lane_pocket_body_exists_on_static_layer asserts
find_child("LanePocket") is not null and WILL FAIL; the two behavioral rest tests WILL FAIL. The tests
are correct and already RED against the missing code. This bug is the reason the suite cannot be green.

Fix: adopt _build_lane_pocket from the prototype branch into the slice table_geometry.gd and add the
call in build(). It must span ONLY x in [LANE_INNER_X, HALF_WIDTH] (the structural test in
test_lane_pocket_drain.gd asserts the -X face does not cross into the center drain region).

---

### BUG-013 [BLOCKING] Plunger node is double-offset by table.gd - the face lands off the table, never strikes the ball

Severity: BLOCKING - the physical plunger strike (the slice headline) cannot fire in the real game.

Slice: core-interactions-physics. Found by QA review 2026-06-19.

Files:
- /home/virus/pinball-game/scripts/table.gd line 237 (plunger.position = TableConfig.BALL_START)
- /home/virus/pinball-game/scripts/plunger.gd lines 127-129 (face seated at PLUNGER_REST_POS,
  contract comment: "table.gd parents this Plunger node at the playfield origin (position ZERO)")

Evidence (the two files disagree on the contract):
1. plunger.gd seats its face at the playfield-LOCAL coordinate PLUNGER_REST_POS = (10, 0.8, 24.0) and
   documents that this works ONLY because the Plunger node sits at the playfield origin (0,0,0).
2. table.gd instead sets plunger.position = BALL_START = (10, 0.8, 23.0).
3. The face's effective playfield position is therefore BALL_START + PLUNGER_REST_POS =
   (20, 1.6, 47.0): x=20 is past the right wall (HALF_WIDTH=12) and z=47 is 22 units past the open
   bottom edge (HALF_LENGTH=25). The face is nowhere near the ball; the strike does nothing.
4. The plunger TESTS pass because test_plunger_launch.gd before_each sets _plunger.position =
   Vector3.ZERO (the contract the script expects). The tests honor the contract; table.gd violates it,
   and NO test exercises the table.gd wiring, so this integration bug is invisible to CI.

Fix: set plunger.position = Vector3.ZERO in table.gd._build_dynamic_elements (the plunger seats its
own face at PLUNGER_REST_POS). Then ADD an integration test that instances the full Table.tscn and
asserts the PlungerFace world/playfield position is in the launch lane next to BALL_START (this is the
missing coverage that let the bug through - see BUG-014).

---

### BUG-014 [HIGH] No integration test exercises table.gd wiring for the slice mechanics (coverage gap)

Severity: HIGH (test debt) - every slice unit test bypasses table.gd, so table.gd integration bugs
(BUG-012 pocket-not-wired-up reachable only via build(), BUG-013 plunger double-offset) sail through
green unit suites. This is the gap that made two BLOCKING defects invisible to CI.

Files:
- /home/virus/pinball-game/tests/test_plunger_launch.gd (builds plunger at Vector3.ZERO, not via table.gd)
- /home/virus/pinball-game/tests/test_target_physical.gd (instances Target.tscn directly)
- /home/virus/pinball-game/tests/test_scene_structure.gd (instances Table.tscn but only checks
  camera/light/mesh, never the plunger position, the lane pocket, or a target body)

Direction to test-builder: add test_table_integration.gd that instances res://scenes/Table.tscn,
waits for _ready, and asserts on the REAL built tree (independent oracle, measured positions):
  1. find_child("LanePocket", true, false) exists under the Playfield (catches BUG-012 end to end).
  2. the PlungerFace playfield-space position is within the launch lane (x in [LANE_INNER_X, HALF_WIDTH],
     z near BALL_START.z), i.e. in light contact with the resting ball (catches BUG-013).
  3. after SETTLE_FRAMES the real Ball rests in the lane (position.z < LANE_POCKET_FACE_Z + radius) -
     the full integrated rest behavior, not the isolated-geometry version.
This belongs in Stream 1 (test debt) and should be written even though it currently fails: it is the
correct pre-fix state and locks BUG-012 and BUG-013 closed.

---

### BUG-015 [BLOCKING] test_plunger.gd: four tests assert ball.launch() is called - that API is deleted in the physical plunger

Severity: BLOCKING (CI) - four tests in the existing test suite will FAIL against the slice's new
plunger.gd because they assert a contract (plunger calls ball.launch()) that was intentionally
removed. They will report failures that look like physics bugs but are stale test logic. This blocks
CI green on the slice branch.

Files:
- /home/virus/pinball-game/tests/test_plunger.gd lines 17-25 (FakeBall stub records launch() calls)
- /home/virus/pinball-game/tests/test_plunger.gd line 132 (assert_eq(fake_ball.launch_call_count, 1))
- /home/virus/pinball-game/tests/test_plunger.gd lines 139-160 (last_launch_speed comparisons)
- /home/virus/pinball-game/tests/test_plunger.gd lines 165-176 (last_launch_direction comparison)
- /home/virus/pinball-game/scripts/plunger.gd lines 208-242 (_do_launch now starts the AnimatableBody3D
  stroke; never calls _ball.launch())

Repro (trace):
1. The old plunger.gd called _ball.launch(direction, speed) in _do_launch(). The FakeBall in
   test_plunger.gd was designed to intercept that call and record the speed + direction.
2. The slice replaced _do_launch() with a physical stroke machine: it sets _stroke_state = FORWARD
   and drives the AnimatableBody3D face. The ball is struck by a physics contact, not a velocity set.
3. The new _do_launch() never calls _ball.launch(). fake_ball.launch_call_count stays 0.
4. Four tests fail:
   - test_release_launches_and_disarms (line 123): asserts launch_call_count == 1, gets 0.
   - test_release_speed_within_bounds (line 134): reads fake_ball.last_launch_speed = 0.0, not in range.
   - test_higher_power_maps_to_higher_speed (line 145): both low_speed and high_speed are 0.0 (equal).
   - test_launch_direction_is_up_table (line 165): reads fake_ball.last_launch_direction = Vector3.ZERO.
5. The other five tests in test_plunger.gd (charge oscillation, meter reset, disarm) do NOT depend
   on ball.launch() and will continue to pass.

Root cause: the slice changed the plunger's internal contract from "set velocity via ball.launch()"
to "strike via AnimatableBody3D contact" without updating the four tests that depended on the old
contract. The four tests are testing a deliberately deleted implementation.

Fix direction: rewrite the four failing tests to verify the new physical contract using
test_strike_at_power() (the test hook already on plunger.gd at line 285) and measure the REAL
ball's current_speed() after physics settle. This mirrors what test_plunger_launch.gd already does
(the correct model for behavioral tests on the physical plunger). Options:
  (a) Convert the four tests in test_plunger.gd to use a real Ball.tscn + test_strike_at_power +
      wait_physics_frames, matching test_plunger_launch.gd's pattern. Remove FakeBall entirely since
      the class is now testing a deleted API.
  (b) Mark the four tests pending() with the reason "tests the deleted ball.launch() API; being
      replaced by test_plunger_launch.gd" to stop the CI failure immediately, then rewrite properly.
  Do NOT remove the five tests that still pass (they correctly verify the charge/oscillation/disarm
  contract, which is unchanged).

Suggested replacement assertion for test_release_launches_and_disarms (the most important one):
  After arm() + hold frames + release: assert is_armed() == false AND _launched_count == 1
  (ball_launched signal fired). The ball.launch() call count is no longer the right oracle;
  the signal and armed state are. These already pass.

---

### BUG-016 [MEDIUM] BUG-001 suggested test predicate tip_x < 0 is wrong - rejects a geometrically correct right flipper

Severity: MEDIUM (test guidance error) - the suggested GUT test in BUG-001 will FAIL against the
CORRECT fixed geometry. If written as described it creates a false-failing test and misleads the
team into thinking the flipper is still broken when it is actually correct.

Files:
- /home/virus/pinball-game/docs/qa/QA_BACKLOG.md BUG-001 "Suggested GUT test" paragraph (now corrected above)
- /home/virus/pinball-game/scripts/flipper.gd lines 183-188 (_apply_handedness, the fix)
- /home/virus/pinball-game/tests/test_world_scale.gd (test_flippers_do_not_overlap_at_pivots exists
  and does correctly verify the gap, but only by arithmetic on config values, not live flipper geometry)

Evidence (arithmetic):
1. With the fix applied: bat_offset_x = FLIPPER_LENGTH * 0.5 * hand_sign = -3.5 for the right flipper.
2. Right pivot at x=+7.0. Right flipper rest_angle = +0.55 rad.
   Body +X in world = (cos(0.55), 0, -sin(0.55)) = (0.853, 0, -0.523).
   Bat tip world offset from pivot = (-FLIPPER_LENGTH) * body_x = (-5.967, 0, 3.659).
   Bat tip world x = 7.0 + (-5.967) = +1.033.
3. tip_x = +1.033 > 0 -- BUG-001's predicate "tip_x < 0" FAILS on the correct geometry.
4. The geometry IS correct: the tip is between the pivot (+7) and center (0), pointing toward
   center as required for an inverted V. Gap between tips = 2.06 units > ball diameter 1.2 units.

Correct predicate for a GUT test that locks the BUG-001 fix:
  right tip x < FLIPPER_PIVOT_SPREAD (to the left of the right pivot)
  AND right tip x > -HALF_WIDTH (hasn't gone past the left wall)
  AND right tip z > FLIPPER_PIVOT_Z (drain side of the pivot)
  AND gap between left tip x and right tip x > BALL_RADIUS * 2.0 (drain mouth is open)

The existing test_flippers_do_not_overlap_at_pivots in tests/test_world_scale.gd covers the gap
condition by pure arithmetic; it will pass with the corrected geometry. A live-flipper geometry
test using the above predicates is additional hardening that can go in test_table_integration.gd
(see BUG-014 direction).

---

### BUG-017 [LOW] ball.gd retains launch() as dead code - stale STABLE CONTRACT comment misleads future coders

Severity: LOW (code clarity, future mis-use risk) - the launch() method is documented as
"The plunger calls this on release" and labelled STABLE CONTRACT, but the physical plunger slice
deleted that call. A future coder reading the contract may call ball.launch() to "launch" the ball,
re-introducing the fake non-physics velocity set that the slice deliberately removed.

Files:
- /home/virus/pinball-game/scripts/ball.gd lines 113-125 (launch() doc comment and implementation)
- /home/virus/pinball-game/scripts/plunger.gd lines 40-41 (contract comment "The plunger calls this")

Evidence:
1. ball.gd line 113 comment: "Impart a launch velocity... The plunger calls this on release."
   This was true before the slice. After the slice, _do_launch() in plunger.gd never calls _ball.launch().
2. plunger.gd contract block still lists "func set_ball(ball: RigidBody3D) -> void" with the note
   "The plunger calls this on release" (paraphrased from the original header for the old contract).
3. FakeBall in test_plunger.gd has a launch() intercept stub that is now dead (BUG-015).
4. A grep for _ball.launch() or ball.launch() across all scripts (excluding comments and tests)
   returns zero production callers. The method is orphaned in production.

Fix: update ball.gd launch() doc comment to state it is NOT called by the physical plunger and is
retained as a utility/test helper (or for future multiball use). Update plunger.gd contract header
to remove the stale reference. Optionally, the "STABLE CONTRACT" label on launch() should be
demoted - it is now an internal utility, not a cross-system integration point.
This is a documentation fix only; do not remove launch() without checking for any non-obvious
callers (e.g. test helpers that may exercise it for other purposes).

---

### BUG-018 [HIGH] Slingshot axis-aligned detector does not cover the rotated solid body corners - active kick silently skips corner contacts

RESOLVED 2026-06-19 (lead polish): added a _detector_yaw() hook in active_kicker.gd (defaults to
_body_yaw()) and rotated the detector CollisionShape3D by it, so the slingshot detector now rotates
WITH the solid body and stays concentric. The slingshot detector box is also padded by one
BALL_RADIUS on BOTH the thin AND the long axis so a corner contact trips body_entered before the ball
reaches the solid. Regression test added: tests/test_slingshot.gd
test_sling_corner_contact_still_kicks_and_scores (fires at the up-table corner, asserts scored once
AND current_speed() >= KICK_MIN_OUTGOING_SPEED). Pop bumper is unaffected (round, _body_yaw 0).

Severity: HIGH - a ball striking a slingshot at its up-table or down-table corners makes a physical
contact with the KickerBody (STATIC_OBSTACLES, CCD applies) but the Area3D detector does NOT fire
body_entered for that contact. The coded active kick is therefore not applied. The ball gets only
the passive PhysicsMaterial bounce (0.5 restitution) instead of the coded KICK_IMPULSE_SPEED (55
u/s) directed into play. This is exactly the "limp bounce" failure mode the active-kick design was
built to avoid (REFERENCES.md prior art).

Severity rationale: HIGH because the outlane scenario (a ball falling from above the slingshot
and grazing its upper corner) is the EXACT USE CASE the slingshot exists to handle ("saved by the
slings"). The corner gap is 0.82 units - larger than the BALL_RADIUS (0.6), so the ball center
can be inside the KickerBody corner zone without the detector shell having fired.

Suspected files/lines:
- /home/virus/pinball-game/scripts/slingshot.gd lines 68-73 (_make_detector_shape)
- /home/virus/pinball-game/scripts/active_kicker.gd lines 218-235 (_build_detector_and_mesh,
  which adds the detector CollisionShape3D with no rotation applied)

Root cause (geometry trace):
1. Slingshot KickerBody is a BoxShape3D of size (SLINGSHOT_LENGTH=5.0, height, SLINGSHOT_THICKNESS=0.8).
2. The body is ROTATED by _body_yaw() = atan2(kick_dir.x, -kick_dir.z) about Y.
   For the left sling: yaw = atan2(0.6, 0.8) = 36.87 degrees.
3. After rotation the solid body's corners in world-XZ extend to Z +/-1.82 (from the origin).
4. The Area3D detector shape (_make_detector_shape) returns a BoxShape3D of size
   (SLINGSHOT_LENGTH=5.0, height, SLINGSHOT_THICKNESS + BALL_RADIUS*2 = 0.8+1.2 = 2.0).
5. The detector shape is added to the Area3D with NO rotation (active_kicker._build_detector_and_mesh
   does not apply _body_yaw to the detector CollisionShape3D).
6. The axis-aligned detector extends only Z +/-1.0, but the solid body corners are at Z +/-1.82.
7. The corner overhang beyond the detector = 1.82 - 1.00 = 0.82 units, larger than BALL_RADIUS.
8. A ball can physically contact the KickerBody corner WITHOUT having entered the detector volume.
   body_entered never fires for that contact. _on_body_entered never runs. _apply_kick is not called.

Repro:
1. Launch the ball from a slingshot test scene. Position the ball at the sling center plus
   the up-table corner offset: e.g. left sling at world origin, ball at (-2.24, 0, -1.82)
   (the corner of the solid body), velocity pointing toward +X and +Z (into the corner).
2. Observe: the ball bounces off the KickerBody (physical contact).
3. Observe: ball.current_speed() after the bounce is NOT >= KICK_MIN_OUTGOING_SPEED (40 u/s)
   unless the incoming speed was already high.
4. watch_signals on the slingshot: scored signal count = 0 (kick never fired, so score never
   emitted). This is zero even though a physical contact happened.

Expected: any contact with the KickerBody solid surface fires the active kick and scores.
Actual: corner contacts that miss the axis-aligned detector get passive bounce only, no kick, no score.

Suggested fix: rotate the detector CollisionShape3D by the same _body_yaw() as the solid body
so the detector and the solid body are co-oriented and the detector fully covers the solid surface.
In _build_detector_and_mesh (or in the subclass's _make_detector_shape), apply the yaw to the
CollisionShape3D node's rotation, not just the shape's size. Alternatively, expand the detector
size so even axis-aligned it fully contains the rotated solid body's bounding box (detector Z
half-size needs to be >= 1.82 + BALL_RADIUS = 2.42, i.e. detector Z size >= 4.84, not 2.0).

Suggested GUT test to lock the fix:
  In test_slingshot.gd, add a test that fires the ball at the UP-TABLE CORNER of the sling
  (ball start at the +corner_z position, velocity pointing into the corner), waits APPROACH_FRAMES,
  and asserts (a) scored signal fired at least once and (b) ball.current_speed() >=
  KICK_MIN_OUTGOING_SPEED after the contact. This is the corner-miss repro, and it must pass.

---

### BUG-019 [MEDIUM] test_rubber_rebound_preserves_momentum fires at the END face of the bat, not the long face - explains the known 24.8% rebound vs the 35% floor

RESOLVED 2026-06-19 (lead polish, also clears B1 / the red CI gate): fixed the TEST geometry in
tests/test_flipper_rubber.gd _fire_at_face to fire HEAD-ON along the bat's long-face normal (computed
from FLIPPER_REST_ANGLE), not straight +Z into the angled end. BAT_BOUNCE was NOT changed (raising it
to paper over a glancing hit would have made a real glancing rebound a trampoline). The rebound-
direction assert in test_ball_rebounds_off_resting_flipper_face now checks the dot with the face
normal (geometry-correct for the angled bat) instead of a bare vz < 0. Head-on at BAT_BOUNCE 0.45
retains ~45% > the 35% floor and < the 115% ceiling.

Severity: MEDIUM (test quality + blocks CI green) - the known-failing test (Stream 1 "REMAINING RED")
fires at the wrong surface. The 35% floor failure is not a physics-engine shortfall or a BAT_BOUNCE
tuning problem: it is that the test geometry aims at the end face of the bat (a glancing angled
contact) rather than the long rubber face. Even the correct BAT_BOUNCE=0.45 cannot produce a 35%
rebound at a 61-degree glancing angle. Raising BAT_BOUNCE to compensate would over-correct the
forward swing behavior. The test geometry needs to be fixed, not the physics tuning.

Suspected files/lines:
- /home/virus/pinball-game/tests/test_flipper_rubber.gd lines 71-77 (_fire_at_face)

Root cause (geometry trace):
1. _fire_at_face places the ball at (along_bat=3.5, 0, -face_offset=-3.3) and fires it at (0, 0, +50).
2. The bat at REST_ANGLE = -0.55 rad (left flipper) lies along world direction (cos(-0.55), 0, sin(-0.55))
   = (0.853, 0, 0.523). Its world Z range is from -0.597 to +4.256 (midpoint at z=1.83).
3. Ball at z=-3.3 is OUTSIDE the bat's Z range (z=-3.3 < z_min=-0.597). The ball therefore
   approaches from UP-TABLE of the bat and hits the END face (the -Z face in body local, now
   pointing at world angle (0.523, 0, -0.853) in world space) rather than the LONG face.
4. The contact angle between the ball velocity (0, 0, 1) and the end-face outward normal
   (0.523, 0, -0.853) is: dot = -0.853. The incidence is 61 degrees off normal (a glancing hit).
5. The effective restitution at a glancing contact is reduced (the normal velocity component is only
   0.853 of the full speed); outgoing speed ~= 50 * 0.853 * 0.45 ~= 19.2 u/s = 38.4% of 50.
   The solver measurement of 24.8% suggests even less energy is retained at this glance angle.
6. The test comment says "we aim the ball at a point partway down the bat from the side (-Z) so it
   strikes the long face". This is only correct if the bat were at angle 0 (pointing along +X).
   At REST_ANGLE=-0.55, the bat is tilted ~31.5 degrees from +X toward +Z, so z=-3.3 is behind
   (up-table of) the entire bat body.

Expected behavior of the test: the ball hits the LONG face of the bat (the big rubber surface), gets
a near-perpendicular rebound at ~45% of the incoming speed (>= 35% floor), and exits along -Z.

Actual behavior: ball hits the END face at a glancing angle; outgoing speed ~24.8% (< 35% floor);
the test_rubber_rebound_preserves_momentum assertion FAILS.

Repro steps:
1. Compute the bat midpoint in world space: 3.5*(cos(-0.55), 0, sin(-0.55)) = (2.986, 0, 1.831).
2. The long face outward normal (up-table face of the bat, body-local -Z) in world:
   (sin(0.55), 0, -cos(0.55)) = (0.523, 0, -0.853).
3. Place ball at midpoint + face_normal * offset = (2.986+0.523*2.6, 0, 1.831-0.853*2.6)
   = (4.35, 0, -0.39). Fire ball velocity = -face_normal * 50 = (-0.523*50, 0, 0.853*50)
   = (-26.15, 0, 42.65) u/s. This hits the LONG face perpendicularly.
4. The perpendicular hit at BAT_BOUNCE=0.45 yields ~22.5 u/s outgoing = 45% >= 35% floor. Passes.

Suggested fix for _fire_at_face:
  Compute the bat rest position geometry at runtime from FLIPPER_REST_ANGLE (do not hardcode
  a z=-3.3 offset that assumes angle=0). Place the ball perpendicular to the long face:
    var bat_dir := Vector3(cos(TableConfig.FLIPPER_REST_ANGLE), 0, sin(TableConfig.FLIPPER_REST_ANGLE))
    var bat_face_normal := Vector3(sin(TableConfig.FLIPPER_REST_ANGLE), 0, -cos(TableConfig.FLIPPER_REST_ANGLE))
    var bat_midpoint := bat_dir * (TableConfig.FLIPPER_LENGTH * 0.5)
    var ball_start := bat_midpoint + bat_face_normal * (TableConfig.FLIPPER_WIDTH * 0.5 + TableConfig.BALL_RADIUS + 2.0)
    _ball.position = ball_start
    _ball.linear_velocity = -bat_face_normal * FIRE_SPEED
  This always fires at the long face regardless of FLIPPER_REST_ANGLE.

Note to physics-programmer: do NOT raise BAT_BOUNCE to fix this test. The current BAT_BOUNCE=0.45
produces the correct rubber feel on the long face (45% rebound, well above 35% floor). Raising it
to compensate for a glancing test geometry would over-energize the ball on normal forward swings.
Fix the test geometry first; if a genuine tuning issue remains after that, adjust BAT_BOUNCE.

---

### BUG-020 [MEDIUM] Lane pocket -X face extends 0.4 units past LANE_INNER_X into the center drain region - can deflect draining balls at the boundary

RESOLVED 2026-06-19 (lead polish): table_geometry.gd _build_lane_pocket now pads the seal slack on
the +X (right-wall) side ONLY (width = (HALF_WIDTH - LANE_INNER_X) + t*0.5, center_x = LANE_INNER_X +
width*0.5), so the -X face lands exactly at LANE_INNER_X (8.0) instead of 7.6. The lane divider at
LANE_INNER_X already closes the -X corner, so no gap. test_lane_pocket_drain.gd
test_lane_pocket_does_not_span_the_center_drain_region was tightened to assert -X face >= LANE_INNER_X
(epsilon), holding the correct boundary instead of the old one-WALL_THICKNESS slack.

Severity: MEDIUM - a ball that drains near the right side of the inverted-V gap (x in [7.6, 8.0])
hits the pocket's -X face before entering the drain volume cleanly. The drain DOES fire eventually
(the drain volume extends from z=21 to z=27 at full table width), but the ball bounces off the
pocket corner first, producing an unexpected trajectory near the drain. Not a hard stuck-ball
(the drain catches it), but the behavior is incorrect and could confuse playtesting.

Suspected files/lines:
- /home/virus/pinball-game/scripts/table_geometry.gd lines 161-178 (_build_lane_pocket)
- /home/virus/pinball-game/scripts/config/table_config.gd line 109 (LANE_POCKET_FACE_Z = 24.5)

Root cause (geometry trace):
1. _build_lane_pocket computes:
   width = (HALF_WIDTH - LANE_INNER_X) + WALL_THICKNESS = (12 - 8) + 0.8 = 4.8
   center_x = (LANE_INNER_X + HALF_WIDTH) * 0.5 = 10.0
   The pocket spans x from 10.0 - 2.4 = 7.6 to 10.0 + 2.4 = 12.4.
2. LANE_INNER_X = 8.0 is the defined boundary between the launch lane (+X of 8) and the
   center drain region (-X of 8). The pocket's -X face at x=7.6 is 0.4 units LEFT of this
   boundary -- it protrudes into the center drain region.
3. The BACKLOG notes the pocket -X face cleared a minimum of 7.2 units (a lower structural guard),
   but the DESIGN-INTENT boundary is LANE_INNER_X = 8.0. The gap between 8.0 and 7.6 is 0.4 units.
4. A ball draining at x=7.7 (just left of the lane boundary) traveling toward z=24.5 hits the
   pocket -X face. The pocket deflects it before it reaches the drain plane cleanly.
5. The drain volume (z: 21 to 27, x: -12 to +12) will still catch the ball, but the unexpected
   bounce at the pocket corner makes the drain feel non-deterministic in this zone.

Expected: the pocket -X face is flush with or right of LANE_INNER_X (x >= 8.0) so no pocket
geometry intrudes into the drain path.

Actual: pocket -X face at x=7.6, 0.4 units past LANE_INNER_X into the drain.

Suggested fix: increase center_x or reduce width so the -X face aligns exactly with LANE_INNER_X:
  Option A (preferred): width = (HALF_WIDTH - LANE_INNER_X) only (no extra WALL_THICKNESS on the -X
  side): width = 4.0. center_x = (LANE_INNER_X + HALF_WIDTH)/2 = 10.0. Pocket spans 10-2.0=8.0 to
  10+2.0=12.0. The -X face is exactly at LANE_INNER_X=8.0. The pocket still seals against the right
  wall (HALF_WIDTH=12) and the lane divider (divider center at x=8, inner edge at x=7.6, so there
  may be a 0.4-unit corner gap - verify separately).
  Option B: keep width=4.8 but shift center_x right by 0.4: center_x = 10.4. Pocket spans 8.0 to
  12.8. Right side slightly past the wall (which is fine if the wall boxes overlap the pocket).

Suggested GUT test to lock the fix:
  Assert in test_lane_pocket_drain.gd that the pocket's -X face position x >= LANE_INNER_X
  (derived from the StaticBody3D position and box size). This complements the existing structural
  assertion and makes the boundary constraint machine-checked.

---

### BUG-021 [LOW] Active kicker kick direction uses playfield-local constants as world-space velocity - introduces a ~0.097-world-unit Y error from table tilt

DEFERRED 2026-06-19 (lead polish, with the filer's own recommendation): the filing says "No immediate
action required; documented as precision debt. Flag for re-evaluation if TILT_DEG is raised above 10
degrees." TILT_DEG is 7; the missing world-Y component is ~5.4 u/s at 55 u/s, not player-perceptible,
and the kick still lands clearly into play. Holding it as precision debt avoids a playfield-local ->
world transform on a hot path for a sub-perceptual gain. Re-open if TILT_DEG exceeds 10.

Severity: LOW - the slingshot kick direction (and by extension the pop bumper's Y=0 clamp) are
computed or applied assuming the playfield coordinate frame is the world frame. At a 7-degree table
tilt the error is small (~5 u/s of unwanted Y-component at 55 u/s nominal kick speed) and does not
flip the kick direction, but it means the ball receives a slight wrong-direction nudge rather than
a precisely in-plane kick. At the current tilt the effect is not player-perceptible. If tilt is
increased later, the error grows proportionally.

Suspected files/lines:
- /home/virus/pinball-game/scripts/active_kicker.gd lines 166-168 (_apply_kick)
  _ball.linear_velocity = dir * target_speed
  where dir is the result of _kick_direction_for, which for slingshots is the PLAYFIELD-LOCAL
  constant SLINGSHOT_LEFT/RIGHT_KICK_DIR (Y=0 in local space, not world space).
- /home/virus/pinball-game/scripts/pop_bumper.gd lines 46-51 (_kick_direction_for)
  to_ball.y = 0.0 zeroes the WORLD-Y component, but the correct in-plane constraint should
  zero the PLAYFIELD-LOCAL Y (the surface normal direction in world space).

Root cause:
The playfield is rotated TILT_DEG=7 degrees about world X. A direction vector that has Y=0 in
playfield-local space has a small nonzero Y in world space. When SLINGSHOT_LEFT_KICK_DIR=(0.6,0,-0.8)
(playfield-local) is applied directly as a world-space linear_velocity, the world-Y component is
world_y = -lz * sin(tilt) = 0.8 * sin(7 deg) = 0.097 per unit of speed, or ~5.4 u/s at 55 u/s.
This is missing: the ball is kicked slightly less upward than physically correct.
For the pop bumper, to_ball.y = 0.0 zeros the world Y, which means the kick direction is constrained
to the world horizontal plane rather than the playfield surface. At 7 degrees this is a small error.

Tests do not catch this: behavioral tests zero ball gravity_scale, so the ball keeps whatever
velocity it was given and the small Y component is not visible in the position oracle.

Impact: LOW at current TILT_DEG=7. No player-visible effect. Documents a precision debt.

Suggested GUT test (future hardening):
  When running behavioral kick tests with the Playfield node at the correct tilt, assert that the
  ball's linear_velocity remains on (or very close to) the playfield surface plane after the kick
  (i.e., the ball does not fly above WALL_HEIGHT after a kick). This catches a large Y-error but
  is tolerant of the small 7-degree approximation error.

---

### BUG-022 [BLOCKING->RESOLVED] Drain trigger volume spanned the full table width and overlapped the launch-lane resting-ball position (review item B3 / N1 / N2)

RESOLVED 2026-06-19 (lead polish): the drain was DRAIN_WIDTH = HALF_WIDTH*2 (full table) centered at
x=0, so its volume covered the launch lane and the resting ball at BALL_START (x=10). Correct behavior
depended entirely on a GameFlow state guard (drain only while BALL_IN_PLAY) - fragile defense-in-depth
masking wrong geometry, against DESIGN's "open CENTER drain between/below the flippers". Fix: sized the
drain to the OPEN CENTER region only. table_config.gd: DRAIN_WIDTH = HALF_WIDTH + LANE_INNER_X (= 20,
spanning x in [-12, 8]) and a new DRAIN_CENTER_X = (LANE_INNER_X - HALF_WIDTH)/2 (= -2). drain.gd now
positions the Area3D at DRAIN_CENTER_X, not x=0, and the stale comment (N2: "DRAIN_Z = HALF_LENGTH +
2.0") was corrected to the real value (HALF_LENGTH - 1.0). The launch lane (x in [8, 12]) is now
OUTSIDE the drain volume by geometry; the center (x=0) is still inside (the center-drains test holds).

N1 coverage (the assertion that would have surfaced B3): added
tests/test_lane_pocket_drain.gd test_lane_resting_ball_does_not_drain - seats the real Ball at
BALL_START, watches the REAL Drain.ball_drained signal for the full settle, and asserts ZERO
emissions (independent oracle, not a flag), plus a sanity check that the ball stayed in the lane.

---

### BUG-023 [BLOCKING] Drain trigger volume overlaps the entire flipper-bat catch zone - a ball falling to the flippers drains before it can be flipped

Severity: BLOCKING - this breaks the core loop at Gate 0 (DESIGN: "the player catches the ball and
chooses a shot"). A ball arriving at the flippers crosses the drain trigger's up-table edge (z=21)
at the flipper PIVOT row, so drain.body_entered fires while the ball is still ~2.66 units up-table
of the flipper faces. It is spent as a drain in BALL_IN_PLAY (the exact state on_ball_drained acts
in - the GameFlow guard does NOT mask this), so the player loses a ball they were about to flip.
Same defect CLASS as BUG-022 (drain geometry overlapping a legitimate ball position), now on the
flipper cradle instead of the launch lane. The BUG-022 fix narrowed the drain in X but never
reconciled the drain's Z extent with the flipper-bat Z span.

Slice: Table reshape + playtest fixes. Found by QA review 2026-06-19 (geometry oracle).

LEAD FIX LANDED 2026-06-19 (polish pass): added FLIPPER_BAT_MAX_Z (23.66, QA's pessimistic oracle)
and DRAIN_BAT_CLEARANCE (0.6) to TableConfig; shrank DRAIN_DEPTH 6.0 -> 1.6 and re-derived DRAIN_Z =
FLIPPER_BAT_MAX_Z + DRAIN_BAT_CLEARANCE + DRAIN_DEPTH/2 = 25.06, so the drain volume's up-table edge
sits at 24.26 - cleanly below the bats (23.66) and above the open bottom mouth. drain.gd comment
updated. Two config asserts added to tests/test_world_scale.gd (up-table edge > FLIPPER_BAT_MAX_Z;
center not far past the open bottom) and one cradle integration test added to
tests/test_table_integration.gd (real Ball seated in the flipper catch zone, real Drain watched,
ZERO ball_drained emissions). table_viz.py DRAIN_Z now tracks the config formula. Awaiting CI green.

Suspected files/lines:
- /home/virus/pinball-game/scripts/config/table_config.gd:108 DRAIN_Z = HALF_LENGTH - 1.0 (= 24)
- /home/virus/pinball-game/scripts/config/table_config.gd:121 DRAIN_DEPTH = 6.0
- /home/virus/pinball-game/scripts/config/table_config.gd:92-93 FLIPPER_PIVOT_SPREAD 7.2 /
  FLIPPER_PIVOT_Z = HALF_LENGTH - 5.0 (= 20)
- /home/virus/pinball-game/scripts/drain.gd:35-52 (box sized DRAIN_WIDTH x WALL_HEIGHT x DRAIN_DEPTH,
  centered at DRAIN_CENTER_X, DRAIN_Z)

Evidence (geometry oracle, derived from the committed constants):
1. Drain trigger box: x in [-16.0, 10.5], z in [DRAIN_Z - DRAIN_DEPTH/2, DRAIN_Z + DRAIN_DEPTH/2]
   = [21.0, 27.0], y centered 0 with height WALL_HEIGHT 2.4 -> y in [-1.2, 1.2].
2. Flipper bats at rest (both sides, symmetric): the bat sweeps from the pivot (x=+/-7.2, z=20.0)
   to the tip (x=+/-1.23, z=23.66). The ENTIRE bat lies at z 21.46..23.66, fully inside the drain
   z-band [21, 27], and at x inside the drain x-band [-16, 10.5].
3. A ball falling down-table toward the flippers reaches z=21 (the drain's up-table edge) BEFORE it
   reaches the bat faces (z 20..23.66). So body_entered fires as the ball passes the pivot row, ~2.66
   units before it could land on a bat.
4. The ball center over a cradling bat sits at y ~= 1.2 (bat-top 0.6 + ball radius 0.6), at the very
   top edge of the drain y-band - on the tilted plane this is borderline, so the EXACT runtime trigger
   point needs a real integration test to pin (see the test-debt item), but the volume overlap is
   unambiguous and the design intent (drain is the gap BELOW/BETWEEN the flippers, not over them) is
   violated by geometry.

Why CI did not catch it: tests/test_world_scale.gd test_drain_position_is_past_flippers asserts only
DRAIN_Z > FLIPPER_PIVOT_Z (24 > 20, passes). It checks the drain CENTER against the pivot, never the
drain VOLUME's up-table edge against the flipper-bat catch zone. The trigger is the volume, not the
center. This is the testability gap.

Suggested fix (lead/physics): push the drain's up-table edge BELOW the flipper-tip z. Options:
  (a) raise DRAIN_Z and/or shrink DRAIN_DEPTH so DRAIN_Z - DRAIN_DEPTH/2 > max flipper-bat z (>23.66),
      e.g. DRAIN_DEPTH 2.0 with DRAIN_Z 25.0 -> edge at 24.0 (just below the tips) - but verify the
      ball still drains before the open bottom edge (HALF_LENGTH 25);
  (b) place the drain trigger purely BELOW the surface in the center gap (a catch box under the open
      mouth) rather than a tall on-plane box that the flipper bats poke into.
  Whatever the choice, the drain's up-table edge must clear the flipper-bat catch zone, and a ball
  dribbling through the open mouth must still drain.

Suggested GUT test to lock the fix (independent oracle): seat the REAL Ball cradled on a REAL left
(then right) flipper held energized, watch Drain.ball_drained for the full settle, assert ZERO
emissions; plus a config assert DRAIN_Z - DRAIN_DEPTH/2 > (max flipper-bat z) so the boundary is
machine-checked the way BUG-022's was.

---

### BUG-024 [HIGH] Left and right slingshot KickerBody (StaticBody3D) geometrically overlaps the LaneGuide wall (StaticBody3D) at the outlane corner

Severity: HIGH - the overlap is in the primary outlane ball-path: every ball heading for the left
or right outlane passes through the X[-12.74, -12.60] x Z[18.0, 18.32] junction on the left side
(symmetric on the right). Two StaticBody3D bodies do not collide with each other, but their
overlapping surfaces create a concave geometry pocket that can produce unpredictable collision
normals when the ball's contact manifold straddles both bodies simultaneously. In the worst case
the solver returns conflicting normals and the ball is ejected at an unpredicted angle or
momentarily has no valid contact face to resolve against, causing a velocity spike (speed
explosion) or a brief clip. This is exactly the kind of static-body seam that CCD does NOT guard
against (CCD prevents tunneling through a moving face, not velocity explosions from dual-body
contact ambiguity).

Found by QA geometry oracle 2026-06-19.

Repro steps (geometry-based, no playtest required):
1. Open scripts/slingshot.gd and scripts/table_geometry.gd.
2. Compute left slingshot KickerBody world extents:
   - Center: (-10.5, 0, 16.5), yaw = atan2(0.6, 0.8) = 36.87 deg
   - Box local half-extents: (SLINGSHOT_LENGTH/2, WALL_HEIGHT/2, SLINGSHOT_THICKNESS/2) = (2.5, 1.2, 0.4)
   - Rotated world X range: [-12.74, -8.26], world Z range: [14.68, 18.32]
3. Compute LaneGuideLeft world extents:
   - Center X: -LANE_GUIDE_DIVIDER_X = -13.0
   - Box half-width in X: WALL_THICKNESS/2 = 0.4 -> X range: [-13.4, -12.6]
   - Z range: [LANE_GUIDE_TOP_Z, LANE_GUIDE_BOTTOM_Z] = [18.0, 23.0]
4. Intersection: X overlap [-12.74, -12.60] (0.14 units), Z overlap [18.0, 18.32] (0.32 units).
   Both bodies are on STATIC_OBSTACLES. The overlap is real geometry interpenetration.
5. Right slingshot / LaneGuideRight is symmetric: X[12.60, 12.74] x Z[18.0, 18.32].

Expected: the slingshot KickerBody outer corner and the lane guide wall do not share any volume.
The gap between them should be at least BALL_RADIUS (0.6 units) to prevent the ball from having
simultaneous contact with both bodies at the seam.

Actual: 0.14 unit X x 0.32 unit Z overlap. The ball (radius 0.6) is larger than either overlap
dimension individually, so it cannot physically sit entirely within the overlap zone. However a
ball traveling along the outer wall CAN touch both bodies simultaneously at the seam (it has
radius > overlap dimension, so both contact normals are active at once). The solver receives two
overlapping StaticBody3D contact normals in a concave-like pocket and must reconcile them. The
Jolt solver may clip velocity, spike it, or produce a micro-stutter depending on the exact
contact manifold resolution order. This is a non-deterministic failure mode: it may not reproduce
every frame, which is what makes it high-severity (silent in testing, visible in play).

Suspected files/lines:
- /home/virus/pinball-game/scripts/config/table_config.gd
  SLINGSHOT_LEFT_POS, SLINGSHOT_RIGHT_POS, SLINGSHOT_LENGTH, SLINGSHOT_THICKNESS (lines ~130-135)
  LANE_GUIDE_DIVIDER_X = HALF_WIDTH - 3.0 = 13.0 (line ~140)
  LANE_GUIDE_TOP_Z = 18.0 (line ~141)
- /home/virus/pinball-game/scripts/slingshot.gd: _build_body() places KickerBody at _pos + yaw
- /home/virus/pinball-game/scripts/table_geometry.gd: _build_lane_guides() places LaneGuide walls

Root cause:
The lane guide Z range starts at LANE_GUIDE_TOP_Z = 18.0. The slingshot outer corner (the
corner of the rotated box at the up-table end of the outer side) lands at Z = 18.32, 0.32 units
BELOW the lane guide top. The two bodies share the Z band [18.0, 18.32]. The fix is to either:
  (a) raise LANE_GUIDE_TOP_Z to at least 18.35 (clear of the sling corner),
  (b) shorten SLINGSHOT_LENGTH by ~0.5 so the outer corner no longer reaches Z=18, or
  (c) shift the sling center slightly down-table (larger Z) by 0.5 units to pull the outer corner
      away from the guide.
Option (a) is the least-intrusive single-constant change and does not alter shot geometry.

Suggested GUT test to lock the fix:
  In test_furniture_layout.gd or a new test_static_body_clearance.gd, for each pair
  (KickerBody world AABB, LaneGuide world AABB), assert the AABB intersection volume is zero
  (or less than an epsilon like 0.01). This is a pure geometry assertion that can be computed
  from the committed TableConfig constants without running physics.

LEAD FIX LANDED 2026-06-19 (polish pass): took option (a) - raised LANE_GUIDE_TOP_Z from
FLIPPER_PIVOT_Z - 2.0 (18.0) to FLIPPER_PIVOT_Z - 1.0 (19.0), clearing the sling outer corner
(18.32) by 0.68 (> BALL_RADIUS 0.6), more headroom than the suggested 18.35. Does not change shot
geometry. Added test_slingshot_and_lane_guide_do_not_overlap to tests/test_furniture_layout.gd: it
computes each body's world AABB from the LIVE instanced scene (global transform x box size over all
8 rotated corners) and asserts the slingshot-vs-guide intersection volume is < 0.001 on both sides.
table_viz.py LANE_GUIDE_TOP_Z now mirrors the new config formula. Awaiting CI green.

---

### BUG-025 [MEDIUM] Plunger face has sync_to_physics = true AND an explicit apply_central_impulse active simultaneously - ball can receive double the intended launch energy if Jolt executes both transfers

Severity: MEDIUM - the design intent of the physical-launch slice was that the impulse would be
the RELIABLE fallback for the unreliable sync_to_physics contact transfer (DESIGN.md and plunger.gd
comments both say sync_to_physics "can be unreliable in Jolt"). The current code leaves
sync_to_physics ON and adds the impulse ON TOP of it. In the common case (Jolt correctly resolves
the sync_to_physics contact transfer), the ball receives both the contact impulse from the solver
AND the explicit apply_central_impulse in _try_apply_launch_impulse(), giving approximately 2x the
intended speed. At full power (PLUNGER_STROKE_SPEED_MAX = 78 u/s) the resulting ball speed could
reach ~156 u/s, which is above KICK_MAX_OUTGOING_SPEED (120 u/s) and may exceed the CCD-safe
validated envelope (the no-tunneling stress test runs at 2 * LAUNCH_SPEED_MAX = 180 u/s, so 156
is inside the test band, but it is above every intended per-mechanism cap). In the uncommon case
(Jolt sync_to_physics does NOT transfer momentum, the stated reason the impulse was added), only
the impulse fires and the launch is correct.

This is a latent behavior-under-physics-engine-version defect: the Jolt build variant or settings
that determine whether AnimatableBody3D velocity bleeds into RigidBody3D contact may change across
Godot upgrades. Today's behavior may differ from CI's Godot version's behavior.

Found by QA code inspection 2026-06-19.

Repro steps:
1. Open /home/virus/pinball-game/scripts/plunger.gd.
2. Line 118: _face.sync_to_physics = true  (sync is ON; face reports velocity to solver).
3. Lines 341-347: _try_apply_launch_impulse() applies apply_central_impulse(up_table_world * ball.mass
   * _stroke_speed) when is_touching() is true.
4. On the first physics frame of the forward stroke (_stroke_state = FORWARD):
   - The face has NOT yet moved this frame, so sync_to_physics velocity from the previous frame is 0.
     The solver adds 0 contact energy. The impulse fires (is_touching is true, face didn't move yet).
   - On subsequent forward frames (_impulse_applied = true blocks re-fire), sync_to_physics CAN
     transfer energy to the ball if the ball is still in contact with the moving face.
5. The net result depends on whether the ball separates from the face after the first-frame impulse.
   If face speed (78 u/s) == impulse-imparted speed (78 u/s), they move at equal speed: the ball
   rides the face and continues receiving sync_to_physics energy every frame until it separates.
   The double-energy case is most likely at high stroke speeds with a heavy ball.

Expected: the ball's outgoing speed equals PLUNGER_STROKE_SPEED_MAX * power_fraction (0 to 78 u/s),
which the test suite asserts (LAUNCH_SPEED_MIN..LAUNCH_SPEED_MAX).

Actual: the ball may reach approximately 2x PLUNGER_STROKE_SPEED_MAX under Jolt when
sync_to_physics contact transfer is active, an excess that the existing test suite may not detect
if the test's SETTLE_FRAMES of 120 bring the ball to a peak-then-slow trajectory rather than a
peak speed snapshot. The tunneling test covers up to 180 u/s (2x LAUNCH_SPEED_MAX = 2*90) but does
not distinguish a plunger-caused speed spike from an intentional stress-test input.

Suspected file/line:
- /home/virus/pinball-game/scripts/plunger.gd line 118: _face.sync_to_physics = true
- /home/virus/pinball-game/scripts/plunger.gd lines 341-347: _try_apply_launch_impulse()

Root cause:
The physical-launch slice added the impulse as a "reliable alternative" to sync_to_physics without
turning sync_to_physics off. The correct fix is one of:
  (a) Disable sync_to_physics on the face (_face.sync_to_physics = false) and rely solely on the
      impulse mechanism (the stated design intent per the architecture note). The face still blocks
      the ball physically via its collision shape; it just doesn't report velocity to the solver.
  (b) Remove the explicit apply_central_impulse and accept sync_to_physics as-is (reverts the
      physical-launch fix rationale, not recommended).
  (c) Guard _try_apply_launch_impulse with a Jolt sync check and only fire if the solver did NOT
      transfer energy (impossible to query directly; option (a) is simpler and safer).
Option (a) is preferred: sync_to_physics = false, impulse only.

Suggested GUT test to lock the fix:
  In test_plunger_launch.gd, add a peak-speed oracle: immediately after ball_launched emits,
  read ball.current_speed() within 2 frames (before damping) and assert it is < LAUNCH_SPEED_MAX
  * 1.1 (a 10% tolerance for physics step alignment). This catches a 2x energy spike (156 u/s >>
  99 u/s cap) without being sensitive to normal launch variance. The existing test asserts
  LAUNCH_SPEED_MIN..LAUNCH_SPEED_MAX on a post-settle position oracle, which does not directly
  bound peak speed at the moment of launch.

LEAD FIX LANDED 2026-06-19 (polish pass): took option (a) - set _face.sync_to_physics = false in
scripts/plunger.gd._build_face so the launch momentum comes SOLELY from the explicit impulse (one
mechanism, no double-count). The face is still a SOLID moving barrier (its collision shape blocks
the ball and backs up the ball's CCD against backward tunneling); it just no longer reports velocity
to the solver. Added test_full_strike_peak_speed_stays_under_double_energy_ceiling to
tests/test_plunger_launch.gd: it fires a full-power strike and samples ball.current_speed() each of
the first 12 frames (in the straight lane, before any arch bounce), asserting the PEAK stays under
LAUNCH_SPEED_MAX * 1.1 = 99 (a correct single-impulse launch peaks ~78; a 2x stack would hit ~156).
Awaiting CI green.

---

### BUG-026 [BLOCKING] Table-reshape slice is RED on the runner - the #1 fix (the launch) does not fire in CI

Severity: BLOCKING - the slice's headline fix (make the plunger actually launch the ball) is proven
FALSE by the runner. CI on the pushed sha is the source of truth and it is FAILURE.

Slice: table-reshape-playtest-fixes. Found by QA peer review 2026-06-20 against the runner artifact
(NOT a doc claim): PR #10, CI run 27858434688, status FAILURE. Totals: 143 tests, 137 passing,
6 FAILING, 942 asserts. The producer gate requires GREEN CI on the pushed sha; this is provably red.

The 6 failing tests, all read off the runner log (independent oracle):
1. test_plunger_launch.gd::test_strike_imparts_velocity_to_ball - ball speed 0.00006 (rest), not > 1.0.
2. test_plunger_launch.gd::test_full_power_outthrows_weak_strike - full 0.000002 NOT > weak 0.00004.
3. test_plunger_launch.gd::test_launched_ball_speed_lands_in_design_range - got 0.000016, need >= 30.
4. test_plunger_launch.gd::test_max_strike_does_not_tunnel... - ball ends z=24.08 > start 23.0 (it
   drifted DOWN-table to the pocket, was never thrown up-table; the strike did nothing 20x).
5. test_table_integration.gd::test_ball_in_flipper_catch_zone_does_not_drain - a real ball at the
   cradle (z=23.06) STILL drains (BUG-023 not actually fixed at runtime - see BUG-028).
6. test_target_no_tunneling.gd::test_tunneling_check_matches_flat_wall_test_threshold - stale
   POST_RADIUS (see BUG-027).

ROOT CAUSE of the launch failures (the four plunger_launch reds), traced from geometry + the impulse
gate in scripts/plunger.gd._try_apply_launch_impulse (line 335: only fires if _ball.is_touching(_face)):
- BALL_START.z = HALF_LENGTH - 2.0 = 23.0; the ball is parked there, then under the 7-deg tilt it
  rolls DOWN-table (+Z) and settles against the lane pocket (LANE_POCKET_FACE_Z = 24.5), measured at
  z ~= 24.08 after SETTLE_FRAMES.
- PLUNGER_REST_POS.z = BALL_START.z + BALL_RADIUS + PLUNGER_FACE_THICKNESS*0.5 = 23.0 + 0.6 + 0.4 =
  24.0. The face is seated at 24.0, which is now UP-table of the settled ball at 24.08.
- So at the moment of the strike the ball is resting against the POCKET, not against the FACE. The
  face at 24.0 is on the wrong side of the ball; is_touching(_face) is FALSE; the impulse never fires;
  the ball never moves. The whole impulse-on-contact mechanism is geometrically defeated by the ball
  settling past the face.
The design is sound (impulse gated on a real contact, independent-oracle correct) but the SEATING is
wrong: the ball must come to rest CONTACTING the face (between the face and the pocket, touching the
face), or the strike must not require a pre-existing contact (the forward stroke must catch up to and
strike the drifting ball). Either way, today the launch is dead in CI exactly as the developer
reported in the deployed build - the fix did not fix it.

Fix direction (physics-programmer): make the resting ball physically touch the plunger face. Options:
(a) seat the face just up-table of BALL_START so the ball, drifting down-table, rests AGAINST the
    face (face down-table of the ball, ball trapped between face and... no - the ball drifts toward
    the pocket, so the face must be DOWN-table of the ball's rest, i.e. between the ball and the
    pocket, and the ball rests on it). Re-derive PLUNGER_REST_POS.z and/or BALL_START.z so the
    settled ball is in continuous contact with the face (assert it: ball.is_touching(face) is TRUE
    after SETTLE_FRAMES, a new structural-behavioral test).
(b) drop the is_touching pre-gate and instead apply the impulse on the first frame the forward stroke
    REGISTERS a fresh contact with the ball (drive the face into the ball even if it starts a hair
    apart), so a ball resting anywhere ahead of the face is struck when the stroke reaches it.
Add a test that asserts the settled ball touches the face (lock the seating), not only that a strike
imparts speed (which masks WHY it failed).

---

### BUG-027 [HIGH] test_target_no_tunneling.gd POST_RADIUS is stale (1.5) after the resize to 2.0 - the resized-target stress gate is wrong AND red

Severity: HIGH - this is the slice-item-5 stress gate ("no tunneling on the BIGGER target at >= 2x
LAUNCH_SPEED_MAX"). The resize raised target.gd POST_RADIUS 1.5 -> 2.0, but this stress test still
hardcodes 1.5, so it both FAILS CI and tests the wrong geometry.

Slice: table-reshape-playtest-fixes. Found by QA peer review 2026-06-20.

Files:
- /home/virus/pinball-game/scripts/target.gd:47  const POST_RADIUS: float = 2.0  (the resize)
- /home/virus/pinball-game/tests/test_target_no_tunneling.gd:28  const POST_RADIUS: float = 1.5 (STALE)

Evidence:
1. git log 990644c..HEAD on tests/test_target_no_tunneling.gd is EMPTY: the slice resized the post
   but NEVER updated this stress test. test_target_physical.gd WAS updated to 2.0 (line 33); this one
   was missed.
2. CI run 27858434688: test_tunneling_check_matches_flat_wall_test_threshold FAILS:
   "[2.0] expected to equal [1.5]: test constant POST_RADIUS (1.500) does not match the actual
   deflector radius (2.000)." The test's own maintenance guard caught it.
3. The stress LOOP also uses the stale 1.5: tunnel_threshold = 1.5 + BALL_RADIUS*0.5 = 1.8, but the
   real far face is at 2.0, so the loop's pass band is mis-calibrated for the body it fires at. The
   gate that is supposed to prove the BIGGER post does not tunnel is not actually measuring the bigger
   post correctly. Even when the consistency assert is fixed, the loop threshold must move to 2.0.

Fix: set POST_RADIUS = 2.0 in test_target_no_tunneling.gd (matching target.gd and
test_target_physical.gd). Better: read the radius from the live Deflector shape in before_each so the
constant cannot drift again (the file already reads it in the consistency test - reuse that). Re-run
the 100-iteration loop at 2x LAUNCH_SPEED_MAX against the 2.0 post and confirm green.

---

### BUG-028 [HIGH] BUG-023 "fix" satisfied the config arithmetic but the real ball still drains in the cradle

Severity: HIGH - the BUG-023 fix (commit 73f8fc7) tuned DRAIN_Z/DRAIN_DEPTH so the CONFIG assert
passes, but the BEHAVIORAL integration test still FAILS: a real ball seated at the cradle drains.
The config oracle is a false comfort; the behavioral oracle is the truth and it is red.

Slice: table-reshape-playtest-fixes. Found by QA peer review 2026-06-20.

Files:
- /home/virus/pinball-game/scripts/config/table_config.gd (DRAIN_Z, DRAIN_DEPTH, FLIPPER_BAT_MAX_Z)
- /home/virus/pinball-game/scripts/drain.gd (the drain Area3D volume)
- /home/virus/pinball-game/tests/test_world_scale.gd::test_drain_up_table_edge_clears_the_flipper_bat_catch_zone (config assert - PASSES)
- /home/virus/pinball-game/tests/test_table_integration.gd::test_ball_in_flipper_catch_zone_does_not_drain (behavioral - FAILS)

Evidence (CI run 27858434688):
1. test_drain_up_table_edge_clears_the_flipper_bat_catch_zone shows '*' (PASS): the arithmetic guard
   DRAIN_Z - DRAIN_DEPTH/2 > FLIPPER_BAT_MAX_Z (23.66) is satisfied.
2. test_ball_in_flipper_catch_zone_does_not_drain FAILS: "Expected Drain to NOT emit ball_drained:
   a ball in the flipper catch zone (z=23.06) must NOT drain (QA BUG-023)" at line 206.
3. So a REAL ball placed where a player cradles it (z=23.06, below the asserted clearance edge) still
   enters the drain volume and fires ball_drained. The config math says the edge clears the bat MAX_Z
   (23.66) but the ball at 23.06 is UP-table of that and STILL drains - meaning either the drain
   volume in drain.gd is larger/positioned differently than the constants imply, or FLIPPER_BAT_MAX_Z
   (23.66) under-states the real catch zone, or the ball settles into the volume from above.
4. This is exactly why the QA backlog mandated TWO oracles for BUG-023 (a config assert AND a
   behavioral integration test). The config assert alone would have shipped this as "fixed".

Fix direction (lead/physics): make the BEHAVIORAL test green, not just the config assert. Either move
the drain volume further down-table (raise DRAIN_Z and/or shrink DRAIN_DEPTH so the actual Area3D
up-table edge sits below the real ball-rest at the cradle), or correct FLIPPER_BAT_MAX_Z to the true
down-table extent of a cradled ball. Verify with the behavioral test, then re-confirm the center
still drains (test_lane_pocket_drain center-X reaches the drain).

---

### BUG-029 [HIGH] Right-side gap zone (x=[9.4,13.6], z=[19.0,23.0]) has no collision bodies - ball exits via open table bottom instead of center drain

Severity: HIGH - a ball that enters the right-side gap zone between the LaneGuideRight wall and the
LaneDivider wall has no lateral containment below z=23.0 and no drain coverage at its X position.
It rolls off the open table bottom edge and is caught by the OOB failsafe (y=-20.0), which calls
on_ball_drained() and spends the ball. The ball IS spent correctly, but it visually disappears from
the right side of the field rather than from the center drain. The gap was widened by the Playtest
fixes 2 lane resize (LANE_INNER_X: 10.5 -> 14.0), which moved the lane divider outboard while the
right lane guide stayed at x=9.0, opening a 4.2-unit gap that no existing geometry closes.

Slice introduced: Playtest fixes 2 (LANE_INNER_X resize 2026-06-20). Gap existed before but was
only ~1.2 units (barely a ball diameter); after the resize it is 4.2 units (3.5 ball diameters) and
trivially enterable.

Files and geometry:
- /home/virus/pinball-game/scripts/config/table_config.gd
  LANE_INNER_X = 14.0, LANE_GUIDE_RIGHT_DIVIDER_X = 9.0, WALL_THICKNESS = 0.8
  LaneGuideRight right face: x = 9.0 + 0.4 = 9.4
  LaneDivider left face: x = 14.0 - 0.4 = 13.6
  Gap width: 4.2 units. Ball diameter: 1.2 units. Ball easily fits.
  LANE_GUIDE_BOTTOM_Z = 23.0. Lane divider bottom_z = HALF_LENGTH - 1.0 = 24.0.
  Center drain x span: [-1.832, 1.832]. Gap zone x=[9.4, 13.6] is entirely outside drain.
- /home/virus/pinball-game/scripts/table_geometry.gd
  _build_lane_guides: places LaneGuideRight at x=9.0, z=[19.0, 23.0].
  _build_lane_divider: places LaneDivider at x=14.0, z=[ARCH+ARCH_R_Z, 24.0].
  _build_lane_pocket: spans x=[14.0, 16.4+] only. Does NOT close gap zone.
  No body closes x=[9.4, 13.6], z=[23.0, 25.0].

Repro steps:
1. Launch the ball. After it enters the main playfield, use the flippers to direct it toward the
   right side at roughly x=11-12 (between the right lane guide at x=9.0 and the lane divider at
   x=14.0) near z=21-22.
2. With insufficient lateral velocity, the ball will drift into x=[9.4, 13.6], z=[19.0, 23.0].
3. Gravity pulls the ball DOWN-TABLE (+Z). Below z=23.0 there are no containing walls.
4. The ball rolls off the open bottom edge (z > 25.0) and falls below y=-20.0.
5. The OOB Area3D fires on_ball_drained(). The ball IS spent.

Expected: a ball that cannot be saved by the flippers should enter the CENTER drain (x in
[-1.832, 1.832], z in [24.26, 25.86]) and trigger ball_drained normally. There is no physical drain
in the gap zone.

Actual: ball disappears from the RIGHT SIDE of the visible table surface. The player sees no clear
drain event. The OOB failsafe recovers the game state but the visual is broken.

Root cause: the Playtest fixes 2 LANE_INNER_X resize moved the lane divider to 14.0 but left the
right lane guide at 9.0. A 4.2-unit open corridor now exists between the two structures at z=[19.0,
23.0], widening below z=23.0 until it merges with the open table bottom. No geometry closes the gap.

Fix direction: close the gap between LaneGuideRight (at x=9.4 right face) and LaneDivider (at
x=13.6 left face) across z=[19.0, 23.0], either by moving one structure to meet the other or adding
a short horizontal connector wall. Verify that any added body does not overlap the right flipper bat
sweep (verified by test_furniture_layout.gd) or the slingshot body (sling ends at z=18.32, guide
starts at z=19.0 - the existing 0.68-unit clearance from BUG-024 fix must be preserved).

Suggested GUT test to lock the fix:
  In test_furniture_layout.gd: assert that the gap zone has no accessible X+Z corridor between
  LaneGuideRight and LaneDivider by checking that both structures together span x=[8.6, 13.6] at
  z=[20.0, 23.0] (no gap wider than BALL_RADIUS*2=1.2 between their facing surfaces).

RESOLVED 2026-06-20 (lead polish, partial - working-as-designed + comment fix): on review the band
between the slingshot (x~10.5) and the lane divider (x=14.0) is the RIGHT OUTLANE (DESIGN "A DRAIN
YOU EARN, EITHER SIDE"): a ball down it drains off the open bottom and is correctly SPENT by the OOB
failsafe, the same way the left side band drains. The center drain is intentionally the narrow inter-
tip mouth only (BUG-023 geometry); side bands are outlanes by design. So the ball being spent is
correct behavior, not a leak. What WAS wrong: (a) the stale TableConfig comment on
LANE_GUIDE_RIGHT_DIVIDER_X still claimed the lane divider was at 10.5 (pre-resize) - corrected to
state the real 14.0 geometry and document the band as the right outlane; (b) the genuinely harmful
consequence this band could feed was the BUG-031 transient false-promotion, now closed independently
(see BUG-031). The right divider stays 9.0 (still the correct inlane/outlane split inboard of the
slingshot). No new geometry added (scope: no new element types).

---

### BUG-030 [HIGH] Slingshot _body_yaw formula makes the face normal point AWAY from the kick direction - face and kick are misaligned by ~143 deg

Severity: HIGH - the comment in slingshot.gd says "the face whose normal _body_yaw rotates to the
kick direction" but the math is wrong. The formula atan2(kick_dir.x, -kick_dir.z) rotates the body
so its local +Z (the kicking face normal) maps to world (0.6, 0, +0.8) for the left slingshot,
whereas the kick direction is (0.6, 0, -0.8). The Z component is inverted: the face normal points
toward the drain (+0.8 in Z), not into play (-0.8 in Z). The correct formula is
atan2(kick_dir.x, kick_dir.z) (note: no negation of kick_dir.z), which maps local +Z to world
(0.6, 0, -0.8) - matching the kick direction exactly.

At runtime the severity is partially mitigated: the velocity SET in _apply_kick (line 167 of
active_kicker.gd) overwrites the ball velocity with kick_dir * 55.0 AFTER the physics solver's
face-normal bounce fires. The kick direction in the code is correct; only the FACE NORMAL orientation
is wrong. The physics outcome (ball going into play at 55 u/s) is correct because the velocity set
overrides the solver bounce for that step. However:
  1. The MESH is also yawed by _body_yaw (slingshot.gd line 106): the visible triangular mesh
     has its kicking face pointing toward the drain, so the player sees the ball hit the BACK of
     the visual slingshot (the apex side), not the face.
  2. The solver's bounce impulse (KICKER_BOUNCE = 0.5) fires in the drain direction for one step
     before _apply_kick overwrites it. This could cause a 1-frame speed anomaly.
  3. The comment is false and will mislead any developer who reads it to verify or modify the yaw.

Files and lines:
- /home/virus/pinball-game/scripts/slingshot.gd line 204: _body_yaw() returns
  atan2(_kick_dir.x, -_kick_dir.z). The formula should be atan2(_kick_dir.x, _kick_dir.z).
- /home/virus/pinball-game/scripts/slingshot.gd line 106: the mesh is yawed by _body_yaw(), so
  the visible mesh has the same face-normal mismatch.
- /home/virus/pinball-game/scripts/slingshot.gd lines 116-127: _triangle_outline(): face_z = +0.4
  (face sits at local +Z). After yaw, local +Z goes to world (sin(yaw), 0, cos(yaw)).

Math oracle:
  Left kick_dir = (0.6, 0, -0.8). Want face_normal_world = (0.6, 0, -0.8).
  Local +Z after yaw theta: (sin(theta), 0, cos(theta)).
  theta = atan2(0.6, -0.8) = 143.13 deg (correct formula: atan2(kick_dir.x, kick_dir.z))
  Actual code: theta = atan2(0.6, 0.8) = 36.87 deg
  Resulting face normal at 36.87 deg: (sin(36.87), 0, cos(36.87)) = (0.6, 0, +0.8) - WRONG sign on Z.

Repro (code trace):
1. Open /home/virus/pinball-game/scripts/slingshot.gd line 202-204.
2. _body_yaw() returns atan2(_kick_dir.x, -_kick_dir.z).
3. For left sling kick_dir = (0.6, 0, -0.8): yaw = atan2(0.6, 0.8) = 36.87 deg.
4. After this rotation, body local +Z in world = (sin(36.87), 0, cos(36.87)) = (0.6, 0, +0.8).
5. This is the DRAIN direction (positive Z = down-table). Not the kick direction (0.6, 0, -0.8).
6. The mesh yawed by _body_yaw (line 106) shows the face pointing toward drain. Visually wrong.

Expected: slingshot face normal in world space = kick direction. Player visually sees ball hit the
angled face and bounce into play. Face and kick are aligned.

Actual: slingshot face normal in world space is roughly anti-parallel to kick direction. The visible
triangle shows its BACK to the approaching ball (ball appears to hit the apex, not the face). The
physics outcome is still correct because _apply_kick sets the velocity to the correct direction.

Root cause: atan2(kick_dir.x, -kick_dir.z) computes the heading from the UP-TABLE axis (-Z), which
yields the complement of the desired rotation. The correct formula to align local +Z with kick_dir
is atan2(kick_dir.x, kick_dir.z) (heading from the DOWN-TABLE axis), which gives 143.13 deg
instead of 36.87 deg.

Fix direction: in slingshot.gd _body_yaw(), change:
  return atan2(_kick_dir.x, -_kick_dir.z)
to:
  return atan2(_kick_dir.x, _kick_dir.z)
Verify both slingshots by asserting body local +Z in world == kick_dir (within epsilon).
The mesh fix follows automatically (it reads _body_yaw). Re-run test_slingshot.gd after the fix
to confirm both kick directions still pass (the kick direction itself is correct in the code; only
the face orientation changes, which the behavioral tests do not currently assert explicitly).

Suggested GUT test to lock the fix:
  In test_slingshot.gd: after instancing each sling, assert that _body.transform.basis.z
  (the body's local +Z in world space) is approximately equal to the configured kick direction
  (dot product > 0.99). Currently the face normal and kick direction are MISALIGNED; after the fix
  this asserts they are the same direction.

RESOLVED 2026-06-20 (lead polish): slingshot.gd _body_yaw() now returns atan2(_kick_dir.x,
_kick_dir.z) (negation removed), exactly the suggested fix. Verified against Godot's actual Y-basis
convention (cross-checked with the arch's proven atan2(-chord.z, chord.x) heading): the body-local
+Z (the kicking-face normal) now maps to _kick_dir, so the visible mesh, the solid body, and the
detector all face into play. The misleading "the face whose normal _body_yaw rotates to the kick
direction" comment is now TRUE. The kick velocity was already correct (set directly in
active_kicker._apply_kick), so no physics behavior changed; only the visible/collider orientation
was corrected. test_slingshot.gd's BUG-018 corner test derives its face axes from the live
_body_yaw(), so it self-adjusts and stays valid.

---

### BUG-031 [MEDIUM] Soft-lock watchdog transient-crossing edge case: a ball that barely crosses LAUNCH_REACHED_PLAY_Z then rolls back into the lane leaves the game in BALL_IN_PLAY with a dead plunger and trapped ball

Severity: MEDIUM - this is a soft-lock that bypasses the Playtest fixes 2 recovery. The recovery
(BUG-024 fix) only protects a ball that NEVER crosses LAUNCH_REACHED_PLAY_Z (z=20.0). A ball that
transiently crosses (e.g. driven by a flipper from the main field back through the guide gap) then
rolls back into the lane promotes to BALL_IN_PLAY via notify_ball_reached_play(), after which:
  - The watchdog stops running (it only runs in LAUNCHING state).
  - The plunger is DISARMED (arm() is only called by request_new_ball/request_relaunch, which
    only fire from READY_TO_LAUNCH transitions: on_ball_drained, on_launch_failed, start_game).
  - The ball rolls back into the lane and rests between the solid plunger face (z=23.6) and the
    solid lane pocket (z=24.5). The ball is physically trapped.
  - The flippers have no reach into the lane (ball at x=15, flippers at x=+/-7.2). No input works.
  - The player must rely on a timeout or external reset that does not exist in BALL_IN_PLAY.
  - SOFT-LOCK: the session is dead until the player quits.

This edge case can occur when:
  a) A ball re-enters the launch-lane channel from the gap zone (x=[9.0, 14.0] near z=19.0),
     crossing ball_local_z < 20.0 in the main field, then rolling back +Z into the lane.
  b) A ball with very low speed enters the playfield (z just below 20.0) and gravity reverses it.

Note: with PLUNGER_STROKE_SPEED_MIN = 35 u/s and lane length = 3 units, the minimum launch speed
(12.1 u/s needed to just cross z=20.0) is lower than the minimum stroke speed, so a direct-launch
transient crossing is NOT possible from the plunger alone. The soft-lock requires the ball to
re-enter the play zone from the side (via the gap zone gap from BUG-029).

Files and lines:
- /home/virus/pinball-game/scripts/game_flow.gd lines 127-137: tick_launch_watch - once the ball
  crosses z < LAUNCH_REACHED_PLAY_Z the LAUNCHING state is exited permanently. No reversal.
- /home/virus/pinball-game/scripts/game_flow.gd lines 143-146: notify_ball_reached_play - sets
  state = BALL_IN_PLAY with an idempotent guard; once set, never reverts to LAUNCHING.
- /home/virus/pinball-game/scripts/plunger.gd lines 258-269: _do_launch - _armed = false on
  launch. arm() is only called from request_new_ball/request_relaunch signals (game_flow.gd).
  BALL_IN_PLAY state never emits either signal, so the plunger cannot be re-armed.
- /home/virus/pinball-game/tests/test_soft_lock_recovery.gd: no test covers the scenario where
  the ball transiently crosses the play line and then rolls back. The existing tests cover:
  (a) ball never crosses (watchdog recovers); (b) ball crosses and stays in play (normal).

Repro steps (requires BUG-029 gap to exist to make the scenario reachable):
1. Launch the ball at any power. Ball enters the main field.
2. Direct the ball toward the right side such that it enters the gap zone (x=[9.4, 13.6],
   z=[19.0, 20.0]) - the small up-table portion of the gap.
3. The ball crosses z < 20.0 (LAUNCH_REACHED_PLAY_Z) briefly while in the gap.
4. tick_launch_watch sees z < 20.0 -> notify_ball_reached_play() -> BALL_IN_PLAY.
5. The ball loses speed and gravity pulls it back +Z (down-table) into the lane.
6. Ball rests in lane at z~23.0. State = BALL_IN_PLAY. Plunger = DISARMED. SOFT-LOCK.

Expected: if the ball returns to the lane after crossing the play line (a state the design intent
calls "reached play"), the game should have a recovery mechanism - either the drain/OOB catches
it, or a watchdog in BALL_IN_PLAY detects a lane-zone ball and triggers on_ball_drained().

Actual: the ball is in BALL_IN_PLAY but trapped in the lane. Neither drain nor OOB fires (ball is
on the surface at z=23.0, not at z>25 or y<-20). No timer recovers BALL_IN_PLAY. Dead session.

Note: the likelihood of this specific repro depends on BUG-029 being present. Fixing BUG-029
(closing the gap zone) may eliminate the primary way to trigger this scenario.

Suggested GUT test to lock awareness of this edge case:
  In test_soft_lock_recovery.gd: add test_transient_crossing_then_roll_back_does_not_soft_lock.
  Feed tick_launch_watch with IN_PLAY_Z for one tick (triggers notify_ball_reached_play -> BALL_IN_PLAY),
  then call on_ball_drained() directly (simulating the OOB catching the ball). Assert state returns
  to READY_TO_LAUNCH and balls_changed fires. This validates the RECOVERY PATH for a ball that
  transiently crossed and then fell off-table (the expected safe recovery), NOT the stuck-lane case.

RESOLVED 2026-06-20 (lead polish, root-cause fix): the false-promotion that enabled this edge case
came from LAUNCH_REACHED_PLAY_Z sitting at the flipper-pivot row (z=20.0), close enough that a ball
draining down a SIDE channel could transiently dip its center across it. FIX: moved the reached-play
line UP-TABLE of the slingshot row (FLIPPER_PIVOT_Z - 3.5 = 16.5) in TableConfig. A ball that
genuinely reached play (climbed the lane, came over the arch) is far up-table of 16.5; a dribble or a
side-roll cannot reach up-table of the slingshots without being kicked back into play (which IS
reaching play). So the watchdog no longer falsely promotes on a transient crossing, and the
specific stuck-lane soft-lock this describes is no longer reachable. Combined with the BUG-029
write-up (the side band is a designed outlane), the transient-crossing path is closed. The repro's
"directly call on_ball_drained" recovery path is also still valid (OOB spends a genuinely off-table
ball). NOT added: a BALL_IN_PLAY lane-zone watchdog - DESIGN scopes recovery to "a ball that NEVER
reached play"; a true in-play-then-stuck ball is out of this slice's scope (and is now unreachable
via this path).

---

### BUG-032 [LOW] Slingshot top-cap winding for the mirrored right slingshot uses forward winding for both sides - top cap faces -Y (into table surface), bottom cap faces +Y (up): caps are culled or lit incorrectly

Severity: LOW - visual only; no physics or game-state impact. The slingshot mesh in
_build_triangle_mesh (slingshot.gd lines 183-188) adds the top cap (at +half_h) wound
A->B->C (counterclockwise when viewed from +Y = from above) and the bottom cap (at -half_h)
wound A->C->B (CW from below). Winding is consistent for the LEFT slingshot (right-hand triangle).
For the RIGHT slingshot (mirrored, apex at C=(-2.5, -2.75) instead of +(2.5, -2.75)), the outline
order changes handedness. With generate_normals(), the computed cap normals may flip, making the
top cap face down (-Y) and the bottom cap face up (+Y). With back-face culling the top cap is
culled (invisible when viewed from above) and the bottom cap is visible from below (inside table).
Since the game uses a playfield-top camera, the top caps of the right slingshot will be invisible.

Files and lines:
- /home/virus/pinball-game/scripts/slingshot.gd lines 162-194: _build_triangle_mesh
- /home/virus/pinball-game/scripts/slingshot.gd lines 115-127: _triangle_outline() - the apex X
  flips sign between left (hand_sign=+1, apex at +2.5) and right (hand_sign=-1, apex at -2.5),
  changing the winding handedness of the CCW-labelled outline.
- /home/virus/pinball-game/scripts/flipper.gd: _emit_tri has a _flip flag that correctly handles
  this for the mirrored right flipper. The slingshot mesh builder has no equivalent flip guard.

Repro (trace):
1. Open slingshot.gd _triangle_outline() for the right sling (mirrored=true).
   Corners: A=(-2.5, 0.4), B=(2.5, 0.4), C=(-2.5, -2.75).  (apex_x=-2.5 for right side)
2. _build_triangle_mesh top cap: adds A, B, C in order at +half_h.
   Cross product (B-A) x (C-A) = (5,0) x (0,-3.15) = (0,0, -15.75). This points in -Z (local),
   which maps to -Y in world space (into the table). The top cap faces DOWN into the surface.
3. With generate_normals(), the computed normal for the top cap triangle will be -Y.
   If StandardMaterial3D has cull_back enabled (default), the top cap is culled when viewed from +Y.

Expected: the top cap of both slingshots (left and right) should face +Y (up, toward the player's
camera). The mesh should be fully visible from a top-down or angled-top camera.

Actual: the right slingshot's top cap winding is reversed due to apex position mirroring. The cap
faces downward (-Y) and may be culled from the player's viewpoint.

Fix direction: in _build_triangle_mesh, detect the mirrored case (_mirrored flag) and emit the top
cap in reversed winding order (A->C->B instead of A->B->C) for the right slingshot, matching the
flipper.gd _emit_tri _flip pattern. Or compute the winding explicitly from the cross product sign
and choose the order that gives +Y. generate_normals() will then compute the correct up-facing normal.

Suggested GUT test to lock the fix:
  No existing test asserts cap face direction. Add a structural test in test_slingshot.gd that
  iterates the ArrayMesh surface to read computed normals and asserts all triangle normals have
  Y > 0 (top cap faces up). This requires enabling Mesh::ARRAY_NORMAL in the vertex array.

RESOLVED 2026-06-20 (lead polish - NOT REPRODUCIBLE as written, hardened anyway): re-deriving the
cross product in actual 3D (the outline (x, z) becomes Vector3(x, half_h, z), so the cap triangle
lies in a constant-Y plane) gives the top-cap normal Y-component = +15.75 for BOTH the left AND the
right slingshot - the cap already faces UP on both sides. The repro's "-Y" conclusion is a sign error
in the 2D X-Z cross-product reasoning (an X-Z cross with constant Y maps to +Y here, not -Y). The
mirror flips only apex_x, and A/B (the kicking-face vertices) are fixed on the same z-line, so the
outline's winding SIGN does NOT flip (unlike flipper.gd, where the WHOLE outline is X-negated). So
there is no actual visual defect. HARDENED REGARDLESS: _build_triangle_mesh now orients each cap from
the outline's signed area (new _signed_area_xz helper) so the top cap is guaranteed +Y and the bottom
-Y for ANY future outline change, with no per-side flag to thread. Result is identical (correct) for
today's geometry; the code is now robust to the class of bug QA was guarding against.

---

## Stream 3 - Regression sweeps (re-verify after changes)
- SLICE Table reshape: THE RUNNER IS RED. The slice HAS now been through CI (PR #10, run
  27858434688 on the pushed sha) and it FAILED: 6 failing tests (see BUG-026/027/028). The producer
  gate (GREEN CI on the pushed sha) CANNOT pass on this sha. Blockers to clear before re-review:
  (1) BUG-026 - the launch does not fire (4 plunger_launch reds; the ball settles past the face so
      is_touching is false and no impulse fires). This is the slice's #1 reason to exist; it is dead.
  (2) BUG-028 - BUG-023 is NOT actually fixed at runtime (cradle still drains) despite the config
      assert passing.
  (3) BUG-027 - the resized-target stress gate has a stale POST_RADIUS (1.5 vs 2.0) and is red.
  After fixes: re-confirm test_world_scale drain asserts AND test_table_integration cradle behavior,
  test_lane_pocket_drain (center still drains, lane does not), test_plunger_launch (all behavioral +
  stress green with a REAL launch), test_target_no_tunneling at the 2.0 post, and a full headless GUT
  run GREEN ON THE RUNNER. Re-derive green from the runner artifact, never from a BACKLOG note.
- SLICE core-interactions-physics: after BUG-012/013/015 fixes land, re-run the FULL GUT suite on
  the runner (not just the slice files) and confirm the pre-slice gates stay green: test_ball_tunneling.gd,
  test_flipper_momentum.gd, test_plunger.gd contract (the five tests that still pass), test_game_flow.gd,
  test_world_scale.gd. The slice touched shared physics config (table_config.gd) so a flipper/world-scale
  regression is possible.
- SLICE real-pinball-furniture: after BUG-018 (detector coverage) and BUG-019 (rubber rebound test
  geometry) fixes land, re-run the FULL slice test suite and confirm: test_pop_bumper.gd,
  test_slingshot.gd, test_active_kicker_no_tunneling.gd, test_flipper_rubber.gd,
  test_furniture_layout.gd, test_shot_geometry.gd all green on the runner. BUG-019 fix must not
  change BAT_BOUNCE; verify test_flipper_momentum.gd stays green (the swing-vs-tap ratio is the
  regression canary for any BAT_BOUNCE or drive-force change).

## How QA stays unblocked (the independence rule in practice)
When there is no new code to test, QA does NOT idle. It (a) writes tests against agreed function
signatures and contracts before the code exists, (b) hardens existing coverage and adds edge cases,
and (c) audits DESIGN.md and the code for testability gaps. There is always test-debt to pull.
