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
