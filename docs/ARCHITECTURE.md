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
- `GameFlow.request_new_ball()`     -> also `HUD.hide_game_over()` (the INVERSE of show_game_over).
  This hides the game-over panel on BOTH a normal new ball and a restart (restart -> start_game ->
  request_new_ball), so the panel is never left visible over a live ball. Restart itself: table.gd
  polls the `launch` action (just-pressed edge) only in GAME_OVER and calls `GameFlow.restart()`.
- Failsafe: a second out-of-bounds `Drain` (a low catch-plane Area3D built in table.gd) routes its
  `body_entered` (filtered to the live ball) into the same `GameFlow.on_ball_drained()`, so a ball
  that escapes the playfield can never soft-lock the game in BALL_IN_PLAY.

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

## 9. SLICE: make the core interactions PHYSICS-BASED (gray-box, 2026-06-19)

This slice converts three EXISTING fake/trigger interactions into REAL physics. It adds NO features.
Design intent: DESIGN.md "Slice design intent". The architecture below is the engineering contract;
the physics-programmer and gameplay-programmer fill DISJOINT files in parallel against it. Nothing
here re-litigates the world scale (section 1), the four physics layers (section 3), or the input map
(section 4): those are unchanged. This slice only adds bodies WITHIN that contract.

### 9.1 What stays the same (do not touch)
- World scale, gravity 200, tilt 7 deg, ball radius/mass/material: UNCHANGED (TableConfig).
- The four physics layers and the two convenience masks: UNCHANGED. Every new body in this slice
  reuses the EXISTING layers; no new layer is introduced. This is the key shared-physics audit
  result (the LEAD task): the lane pocket and physical targets are STATIC_OBSTACLES, the plunger
  face is a KINEMATIC_OBSTACLE, exactly like walls and flippers already are. The ball already
  collides with all three via BALL_COLLISION_MASK, so the new bodies interoperate with zero mask
  changes and the flipper tests cannot regress from a layer/mask edit (there is none).
- The plunger PUBLIC contract (signals power_changed/ball_launched; methods arm/disarm/set_ball/
  is_armed; power 0..1): UNCHANGED byte-for-byte. GameFlow, the HUD, and table.gd wiring depend on
  it. The collision-driven strike is an INTERNAL change behind that contract.
- The target PUBLIC contract (signal scored(points: int); method set_ball(ball); export points):
  UNCHANGED. table.gd still types `targets: Array[Area3D]` (see 9.4 for why the detector stays an
  Area3D), still calls set_ball, still connects scored -> GameFlow.on_target_scored. The 3 target
  positions and the flat 100-point value: UNCHANGED.
- Flippers: NOT redesigned. The physics-programmer only VERIFIES the existing momentum/snap tests
  stay green after this slice's bodies/materials land.

### 9.2 Shared-physics audit (the LEAD deliverable - the integration contract)
The three conversions touch shared physics only in these well-bounded ways; everything else is local
to one file:
- LAYERS/MASKS: no change. New bodies reuse PhysicsLayers constants (table above). Asserted by the
  existing test_physics_layers.gd (unchanged) plus new STRUCTURAL asserts that each new body sits on
  the intended layer (test_physics_layers extension, see 9.6).
