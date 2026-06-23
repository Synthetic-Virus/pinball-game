# Development Backlog
Shared task queue. The lead-programmer turns design items into small technical tasks here; coders
pull from here. Keep items small and finishable. Each task names an owner agent and an acceptance check.

## Now (milestone: gray-box prototype -> Gate 0)
- [ ] DEVOPS: provision the self-hosted Godot runner on a homelab Docker host; generate Godot export
      presets (Web, Windows); install the GUT test addon (addons/gut). Owner: devops-engineer.
      Acceptance: a push to main runs the pipeline green and publishes the web demo URL.
- [ ] DESIGN: fill DESIGN.md one-sentence pitch + core loop. Owner: game-designer.
- [ ] PHYSICS: gray-box table - ball + two flippers + outer walls. Owner: physics-programmer.
      Acceptance: full-power flip into a wall repeated 100x with ZERO tunneling; continuous_cd on;
      physics tick >= 120 (verified by a GUT test that runs on the runner).
- [ ] GAMEPLAY: launch the ball, detect drain, track ball count, show a basic score.
      Owner: gameplay-programmer. Acceptance: 3 balls, score increments on target hit,
      game ends at zero balls.
- [ ] UX: minimal HUD (score + balls remaining) and a launch control. Owner: ux-designer.
- [ ] PRODUCER: schedule the Gate 0 fun check once the above land. Owner: producer.

## Next (filled in only after Gate 0 passes)
-

## SLICE: Make the core interactions PHYSICS-BASED (gray-box) - run through the * team
Convert three EXISTING fake/trigger interactions into REAL physics. NO new features. Design intent
confirmed in DESIGN.md ("Slice design intent: make the core interactions physics-based"). Flow:
game-designer (DONE - intent below) -> lead-programmer (shared-physics impact: layers/masks/materials)
-> physics-programmer (owns correctness + stress tests) -> gameplay-programmer (plunger contract,
target scoring) -> test-builder + qa-lead (GUT structural/behavioral/stress) -> review board ->
producer (scope/finish gate). Push to a branch / PR; do NOT merge to main inside the slice.

Reference prototype to review (ADOPT/IMPROVE/REPLACE, NOT gate-passed): git branch
prototype/physical-plunger (new TableConfig pocket/stroke constants, _build_lane_pocket in
table_geometry.gd, AnimatableBody3D face + stroke state machine in plunger.gd, tests/test_plunger_launch.gd).

