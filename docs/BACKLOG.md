# Development Backlog
Shared task queue. The lead-programmer turns design items into small technical tasks here; coders
pull from here. Keep items small and finishable. Each task names an owner agent and an acceptance check.

## Now (milestone: gray-box prototype -> Gate 0)
- [ ] DEVOPS: provision the self-hosted Godot runner on a homelab Docker host; generate Godot export
      presets (Web, Windows); install the GUT test addon (addons/gut). Owner: gamedev-devops-engineer.
      Acceptance: a push to main runs the pipeline green and publishes the web demo URL.
- [ ] DESIGN: fill DESIGN.md one-sentence pitch + core loop. Owner: gamedev-game-designer.
- [ ] PHYSICS: gray-box table - ball + two flippers + outer walls. Owner: gamedev-physics-programmer.
      Acceptance: full-power flip into a wall repeated 100x with ZERO tunneling; continuous_cd on;
      physics tick >= 120 (verified by a GUT test that runs on the runner).
- [ ] GAMEPLAY: launch the ball, detect drain, track ball count, show a basic score.
      Owner: gamedev-gameplay-programmer. Acceptance: 3 balls, score increments on target hit,
      game ends at zero balls.
- [ ] UX: minimal HUD (score + balls remaining) and a launch control. Owner: gamedev-ux-designer.
- [ ] PRODUCER: schedule the Gate 0 fun check once the above land. Owner: gamedev-producer.

## Next (filled in only after Gate 0 passes)
-

## SLICE: Make the core interactions PHYSICS-BASED (gray-box) - run through the gamedev-* team
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
      Owner: gamedev-lead-programmer.
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
      the drain (the pocket did not close the center). Owner: gamedev-physics-programmer +
      gamedev-gameplay-programmer (the center-still-drains half) + gamedev-test-builder.
      DONE 2026-06-19 (lead polish pass, QA BUG-012): the _build_lane_pocket builder was DROPPED during
      the original slice integration (build() called surface/walls/divider/arch only). Restored from
      prototype/physical-plunger and wired into TableGeometry.build() so the ball actually rests in the
      lane in the integrated game, not just the unit test. Verified the pocket -X face (x=7.6) clears
      the structural center-drain guard (minimum 7.2).
- [ ] PHYSICS+GAMEPLAY: physical plunger - a collision body (AnimatableBody3D on KINEMATIC_OBSTACLES,
      like flippers) that STRIKES the resting ball; the existing meter (power 0..1) maps to strike
      strength so the launched ball ends in LAUNCH_SPEED_MIN..MAX. PRESERVE the contract
      (power_changed/ball_launched; arm/disarm/set_ball/is_armed) exactly. Owner: gamedev-physics-
      programmer (internal strike) + gamedev-gameplay-programmer (contract re-verify).
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
      farming, no pass-through, no tunneling at >= ~2x LAUNCH_SPEED_MAX. Owner: gamedev-gameplay-
      programmer + gamedev-physics-programmer.
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
      because every other slice test bypasses table.gd. Owner: gamedev-lead-programmer (folded into the
      polish pass) + gamedev-test-builder. DONE 2026-06-19: tests/test_table_integration.gd instances
      res://scenes/Table.tscn and asserts (a) a LanePocket StaticBody3D on STATIC_OBSTACLES exists,
      (b) the PlungerFace, mapped from world space back into playfield-local, sits inside the lane in X
      and at PLUNGER_REST_POS.z (catches the double-offset), and (c) the real ball settles and stays in
      the lane. Written to FAIL pre-fix and PASS post-fix (locks both blockers closed).
- [ ] PHYSICS: VERIFY flippers still impart real momentum (no redesign). Acceptance: existing
      test_flipper_momentum.gd stays green after the shared-physics changes. Owner: gamedev-physics-programmer.
- [ ] PHYSICS/QA: extend GUT stress tests so the fast ball (>= ~2x LAUNCH_SPEED_MAX) does NOT tunnel
      through the plunger face, lane pocket, targets, walls, arch, or flippers, asserted against REAL
      instanced bodies measuring real position/velocity (independent-oracle, never a counter).
      FILES: tests/test_target_no_tunneling.gd (target post, scaffolded - fill the loop);
      tests/test_plunger_launch.gd (face + pocket, adopt from prototype); test_ball_tunneling.gd stays
      green (the flat-wall headline gate, unchanged). Acceptance: stress suite GREEN on the homelab
      godot runner (the artifact, not a doc claim). Owner: gamedev-physics-programmer + gamedev-qa-lead.
- [ ] PRODUCER: scope/finish gate. Confirm scope held (no new features) and both physics-first claims
      are GREEN on the runner before any merge to main. Owner: gamedev-producer.

## Icebox (deliberately deferred - NOT now)
- multiball, ramps, bumpers, special modes, meta-progression, multiple tables, art pass, audio pass,
  Steam integration, menus beyond the minimum.
- INFRA (deferred 2026-06-17): activate the public demo URL via the prepped Cloudflare tunnel (docs/INFRA.md section 6). Needs the connector token from the CF Zero Trust dashboard pasted into the VM .env as CF_TUNNEL_TOKEN, then `docker compose --profile tunnel up -d`. Demo is LAN-only at 10.1.1.214:8080 until then. NOT needed to start dev.

## SLICE: Core 3D table rebuild on Jolt (run through the gamedev-* team)
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
      at >= 2x LAUNCH_SPEED_MAX), CCD on. Owner: gamedev-physics-programmer.
- [ ] PHYSICS: scripts/flipper.gd - hinge joint + driven solenoid force + return spring (NOT
      kinematic). configure()/is_energized()/tip_speed(). Acceptance: test_flipper_momentum.gd green
      (full swing out-throws a tap, force-driven, ~50 ms snap), no inverted-V overlap.
      Owner: gamedev-physics-programmer.
- [x] GAMEPLAY: scripts/plunger.gd - oscillating power meter (~0.5-1.0 s sweep), power->speed launch.
      Acceptance: test_plunger.gd green. Owner: gamedev-gameplay-programmer.
      DONE 2026-06-17: pingpong oscillation at CHARGE_RATE 2.5 (0.8 s sweep), lerpf power->speed,
      arm/disarm/set_ball/is_armed stable. tests/test_plunger.gd filled with 9 concrete assertions.
- [x] GAMEPLAY: scripts/drain.gd + scripts/target.gd - drain detect + scoring target w/ knock-back.
      Owner: gamedev-gameplay-programmer.
      DONE 2026-06-17: drain.gd - Area3D, BoxShape3D from TableConfig, PhysicsLayers.BALLS mask,
      body_entered guard on _ball. target.gd - CylinderShape3D + CylinderMesh, kick_dir on XZ plane,
      MIN_KICK_DIST_SQ guard, scored(points) emitted before kick.
- [x] GAMEPLAY: scripts/game_flow.gd + scripts/hud.gd - state machine + HUD. Acceptance:
      test_game_flow.gd green; HUD ticks on hit, drain message, game over + restart.
      Owner: gamedev-gameplay-programmer.
      DONE 2026-06-17: game_flow.gd - explicit State enum, all guards in place, no phantom scores,
      restart only from GAME_OVER. hud.gd - full Control tree built in code, meter color lerp,
      game-over panel. tests/test_game_flow.gd filled with 15 concrete assertions.
- [x] LEAD: scripts/table_geometry.gd (surface/walls/arch/lane) + table.gd build+wire bodies; fill the
      element-instancing TODOs once ball/flipper land. Owner: gamedev-lead-programmer.
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
      Owner: gamedev-test-builder + gamedev-qa-lead.
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