- PHYSICS MATERIALS: three materials, each LOCAL to its body, none shared/mutated globally:
  1. Ball material (bounce 0.15, friction 0.4): UNCHANGED, owned by ball.gd. This is the restitution
     that makes the target bounce momentum-preserving (see 9.4); do not change it for the target.
  2. Plunger face material (bounce ~0.1, friction ~0.4): a clean momentum transfer, not a trampoline.
     LOCAL to the face body in plunger.gd. Owned by physics-programmer.
  3. Target deflector material (bounce: physics-programmer's tuned value): LOCAL to the target's
     StaticBody3D in target.gd. This is the ONE genuinely new feel knob in the slice. Constraint:
     the ball must come OFF the target with its momentum (designer's #1 fun risk). A near-elastic
     deflector (bounce ~0.5-0.9) preserves speed via the SOLVER, replacing the old manual velocity
     rewrite. The physics-programmer tunes the exact value and OWNS the no-trap guarantee; the
     gameplay-programmer owns scoring/cooldown and does NOT write velocity (the solver bounces).
- TIME STEP / CCD: unchanged (240 Hz, ball CCD on). Every new body is either static (pocket, target
  deflector) or a CCD-capable driven body (plunger face uses sync_to_physics; consider continuous_cd
  on the face as the flipper bat already does). The no-tunneling gate (9.6) proves the fast ball does
  not punch through ANY new body.

### 9.3 Conversion 1 - LAUNCH (lane pocket + physical plunger)
Two defects from the deployed demo: the ball fell out the open lane bottom, and the plunger was fake
(it set linear_velocity directly). The fix has a static half and a kinematic half.

STATIC half (lane pocket) - new TableConfig constants + TableGeometry._build_lane_pocket:
- A StaticBody3D box on STATIC_OBSTACLES spanning ONLY the lane in X (x in [LANE_INNER_X, HALF_WIDTH],
  widened by one wall thickness so it seals to the right wall and the divider with no corner gap),
  standing WALL_HEIGHT tall, its up-table face at LANE_POCKET_FACE_Z near +HALF_LENGTH. It stops the
  ball resting in the chute. It does NOT span x in [-HALF_WIDTH, LANE_INNER_X], so the CENTER DRAIN
  region stays open (constraint honored). A full-width bottom wall is WRONG and would block the drain.
- BALL_START sits just up-table of the pocket face so the resting ball leans against it (no overlap).

KINEMATIC half (physical plunger face) - internal to plunger.gd, contract preserved:
- An AnimatableBody3D face on KINEMATIC_OBSTACLES (mask = KINEMATIC_COLLISION_MASK = balls only),
  sync_to_physics = true so its scripted motion reports velocity to the solver and strikes the ball
  with REAL momentum. Seated at PLUNGER_REST_POS in light contact with the resting ball's down-table
  surface, just up-table of the pocket (no static/kinematic overlap).
- A STROKE STATE MACHINE (IDLE/FORWARD/RETURN): on release, latch a forward stroke speed mapped from
  power (PLUNGER_STROKE_SPEED_MIN..MAX), drive the face up-table at that speed for PLUNGER_STROKE_
  LENGTH, then return to rest. The CONTACT throws the ball; plunger.gd never sets ball velocity.
- The PUBLIC contract is untouched: arm/disarm/set_ball/is_armed/power_changed/ball_launched behave
  exactly as before (ball_launched still fires as the strike begins; disarm still latches BUG-008).
- TEST HOOKS (inert in play, mirroring the flipper's force_energized): test_strike_at_power(power),
  face_position(), is_stroking(). Headless GUT cannot hold a key across frames, so the launch test
  drives the hook and measures the REAL ball.

ADOPTION NOTE: the prototype/physical-plunger branch already implements this exact shape (new
TableConfig pocket+stroke constants, _build_lane_pocket, the AnimatableBody3D face + stroke machine,
and tests/test_plunger_launch.gd) and it is SOUND and well-commented. The physics-programmer should
ADOPT it (cherry-pick / re-apply onto the slice branch), then own correctness and the stress asserts.
It was NOT gate-passed; it still goes through QA + the review board + the producer. The branch's
ball.gd still SETS velocity in launch() (unused once the strike drives the ball); the launch() helper
may stay as a test utility, but production launch must come from the strike contact, not a velocity
set, and the launch test must assert that (ball speed rises from rest with NO call to launch()).

### 9.4 Conversion 2 - POINT THINGS (physical targets)
Today target.gd is an Area3D pass-through that rewrites the ball's velocity (a coded kick). The fix
makes the target a SOLID body the ball bounces off, with the score firing on the physics contact and
NO velocity rewrite (the solver bounce preserves momentum). The decision that resolves "a StaticBody
cannot detect contact":

DECISION - DEFLECTOR + DETECTOR, one scene root stays an Area3D:
- target.gd's ROOT stays an Area3D (so the PUBLIC contract, table.gd's `Array[Area3D]`, and the
  scored signal wiring are byte-for-byte unchanged - the Area3D is now the DETECTOR shell).
- The Area3D builds a CHILD StaticBody3D "Deflector" on STATIC_OBSTACLES with a CylinderShape3D
  (the same 1.5-radius post the player aims at) and a near-elastic PhysicsMaterial. THIS is the solid
  post: the ball physically collides with it and bounces, momentum preserved by restitution. The
  physics-programmer tunes the deflector bounce and owns "the ball never traps/dies on the target".
- The Area3D's OWN CollisionShape3D is a slightly LARGER cylinder shell (radius = deflector +
  ~BALL_RADIUS) on no layer, mask = BALLS, monitoring only. body_entered fires when the ball touches
  the post; that is the score-on-contact event. The Area no longer sets linear_velocity at all (the
  old manual kick is DELETED - it was the designer's #1 fun risk and the solver now does the bounce).
- BUG-007 cooldown: UNCHANGED. The RETRIGGER_COOLDOWN_S dead-time after a hit stays, so a ball
  grinding against the post on the tilted plane cannot farm points every frame. The cooldown guards
  the SCORE, not the bounce (the bounce is always physical).
- Score-on-contact ordering: scored(points) emits inside body_entered, gated by the cooldown. The
  ball's deflection is the solver's job and happens on the same contact regardless of the cooldown.

WHY keep the Area3D root rather than swap to a StaticBody root: a StaticBody3D emits NO body_entered
(it detects nothing), so a pure-StaticBody target could deflect but never know it was hit. Wrapping a
StaticBody deflector inside the existing Area3D detector gives BOTH a real physics bounce AND a clean
contact event, while preserving the entire public contract and table.gd's types with zero edits
elsewhere. The 3 positions and 100-point value are unchanged.

### 9.5 Conversion 3 - FLIPPERS (verify only, no redesign)
The flippers are already force-driven (hinge + driven force + return spring) with momentum/snap tests
green on main (CI run 27794688808). The physics-programmer VERIFIES no regression after this slice:
re-run test_flipper_momentum.gd and test_ball_tunneling.gd on the slice branch. Because this slice
changes NO layers, NO masks, and does not touch the ball material or flipper.gd, a regression would
be surprising; the verification is the proof, not an assumption.

### 9.6 Test matrix for this slice (extends section 7; CI on the runner is the source of truth)

| File | Class | Proves | Owner |
|------|-------|--------|-------|
| test_plunger_launch.gd (NEW) | structural+behavioral+stress | lane pocket + plunger-face bodies exist on correct layers; a strike imparts velocity FROM REST with no launch() call; full strike out-throws weak (>=1.5x); resulting speed lands ~LAUNCH_SPEED_MIN..MAX; ball rests in lane and does not exit the bottom; max strike never tunnels the face or pocket | physics + test-builder |
| test_lane_pocket_drain.gd (NEW) | behavioral | a ball at lane-X rests (stopped by pocket) AND a ball at center-X still reaches the drain (pocket did not close the center drain) | gameplay + test-builder |
| test_target_physical.gd (NEW) | structural+behavioral | target has a solid StaticBody3D deflector on STATIC_OBSTACLES + an Area3D detector on the BALLS mask; ball BOUNCES off (measured direction change AND momentum kept, not killed); scores ONCE per contact; cooldown blocks per-frame farming; the ball does NOT pass through (no pass-through) | gameplay + test-builder |
| test_target_no_tunneling.gd (NEW, or fold into the tunneling stress) | stress | a ball fired at >= ~2x LAUNCH_SPEED_MAX at the target deflector never ends up behind it | physics + qa |
| test_ball_tunneling.gd (EXTEND) | stress | unchanged headline gate stays green; ADD that the fast ball does not tunnel the lane pocket and (covered above) the plunger face/target | physics + qa |
| test_flipper_momentum.gd (VERIFY) | regression | stays green after the slice (no redesign) | physics |
| test_plunger.gd (VERIFY) | contract | the unchanged plunger contract stays green; the strike is internal | gameplay |

INDEPENDENT-ORACLE RULE (hard): every physics assertion reads the BALL's measured position or
current_speed(), never a self-reported counter. Position cannot lie about tunneling or pass-through;
speed cannot lie about a strike or a momentum-preserving bounce. A green suite that asserts only that
nodes exist (no measured physical behavior) is a FAIL (developer directive: "test the game like a web
app" means structural AND behavioral AND stress).

### 9.7 File ownership for THIS slice (DISJOINT - no two coders edit the same file)
Read-only CONTRACT files (lead-owned; physics-programmer may ADD pocket/stroke constants to
table_config.gd as part of adopting the prototype, then it is frozen again - coordinate the one edit):
- scripts/config/table_config.gd  ADD: LANE_POCKET_FACE_Z, LANE_POCKET_THICKNESS, PLUNGER_STROKE_*,
  PLUNGER_FACE_*, PLUNGER_REST_POS (adopt from prototype). Owner of the edit: physics-programmer,
  reviewed by lead. No existing constant changes value.
- scripts/config/physics_layers.gd  NO CHANGE (frozen).

Lead-programmer (architecture + the static lane pocket + this doc):
- scripts/table_geometry.gd  ADD _build_lane_pocket (adopt from prototype) + call it in build().
- docs/ARCHITECTURE.md (this section), docs/BACKLOG.md slice tasks.
- scripts/table.gd  ONLY if the target wrapper needs a wiring tweak; the contract is designed so it
  does NOT (targets stay Array[Area3D], same set_ball + scored wiring). Lead confirms no edit needed.

Physics-programmer (the physical bodies + every no-tunneling guarantee):
- scripts/plunger.gd  internal: AnimatableBody3D face + stroke state machine + test hooks. PUBLIC
  contract unchanged. (Adopt from prototype, then own correctness.)
- scripts/target.gd  the StaticBody3D deflector child + its PhysicsMaterial bounce tuning + the
  no-trap guarantee. (Shared file with gameplay below - see the split.)
- scripts/ball.gd  only if the strike needs a material/CCD touch; otherwise UNCHANGED.
- Owns: test_plunger_launch.gd physics asserts, test_target_no_tunneling.gd, the tunneling extension.

  SPLIT NOTE for target.gd (the one file two roles touch): to keep them DISJOINT in practice, the
  gameplay-programmer owns the DETECTOR + scoring + cooldown half (the Area3D shell, body_entered,
  scored.emit, RETRIGGER_COOLDOWN_S) and the physics-programmer owns the DEFLECTOR half (the child
  StaticBody3D, its shape, its PhysicsMaterial, the bounce/no-trap tuning). They are different
  functions in the file (_build_deflector vs _on_body_entered); land the gameplay scoring rewrite
  first (delete the manual kick), then the physics deflector, on the same slice branch in sequence,
  not in parallel edits to the same lines. Lead arbitrates if they collide.

Gameplay-programmer (scoring/flow behind the unchanged contracts):
- scripts/target.gd  detector + scoring + cooldown half (delete the manual velocity kick; the solver
  bounces now). PUBLIC contract unchanged.
- scripts/game_flow.gd, scripts/hud.gd, scripts/drain.gd  UNCHANGED (the conversions are invisible to
  them behind the stable signals).
- Owns: test_lane_pocket_drain.gd, the behavioral half of test_target_physical.gd, plunger contract
  re-verify (test_plunger.gd stays green).

Test-builder + qa-lead:
- tests/*.gd  the four NEW files + the extension/verify runs. addons/gut already vendored.