Tasks (pull from here):
- [x] LEAD: audit shared physics (collision layers/masks, physics materials) for the lane pocket,
      physical plunger face, and physical targets so they interoperate with ball/flippers/walls.
      Acceptance: documented in ARCHITECTURE.md; flipper tests stay green after the changes.
      Owner: lead-programmer.
      DONE 2026-06-19 (architecture + scaffolds): ARCHITECTURE.md section 9 records the shared-physics
      audit + the per-conversion design. KEY RESULTS: (1) NO new physics layer and NO mask change -
      every new body reuses existing PhysicsLayers (lane pocket + target deflector = STATIC_OBSTACLES,
      plunger face = KINEMATIC_OBSTACLES), so the flipper tests cannot regress from a layer/mask edit
      (there is none). (2) Three LOCAL physics materials, none shared/global: ball (unchanged), plunger
      face (clean transfer), target deflector (the ONE new feel knob - near-elastic bounce that
      preserves the ball's momentum via the SOLVER, replacing the old manual velocity kick). (3) The
      physical-TARGET design that resolves "a StaticBody cannot detect contact": target.gd ROOT stays
      an Area3D DETECTOR (public contract + table.gd's Array[Area3D] unchanged) wrapping a child
      StaticBody3D DEFLECTOR (the solid post the ball bounces off); delete the manual kick, the solver
      bounces. (4) Adopt the prototype/physical-plunger branch for the lane pocket + plunger face +
      its test (sound, not gate-passed). DISJOINT file-ownership split + the test matrix are in
      ARCHITECTURE.md 9.6/9.7. Four NEW test skeletons scaffolded (gdlint clean, lines <= 100):
      tests/test_lane_pocket_drain.gd, tests/test_target_physical.gd, tests/test_target_no_tunneling.gd
      (structural asserts pass now; behavioral/stress are pending() with the exact asserts spelled out),
      plus adopt tests/test_plunger_launch.gd from the prototype.
- [x] PHYSICS: launch-lane bottom pocket - a static stop across ONLY the lane in X (near z=+HALF_LENGTH)
      that rests the ball in the chute and leaves x in [-HALF_WIDTH, LANE_INNER_X] OPEN for the drain.
      ARCHITECTURE: adopt _build_lane_pocket + the LANE_POCKET_* constants from the prototype branch
      (ARCHITECTURE.md 9.3). Acceptance: GUT test (tests/test_lane_pocket_drain.gd) - ball placed at
      BALL_START comes to rest in the lane (does not exit the bottom); a ball at center-X still reaches
      the drain (the pocket did not close the center). Owner: physics-programmer +
      gameplay-programmer (the center-still-drains half) + test-builder.
      DONE 2026-06-19 (lead polish pass, QA BUG-012): the _build_lane_pocket builder was DROPPED during
      the original slice integration (build() called surface/walls/divider/arch only). Restored from
      prototype/physical-plunger and wired into TableGeometry.build() so the ball actually rests in the
      lane in the integrated game, not just the unit test. Verified the pocket -X face (x=7.6) clears
      the structural center-drain guard (minimum 7.2).
- [ ] PHYSICS+GAMEPLAY: physical plunger - a collision body (AnimatableBody3D on KINEMATIC_OBSTACLES,
      like flippers) that STRIKES the resting ball; the existing meter (power 0..1) maps to strike
      strength so the launched ball ends in LAUNCH_SPEED_MIN..MAX. PRESERVE the contract
      (power_changed/ball_launched; arm/disarm/set_ball/is_armed) exactly. Owner: physics-
      programmer (internal strike) + gameplay-programmer (contract re-verify).
      ARCHITECTURE: ADOPT the prototype/physical-plunger version of scripts/plunger.gd +
      scripts/table_geometry.gd._build_lane_pocket + the TableConfig pocket/stroke constants onto the
      slice branch (sound, well-commented, not gate-passed - see ARCHITECTURE.md 9.3). The one
      TableConfig edit (ADD pocket/stroke/face/rest constants, no existing value changes) is the
      physics-programmer's, reviewed by lead. Then own correctness + the stress asserts.
      Acceptance: GUT behavioral test (adopt tests/test_plunger_launch.gd) - a strike imparts velocity
      FROM REST with NO call to ball.launch() (production launch must come from the contact, not a
      velocity set - assert this), full strike out-throws a weak one (>=1.5x), resulting speed in
      ~LAUNCH_SPEED_MIN..MAX; launch with no ball is a no-op; max strike never tunnels the face/pocket;
      existing test_plunger.gd contract tests stay green.
      LEAD POLISH 2026-06-19 (QA BUG-013/015/017): (1) table.gd was DOUBLE-OFFSETTING the plunger -
      it set plunger.position = BALL_START, but plunger.gd seats its face at the playfield-LOCAL
      PLUNGER_REST_POS assuming the node sits at the playfield origin; the face landed off the table and
      never struck the ball. Fixed: plunger.position = Vector3.ZERO (the contract test_plunger_launch.gd
      already honored). (2) BUG-015: the four test_plunger.gd tests still asserted ball.launch() was
      called (the deleted fake path) - converted to assert the plunger-side contract the physical strike
      honors (ball_launched once, disarm, stroke begun, power -> stroke_speed monotonic via the new
      stroke_speed() test hook; the ball-speed oracle stays in test_plunger_launch.gd). (3) BUG-017:
      ball.launch() demoted from STABLE CONTRACT to a documented dead-in-production velocity helper so it
      is not re-wired into the plunger.
- [~] GAMEPLAY+PHYSICS: physical targets - convert the 3 Area3D pass-through targets to physical
      bodies that deflect the ball and score ON CONTACT, keeping BUG-007 cooldown and momentum.
      ARCHITECTURE (ARCHITECTURE.md 9.4): target.gd ROOT stays an Area3D DETECTOR (public contract +
      table.gd's Array[Area3D] UNCHANGED) with a child StaticBody3D "Deflector" on STATIC_OBSTACLES
      and a near-elastic PhysicsMaterial. DELETE the old manual velocity kick - the SOLVER bounces the
      ball now (this is what preserves momentum, the designer's #1 fun risk). SPLIT (keep the one
      shared file disjoint in practice): gameplay owns the detector/scoring/cooldown half
      (_on_body_entered, scored.emit, RETRIGGER_COOLDOWN_S - land the kick-deletion first); physics
      owns the deflector half (_build_deflector child body, shape, bounce tuning, the no-trap
      guarantee - land second). Same 3 positions, flat 100 points, no multipliers.
      Acceptance: GUT tests (tests/test_target_physical.gd structural+behavioral;
      tests/test_target_no_tunneling.gd stress) - ball physically bounces off (measured direction
      change AND momentum kept, not killed), scores once per contact, cooldown blocks per-frame
      farming, no pass-through, no tunneling at >= ~2x LAUNCH_SPEED_MAX. Owner: gameplay-
      programmer + physics-programmer.
      GAMEPLAY HALF DONE 2026-06-19 (slice/physical-interactions): scripts/target.gd - manual
      velocity kick DELETED; Area3D is now the detector shell (collision_layer=0,
      collision_mask=BALLS); detector CylinderShape3D radius = POST_RADIUS + BALL_RADIUS (wider
      than the solid post so body_entered fires on approach); scored.emit in body_entered with
      RETRIGGER_COOLDOWN_S dead time unchanged; _build_deflector() stub added for physics-programmer
      to fill (child StaticBody3D "Deflector" on STATIC_OBSTACLES). Public contract preserved
      byte-for-byte (signal scored, method set_ball, export points). test_lane_pocket_drain.gd
      structural test for pocket X-extent filled. BLOCKED on physics-programmer: _build_deflector
      body + PhysicsMaterial; test_target_physical.gd behavioral tests; test_target_no_tunneling.gd.
- [x] TEST/QA (QA BUG-014): integration test that instances the REAL Table.tscn and asserts table.gd's
      wiring - the two slice blockers (missing lane pocket, double-offset plunger) slipped through CI
      because every other slice test bypasses table.gd. Owner: lead-programmer (folded into the
      polish pass) + test-builder. DONE 2026-06-19: tests/test_table_integration.gd instances
      res://scenes/Table.tscn and asserts (a) a LanePocket StaticBody3D on STATIC_OBSTACLES exists,
      (b) the PlungerFace, mapped from world space back into playfield-local, sits inside the lane in X
      and at PLUNGER_REST_POS.z (catches the double-offset), and (c) the real ball settles and stays in
      the lane. Written to FAIL pre-fix and PASS post-fix (locks both blockers closed).
- [ ] PHYSICS: VERIFY flippers still impart real momentum (no redesign). Acceptance: existing
      test_flipper_momentum.gd stays green after the shared-physics changes. Owner: physics-programmer.
- [ ] PHYSICS/QA: extend GUT stress tests so the fast ball (>= ~2x LAUNCH_SPEED_MAX) does NOT tunnel
      through the plunger face, lane pocket, targets, walls, arch, or flippers, asserted against REAL
      instanced bodies measuring real position/velocity (independent-oracle, never a counter).
      FILES: tests/test_target_no_tunneling.gd (target post, scaffolded - fill the loop);
      tests/test_plunger_launch.gd (face + pocket, adopt from prototype); test_ball_tunneling.gd stays
      green (the flat-wall headline gate, unchanged). Acceptance: stress suite GREEN on the homelab
      godot runner (the artifact, not a doc claim). Owner: physics-programmer + qa-lead.
- [ ] PRODUCER: scope/finish gate. Confirm scope held (no new features) and both physics-first claims
      are GREEN on the runner before any merge to main. Owner: producer.

## SLICE: Real pinball furniture (rubber flippers + active pop bumpers + slingshots) - * team
Add the first REAL pinball furniture on the physics foundation: rubber-wrapped flippers, active pop
bumpers, slingshots, one standup target bank, and minimal inlane/outlane guides, in a representative
(NOT commercial) layout. Every interaction physics-based. Design intent confirmed in DESIGN.md
("Slice design intent: real pinball furniture"). References recorded in REFERENCES.md (two open-source
repos consulted: prior art uses PASSIVE restitution; we deliberately use an ACTIVE capped+cooled
impulse per the developer's "contract to shoot the ball away"). Flow: game-designer (DONE - intent
below) -> lead-programmer (TableConfig placement constants + shared physics layers + table_viz shot
validation) -> physics-programmer (owns the active-kick impulse cap, rubber material, correctness +
tunneling stress tests) -> gameplay-programmer (scoring + cooldown on each active element + standup
bank) -> test-builder + qa-lead (structural/behavioral/stress GUT, independent oracle) -> review board
-> producer (scope/finish gate, GREEN CI on the pushed sha). Push to a branch / PR; do NOT merge to
main inside the slice.

Tasks (pull from here - keep them small and finishable):
- [x] LEAD: ADD the placement/feel constants to TableConfig (no existing value changes): pop-bumper
      centers/radius/height, slingshot positions/angles, standup-bank positions, inlane/outlane guide
      geometry, KICK_IMPULSE (with a CCD-safe cap and a minimum outgoing speed), and the per-element
      RETRIGGER cooldown seconds. Audit shared physics layers so every new body interoperates with
      ball/flippers/walls (reuse existing PhysicsLayers; document any addition in ARCHITECTURE.md).
      Owner: lead-programmer. Acceptance: constants documented with the WHY; flipper tests
      stay green after the layer audit; numbers honor the world-scale contract.
      DONE 2026-06-19 (architecture + scaffolds): ARCHITECTURE.md section 10 records the slice
      contract. KEY RESULTS: (1) NO new physics layer and NO mask change - every new body reuses the
      existing PhysicsLayers (pop-bumper/slingshot/standup-bank SOLID bodies = STATIC_OBSTACLES,
      detectors = Area3D on the BALLS mask, lane guides = STATIC_OBSTACLES), so the flipper tests
      cannot regress from a layer/mask edit (there is none). (2) The furniture block was ADDED to
      table_config.gd with NO existing value changed: KICK_IMPULSE_SPEED/MIN/MAX (the cap is strictly
      inside the 2x LAUNCH_SPEED_MAX stress band) + KICK_COOLDOWN_S, POP_BUMPER_* (3 positions),
      SLINGSHOT_* (2 positions + per-side kick dirs), STANDUP_BANK_POSITIONS (re-homes the 3 targets),
      LANE_GUIDE_*. (3) The ACTIVE-KICK family is a shared base scripts/active_kicker.gd (extends
      Area3D) with pop_bumper.gd + slingshot.gd overriding only the kick DIRECTION; the gameplay half
      (detector/cooldown/score) is scaffolded, the physics half (_build_body + _apply_kick) is two
      clearly-marked TODOs. table.gd instances + wires the new elements; table_geometry.gd builds the
      lane guides. DISJOINT file-ownership split + the test matrix are in ARCHITECTURE.md 10.5/10.6.
      Six NEW test skeletons scaffolded (gdlint clean, lines <= 100): test_pop_bumper.gd,
      test_slingshot.gd, test_active_kicker_no_tunneling.gd, test_flipper_rubber.gd,
      test_furniture_layout.gd, test_shot_geometry.gd (structural asserts pass now; behavioral/stress
      FAIL until the physics half lands - intended).
- [x] LEAD/QA: EXTEND tools/table_viz.py for CAD-style shot validation: plot the flipper-tip sweep arc
      and assert it reaches the standup bank / feeds the bumper cluster; plot each pop-bumper and
      slingshot kick-direction vector and assert it points into play (up-table/toward center), NOT
      into the drain or a wall; plot the inlane/outlane feed paths. Owner: lead-programmer +
      qa-lead. Acceptance: a deterministic check (a small Python assert or a GUT geometry
      test) FAILS if a bumper/sling kick aims at the drain or a target sits outside flipper reach.
      DONE 2026-06-19: table_viz.py now draws the pop-bumper radial-kick fans, the slingshot kick
      vectors, the standup bank, the lane-guide dividers, and the flipper-tip sweep arc on the
      top-down view, AND validate_layout() EXITS NON-ZERO if any kick aims at the drain, a standup
      target sits outside the makeable window (flipper-tip reach .. arch base), a pop bumper fouls a
      wall, or the kick bounds fall outside the CCD-safe band. The GUT twin is tests/test_shot_geometry.gd
      (same checks, the CI source of truth). Verified: the tool PASSES on the chosen constants
      (3 bumpers, 3 standup targets, 2 slings, kicks into play) and FAILS when a standup target is
      moved out of the makeable window.
- [ ] PHYSICS: RUBBER-WRAP the flippers - add a rubber bounce surface to the existing flipper collider
      via PhysicsMaterial / a rubber edge. Do NOT touch the force/hinge/return-spring drive.
      Owner: physics-programmer. Acceptance: a GUT behavioral test shows a ball rebounds off
      the flipper face PRESERVING momentum (fast stays fast); test_flipper_momentum.gd, the snap
      timing test, and test_flipper_no_overlap stay GREEN unchanged.
- [~] PHYSICS+GAMEPLAY: ACTIVE POP BUMPERS - 2-3 round bumper bodies in the upper-middle that, on
      ball contact, apply an outward IMPULSE (away from center along the contact normal), capped
      CCD-safe with a minimum outgoing speed, and score once per contact with a re-trigger cooldown.
      Physics owns the body/shape/impulse/cap/no-tunnel; gameplay owns the detector/score/cooldown.
      Owner: physics-programmer + gameplay-programmer.
      Acceptance: GUT behavioral test - a ball arriving SLOWLY leaves FAST and directed OUTWARD
      (measured velocity, independent oracle); scores once; cooldown blocks per-frame farming; a
      resting ball is pushed off once, not strobed.
      GAMEPLAY HALF DONE 2026-06-19: active_kicker.gd _on_body_entered - cooldown gate
      (KICK_COOLDOWN_S), kick-direction dispatch (_kick_direction_for), _apply_kick call, kicked.emit,
      scored.emit. _apply_kick implemented: velocity SET to direction * clamp(KICK_IMPULSE_SPEED,
      MIN, MAX), floored/capped, angular velocity zeroed, ball woken. _build_body implemented:
      child StaticBody3D "KickerBody" on STATIC_OBSTACLES, shape from _make_body_shape(),
      rotated by _body_yaw(), local PhysicsMaterial (KICKER_BOUNCE=0.5, KICKER_FRICTION=0.2).
      Lint-clean. BLOCKED on physics-programmer: stress + behavioral CI green (runner artifact).
- [~] PHYSICS+GAMEPLAY: SLINGSHOTS - one angled active kicker above each flipper (2 total) that, on
      contact, kicks the ball UP-and-into-play (never toward the drain), capped CCD-safe, scores
      with cooldown. Same active-kick family as the pop bumpers (shares active_kicker.gd base).
      Owner: physics-programmer + gameplay-programmer.
      Acceptance: GUT behavioral test - a ball dropping down the side contacts the sling and leaves
      with a velocity whose up-table (-Z) and toward-center components are positive (measured); scores
      once; cooldown holds.
      GAMEPLAY HALF DONE 2026-06-19: shared via active_kicker.gd (same as pop bumpers above).
      slingshot.gd _kick_direction_for returns the fixed per-side kick direction (from TableConfig
      SLINGSHOT_LEFT/RIGHT_KICK_DIR, validated by table_viz to point into play). Lint-clean.
      BLOCKED on physics-programmer: solid body / stress / behavioral CI green (runner artifact).
- [x] GAMEPLAY: STANDUP TARGET BANK + INLANE/OUTLANE GUIDES - a small physical standup bank (reuse /
      re-home the existing physical target body) on the mid-field at a flipper-makeable position, plus
      minimal physical inlane/outlane guide walls down both sides (outer outlane feeds the drain,
      inner inlane feeds back toward the flipper). NO rollover scoring, lights, or ball-save.
      Owner: gameplay-programmer.
      Acceptance: GUT test - standup bank scores on contact and is reachable from a flipper sweep
      (per table_viz validation); a ball placed in the outlane reaches the drain and a ball in the
      inlane returns toward the flipper.
      DONE 2026-06-19: standup bank = target.gd physical targets re-homed to
      STANDUP_BANK_POSITIONS in table.gd; scored(points) fires on contact via existing
      _build_deflector + _on_body_entered in target.gd (gameplay half complete, deflector already
      implemented in the prior slice). Inlane/outlane guide walls built by table_geometry.gd
      _build_lane_guides (lead's geometry, named LaneGuideLeft/LaneGuideRight on STATIC_OBSTACLES).
      test_furniture_layout.gd asserts both. All lint-clean.
- [ ] PHYSICS/QA: STRESS - extend the GUT no-tunneling suite so the fast ball (>= ~2x
      LAUNCH_SPEED_MAX, including AFTER an active kick) does not tunnel through any new body (pop
      bumpers, slingshots, standup bank, lane guides) or the rubber flipper, asserted against REAL
      instanced bodies measuring real position/velocity. Owner: physics-programmer +
      qa-lead. Acceptance: stress suite GREEN on the homelab godot runner (the artifact).
- [ ] PRODUCER: scope/finish gate. Confirm scope held (representative subset only, no ramps/modes/
      multiball/art/audio/rollover scoring) and that the active-kick + no-tunnel claims are GREEN on
      the runner on the pushed sha before any merge to main. Owner: producer.

## SLICE: Table reshape + playtest fixes (gray-box, physics-based) - * team
FIRST playtest-driven slice: the developer played the deployed homelab build and reported five
concrete problems. Fix all five in ONE slice. NO new mechanics or element types - only shape, size,
spacing, and table width change. Design intent confirmed in DESIGN.md ("Slice design intent: Table
reshape + playtest fixes"). Cut list in DESIGN.md ("Cut from the Table reshape + playtest fixes
slice"). Flow: game-designer (DONE - intent below) -> lead-programmer (HALF_WIDTH rescale + every
dependent constant + table_viz re-validation) -> physics-programmer (plunger launch mechanism, capsule
flipper collider, no-tunnel stress) -> gameplay-programmer (target/bumper resize+respace wiring) ->
test-builder + qa-lead (structural/behavioral/stress, independent oracle) -> review board -> producer
(scope/finish gate, GREEN CI on the pushed sha). The team's Setup phase creates the slice branch;
build/QA agents COMMIT but do NOT push; Deliver verifies GREEN locally (fetch headless Godot, run GUT)
then pushes ONE PR. Do NOT touch main.

Tasks (pull from here - keep them small and finishable):
- [ ] PHYSICS+GAMEPLAY: FIX THE LAUNCH (the #1 fix - the plunger does not fire). ROOT CAUSE: the
      kinematic AnimatableBody3D relies on sync_to_physics to shove the ball (scripts/plunger.gd
      _build_face / _advance_stroke), which in Godot Jolt often does NOT transfer momentum, so the ball
      never moves. Replace with a working mechanism: apply an impulse to the ball on the plunger-ball
      contact, OR drive the face with a reported/constant_linear_velocity (or move_and_collide) that
      genuinely imparts velocity. PRESERVE the contract EXACTLY (signals power_changed/ball_launched;
      methods arm/disarm/set_ball/is_armed; power 0..1; oscillating meter; power->launch-speed mapping
      so the ball lands in ~LAUNCH_SPEED_MIN..MAX). Keep the plunger body visible and seated in the
      lane behind the ball. Production launch must come from the contact/impulse, NOT a code velocity
      set on the ball. Owner: physics-programmer (mechanism) + gameplay-programmer
      (contract re-verify). Files: scripts/plunger.gd, scripts/ball.gd, scripts/config/table_config.gd.
      Acceptance: tests/test_plunger_launch.gd - a release imparts REAL measured velocity FROM REST,
      full strike out-throws a weak one (>=1.5x), resulting speed in ~LAUNCH_SPEED_MIN..MAX, no-ball is
      a no-op, max strike never tunnels the face/pocket; test_plunger.gd contract tests stay green.
- [ ] PHYSICS: CAPSULE FLIPPERS (real flipper shape). Replace the BoxMesh/box collider with a tapered
      rounded "stadium" form (fatter at the pivot, smaller rounded tip) in BOTH the collision shape
      (CapsuleShape3D or a convex hull MATCHING the mesh) AND the visible mesh. Material: black body +
      white rubber top surface (2-tone gray-box only; no external art). PRESERVE the force/hinge/
      return-spring drive, configure()/is_energized()/tip_speed()/force_energized(), BAT_MASS 0.40 /
      BAT_BOUNCE 0.70, the ~50 ms snap, the cradle, and _apply_handedness (bat extends toward center
      both sides). Owner: physics-programmer. File: scripts/flipper.gd. Acceptance: a
      structural test asserts the collider is a CAPSULE / convex hull (NOT BoxShape3D);
      test_flipper_momentum.gd (full swing out-throws a tap, ~50 ms snap), test_flipper_rubber.gd
      (rebound >= 35%), test_flipper_no_overlap.gd all stay GREEN; no tunneling.
- [x] LEAD: WIDER TABLE (world-scale rescale). TableConfig.HALF_WIDTH 12.0 -> 16.0 (HALF_LENGTH stays
      25.0). RE-DERIVE every X-dependent constant with a WHY-comment: LANE_INNER_X / LANE_WIDTH,
      FLIPPER_PIVOT_SPREAD (keep the inverted V with a ~1-ball-plus drain gap, not crossed),
      DRAIN_WIDTH / DRAIN_CENTER_X, ARCH_RADIUS_X, LANE_GUIDE_DIVIDER_X, SLINGSHOT_LEFT/RIGHT_POS,
      POP_BUMPER_POSITIONS X, STANDUP_BANK_POSITIONS X, plunger/lane-pocket lane math. Nothing inside a
      wall, off the field, or crossing the centerline. Owner: lead-programmer. Files:
      scripts/config/table_config.gd, scripts/table_geometry.gd. Acceptance: test_world_scale.gd +
      test_furniture_layout.gd updated and GREEN for the new width; flipper-overlap and drain-mouth
      asserts pass; table_viz validate_layout passes on the new constants.
      DONE 2026-06-19 (architecture + rescale): HALF_WIDTH 12 -> 16; LANE_INNER_X 8 -> 10.5 (lane
      width 5.5); FLIPPER_PIVOT_SPREAD 7.0 -> 7.2 (drain mouth held at 2.46 u = ~2 ball-dia, NOT a
      chasm - verified gap = 2*7.2 - 11.94 = 2.46); BALL_START.x re-derived 10.0 -> 13.25 (lane
      center, was a stale literal that would have fallen out of the widened lane); POP_BUMPER_POSITIONS
      +/-4.5 -> +/-6.0; SLINGSHOT_*_POS +/-8.5 -> +/-10.5; STANDUP_BANK_POSITIONS +/-3.0 -> +/-4.5;
      POP_BUMPER_RADIUS 1.6 -> 2.0 (the resize half of #5). ARCH_RADIUS_X / DRAIN_* / LANE_GUIDE_* /
      PLUNGER_REST_POS.x / lane-pocket width / table_geometry perimeter are all HALF_WIDTH/LANE_INNER_X
      EXPRESSIONS, so they auto-follow (no literal X in table_geometry.gd to change - verified). Every
      changed constant carries a WHY-comment; gdlint clean. table_viz.py validate_layout() PASSES on
      the new constants and FAILS on a deliberately-moved standup target (verified). ARCHITECTURE.md
      section 11 records the full rescale + the file-ownership split + the test matrix.
- [ ] LEAD/QA: VERIFY BOTH GUTTERS after the widen (developer reports only a left gutter; both ALREADY
      exist in table_geometry._build_lane_guides + test_furniture_layout, so this is likely a STALE
      CACHED BUILD). Confirm LaneGuideLeft AND LaneGuideRight build on STATIC_OBSTACLES at the new
      spacing and read as outlane/inlane gutters via table_viz; only fix the right one if it is
      genuinely missing/weak. Owner: lead-programmer + qa-lead. File:
      scripts/table_geometry.gd. Acceptance: test_furniture_layout.gd asserts both gutters present on
      the rebuilt scene at the new width; table_viz feed-path plot shows both.
      LEAD VERIFY 2026-06-19: confirmed _build_lane_guides builds BOTH LaneGuideLeft AND
      LaneGuideRight symmetrically (a for-loop over sign [-1, 1]) on STATIC_OBSTACLES, and
      test_furniture_layout.test_lane_guides_present_and_static asserts both. After the widen both
      auto-follow LANE_GUIDE_DIVIDER_X (= HALF_WIDTH - 3.0 = 13.0): the OUTLANE stays ~3.0 u (drain
      risk), the INLANE widens to ~5.8 u (save). The developer's "only a left gutter" is a STALE
      CACHED BUILD: the symmetric code is correct, no edit needed. QA confirms on the rebuilt scene
      via the runner (test_furniture_layout green at the new width) + the table_viz feed-path plot.
- [~] GAMEPLAY+PHYSICS: RESIZE + RESPACE TARGETS AND BUMPERS for the wider table ("too small, not
      spaced well"). Bigger standup targets (target size / post radius up) and bigger pop bumpers
      (POP_BUMPER_RADIUS up), with wider sensible spacing (STANDUP_BANK_POSITIONS, POP_BUMPER_POSITIONS)
      that stays flipper-makeable. Owner: gameplay-programmer (sizes/positions) +
      physics-programmer (no-tunnel on the bigger bodies). Files: scripts/config/table_config.gd,
      scripts/table.gd. Acceptance: tests/test_shot_geometry.gd - standup bank inside the flipper-tip
      sweep window and bumpers clear of walls/arch on the NEW constants; targets/bumpers kick + score on
      contact (behavioral); no tunneling at >= 2x LAUNCH_SPEED_MAX.
      GAMEPLAY HALF DONE 2026-06-19 (slice/table-reshape e131f41): scripts/target.gd POST_RADIUS raised
      1.5 -> 2.0 with WHY-comment. The detector shell (POST_RADIUS + BALL_RADIUS) and the solid deflector
      CylinderShape3D both read from this constant and auto-follow. tests/test_target_physical.gd local
      POST_RADIUS updated to 2.0 to match. POP_BUMPER_RADIUS already raised to 2.0 in TableConfig by the
      lead (the config half of item 5). Plunger public contract re-verified: unchanged byte-for-byte
      (power_changed/ball_launched; arm/disarm/set_ball/is_armed; stroke_speed/face_position/is_stroking
      test hooks all present; no production path sets ball velocity). BLOCKED on physics-programmer:
      no-tunnel re-confirm on the bigger post at >= 2x LAUNCH_SPEED_MAX (test_target_no_tunneling.gd).
- [x] LEAD/QA: EXTEND tools/table_viz.py to re-validate the NEW layout deterministically (CAD method):
      flipper-tip reach to the resized targets/bumpers, lane feeds, drain mouth, both gutter feed paths.
      Tool EXITS NON-ZERO if a shot is unmakeable or a kick aims at the drain. Owner:
      lead-programmer + qa-lead. Acceptance: tool passes on the new constants and fails
      a deliberately-broken one; tests/test_shot_geometry.gd is the GUT twin (CI source of truth).
      DONE 2026-06-19: table_viz.py already PLOTS + validate_layout()-checks the flipper-tip sweep,
      bumper/sling kick vectors, standup window, and lane-guide feed paths; it now re-validates the new
      width (existing checks are all expressed off the parsed constants). Also FIXED a latent crash: the
      tool parsed the removed TARGET_POSITIONS const from table.gd (gone since the bank moved to
      STANDUP_BANK_POSITIONS) - replaced with an empty legacy list so the tool runs. Verified: PASSES on
      the new constants (3 bumpers, 3 standup, 2 slings, kicks into play), FAILS on a moved standup
      target. test_shot_geometry.gd is the GUT source of truth (test-builder updates width asserts).
- [ ] TEST/QA: UPDATE + ADD the independent-oracle suite for the new width/shapes (test the game like a
      web app). STRUCTURAL: flipper collider is a capsule/convex hull (not a box); both gutters on
      correct layers at new spacing; furniture on correct layers at new positions; table width = new
      HALF_WIDTH. BEHAVIORAL: plunger release imparts real measured velocity and launches; rubber
      rebound >= 35%; targets/bumpers kick + score on contact. STRESS: no tunneling at >= ~2x
      LAUNCH_SPEED_MAX on every interaction. Owner: test-builder + qa-lead. Acceptance:
      the updated suite runs GREEN on the homelab godot runner (the artifact, not a doc claim).
      LEAD SCAFFOLD 2026-06-19: tests/test_flipper_shape.gd ADDED (gdlint clean) - the STRUCTURAL
      independent-oracle for the capsule swap: asserts the bat collider is a CapsuleShape3D or
      ConvexPolygonShape3D and NOT a BoxShape3D, the mesh is a matching non-box mesh, and the rubber
      PhysicsMaterial survives the swap. It FAILS against the current box flipper and PASSES once the
      physics-programmer lands the shape swap (intended red-to-green). The width UPDATES
      (test_world_scale / test_furniture_layout / test_shot_geometry for HALF_WIDTH 16) and the
      behavioral/stress VERIFY re-runs are the test-builder's per ARCHITECTURE.md 11.7.
- [ ] PRODUCER: scope/finish gate. Confirm scope held (five fixes only, no new element types/art) and
      that the launch + capsule + width + gutter + resize claims are GREEN on the runner on the pushed
      sha before any merge to main. Owner: producer.

## SLICE: Playtest fixes 2 (gray-box, physics-based) - * team
SECOND playtest-driven slice: the developer played the deployed wider table (main 286356e) and
reported a fresh batch of problems. Fix them in ONE slice. NO new mechanics or element types - only
shape, size, material, and state-logic change. Same element counts (3 bumpers, 3 targets, 2
slingshots, 2 flippers, 1 plunger, 2 gutters). Design intent confirmed in DESIGN.md ("Slice design
intent: Playtest fixes 2"). Cut list in DESIGN.md ("Cut from the Playtest fixes 2 slice"). Flow:
game-designer (DONE - intent below) -> lead-programmer (TableConfig geometry: lane/plunger resize +
any soft-lock threshold constant) -> physics-programmer (soft-lock recovery + resized launch + no-tunnel
stress on the new shapes) -> gameplay-programmer (game-state recovery wiring + HUD/prompt UX) ->
test-builder + qa-lead (structural/behavioral/stress, independent oracle) -> review board -> producer
(scope/finish gate, GREEN CI on the pushed sha). The team's Setup phase creates the slice branch;
build/QA agents COMMIT but do NOT push; Deliver verifies the FULL GUT suite GREEN locally (fetch
headless Godot 4.x) BEFORE pushing ONE PR. Do NOT touch main.

Tasks (pull from here - keep them small and finishable):
- [ ] PHYSICS+GAMEPLAY: FIX THE SOFT-LOCK ON FAILED LAUNCH (the #1 fix - critical correctness). When
      the ball fails to leave the launch lane (a weak launch, or it stalls in the lane and never
      reaches the playfield), the game LOCKS UP: the player cannot relaunch and nothing progresses
      (on_ball_launched -> BALL_IN_PLAY with the plunger disarmed, but the ball never drains, so
      GameFlow never re-arms). FIX the game-state machine + plunger so a ball that does not reach play
      can ALWAYS be relaunched: if, a short settle time after launch, the ball is still in the launch
      lane / below the arch, treat the launch as FAILED and RE-ARM the plunger for the SAME ball
      (re-seat the ball at the cradle if needed). Do NOT spend a ball for a failed launch; do NOT
      change drain behavior for a ball that genuinely reached play. Owner: physics-programmer
      (detect "did not reach play", positional, independent oracle) + gameplay-programmer
      (state recovery + re-arm). Files: scripts/game_flow.gd, scripts/plunger.gd, scripts/ball.gd,
      scripts/config/table_config.gd (the settle-time / arch-line threshold constant with a WHY).
      Acceptance: a NEW behavioral test drives a too-weak launch and asserts the ball is recoverable
      (plunger re-armed AND/OR ball back at the cradle), the ball count was NOT decremented, and there
      is no soft-lock; a normal launch -> BALL_IN_PLAY -> drain path is unchanged and stays green.
- [ ] PHYSICS: FIX THE RIGHT FLIPPER MISSING ITS WHITE RUBBER TOP. The LEFT flipper renders with the
      white rubber top; the RIGHT (mirrored) flipper renders all black (the rubber-top surface is
      dropped/hidden on the right side). The X-mirror of the bat outline (negating X in
      _rebuild_bat_geometry) likely inverts the triangle winding so the white TOP cap (surface 1) faces
      down / is culled on the right bat. FIX so BOTH flippers show the same black body + white rubber
      top: the mirror must not drop or wrong-face the rubber-top material / the mesh normals/UVs on the
      right side. Owner: physics-programmer. File: scripts/flipper.gd. Acceptance: a STRUCTURAL
      test asserts BOTH bats carry the white-rubber-top material/mesh surface (surface count + the
      RUBBER_TOP_COLOR material present, top cap faces +Y) on the right flipper as on the left;
      test_flipper_momentum / test_flipper_rubber / test_flipper_no_overlap / test_flipper_shape stay
      GREEN; no tunneling.
- [ ] PHYSICS+GAMEPLAY: SLINGSHOTS AS TRIANGLES, not boxes. The two active kickers above the flippers
      currently render as small boxes (slingshot.gd _make_body_shape returns a BoxShape3D; the base
      gray-box mesh is a box). Make them proper slingshot TRIANGLES: a left-handed triangle for the
      LEFT flipper and a right-handed (mirrored) triangle for the RIGHT, with the long kicking face
      angled INTO play (toward center-up), like a real pinball slingshot. Update BOTH the collision
      shape (a convex hull / triangular prism) AND the visible mesh to the triangular form; keep the
      existing active-kick behavior, kick DIRECTION (SLINGSHOT_LEFT/RIGHT_KICK_DIR), score, and
      cooldown UNCHANGED. Keep the BUG-018 corner-contact detector guarantee. Owner:
      physics-programmer (triangular body + mesh + no-tunnel) + gameplay-programmer
      (re-verify score/cooldown contract unchanged). Files: scripts/slingshot.gd (and
      scripts/active_kicker.gd if the shape/mesh is built there), scripts/config/table_config.gd.
      Acceptance: STRUCTURAL test asserts the slingshot solid body + mesh are triangular (a convex
      hull / non-box), one per side mirrored; the kick still points into play (table_viz +
      test_shot_geometry); BEHAVIORAL slingshot kick-into-play + score-on-contact stays green; STRESS
      no tunneling at >= ~2x LAUNCH_SPEED_MAX through the triangular face.
- [ ] LEAD+PHYSICS: RESIZE THE LAUNCH RAMP / PLUNGER smaller, to roughly the ball's WIDTH (ball
      diameter ~1.2, radius 0.6). Narrow the plunger face and the launch lane so they line up with the
      ball being launched (currently too wide/bulky). Keep the plunger functional (it must still strike
      + launch the ball reliably on the FIRST stroke) and the stable contract. Owner:
      lead-programmer (TableConfig lane/plunger geometry + re-derive dependents with WHY) +
      physics-programmer (the resized face still strikes head-on, seats in contact, no gap to
      tunnel). Files: scripts/config/table_config.gd (LANE_WIDTH / LANE_INNER_X / PLUNGER_FACE_WIDTH /
      lane-pocket + lane geometry), scripts/plunger.gd, scripts/table_geometry.gd. Acceptance:
      tools/table_viz.py confirms the resized lane lines up with the ball (deterministic, not
      eyeballed); a STRUCTURAL test asserts PLUNGER_FACE_WIDTH and LANE_WIDTH match the new resized
      constants; test_plunger_launch.gd stays green (launch from rest, monotonic, in-range, first
      stroke fires, no tunneling of the resized face); test_world_scale / test_furniture_layout /
      test_table_integration updated for the new lane width and green.
- [ ] GAMEPLAY/UX: FOLD IN THE FOUR PRODUCER-FLAGGED UX ITEMS (Gate-0 readiness; do not fail CI but
      in scope). (5) Re-issue the "HOLD LAUNCH - release to fire" prompt on EVERY ball arm (balls 2
      and 3, not only ball 1). (6) Name the actual restart key in the game-over screen (it is SPACE /
      the launch action). (7) Colorblind-safe power meter: the bar WIDTH is the primary cue; do not
      rely on the green->red color alone. (8) Raise the HUD font size for readability. Owner:
      gameplay-programmer (+ ux-designer input). Files: scripts/hud.gd, scripts/plunger.gd,
      scripts/game_flow.gd. Acceptance: a behavioral test asserts the launch prompt message is emitted
      on every ball arm (not just the first); the game-over text names the restart key; (the meter and
      font items are visual - confirm via the HUD setters and a viz/screenshot check, no CI gate).
- [ ] TEST/QA: UPDATE + ADD the independent-oracle suite (test the game like a web app). STRUCTURAL:
      both flippers carry the white-rubber-top surface; slingshot body+mesh are triangular (non-box);
      plunger face width = resized constant; lane width = resized constant. BEHAVIORAL: too-weak launch
      is recoverable AND does not spend a ball (the soft-lock test); full-power first-stroke launch
      still works; slingshot kicks into play + scores; launch prompt on every ball arm. STRESS: no
      tunneling at >= ~2x LAUNCH_SPEED_MAX through the resized plunger face and the triangular
      slingshot. Real instanced bodies, measured position/velocity, never a self-reported counter.
      Owner: test-builder + qa-lead. Acceptance: the FULL updated suite runs GREEN on
      the homelab godot runner (the artifact, not a doc claim).
      LEAD POLISH 2026-06-20 (QA findings B2 + BUG-029..032): folded in the hardening this slice owns.
      (B2) tests/test_soft_lock_integration.gd ADDED - instances the REAL Table.tscn, fires a too-weak
      strike through the real plunger, lets the live watchdog run past LAUNCH_SETTLE_TIME_S, and
      asserts plunger.is_armed() true + NO balls_changed (the headline soft-lock fix, on the integrated
      tree, not just the unit GameFlow). The false "integration check at the bottom" header claim in
      test_soft_lock_recovery.gd is corrected to point at the new file. (BUG-031, root-cause) hardened
      LAUNCH_REACHED_PLAY_Z from the flipper-pivot row (z=20) to the slingshot row (FLIPPER_PIVOT_Z -
      3.5 = 16.5) so a side-draining ball can no longer transiently dip across the line and falsely
      promote to BALL_IN_PLAY (the secondary soft-lock path). (BUG-030) slingshot.gd _body_yaw() fixed
      to atan2(x, z) so the visible triangle face + solid body + detector all face the actual kick
      direction (was 180 deg off, pointing the face at the drain - physics was already correct).
      (BUG-029) confirmed the right field band is a designed OUTLANE (OOB spends correctly); corrected
      the stale LANE_GUIDE_RIGHT_DIVIDER_X comment (lane divider is 14.0, not 10.5). (BUG-032) NOT
      reproducible (the cap already faces +Y on both sides - QA had a 2D-cross sign error); hardened the
      cap winding via signed-area anyway. All changed files gdlint-clean, no emoji/em-dash, lines <=100.
- [ ] PRODUCER: scope/finish gate. Confirm scope held (eight fixes only, no new element types/art/
      rescale) and that the soft-lock + flipper-material + triangular-sling + lane-resize + UX claims
      are GREEN on the runner on the pushed sha before any merge to main. Owner: producer.

## SLICE: Fix the launch (gray-box, physics-based) - * team
CONFIRMED playability bug on the deployed build (main): the developer plunges and the ball climbs
partway up the launch chute, stalls, and rolls back, so play cannot start reliably across the power
meter. This is a CORRECTNESS slice: NO new mechanics or element types, same element counts, every
interaction physics-based. Fix the launch so EVERY plunge (the whole meter, including MIN power)
delivers the ball over the arch into the playfield, AND close the test gap that let a non-clearing
launch ship. Design intent confirmed in DESIGN.md ("Slice design intent: Fix the launch"). Cut list in
DESIGN.md ("Cut from the Fix the launch slice"). Flow: game-designer (DONE - intent below) ->
physics-programmer (MEASURE the cause headless, then fix the measured cause) -> lead-programmer (any
TableConfig speed/friction/lane edit, re-derive dependents with WHY) -> gameplay-programmer (re-verify
the plunger contract unchanged) -> test-builder + qa-lead (the behavioral lane-clear oracle +
structural/stress) -> review board -> producer (scope/finish gate, GREEN CI on the pushed sha). The
team's Setup phase creates the slice branch; build/QA agents COMMIT but do NOT push; Deliver verifies
the FULL GUT suite GREEN locally (fetch headless Godot 4.x, run GUT) BEFORE pushing ONE PR. Do NOT
touch main.

THE DIAGNOSIS (geometry, confirmed by the designer; physics MEASURES it before fixing): ball rests at
BALL_START.z = HALF_LENGTH - 2.0 = 23.0; the arch is at ARCH_CENTER_Z = -HALF_LENGTH + 6.0 = -19.0,
so the climb is ~42 units. Down-slope decel = GRAVITY*sin(TILT_DEG) = 200*sin(7) = ~24.4 u/s^2.
Clearing 42 units from rest needs ~sqrt(2*24.4*42) = ~45.3 u/s at the ball BEFORE rattle/friction loss.
But LAUNCH_SPEED_MIN = 30 and PLUNGER_STROKE_SPEED_MIN = 30 -> the entire lower half of the meter
physically cannot clear the lane (primary cause (a): the floor is too low). Physics must also rule in/out
(b) impulse under-delivery and (c) rattle/friction in the snug 2.0-unit lane.

Tasks (pull from here - keep them small and finishable):
- [ ] LEAD: ARCHITECT + SCAFFOLD. ARCHITECTURE.md section 13 records the slice contract: the geometry
      diagnosis, the measure-first protocol, the file-ownership split (DISJOINT so physics/test-builder
      work in parallel), the shared-physics audit (NO new layer/mask; lane walls have NO PhysicsMaterial
      today so a low-friction lane wall is a clean physics-owned option), and the test matrix. Two NEW
      test skeletons scaffolded (gdlint clean, lines <= 100, stable typed signatures + helpers so the
      coders fill bodies without conflict): tests/test_launch_diagnostic.gd (the MIN/MID/MAX measurement
      rig, physics fills the asserts) and tests/test_launch_clears_lane.gd (the behavioral lane-clear
      oracle, test-builder fills the asserts). Owner: lead-programmer.
      DONE 2026-06-20.
- [ ] PHYSICS: DIAGNOSE BY MEASUREMENT. Headless, on the REAL tilted Playfield + REAL TableGeometry
      (build exactly like tests/test_plunger_launch.gd: rotated TILT_DEG about X, TableGeometry.build,
      shipping Plunger.tscn + Ball.tscn), fire test_strike_at_power at MIN, MID, and MAX and MEASURE:
      (a) the ball's current_speed() just after the strike resolves, and (b) the apex - the lowest Z
      (most up-table) the ball reaches before rolling back. Determine which is true: (a) floor too low
      (the ~45 u/s climb requirement vs LAUNCH_SPEED_MIN 30), (b) the impulse under-delivers (full
      power < LAUNCH_SPEED_MAX at the ball), (c) the snug 2.0-unit lane bleeds energy to rattle +
      BALL_FRICTION 0.4. Owner: physics-programmer. Files: tests/test_launch_diagnostic.gd
      (SCAFFOLDED by lead - fill the two measurement asserts; stable helpers _measure_delivered_speed /
      _measure_apex already built). Acceptance: the measured speeds and apexes at MIN/MID/MAX are
      REPORTED in the deliverable, and the cause(s) named from the numbers.
- [ ] PHYSICS+LEAD: FIX THE MEASURED CAUSE(S). Raise LAUNCH_SPEED_MIN (and PLUNGER_STROKE_SPEED_MIN
      feeding it) so EVEN A MINIMUM plunge clears the lane into play with margin over ~45 u/s plus the
      measured rattle/friction loss - the WHOLE meter must be useful, no dead bottom half. Keep
      LAUNCH_SPEED_MAX a satisfying hard plunge clearly stronger than the new min (raise MAX if needed
      to keep a readable weak-vs-strong spread). IF the measurement shows rattle/friction is a real
      contributor, lower the lane-wall / ball-lane friction or widen the lane SLIGHTLY (never back to a
      bulky box; keep the developer's snug ball-width look). Keep the plunger face striking square with
      no gap. If the impulse under-delivers, fix the impulse sizing so the delivered ball speed lands in
      LAUNCH_SPEED_MIN..MAX. WHY-comment every changed number with the measured value behind it.
      Owner: physics-programmer (impulse/friction) + lead-programmer (TableConfig
      constants + re-derive dependents). Files: scripts/config/table_config.gd, scripts/plunger.gd,
      scripts/ball.gd, scripts/table_geometry.gd (only the lane-friction/widen IF measured). Acceptance:
      the new behavioral lane-clear test (below) passes at MIN/low/mid; test_plunger_launch.gd and
      test_plunger_lane_size.gd stay green; the plunger contract is unchanged byte-for-byte.
- [x] GAMEPLAY: PLUNGER CONTRACT RE-VERIFY. Confirm scripts/plunger.gd public contract is unchanged
      byte-for-byte after any tuning: signals power_changed(power)/ball_launched; methods
      arm/disarm/set_ball/is_armed; power 0..1; oscillating meter; launch from contact-impulse, never
      a code velocity set (QA BUG-017 stays honored). Confirm test_plunger.gd contract tests stay
      green. Owner: gameplay-programmer. File: scripts/plunger.gd (read-only re-verify).
      DONE 2026-06-20: contract confirmed intact - no code edit was required. All signals, methods,
      and the impulse-on-contact mechanism are byte-for-byte the same as the Playtest fixes 2 slice
      delivered. test_plunger.gd asserts the same contract this slice leaves unchanged. No production
      code was modified by the gameplay-programmer in this slice.
- [x] TEST/QA: CLOSE THE TEST GAP - add a BEHAVIORAL lane-clear oracle. On the real tilted lane
      geometry, fire a launch at MIN power (and a low/mid power) and assert the ball's apex crosses
      up-table PAST the lane exit / arch into the play area (ball center crosses up-table of
      LAUNCH_REACHED_PLAY_Z / the lane-divider top), then settles in the OPEN playfield, NOT back in
      the lane. Use the ball's MEASURED position as the oracle (position cannot lie). Owner:
      test-builder + qa-lead. Files: tests/test_launch_clears_lane.gd (SCAFFOLDED by
      lead - stable rig + helper _launch_and_track + three pending() asserts spelled out; fill the
      asserts). Acceptance: the lane-clear test FAILS against the current too-low floor and PASSES
      after the fix (intended red-to-green); test_plunger_launch.gd + test_plunger_lane_size.gd stay
      GREEN.
      DONE 2026-06-20 (gameplay-programmer, filling the test-builder role for the pending asserts):
      tests/test_launch_clears_lane.gd - three pending() bodies replaced with real asserts. (1)
      test_min_power_launch_clears_lane_into_play: fires power 0.0, asserts apex_z <
      LAUNCH_REACHED_PLAY_Z and final.x < LANE_INNER_X. (2)
      test_low_mid_power_launch_clears_lane_into_play: fires 0.0 and 0.4, asserts both clear
      LAUNCH_REACHED_PLAY_Z AND mid apex <= min apex + 1.0 (monotonic, physics-jitter tolerant).
      (3) test_cleared_ball_settles_in_open_field_not_the_lane: fires 0.0, asserts final.x <
      LANE_INNER_X - BALL_RADIUS AND final.z < BALL_START.z (not back at the cradle). All three are
      INDEPENDENT ORACLE (ball.position). Written to FAIL against the current floor (LAUNCH_SPEED_MIN
      30 cannot clear 42 units) and PASS after the physics-programmer raises the floor. gdlint clean.
- [ ] PHYSICS/QA: NO-TUNNEL RE-CONFIRM AT THE NEW MAX. If LAUNCH_SPEED_MAX is raised, update every
      no-tunnel stress test to fire at >= 2x the NEW max and confirm zero tunneling through the plunger
      face, lane pocket, walls, arch, targets, pop bumpers, slingshots, lane guides, and flippers,
      against REAL instanced bodies measuring real position/velocity. Owner: physics-programmer
      + qa-lead. Files: tests/test_plunger_launch.gd, tests/test_ball_tunneling.gd,
      tests/test_target_no_tunneling.gd, tests/test_active_kicker_no_tunneling.gd. Acceptance: the full
      stress suite GREEN on the homelab godot runner at >= 2x the new max (the artifact, not a doc claim).
- [ ] PRODUCER: scope/finish gate. Confirm scope held (launch tuning + lane-clear test only, no new
      element types/art/rescale) and that the lane-clear + no-tunnel claims are GREEN on the runner on
      the pushed sha before any merge to main. Owner: producer.

## Icebox (deliberately deferred - NOT now)
- multiball, ramps, bumpers, special modes, meta-progression, multiple tables, art pass, audio pass,
  Steam integration, menus beyond the minimum.
- INFRA (deferred 2026-06-17): activate the public demo URL via the prepped Cloudflare tunnel (docs/INFRA.md section 6). Needs the connector token from the CF Zero Trust dashboard pasted into the VM .env as CF_TUNNEL_TOKEN, then `docker compose --profile tunnel up -d`. Demo is LAN-only at 10.1.1.214:8080 until then. NOT needed to start dev.

## SLICE: Core 3D table rebuild on Jolt (run through the * team)
Replace the hand-coded kinematic gray-box (scripts/Main.gd) with a properly-architected 3D table on the
modern Jolt foundation, adopting the patterns in docs/pinhead-tech-notes.md. This slice is meant to go
through the full process: game-designer (confirm core-table intent) -> lead-programmer (architecture: scene
structure, world scale, physics layers, input map) -> physics-programmer (force-driven Jolt flippers + ball
CCD + tuning) -> gameplay-programmer (plunger power meter, drain, scoring) -> test-builder + qa-lead
(GUT tests; the CI test job currently SKIPS because addons/gut is missing - install it) -> peer review board
-> producer (scope/finish gate).

Acceptance (resubmission: both physics-first gates below are now REAL and GREEN on the runner -
CI run 27794688808 on sha fc82849: 62 tests, 353 asserts, all passed):
- [x] Force-driven flippers (hinge + driven force + return spring), NOT kinematic; do not overlap; impart
      real momentum to the ball. (DONE: test_flipper_momentum.gd drives force_energized() with REAL
      assertions - full swing >= 1.5x a tap (ball current_speed, not tip_speed), tip_speed rises within the
      ~50 ms snap window - executed GREEN on the runner, NOT pending(). CI run 27794688808.)
- [x] Action-based input map (left_flipper/right_flipper/launch/nudge).
- [x] Ball with continuous_cd; a GUT stress test asserts zero tunneling at full flip speed. (DONE: the
      100-iteration stress loop in test_ball_tunneling.gd fires an instanced REAL Ball.tscn, not a
      hand-built RigidBody3D, and executed GREEN on the runner. CI run 27794688808.)
- [x] Rounded top arch guides the launched ball into the playfield. (sealed overlapping-segment arch.)
- [x] Plunger power meter (hold to charge an oscillating meter, release to launch at that power).
- [x] Open center drain + ball count + basic score. (center drain + OOB failsafe + targets, all wired.)
- [x] Physics layers (Playfield / Static Obstacles / Kinematic Obstacles / Balls).
- [x] addons/gut installed so the CI test job runs real tests instead of skipping. (vendored v9.4.0, MIT.)
- [x] A chosen, documented world scale (pinhead uses gravity 200 with a larger scale; pick and write it down).
References: docs/pinhead-tech-notes.md, docs/REFERENCES.md, docs/old-software-analysis.md.

### Architecture LANDED (lead-programmer) - see docs/ARCHITECTURE.md
Scene structure, world scale (TableConfig autoload, gravity 200), physics layers (PhysicsLayers
autoload + project.godot), action input map, and the file-ownership split are decided and scaffolded.
Skeleton files have STABLE typed signatures + signal contracts so the two coders fill DISJOINT files
in parallel. addons/gut (v9.4.0, MIT) is vendored so CI runs tests instead of skipping. Old
scripts/Main.gd + scenes/Main.tscn removed; root scene is now scenes/Table.tscn.

Tasks (pull from here):
- [ ] PHYSICS: scripts/ball.gd - RigidBody with continuous_cd, mass/material/shape from TableConfig,
      reset_to_start/reset_to/launch helpers. Acceptance: test_ball_tunneling.gd green (zero tunnel
      at >= 2x LAUNCH_SPEED_MAX), CCD on. Owner: physics-programmer.
- [ ] PHYSICS: scripts/flipper.gd - hinge joint + driven solenoid force + return spring (NOT
      kinematic). configure()/is_energized()/tip_speed(). Acceptance: test_flipper_momentum.gd green
      (full swing out-throws a tap, force-driven, ~50 ms snap), no inverted-V overlap.
      Owner: physics-programmer.
- [x] GAMEPLAY: scripts/plunger.gd - oscillating power meter (~0.5-1.0 s sweep), power->speed launch.
      Acceptance: test_plunger.gd green. Owner: gameplay-programmer.
      DONE 2026-06-17: pingpong oscillation at CHARGE_RATE 2.5 (0.8 s sweep), lerpf power->speed,
      arm/disarm/set_ball/is_armed stable. tests/test_plunger.gd filled with 9 concrete assertions.
- [x] GAMEPLAY: scripts/drain.gd + scripts/target.gd - drain detect + scoring target w/ knock-back.
      Owner: gameplay-programmer.
      DONE 2026-06-17: drain.gd - Area3D, BoxShape3D from TableConfig, PhysicsLayers.BALLS mask,
      body_entered guard on _ball. target.gd - CylinderShape3D + CylinderMesh, kick_dir on XZ plane,
      MIN_KICK_DIST_SQ guard, scored(points) emitted before kick.
- [x] GAMEPLAY: scripts/game_flow.gd + scripts/hud.gd - state machine + HUD. Acceptance:
      test_game_flow.gd green; HUD ticks on hit, drain message, game over + restart.
      Owner: gameplay-programmer.
      DONE 2026-06-17: game_flow.gd - explicit State enum, all guards in place, no phantom scores,
      restart only from GAME_OVER. hud.gd - full Control tree built in code, meter color lerp,
      game-over panel. tests/test_game_flow.gd filled with 15 concrete assertions.
- [x] LEAD: scripts/table_geometry.gd (surface/walls/arch/lane) + table.gd build+wire bodies; fill the
      element-instancing TODOs once ball/flipper land. Owner: lead-programmer.
      DONE 2026-06-18 (polish pass): table_geometry.gd builds the surface (PLAYFIELD layer), full-length
      side walls + top wall (bottom OPEN for the drain), lane divider, and an overlapping-segment arch
      that seals (no gap a fast ball squeezes through). table.gd instances Ball/2x Flipper/Plunger/3x
      Target/Drain + a failsafe OOB catch-plane, calls set_ball on every detector, and wires ALL signals
      in one place incl. game_over -> show_game_over and a JUST-PRESSED restart poll that hides the panel
      via _on_request_new_ball. Folded-in hardening (QA findings): BUG-001 right-flipper mirror (bat now
      extends toward center on both sides) in flipper.gd; FLIPPER_PIVOT_SPREAD 5->7 so the inverted-V
      leaves a positive gap (was crossing center, gap -1.9 -> +2.07); DRAIN_Z moved inside the field so
      no naive bottom wall can block it (BUG-004); OOB failsafe drain (BUG-006); target now PRESERVES
      momentum + has a re-trigger cooldown (BUG-007); plunger requires release-before-charge after arm
      (BUG-008); tip_speed() projects onto the hinge axis (BUG-010).
- [~] TEST/QA: fill the tests/*.gd stubs against the stable signatures; confirm CI test job runs GUT.
      Owner: test-builder + qa-lead.
      RESUBMISSION SCOPE (the slice signs off only when BOTH run GREEN on the homelab godot runner,
      NOT pending/skipped):
        1. test_ball_tunneling.gd - the 100-iteration stress loop fires an instanced REAL Ball.tscn
           (mass/shape/material/CCD/layers as the shipping system), not a hand-built RigidBody3D. DONE.
        2. test_flipper_momentum.gd - the two headline asserts (test_full_swing_outthrows_a_tap,
           test_flipper_reaches_full_swing_quickly) drive flipper.force_energized() with REAL assertions
           (full swing >= 1.5x a tap on ball current_speed; tip_speed rises within the ~50 ms snap
           window), replacing the pending() stubs. DONE.
      DEFERRED to BACKLOG Next / QA_BACKLOG (do NOT block this resubmission): test_table_integration.gd,
      test_target_no_double_score.gd, test_flipper_no_overlap.gd, the BUG-009 bounce-tolerance relax.
