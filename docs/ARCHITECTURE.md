# Architecture: Core 3D table rebuild on Jolt

Owner: gamedev-lead-programmer. This is the engineering contract for the "Core 3D table rebuild on
Jolt" slice (docs/BACKLOG.md). It records the scene structure, world scale, physics layers, input
map, file ownership, and the signal contracts. The physics-programmer and gameplay-programmer fill
DIFFERENT files against the stable signatures below, in parallel, without conflict.

Design source of truth: docs/DESIGN.md. Patterns: docs/pinhead-tech-notes.md. The OLD hand-coded
kinematic gray-box (scripts/Main.gd, scenes/Main.tscn) is REMOVED and replaced by this structure.

## 1. World scale (THE CONTRACT - do not re-litigate per element)

The decision lives as code in `scripts/config/table_config.gd` (autoload `TableConfig`). That file
is the single source of truth; the numbers below are a human-readable summary. If a number must
change, change it in TableConfig (one edit) and tell the team, because it re-scales the whole table.

- Units: abstract "world units" (treat ~1 unit ~= 1 cm for intuition only).
- Gravity magnitude: 200 (project `physics/3d/default_gravity` AND `TableConfig.GRAVITY`, kept in
  sync). High gravity at a tens-of-units scale is what the pinhead force-flipper tuning is built for
  and keeps Jolt's solver well behaved. NOT the old tiny 0.013 m / 9.8 scale.
- Table tilt: 7 degrees. Modeled by ROTATING the Playfield node about X; gravity stays world-down
  (-Y), so the down-slope component pulls the ball toward the drain.
- Ball: radius 0.6, mass 0.6, bounce 0.15, friction 0.4.
- Playfield: half-width 12 (24 wide), half-length 25 (50 long), wall height 2.4, thickness 0.8.
- Launch lane: up the RIGHT side, inner divider at x = 8.
- Arch: rounded top, 16-segment polyline, spans the width, turns the launched ball into the field.
- Flippers: length 7, pivots spread +/-5 (inverted V), seated 5 units up from the drain end.
- Drain: open trigger volume just past the flippers (z = half_length + 2).
- Launch speed: power 0..1 maps to 30..90 units/s.

## 2. Scene structure

```
scenes/Table.tscn  (Node3D, scripts/table.gd)   ROOT, orchestrator + signal wiring
  Environment / Camera / Light                  gray-box presentation (lead)
  Playfield (Node3D, rotated 7 deg about X)     the tilted table plane
    Surface + Walls + Arch + Lane divider        static geometry (scripts/table_geometry.gd, lead)
    LeftFlipper / RightFlipper                    scenes/elements/Flipper.tscn (physics)
    Targets (a few)                               scenes/elements/Target.tscn  (gameplay)
    Plunger                                       scenes/elements/Plunger.tscn (gameplay)
    Drain (Area3D)                                scripts/drain.gd             (gameplay)
    Ball                                          scenes/elements/Ball.tscn    (physics)
  GameFlow (Node)                                 scripts/game_flow.gd         (gameplay)
  HUD (CanvasLayer)                               scripts/hud.gd               (gameplay)
```

`table.gd` builds the playfield, instances the element scenes, assigns typed handles, and is the ONE
place cross-system signals are connected (`_wire_signals`). A coder may change a system's internals
freely as long as the documented signal/method signatures hold.

## 3. Physics layers

Defined in `scripts/config/physics_layers.gd` (autoload `PhysicsLayers`) and mirrored in
project.godot `[layer_names]`. Code uses the named constants, never raw bit numbers.

| Layer | Bit | Members |
|-------|-----|---------|
| Playfield (1) | 1 | the flat table surface |
| StaticObstacles (2) | 2 | walls, arch, lane divider, targets, drain guides |
| KinematicObstacles (3) | 4 | flippers, plunger (driven physics bodies) |
| Balls (4) | 8 | the pinball(s) |

Convenience masks: `BALL_COLLISION_MASK` (ball hits all four layers), `KINEMATIC_COLLISION_MASK`
(flipper/plunger only need to hit Balls).

## 4. Input map (action-based)

Defined in project.godot `[input]`. Code reads ACTIONS, never raw keys (pinhead pattern 2), so
remap is cheap later. Flippers must register on the SAME physics frame as the press (no input lag):
poll the action in `_physics_process`, do not route through `_input`.

| Action | Default keys | Used by |
|--------|--------------|---------|
| left_flipper | A, Left-Arrow | LeftFlipper |
| right_flipper | D, Right-Arrow | RightFlipper |
| launch | Space | Plunger (also restart from game over) |
| nudge | Up-Arrow, W | nudge (present this slice; tuning minimal, DESIGN cut) |

