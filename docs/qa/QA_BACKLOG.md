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

## Stream 3 - Regression sweeps (re-verify after changes)
- SLICE core-interactions-physics: after BUG-012/013/015 fixes land, re-run the FULL GUT suite on
  the runner (not just the slice files) and confirm the pre-slice gates stay green: test_ball_tunneling.gd,
  test_flipper_momentum.gd, test_plunger.gd contract (the five tests that still pass), test_game_flow.gd,
  test_world_scale.gd. The slice touched shared physics config (table_config.gd) so a flipper/world-scale
  regression is possible.

## How QA stays unblocked (the independence rule in practice)
When there is no new code to test, QA does NOT idle. It (a) writes tests against agreed function
signatures and contracts before the code exists, (b) hardens existing coverage and adds edge cases,
and (c) audits DESIGN.md and the code for testability gaps. There is always test-debt to pull.