left/right nudge are deferred (DESIGN cut list); one `nudge` action exists now.

## 5. File ownership map

Read-only CONTRACT files (lead-owned; nobody edits during implementation):
- `scripts/config/table_config.gd`   world scale + geometry numbers + helpers.
- `scripts/config/physics_layers.gd` named collision layers + masks.

Lead-programmer (architecture + shell; does not block the coders):
- `scripts/table.gd`           orchestrator + signal wiring.
- `scripts/table_geometry.gd`  static surface/walls/arch/lane builder.
- `scenes/Table.tscn`, `scenes/elements/*.tscn`  scene wrappers.
- project.godot, docs/ARCHITECTURE.md, addons/gut (vendored).

Physics-programmer (force-driven physics + the no-tunneling gate):
- `scripts/ball.gd`     RigidBody, CCD, mass/material, reset/launch helpers.
- `scripts/flipper.gd`  hinge joint + driven solenoid force + return spring (NOT kinematic).

Gameplay-programmer (launch, scoring, flow, HUD):
- `scripts/plunger.gd`    oscillating power meter, power->speed launch.
- `scripts/drain.gd`      drain detection.
- `scripts/target.gd`     scoring target + knock-back.
- `scripts/game_flow.gd`  state machine (score, balls, game over, restart).
- `scripts/hud.gd`        score/balls/meter/message/game-over display.

Test-builder + qa-lead:
- `tests/*.gd`            GUT tests (see section 7). addons/gut is already vendored.

These sets are DISJOINT: the physics and gameplay coders never edit the same file.

## 6. Signal contracts (the integration seam)

Connected once in `table.gd._wire_signals()`. Keep these signatures stable.

- `Drain.ball_drained()`            -> `GameFlow.on_ball_drained()`
- `Target.scored(points: int)`      -> `GameFlow.on_target_scored(points)`
- `Plunger.ball_launched()`         -> `GameFlow.on_ball_launched()`
- `Plunger.power_changed(power)`    -> `HUD.set_meter(power)`
- `GameFlow.request_new_ball()`     -> table.gd resets `Ball` + arms `Plunger`
- `GameFlow.score_changed(score)`   -> `HUD.set_score(score)`
- `GameFlow.balls_changed(balls)`   -> `HUD.set_balls(balls)`
- `GameFlow.message(text: String)`  -> `HUD.set_message(text)`
- `GameFlow.game_over(final)`       -> `HUD.show_game_over(final)`

Element method contracts (called by table.gd / each other):
- `Ball.reset_to_start()`, `Ball.reset_to(pos)`, `Ball.launch(dir, speed)`, `Ball.current_speed()`
- `Flipper.configure(action_name, mirrored)`, `Flipper.is_energized()`, `Flipper.tip_speed()`
- `Plunger.arm()`, `Plunger.disarm()`, `Plunger.set_ball(ball)`, `Plunger.is_armed()`
- `GameFlow.start_game()`, `on_target_scored(points)`, `on_ball_launched()`, `on_ball_drained()`,
  `restart()`, `current_state()`

## 7. Test matrix (CI runs these on the homelab runner; addons/gut vendored)

| File | Proves | Owner |
|------|--------|-------|
| test_world_scale.gd | TableConfig scale internally consistent + matches project gravity | test-builder |
| test_physics_layers.gd | four distinct layers + correct masks | test-builder |
| test_input_map.gd | left_flipper/right_flipper/launch/nudge actions exist with events | test-builder |
| test_ball_tunneling.gd | **HEADLINE GATE**: full-speed ball never tunnels a wall; CCD on | test-builder + physics |
| test_flipper_momentum.gd | full swing out-throws a tap; flipper is force-driven not kinematic; ~50 ms snap | test-builder + physics |
| test_game_flow.gd | score/balls/drain/game-over/restart state machine | test-builder + gameplay |
| test_plunger.gd | meter oscillates 0..1, release launches/disarms, power maps to speed | test-builder + gameplay |

Independent-oracle rule for the physics tests: assert the BALL's measured position/speed, not a
collision count the body self-reports. Position cannot lie about tunneling; speed cannot lie about
momentum.

## 8. Build / CI

Laptop is a thin client; the homelab runner (label `godot`) builds and tests. addons/gut is vendored
(v9.4.0, MIT) so the CI `test` job now RUNS GUT instead of skipping. The runner command already
targets `res://tests` (.github/workflows/ci.yml); `.gutconfig.json` pins the discovery settings.
