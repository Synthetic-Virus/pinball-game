# Architecture: Core 3D table rebuild on Jolt

Owner: lead-programmer. This is the engineering contract for the "Core 3D table rebuild on
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

## 10. SLICE: real pinball furniture (rubber flippers + active pop bumpers + slingshots, 2026-06-19)

This slice adds the first REAL pinball FURNITURE on the physics foundation: rubber-wrapped flippers,
active pop bumpers, slingshots, one standup target bank, and minimal inlane/outlane guides, in a
REPRESENTATIVE (not commercial) layout. Design intent: DESIGN.md "Slice design intent: real pinball
furniture". Prior art + the active-vs-passive finding: REFERENCES.md. As before, the physics-programmer
and gameplay-programmer fill DISJOINT files against the stable signatures below. Nothing re-litigates
the world scale (section 1), the four physics layers (section 3), or the input map (section 4).

### 10.1 What stays the same (do not touch)
- World scale, gravity 200, tilt 7 deg, ball radius/mass/material: UNCHANGED (TableConfig).
- The four physics layers + two masks: UNCHANGED. EVERY new body in this slice reuses the EXISTING
  layers (the LEAD shared-physics audit result): pop-bumper / slingshot / standup-bank SOLID bodies
  are STATIC_OBSTACLES (exactly like walls + the existing target deflector); the lane guides are
  STATIC_OBSTACLES; the detectors are Area3D on the BALLS mask (layer 0). No new layer, no mask edit,
  so the flipper momentum/snap/no-overlap tests CANNOT regress from a layer/mask change (there is
  none). The flipper drive (force/hinge/return spring) is NOT touched - only the bat PhysicsMaterial
  bounce is raised to a rubber value.
- The plunger / lane pocket / arch / drain / GameFlow / HUD: UNCHANGED. The new furniture scores
  through the EXISTING GameFlow.on_target_scored(points) handler (the active kick is invisible to the
  flow behind the scored signal), so no new GameFlow method and no HUD change.

### 10.2 The ACTIVE-KICK family (the one genuinely new mechanic)
Pop bumpers and slingshots are the SAME mechanical family - on ball contact, fire the ball AWAY with a
coded outward IMPULSE (the developer's "contracts to shoot the ball away"), capped CCD-safe, with a
minimum outgoing speed, scored once, behind a per-element cooldown. They differ ONLY in the kick
DIRECTION. So the shared logic lives in ONE base, scripts/active_kicker.gd (extends Area3D), and the
two concrete elements override only the direction:
- scripts/active_kicker.gd  - the base: detector + cooldown + score (gameplay half) and the solid body
  + the capped/floored/directed impulse (physics half, _build_body + _apply_kick are the TODOs).
- scripts/pop_bumper.gd      - _kick_direction_for() = RADIALLY OUTWARD from the bumper center.
- scripts/slingshot.gd       - _kick_direction_for() = the FIXED face normal into play (per side).
This mirrors the proven target.gd pattern (Area3D detector wrapping a solid StaticBody3D) and extends
it from PASSIVE (target: solver bounce only) to ACTIVE (these: solver bounce PLUS a coded impulse).
PASSIVE-only restitution is explicitly REJECTED for these elements (REFERENCES.md, DESIGN.md): an
impulse is needed so a SLOW ball still leaves FAST.

KICK CONTRACT (TableConfig, the LEAD constants - the physics-programmer honors all three):
- KICK_IMPULSE_SPEED 55      nominal outgoing speed along the kick direction.
- KICK_MIN_OUTGOING_SPEED 40 hard floor (a crawl-in still travels) - behavioral tests assert this.
- KICK_MAX_OUTGOING_SPEED 120 the CCD-SAFE CAP. Strictly inside the no-tunneling stress band
  (stress fires at 2x LAUNCH_SPEED_MAX = 180), so a STACKED kick can never produce a speed the stress
  test never proved safe. This is the load-bearing "active kick must not be tuned so hot it tunnels".
- KICK_COOLDOWN_S 0.25       per-element re-trigger dead time (BUG-007 family). Gates BOTH the kick
  AND the score (unlike the target, which gates only the score): an element re-kicking every frame
  would launch a resting ball at escape velocity.

### 10.3 Element contracts (stable signatures the coders fill against)
- ActiveKicker (base): signal scored(points), signal kicked(direction), func set_ball(ball),
  var points; overridable _kick_direction_for(ball_pos), _make_body_shape(), _make_detector_shape(),
  _body_yaw(); physics TODOs _build_body() + _apply_kick(direction). The detector + mesh are built by
  the base (lead boilerplate); the SOLID body + IMPULSE are the physics half.
- PopBumper: func configure() (pulls radius/height/score from TableConfig).
- Slingshot: func configure(mirrored: bool) (picks the per-side kick direction + face yaw).
- Standup bank: REUSES target.gd unchanged, re-homed to TableConfig.STANDUP_BANK_POSITIONS.
- Lane guides: STATIC geometry built in table_geometry.gd._build_lane_guides (lead).
- Rubber flipper: physics-programmer raises the bat PhysicsMaterial bounce (BAT_BOUNCE) to a rubber
  value in flipper.gd ONLY (no drive change).

### 10.4 CAD shot validation (the deterministic geometry oracle)
tools/table_viz.py is EXTENDED to (a) DRAW the pop-bumper radial-kick fans, the slingshot kick
vectors, the standup bank, the lane guides, and the flipper-tip sweep arc on the top-down view, and
(b) VALIDATE the layout deterministically (validate_layout()): it EXITS NON-ZERO if any kick aims at
the drain, a standup target sits outside the makeable window (between the flipper-tip reach and the
arch base), a pop bumper fouls a wall, or the kick bounds fall outside the CCD-safe band. This is the
laptop-side (thin-client) pre-check; tests/test_shot_geometry.gd is the SAME checks as a GUT test (the
CI source of truth). The discipline: validate shot geometry by NUMBER, never by eyeballing the PNG.

### 10.5 Test matrix for this slice (extends sections 7 + 9.6; CI on the runner is the source of truth)

| File | Class | Proves | Owner |
|------|-------|--------|-------|
| test_pop_bumper.gd (NEW) | structural+behavioral | solid KickerBody on STATIC_OBSTACLES + detector on BALLS; a SLOW ball leaves FAST (>= KICK_MIN), directed OUTWARD (-z), capped (<= KICK_MAX); scores once; cooldown bounds farming | physics + gameplay + test-builder |
| test_slingshot.gd (NEW) | structural+behavioral | solid body on STATIC_OBSTACLES; both sides kick UP-table (-z) AND toward center; min outgoing speed; scores once; kick-dir constants point into play | physics + gameplay + test-builder |
| test_active_kicker_no_tunneling.gd (NEW) | stress | a REAL ball at >= 2x LAUNCH_SPEED_MAX never tunnels the pop-bumper or slingshot body, and post-kick speed stays <= the CCD-safe cap (stacked-kick safety) | physics + qa |
| test_flipper_rubber.gd (NEW) | structural+behavioral | bat PhysicsMaterial bounce reads as rubber (> 0.25); a ball rebounds off the RESTING flipper face preserving momentum (>= 35%, no trampoline > 115%) | physics + test-builder |
| test_furniture_layout.gd (NEW) | structural integration | the REAL Table.tscn instances the bumpers/slings/standup-bank/lane-guides on the right layers in the right regions (catches table.gd wiring gaps, the prior-slice failure mode) | test-builder + qa |
| test_shot_geometry.gd (NEW) | geometry | standup bank inside the makeable window; pop bumpers upper-middle clear of walls; sling kicks never aim at the drain; kick bounds inside the CCD-safe band | lead + qa |
| test_flipper_momentum.gd (VERIFY) | regression | stays green after the rubber surface (no drive change) | physics |
| test_ball_tunneling.gd (VERIFY) | regression | the flat-wall headline gate stays green | physics |

INDEPENDENT-ORACLE RULE (hard, unchanged): every physics assertion reads the BALL's measured
position or current_speed()/linear_velocity, never a self-reported counter. A green suite that asserts
only node existence (no measured outward velocity / no measured rebound) is a FAIL.

### 10.6 File ownership for THIS slice (DISJOINT - no two coders edit the same lines)
Read-only CONTRACT files (lead-owned; FROZEN after this scaffold):
- scripts/config/table_config.gd  the LEAD ADDED the furniture block (KICK_*, POP_BUMPER_*,
  SLINGSHOT_*, STANDUP_BANK_POSITIONS, LANE_GUIDE_*). No existing value changed. Frozen.
- scripts/config/physics_layers.gd  NO CHANGE (frozen).

Lead-programmer (architecture + static geometry + the CAD tool + this doc):
- scripts/active_kicker.gd  the shared base SHELL: detector+mesh+cooldown+score+direction dispatch +
  the geometry hooks. The physics TODOs (_build_body, _apply_kick) are clearly marked for physics.
- scripts/pop_bumper.gd, scripts/slingshot.gd  the small direction/geometry subclasses (stable).
- scripts/table.gd  instances + wires the new elements (done in this scaffold).
- scripts/table_geometry.gd  _build_lane_guides (done in this scaffold).
- scenes/elements/PopBumper.tscn, Slingshot.tscn  scene wrappers (done).
- tools/table_viz.py  the CAD shot-validation extension (done). docs/ARCHITECTURE.md (this section).

Physics-programmer (the active impulse + the solid bodies + every no-tunneling guarantee):
- scripts/active_kicker.gd  FILL _build_body() (the solid StaticBody3D "KickerBody" + shape from
  _make_body_shape() + _body_yaw() for the slingshot + a local PhysicsMaterial) and _apply_kick()
  (the capped/floored/directed impulse honoring KICK_MIN/IMPULSE/MAX). These are the ONLY two
  functions the physics-programmer touches in this file; they are disjoint from the gameplay half
  (_on_body_entered + cooldown), exactly like the target.gd deflector/detector split.
- scripts/flipper.gd  raise the bat PhysicsMaterial bounce (BAT_BOUNCE) to a rubber value. Drive
  UNCHANGED. Keep test_flipper_momentum.gd + the snap/overlap tests green (tune the material, not
  the drive, if a number drifts).
- Owns: test_pop_bumper.gd (physics asserts), test_slingshot.gd (physics asserts),
  test_active_kicker_no_tunneling.gd, test_flipper_rubber.gd, the flipper regression re-runs.

Gameplay-programmer (scoring behind the unchanged contract):
- scripts/active_kicker.gd  OWNS the detector/score/cooldown half ALREADY SCAFFOLDED (_on_body_entered
  + the KICK_COOLDOWN_S gate + scored.emit). Verify it once the physics half lands; tune nothing in
  the physics functions. game_flow.gd, hud.gd, drain.gd UNCHANGED.
- scripts/target.gd UNCHANGED (the standup bank reuses it as-is, only re-homed by table.gd).
- Owns: the behavioral score/cooldown asserts in test_pop_bumper.gd + test_slingshot.gd.

Test-builder + qa-lead:
- tests/*.gd  the six NEW files (scaffolded with the exact asserts) + the regression re-runs.

SPLIT NOTE for active_kicker.gd (one file, two roles, kept DISJOINT by function): gameplay owns
_on_body_entered + the cooldown + scored.emit (already written); physics owns _build_body + _apply_kick
(the two clearly-marked TODOs). They are different functions; land the physics half on the same slice
branch after confirming the gameplay half. Lead arbitrates if they collide.

## 11. SLICE: Table reshape + playtest fixes (gray-box, 2026-06-19)

FIRST playtest-driven slice: the developer played the deployed homelab build and reported FIVE
concrete problems. This slice fixes all five in one pass. It adds NO new mechanics or element TYPES;
it only changes shape, size, spacing, and the table WIDTH. Design intent: DESIGN.md "Slice design
intent: Table reshape + playtest fixes". As before, the physics-programmer and gameplay-programmer
fill DISJOINT files against the stable signatures here. Nothing re-litigates the scene structure
(section 2), the four physics layers (section 3), or the input map (section 4) - all UNCHANGED.

### 11.1 What stays the same (do not touch)
- SCENE STRUCTURE (section 2): UNCHANGED. Same node tree, same element scenes, same wiring in
  table.gd. The five fixes are shape/size/spacing/width changes WITHIN that tree, plus an internal
  mechanism swap in the plunger and a shape swap in the flipper.
- PHYSICS LAYERS + MASKS (section 3): UNCHANGED. NO new layer, NO mask edit. The capsule flipper
  stays a RigidBody3D on KINEMATIC_OBSTACLES (exactly the box flipper's layer); the plunger face
  stays an AnimatableBody3D on KINEMATIC_OBSTACLES; the widened walls/furniture stay STATIC_OBSTACLES
  / Area3D detectors. So the flipper/ball tests CANNOT regress from a layer/mask change (there is
  none). This is the shared-physics audit result for this slice: the only shared surface touched is
  the world-scale CONTRACT (TableConfig X-constants), which is the lead's single edit.
- INPUT MAP (section 4): UNCHANGED. No new actions; same left_flipper/right_flipper/launch/nudge.
- THE PLUNGER PUBLIC CONTRACT: UNCHANGED byte-for-byte (power_changed/ball_launched; arm/disarm/
  set_ball/is_armed; power 0..1; the oscillating meter + the power->stroke-speed mapping). The launch
  FIX is INTERNAL: swap the unreliable sync_to_physics momentum transfer for one that genuinely
  imparts velocity on the plunger-ball CONTACT. test_strike_at_power / face_position / is_stroking /
  stroke_speed test hooks STAY.
- THE FLIPPER PUBLIC CONTRACT + DRIVE: UNCHANGED. configure()/is_energized()/tip_speed()/
  force_energized() stay; BAT_MASS 0.40 / BAT_BOUNCE 0.70 stay (the rubber-rebound >= 35% gate); the
  force/hinge/return-spring drive, the ~50 ms snap, the cradle, and _apply_handedness stay. Only the
  bat SHAPE (mesh AND collider) changes from a box to a tapered rounded stadium.
- TARGET / ACTIVE-KICKER PUBLIC CONTRACTS: UNCHANGED. Only sizes/positions (TableConfig + the target
  POST size) change.

### 11.2 Fix 1 - LAUNCH (internal mechanism swap, plunger.gd) - PHYSICS
ROOT CAUSE (code review): the plunger is a kinematic AnimatableBody3D that relies on
sync_to_physics to shove the ball during its FORWARD stroke (plunger.gd _build_face sets
sync_to_physics = true; _advance_stroke moves the face by setting .position). In Godot's built-in
Jolt this transform-derived velocity often does NOT transfer to the resting ball, so the ball never
moves - the deployed plunger is dead.
FIX (physics-programmer's discretion, behind the EXACT contract): replace the unreliable transfer
with a mechanism that genuinely imparts velocity ON THE CONTACT. Acceptable options (pick one,
document the WHY):
  (a) drive the kinematic face with a reported/constant_linear_velocity each forward frame
      (AnimatableBody3D + set the body's reported linear velocity), so Jolt sees a moving body with
      real velocity at the contact; OR
  (b) move_and_collide the face and, on the reported collision with the ball, apply the contact
      impulse the face's motion implies; OR
  (c) detect the plunger-ball contact and apply_central_impulse to the ball sized from the stroke
      speed (an impulse-on-contact - still a CONTACT event, not a free velocity set).
HARD CONSTRAINTS the launch test (test_plunger_launch.gd) asserts and the physics-programmer honors:
  - Production launch comes FROM the contact/impulse, NOT from a code velocity set on the ball
    (ball.launch() stays demoted/unused in production - QA BUG-017).
  - From rest, more meter => faster ball (monotonic); full strike >= 1.5x a weak one; resulting
    ball speed lands ~LAUNCH_SPEED_MIN..MAX (the existing mapping/tuning is NOT re-litigated).
  - A release with NO ball present is a no-op.
  - A max strike never tunnels the face or the lane pocket (ball CCD + the cap stay safe).
  - The plunger body stays VISIBLE and seated behind the ball at PLUNGER_REST_POS (now x=13.25 after
    the widen - this auto-follows since PLUNGER_REST_POS.x is (LANE_INNER_X+HALF_WIDTH)*0.5).
FILES: scripts/plunger.gd (internal mechanism), scripts/ball.gd (only if the chosen mechanism needs
a material/CCD/contact-report touch), scripts/config/table_config.gd is LEAD-frozen after the widen
(physics reads, does not edit).

### 11.3 Fix 2 - CAPSULE FLIPPER (shape swap, flipper.gd) - PHYSICS
Replace the BoxMesh/BoxShape3D bat with a tapered rounded "stadium" form (fatter at the pivot,
smaller rounded tip) in BOTH the visible mesh AND the collision shape, with the collider and mesh
AGREEING. Implementation at the physics-programmer's discretion within these constraints:
  - COLLIDER: a CapsuleShape3D (laid along the bat's long X axis) OR a ConvexPolygonShape3D hull that
    matches the visible tapered mesh. It must NOT be a BoxShape3D (the structural test asserts this).
    A CapsuleShape3D is the simplest "stadium": rounded ends, constant radius - acceptable as the
    gray-box shape. A taper (fat pivot -> thin tip) is the design intent; a convex hull or a
    capsule-plus-taper-scale both satisfy it. Keep ONE end at the pivot and taper toward the tip, on
    the SAME _apply_handedness logic (the bat must still extend toward center for both sides - the
    offset sign in _apply_handedness must follow the new shape's long axis exactly as it does the box
    half-length today).
  - MESH: a matching capsule/tapered mesh (CapsuleMesh or a built mesh) so the collider and the
    visible bat agree - "where on the bat the ball hits matters".
  - MATERIAL: a 2-tone gray-box look - BLACK body + WHITE rubber TOP surface. Gray-box materials
    only (StandardMaterial3D albedo); the kenney.nl CC0 art pass is LATER and must NOT block this
    slice. The white "rubber top" is a visual cue for the rubber surface; the rubber FEEL stays
    BAT_BOUNCE 0.70 (unchanged).
  - PRESERVE: BAT_MASS 0.40, BAT_BOUNCE 0.70, the drive, the snap, the cradle, the hinge limits, and
    every test hook. tip_speed() still reads |omega about the hinge axis| * FLIPPER_LENGTH (the lever
    arm is the pivot-to-tip distance, unchanged by the shape).
  - NO TUNNELING at >= 2x LAUNCH_SPEED_MAX (the bat keeps continuous_cd = true).
FILE: scripts/flipper.gd ONLY.

### 11.4 Fix 3 - WIDER TABLE (world-scale rescale, table_config.gd) - LEAD (DONE in this scaffold)
HALF_WIDTH 12 -> 16 (~33% wider); HALF_LENGTH stays 25 (widen only). The lead RE-DERIVED every
X-dependent constant with a WHY-comment. Summary of the rescale (the code in table_config.gd is the
source of truth):
  - HALF_WIDTH 12 -> 16. ARCH_RADIUS_X = HALF_WIDTH auto-follows (spans the new width). DRAIN_WIDTH /
    DRAIN_CENTER_X are HALF_WIDTH/LANE_INNER_X expressions, auto-follow. The perimeter/surface in
    table_geometry.gd are all HALF_WIDTH expressions, auto-follow.
  - LANE_INNER_X 8 -> 10.5 (lane width 4 -> 5.5, kept proportional). LANE_WIDTH, PLUNGER_FACE_WIDTH
    (LANE_WIDTH-0.6), PLUNGER_REST_POS.x ((LANE_INNER_X+HALF_WIDTH)*0.5 = 13.25), lane-pocket width
    all auto-follow. BALL_START.x re-derived to the lane center 13.25 (was a stale literal 10.0).
  - FLIPPER_PIVOT_SPREAD 7.0 -> 7.2: the drain mouth is held at ~2.46 units (~2 ball diameters, NOT
    a chasm) by NOT scaling the gap with the width; the pivots move out just enough to deliver that
    mouth while nudging the flippers outward on the wider field. Verified: gap = 2*7.2 - 11.94 = 2.46.
  - LANE_GUIDE_DIVIDER_X = HALF_WIDTH - 3.0 (auto to 13.0): holds the OUTLANE at ~3.0 units while the
    INLANE widens to ~5.8 with the table (both gutters per side; fix 4).
  - Furniture X (the hardcoded arrays): POP_BUMPER_POSITIONS +/-4.5 -> +/-6.0; SLINGSHOT_*_POS
    +/-8.5 -> +/-10.5 (outboard of the new pivots); STANDUP_BANK_POSITIONS +/-3.0 -> +/-4.5.
  - RESIZE (fix 5): POP_BUMPER_RADIUS 1.6 -> 2.0.
Re-validated DETERMINISTICALLY by tools/table_viz.py validate_layout() (PASSES on the new constants;
FAILS on a deliberately-broken one - verified) and by test_world_scale.gd / test_furniture_layout.gd
/ test_shot_geometry.gd (the GUT source of truth; the test-builder updates the width-dependent
asserts). Nothing ends in a wall, off-field, or across the centerline.
FILES: scripts/config/table_config.gd (DONE), scripts/table_geometry.gd (already all-expressions, no
literal X to change - verified).

### 11.5 Fix 4 - GUTTERS BOTH SIDES (verify, table_geometry.gd) - LEAD/QA
table_geometry._build_lane_guides ALREADY builds LaneGuideLeft AND LaneGuideRight symmetrically
(a for-loop over sign [-1, 1]) on STATIC_OBSTACLES, and test_furniture_layout asserts both. The
developer's "only a left gutter" is almost certainly a STALE CACHED BUILD. After the widen both
guides auto-follow LANE_GUIDE_DIVIDER_X (= 13.0). DELIVERABLE: VERIFY both build and read as
outlane/inlane gutters on the rebuilt scene (test_furniture_layout green + table_viz feed-path plot
shows both); only fix the right one if it is genuinely missing/weak. No new gutter system.
FILE: scripts/table_geometry.gd (verify; edit only if a real defect is found).

### 11.6 Fix 5 - RESIZE + RESPACE TARGETS AND BUMPERS - GAMEPLAY + PHYSICS
The TableConfig half is DONE (POP_BUMPER_RADIUS 2.0; +/-6.0 bumpers; +/-4.5 standup bank). The
remaining half:
  - GAMEPLAY: raise the standup target POST size in scripts/target.gd (POST_RADIUS up, e.g. 1.5 ->
    ~2.0, and keep the detector shell = POST_RADIUS + BALL_RADIUS). Bigger target reads as
    aim-able; keep it inside the makeable window (test_shot_geometry). table.gd already re-homes the
    targets to STANDUP_BANK_POSITIONS (no table.gd edit needed).
  - PHYSICS: confirm the bigger pop bumper / target bodies still hold the no-tunnel gate at >= 2x
    LAUNCH_SPEED_MAX (a bigger static body is EASIER not to tunnel, but assert it).
FILES: scripts/target.gd (gameplay: POST_RADIUS), scripts/config/table_config.gd (LEAD-frozen;
already resized), scripts/table.gd (no edit - reads the constants).

### 11.7 Test matrix for this slice (extends sections 7 / 9.6 / 10.5; CI is the source of truth)

| File | Class | Proves | Owner |
|------|-------|--------|-------|
| test_flipper_shape.gd (NEW) | structural | the flipper collider is a CapsuleShape3D or ConvexPolygonShape3D, NOT a BoxShape3D; the mesh is a matching non-box mesh; bat carries the rubber PhysicsMaterial (bounce 0.70) | physics + test-builder |
| test_plunger_launch.gd (UPDATE) | behavioral+stress | from rest a release imparts REAL measured velocity (no ball.launch()); monotonic (full >= 1.5x weak); speed ~LAUNCH_SPEED_MIN..MAX; no-ball is a no-op; max strike never tunnels the face/pocket. Re-confirm against the NEW launch mechanism + the widened lane (x=13.25). | physics + test-builder |
| test_plunger.gd (VERIFY) | contract | the unchanged plunger contract + stroke_speed mapping stay green | gameplay |
| test_flipper_momentum.gd (VERIFY) | regression | full swing out-throws a tap; ~50 ms snap - green after the shape swap (drive unchanged) | physics |
| test_flipper_rubber.gd (VERIFY) | regression | rubber rebound >= 35% off the resting face - green with the capsule shape (the _face_normal helper reads the LIVE bat basis, so it tracks the new shape's long axis) | physics |
| test_world_scale.gd (UPDATE) | structural | the scale asserts pass at HALF_WIDTH 16: BALL_START in the new lane; flipper gap > 0; the existing internal-consistency checks | test-builder |
| test_furniture_layout.gd (UPDATE/VERIFY) | structural integration | the REAL Table.tscn instances bumpers/slings/standup-bank on the right layers at the NEW positions; BOTH LaneGuideLeft AND LaneGuideRight present on STATIC_OBSTACLES (fix 4) | test-builder + qa |
| test_shot_geometry.gd (VERIFY/UPDATE) | geometry | standup bank inside the makeable window and bumpers clear of walls on the NEW constants; sling kicks never aim at the drain; kick bounds in the CCD-safe band | lead + qa |
| test_pop_bumper.gd / test_slingshot.gd (VERIFY) | behavioral | kick + score on contact still hold at the new sizes/positions | physics + gameplay |
| test_active_kicker_no_tunneling.gd (VERIFY) | stress | no tunneling through the bigger bumper/sling bodies at >= 2x LAUNCH_SPEED_MAX | physics + qa |
| test_ball_tunneling.gd (VERIFY) | regression | the flat-wall headline gate stays green at the new width | physics |
| test_scene_structure.gd / test_table_integration.gd (VERIFY) | render/integration | the real scene still builds + frames at the new width (the framer is HALF_WIDTH-driven, auto-follows) | test-builder |

INDEPENDENT-ORACLE RULE (hard, unchanged): every physics assertion reads the BALL's measured
position or current_speed()/linear_velocity, never a self-reported counter. A green suite that asserts
only node existence (no measured launch velocity / no measured rebound / no measured non-box shape)
is a FAIL ("test the game like a web app": structural AND behavioral AND stress).

### 11.8 File ownership for THIS slice (DISJOINT - no two coders edit the same lines)
Read-only CONTRACT files (lead-owned; FROZEN after this scaffold):
- scripts/config/table_config.gd  the WIDEN rescale (DONE: HALF_WIDTH 16 + every X-derivation +
  the furniture resize/respace). No further edits; physics/gameplay READ it. Frozen.
- scripts/config/physics_layers.gd  NO CHANGE (frozen).

Lead-programmer (architecture + the rescale + static geometry verify + the CAD tool + this doc):
- scripts/config/table_config.gd  the widen (DONE).
- scripts/table_geometry.gd  VERIFY both gutters build at the new width (all-expression geometry,
  no literal X to change - confirmed; edit only if a real defect surfaces).
- tools/table_viz.py  fixed the stale TARGET_POSITIONS parse + re-validated the new layout (DONE).
- scripts/table.gd  NO edit expected (it reads the constants; the framer is HALF_WIDTH-driven).
- docs/ARCHITECTURE.md (this section), docs/BACKLOG.md slice tasks.

Physics-programmer (the launch mechanism + the capsule shape + every no-tunnel guarantee):
- scripts/plunger.gd  INTERNAL: swap the launch mechanism (11.2) behind the unchanged contract.
- scripts/flipper.gd  the capsule/convex SHAPE swap + the 2-tone material (11.3). Drive unchanged.
- scripts/ball.gd  ONLY if the chosen launch mechanism needs a contact-report/material/CCD touch.
- scripts/target.gd  ONLY the no-tunnel re-confirm on the bigger post (the POST_RADIUS bump is
  gameplay's, below - keep the two halves disjoint by function as in 9.7).
- Owns: test_flipper_shape.gd physics asserts, test_plunger_launch.gd, the flipper + tunneling
  regression re-runs.

Gameplay-programmer (sizes/positions behind the unchanged contracts):
- scripts/target.gd  raise POST_RADIUS (and keep the detector shell = POST_RADIUS + BALL_RADIUS)
  for the bigger standup target (11.6). PUBLIC contract unchanged.
- scripts/plunger.gd  re-verify the public contract after the physics mechanism swap (do NOT touch
  the mechanism). game_flow.gd, hud.gd, drain.gd, active_kicker.gd UNCHANGED.
- Owns: test_plunger.gd verify, the behavioral score asserts in test_pop_bumper/test_slingshot.

  SPLIT NOTE for target.gd (one file, two roles, kept DISJOINT by function): gameplay owns the
  POST_RADIUS / detector / _on_body_entered half; physics owns _build_deflector + the no-trap/no-
  tunnel guarantee. Land the gameplay POST_RADIUS bump first, then the physics no-tunnel re-confirm,
  on the same slice branch in sequence. Lead arbitrates if they collide.

Test-builder + qa-lead:
- tests/*.gd  the ONE new file (test_flipper_shape.gd) + the width/furniture UPDATES + the VERIFY
  re-runs. Update the width-dependent asserts in test_world_scale / test_furniture_layout /
  test_shot_geometry for HALF_WIDTH 16. addons/gut already vendored.

## 12. SLICE: Playtest fixes 2 (gray-box, physics-based, 2026-06-20)
Second playtest-driven FIX pass on the deployed wider table (main 286356e). DESIGN intent: docs/
DESIGN.md "Slice design intent: Playtest fixes 2"; cut list "Cut from the Playtest fixes 2 slice".
Eight items: two CORRECTNESS (soft-lock recovery, lane/plunger resize), two SHAPE/MATERIAL (right-
flipper rubber top, triangular slingshots), four UX (every-ball prompt, named restart key, colorblind
meter, bigger HUD font). NO new element TYPES; same COUNTS (3 bumpers, 3 targets, 2 slings, 2
flippers, 1 plunger, 2 gutters). This is NOT a table rescale: HALF_WIDTH 16 / HALF_LENGTH 25 / ball
radius 0.6 / gravity 200 / flipper geometry / furniture positions all STAY (only the LANE narrows and
the PLUNGER FACE + SLINGSHOT shapes + the FLIPPER material change).

### 12.0 What is UNCHANGED (the contracts every fix lives behind)
- SCENE TREE (section 5): unchanged. Same Table -> Playfield -> {geometry, flippers, targets,
  bumpers, slings, plunger, drains, ball} + GameFlow + HUD. The fixes are internal to those nodes.
- PHYSICS LAYERS + MASKS (section 3): UNCHANGED. NO new layer, NO mask edit. The triangular sling
  body stays a StaticBody3D on STATIC_OBSTACLES (exactly the box sling's layer); the resized plunger
  face stays an AnimatableBody3D on KINEMATIC_OBSTACLES. The flipper/ball tests CANNOT regress from a
  layer change (there is none).
- INPUT MAP (section 4): UNCHANGED. launch is still SPACE (the named restart key in fix 6).
- PLUNGER PUBLIC CONTRACT: UNCHANGED (power_changed/ball_launched; arm/disarm/set_ball/is_armed;
  power 0..1; the meter + power->stroke-speed mapping; the test hooks). The face RESIZE and the soft-
  lock re-arm are INTERNAL / behind it.
- FLIPPER PUBLIC CONTRACT + DRIVE: UNCHANGED. configure/is_energized/tip_speed/force_energized;
  BAT_MASS 0.40 / BAT_BOUNCE 0.70; the drive, snap, cradle, _apply_handedness, the convex-hull shape.
  Fix 2 is MATERIAL/MESH-WINDING correctness only.
- SLINGSHOT / ACTIVE-KICKER KICK CONTRACT: UNCHANGED. scored/kicked/set_ball; the kick DIRECTION
  (SLINGSHOT_LEFT/RIGHT_KICK_DIR), the cap/floor (KICK_MIN/MAX), the cooldown (KICK_COOLDOWN_S), the
  BUG-018 corner detector guarantee. Fix 3 is a SHAPE swap (box -> triangular hull) behind that kick.
- GameFlow public SIGNATURES: start_game/on_target_scored/on_ball_launched/on_ball_drained/restart/
  current_state STAY. The soft-lock fix ADDS new contract (LAUNCHING state, request_relaunch,
  tick_launch_watch, notify_ball_reached_play, on_launch_failed) - additive, not a break.

### 12.1 Fix 1 - SOFT-LOCK RECOVERY (state machine + watchdog) - GAMEPLAY + PHYSICS
ROOT CAUSE: on_ball_launched went READY_TO_LAUNCH -> BALL_IN_PLAY and the plunger disarmed. A ball
that never reached play and never drained left the machine stuck in BALL_IN_PLAY with a dead plunger
forever - the reported soft-lock. A too-weak launch (dribble back) or a stall is unrecoverable.
THE FIX (a positional watchdog, NOT a ball-save, NOT a new mechanic):
  - GameFlow gains a LAUNCHING state between launch and confirmed-in-play. on_ball_launched enters
    LAUNCHING (not BALL_IN_PLAY).
  - table.gd._physics_process feeds the ball's MEASURED playfield-local Z to
    GameFlow.tick_launch_watch(ball.position.z, delta) every frame (independent oracle - the real
    body position, never a flag). GameFlow only acts on it while LAUNCHING.
  - tick_launch_watch: if the ball crossed up-table of TableConfig.LAUNCH_REACHED_PLAY_Z (=
    FLIPPER_PIVOT_Z) -> notify_ball_reached_play -> BALL_IN_PLAY (normal play, drain/spend unchanged);
    else once TableConfig.LAUNCH_SETTLE_TIME_S (2.0 s) elapses with the ball still in the lane ->
    on_launch_failed -> READY_TO_LAUNCH + request_relaunch (re-seat + re-arm the SAME ball), and
    CRITICALLY no balls_changed (no ball spent).
  - table.gd wires request_relaunch to the SAME _on_request_new_ball reset+arm path as a new ball; the
    distinct signal makes the recovery intent explicit and lets a test tell a recovery from a fresh
    ball (no ball consumed).
THRESHOLD CONTRACT (TableConfig, with WHY-comments): LAUNCH_REACHED_PLAY_Z = FLIPPER_PIVOT_Z (the
ball is unambiguously in play once it is up-table of the flipper row; a dribble stays near z=23, far
down-table of the 20.0 line); LAUNCH_SETTLE_TIME_S = 2.0 (a real launch crosses the line in well
under a second; 2.0 s never falsely recovers a slow-but-successful launch yet breaks a real soft-lock
fast). The watchdog re-checks each frame after the timer so a ball crawling up after the window is
still handled correctly.
FILES: scripts/game_flow.gd (state + recovery, GAMEPLAY), scripts/table.gd (feed the watchdog + wire
request_relaunch, LEAD wiring), scripts/config/table_config.gd (the two threshold constants, LEAD),
scripts/ball.gd (only if the physics-programmer needs a re-seat/contact tweak; reset_to_start already
exists). PHYSICS owns confirming the positional oracle is robust against tilt drift in the live scene.

### 12.2 Fix 2 - RIGHT FLIPPER RUBBER TOP (mesh winding) - PHYSICS
ROOT CAUSE: _rebuild_bat_geometry mirrors the bat outline by negating X for the right flipper, which
REVERSES the perimeter winding. _build_bat_mesh wound the top cap (surface 1, RUBBER_TOP_COLOR) and
sides for the +X order, so on the mirrored bat the white top cap faces DOWN (-Y) and is backface-
culled - the right flipper renders all black.
THE FIX (lead scaffolded the correction point; physics owns/verifies it): _build_bat_mesh now takes
hand_sign and emits every triangle through _emit_tri(..., flip := hand_sign < 0), which swaps the two
non-apex vertices for the mirrored bat so all windings (top cap, bottom cap, sides) keep their normals
facing the same way. The white rubber top faces +Y on BOTH bats. Drive/shape/material UNCHANGED.
FILE: scripts/flipper.gd ONLY.

### 12.3 Fix 3 - TRIANGULAR SLINGSHOTS (shape swap behind the same kick) - PHYSICS (+ gameplay verify)
ROOT CAUSE: slingshot._make_body_shape returned a BoxShape3D and the base drew a generic box mesh, so
the slings read as small squares.
THE FIX: a triangular prism. active_kicker.gd gains a _make_mesh() override hook (the base returns the
old box for the round pop bumper; the slingshot overrides it). slingshot.gd builds a right-triangle
footprint via _triangle_outline (long KICKING FACE along local +X at +Z so its normal is +Z, which
_body_yaw rotates to the EXISTING kick direction - the kick is byte-for-byte unchanged), apex offset
per handedness (left- vs right-handed), extruded to a ConvexPolygonShape3D body + a matching mesh
(they AGREE). The detector is the same triangle padded one BALL_RADIUS (keeps the BUG-018 corner-
contact guarantee). TRIANGLE_BACK_DEPTH is a local proportion constant (no TableConfig edit). Kick
direction/score/cooldown/CCD cap UNCHANGED (the base owns them). PHYSICS owns the no-tunnel re-confirm
on the triangular face; gameplay re-verifies score/cooldown unchanged.
FILES: scripts/slingshot.gd (triangle shape + mesh), scripts/active_kicker.gd (the _make_mesh hook).

### 12.4 Fix 4 - LANE + PLUNGER RESIZE (TableConfig geometry) - LEAD (+ physics verify)
The lane narrows to a snug ~ball-width chute: LANE_INNER_X 10.5 -> 14.0 (LANE_WIDTH 5.5 -> 2.0, ~1.7
ball diameters). PLUNGER_FACE_WIDTH = LANE_WIDTH - 0.6 auto-follows to 1.4 (a ball-and-a-bit, wider
than the 1.2 ball so an off-center rest is struck square, fits the lane with clearance). The lane
center moves to 15.0; BALL_START.x re-derived 13.25 -> 15.0 (the lane center, head-on with the face;
PLUNGER_REST_POS.x is the same expression, auto-follows). The right lane-guide divider (9.0) still
sits inboard of the new lane (between pivot 7.2 and 14.0), no change. NOT a rescale: HALF_WIDTH 16 /
HALF_LENGTH 25 stay. Re-validated DETERMINISTICALLY by tools/table_viz.py validate_layout() (new check
5: the lane is a snug ball-width chute, the ball is centered and inside the lane, the face is wider
than the ball and fits the lane) - PASSES on the new constants, EXITS NON-ZERO on a broken lane
(verified). PHYSICS confirms the resized face still strikes the seated ball with no gap and never
tunnels (test_plunger_launch). FILES: scripts/config/table_config.gd (LEAD), tools/table_viz.py
(LEAD), scripts/plunger.gd / scripts/table_geometry.gd (READ the constants - face box + lane pocket
auto-follow PLUNGER_FACE_WIDTH / LANE_WIDTH; no literal edit expected, physics verifies).

### 12.5 Fixes 5-8 - UX WIRING (Gate-0 readiness, no CI gate) - GAMEPLAY
5. EVERY-BALL PROMPT: GameFlow.on_ball_drained re-arm now emits "BALL DRAINED\nHOLD LAUNCH - release
   to fire" (was just "BALL DRAINED"); on_launch_failed re-emits the prompt too. Ball 1 already got it
   from start_game. So the prompt appears on every ball arm.
6. NAMED RESTART KEY: hud.show_game_over says "press SPACE to restart" (launch is bound to SPACE,
   verified in project.godot). Was the ambiguous "press LAUNCH to restart".
7. COLORBLIND-SAFE METER: hud.set_meter already encodes power as bar WIDTH (the primary cue); the
   color lerp is now explicitly SECONDARY and a high-contrast white OUTLINE (METER_OUTLINE_COLOR) is
   drawn around the meter so the filled LENGTH reads without relying on hue.
8. BIGGER HUD FONT: hud._apply_font_size sets HUD_FONT_SIZE (28) on every label and
   GAME_OVER_FONT_SIZE (34) on the game-over panel via add_theme_font_size_override.
FILE: scripts/hud.gd (6/7/8), scripts/game_flow.gd (5). These do not fail CI but are in scope; folded
in, not deferred.

### 12.6 Physics north-star (unchanged, re-asserted on the new shapes)
Ball continuous_cd at 240 Hz; ZERO tunneling at >= ~2x LAUNCH_SPEED_MAX through the RESIZED plunger
face and the NEW triangular slingshot face (and every existing body). Proven by GUT against REAL
instanced bodies measuring real position/velocity (independent oracle). The triangular sling body is
STATIC and the kick stays capped at KICK_MAX_OUTGOING_SPEED (120, well under the 180 stress band), so
the no-tunnel gate holds exactly as the box sling's did - physics RE-CONFIRMS, does not re-tune.

### 12.7 Test matrix for this slice (CI is the source of truth; independent-oracle rule applies)

| File | Class | Proves | Owner |
|------|-------|--------|-------|
| test_soft_lock_recovery.gd (NEW) | behavioral | a too-weak launch recovers (READY_TO_LAUNCH + request_relaunch) and does NOT spend a ball; a launch that reaches play promotes to BALL_IN_PLAY; a genuine drain still spends; the every-ball prompt re-issues. Real GameFlow state + ball count + signals, never a counter. | gameplay + test-builder |
| test_flipper_rubber_top.gd (NEW) | structural | BOTH bats carry the white RUBBER_TOP_COLOR surface AND the right bat's top cap faces +Y (not culled). Real instanced left + right mesh surfaces/normals. | physics + test-builder |
| test_plunger_lane_size.gd (NEW) | structural | LANE_WIDTH is a snug ball-width chute; PLUNGER_FACE_WIDTH is wider than the ball and fits the lane; ball + plunger share the lane center; the BUILT PlungerFace box width == PLUNGER_FACE_WIDTH. | lead + test-builder |
| test_slingshot.gd (UPDATE) | structural | the slingshot body is a ConvexPolygonShape3D (NOT a box) and the mesh is non-box; left and right are MIRRORED; the existing kick-into-play / score / corner-contact behavioral tests stay green. | physics + gameplay + test-builder |
| test_plunger_launch.gd (VERIFY) | behavioral+stress | the RESIZED face still launches from rest on the first stroke (monotonic, in-range, no-ball no-op) and never tunnels the face/pocket at the new lane width (x=15.0). | physics + test-builder |
| test_plunger.gd (VERIFY) | contract | the unchanged plunger contract + stroke_speed mapping stay green. | gameplay |
| test_flipper_momentum.gd / test_flipper_rubber.gd / test_flipper_shape.gd / test_flipper_no_overlap.gd (VERIFY) | regression | drive/snap/rebound/shape unchanged after the mesh-winding fix (the fix touches only mesh winding, not the collider or drive). | physics |
| test_active_kicker_no_tunneling.gd (VERIFY/EXTEND) | stress | no tunneling through the NEW triangular sling face at >= ~2x LAUNCH_SPEED_MAX, real instanced body. | physics + qa |
| test_shot_geometry.gd (VERIFY) | geometry | sling kicks still point into play on the unchanged kick dirs; the new lane geometry validates. | lead + qa |
| test_world_scale.gd / test_furniture_layout.gd / test_table_integration.gd (UPDATE/VERIFY) | structural integration | the new LANE_WIDTH / BALL_START / lane-pocket are consistent; the real Table.tscn still builds + the ball seats in the resized lane. | test-builder |
| test_game_flow.gd (UPDATE) | unit | the new LAUNCHING state + transitions are exercised; existing transitions still pass with the new state inserted. | gameplay + test-builder |

INDEPENDENT-ORACLE RULE (hard): every physics/behavioral assertion reads the REAL ball position /
current_speed()/linear_velocity OR the REAL built node's shape/material, never a self-reported flag.
The soft-lock behavioral test is MANDATORY and NEW.

### 12.8 File ownership for THIS slice (DISJOINT - no two coders edit the same lines)
Read-only CONTRACT files (lead-owned; FROZEN after this scaffold):
- scripts/config/table_config.gd  the lane/plunger RESIZE (LANE_INNER_X/LANE_WIDTH/BALL_START) + the
  two soft-lock threshold constants (LAUNCH_REACHED_PLAY_Z, LAUNCH_SETTLE_TIME_S). No further edits;
  physics/gameplay READ it. Frozen.
- scripts/config/physics_layers.gd  NO CHANGE (frozen).

Lead-programmer (geometry resize + the watchdog wiring + the CAD tool + this doc):
- scripts/config/table_config.gd  the resize + thresholds (DONE).
- scripts/table.gd  feed GameFlow.tick_launch_watch from _physics_process + wire request_relaunch
  (DONE - wiring only, no game rules).
- tools/table_viz.py  the lane-fit validation check 5 (DONE; PASSES on the new constants, fails a
  broken lane - verified).
- scripts/active_kicker.gd  the _make_mesh() override HOOK (DONE - boilerplate, the base returns the
  old box; the slingshot fills the triangle mesh).
- docs/ARCHITECTURE.md (this section), docs/BACKLOG.md slice tasks.

Physics-programmer (the soft-lock positional oracle + the flipper winding + the triangle no-tunnel):
- scripts/game_flow.gd  ONLY if the positional oracle needs a different threshold/logic than the
  scaffold (the recovery state machine itself is gameplay's, below - keep disjoint by function:
  physics owns "did it reach play" detection robustness, gameplay owns the state transitions).
- scripts/flipper.gd  fix 2: verify/tune the _emit_tri winding correction so the right bat's rubber
  top faces +Y (the scaffold implements it; physics confirms in the headless render-surface test).
- scripts/slingshot.gd  fix 3: own the triangular body's no-tunnel guarantee; tune TRIANGLE_BACK_DEPTH
  if the stress test needs it. The triangle outline + mesh are scaffolded; physics owns correctness.
- scripts/ball.gd  ONLY if the soft-lock re-seat needs a contact/sleep tweak (reset_to_start exists).
- Owns: test_flipper_rubber_top.gd physics/render asserts, test_plunger_launch.gd re-confirm, the
  triangular sling no-tunnel re-run, the soft-lock positional-oracle robustness in the live scene.

Gameplay-programmer (the recovery state machine + the UX wiring):
- scripts/game_flow.gd  the LAUNCHING state + tick_launch_watch/notify_ball_reached_play/
  on_launch_failed + the every-ball prompt (scaffolded functional; gameplay owns/finishes it).
- scripts/hud.gd  fixes 6/7/8 (named restart key, colorblind meter outline, bigger font) - scaffolded
  functional; gameplay/ux finishes/tunes the visual values.
- scripts/plunger.gd  re-verify the public contract after the lane resize (it READS the resized
  constants; no internal mechanism edit for this slice).
- Owns: test_soft_lock_recovery.gd behavioral asserts, test_game_flow.gd state-machine update,
  test_slingshot.gd score/cooldown verify.

Test-builder + qa-lead:
- tests/*.gd  the three NEW files (test_soft_lock_recovery, test_flipper_rubber_top,
  test_plunger_lane_size) + the test_slingshot triangle structural UPDATE + the VERIFY re-runs +
  the width-dependent UPDATES (test_world_scale / test_furniture_layout / test_table_integration for
  LANE_WIDTH 2.0 / BALL_START.x 15.0). addons/gut already vendored.

## 13. SLICE: Fix the launch (gray-box, physics-based, 2026-06-20)

Owner: lead-programmer (this section + the test scaffolds + the file-ownership split).
This slice fixes a CONFIRMED playability bug on main: the ball climbs partway up the launch chute,
stalls, and rolls back, so play cannot start across the power meter. It is a CORRECTNESS slice:
launch SPEED tuning + a new behavioral lane-clear TEST (+ a friction/small-widen tweak ONLY IF the
measurement proves rattle is a real cause). NO new element types, no rescale, no re-home, no flipper/
meter/watchdog re-tune. The plunger contract and impulse-on-contact launch are UNCHANGED. Design
intent: DESIGN.md "Slice design intent: Fix the launch"; backlog: BACKLOG.md "SLICE: Fix the launch".

### 13.1 The bug, in the geometry (designer's read; physics MEASURES it before fixing)
The numbers fall out of the LOCKED TableConfig geometry, not a guess:
- The ball rests at BALL_START.z = HALF_LENGTH - 2.0 = 23.0. The arch curves over at
  ARCH_CENTER_Z = -HALF_LENGTH + 6.0 = -19.0. The up-table climb from rest to the arch is ~42 units.
- The down-slope deceleration on the 7-degree tilt is GRAVITY * sin(TILT_DEG) = 200 * sin(7) =
  ~24.4 u/s^2.
- Clearing 42 units from rest therefore needs ~sqrt(2 * 24.4 * 42) = ~45.3 u/s AT THE BALL, BEFORE
  any loss to wall rattle or friction.
- But LAUNCH_SPEED_MIN = 30 and PLUNGER_STROKE_SPEED_MIN = 30: the ENTIRE LOWER HALF of the meter
  delivers a ball that physically cannot reach the arch. It climbs, stalls, rolls back. The bottom of
  the meter is a DEAD ZONE. This is primary cause (a): the speed FLOOR is below what the lane needs.

### 13.2 Diagnose by measurement FIRST (physics-programmer, do NOT guess)
Headless, on the REAL tilted Playfield with the REAL TableGeometry (build EXACTLY as
tests/test_plunger_launch.gd does: a Playfield Node3D rotated TILT_DEG about X, TableGeometry.build,
the shipping Plunger.tscn + Ball.tscn, plunger.set_ball(ball), ball.reset_to_start). Fire
test_strike_at_power at MIN (0.0), MID (0.5), MAX (1.0) and MEASURE, per power level:
  (a) the ball's current_speed() just after the strike resolves (sample the PEAK over the first
      ~12 frames, like test_full_strike_peak_speed_stays_under_double_energy_ceiling), and
  (b) the APEX: the LOWEST z (most up-table, -Z) the ball center reaches before it rolls back
      (track min(ball.position.z) each frame over ~2-3 s, before any down-roll).
Then NAME which cause(s) are true from the numbers:
  (a) FLOOR TOO LOW: delivered speed at MIN < the ~45.3 u/s climb requirement, and/or apex at MIN/MID
      stalls down-table of LAUNCH_REACHED_PLAY_Z (= FLIPPER_PIVOT_Z - 3.5 = 16.5) without clearing.
  (b) IMPULSE UNDER-DELIVERS: delivered speed at MAX < LAUNCH_SPEED_MAX (90). The impulse sizes the
      ball to _stroke_speed (PLUNGER_STROKE_SPEED_MAX = 78, not 90), so even a perfect transfer tops
      out at ~78; confirm whether the real transfer lands there or lower.
  (c) RATTLE/FRICTION STALL: the apex at MID is well short of what (a)'s ballistic math predicts from
      the measured delivered speed (energy was bled to BALL_FRICTION 0.4 + wall contacts in the snug
      2.0-unit lane), i.e. delivered speed looks adequate but the ball still does not clear.
REPORT the six numbers (speed + apex at MIN/MID/MAX) in the deliverable. The fix is sized FROM them.

### 13.3 The fix - tuning, sized to the geometry (physics-programmer + lead)
Fix the MEASURED cause(s). The expected primary fix is RAISING THE FLOOR; the secondaries are
conditional on the measurement.
- RAISE LAUNCH_SPEED_MIN and PLUNGER_STROKE_SPEED_MIN so EVEN A MIN plunge clears the lane into play
  with margin. The floor must exceed ~45.3 u/s (the ballistic climb requirement) PLUS the measured
  rattle/friction loss PLUS a sensible safety margin. A reasonable target (physics confirms from the
  measurement) is a floor around 55-65 u/s so a MIN plunge clears the arch and crosses
  LAUNCH_REACHED_PLAY_Z well before LAUNCH_SETTLE_TIME_S (2.0 s). WHY-comment the chosen number with
  the measured delivered-speed-vs-apex that justifies it.
- KEEP LAUNCH_SPEED_MAX a satisfying hard plunge CLEARLY stronger than the new min. Preserve the
  weak-vs-strong spread the test_plunger_launch >= 1.5x feel floor checks: if the new floor is ~60 and
  MAX stays 90 the spread is 1.5x at the FEEL targets, but the DELIVERED ratio must still pass; raise
  LAUNCH_SPEED_MAX (and PLUNGER_STROKE_SPEED_MAX) if needed so the delivered full/min ratio stays
  >= 1.5x with the raised floor. If MAX rises, see 13.5 (no-tunnel re-confirm at 2x the NEW max).
- The mapping power->speed STILL lives off TableConfig.LAUNCH_SPEED_MIN/MAX (PLUNGER_STROKE_SPEED_*
  feed it). The impulse sizing in plunger.gd._try_apply_launch_impulse targets _stroke_speed; if the
  measurement shows the delivered speed lands BELOW _stroke_speed (cause b), the physics-programmer
  may correct the impulse sizing so the delivered ball speed lands in LAUNCH_SPEED_MIN..MAX - this is
  an internal sizing fix behind the unchanged contract, NOT a mechanism change.
- IF AND ONLY IF the measurement proves rattle/friction is a real contributor (cause c): the preferred
  fixes, in order, are (1) lower BALL_FRICTION slightly, or (2) add a LOW-FRICTION PhysicsMaterial to
  the lane walls (the lane divider + right wall - they have NO material today; _make_box_body sets
  none, so they inherit the default), or (3) a SMALL lane widen (LANE_INNER_X nudged down a little,
  keeping LANE_WIDTH a snug ball-width chute). NEVER a return to a bulky box. Keep the plunger face
  square to the ball (PLUNGER_FACE_WIDTH = LANE_WIDTH - 0.6 auto-follows any widen; test_plunger_lane_
  size.gd must stay green). If the floor-raise alone clears the whole meter, do NOT touch geometry.

### 13.4 Shared-physics impact (lead audit)
- NO new physics layer, NO mask change. This slice edits SCALAR tuning constants and (conditionally)
  a friction value / a local PhysicsMaterial on existing lane bodies. No body changes layer/mask, so
  the flipper/ball/furniture interop is untouched and those tests cannot regress from a routing edit.
- IF the lane-friction option is taken: the lane-wall PhysicsMaterial is LOCAL to those two bodies
  (not the shared _gray_material, which is visual-only). It must NOT change the perimeter walls' feel
  for the rest of the table (only the lane divider + right wall). Lowering BALL_FRICTION instead is
  global to the ball; physics confirms it does not regress flipper cradle/rubber tests if chosen.
- IF LAUNCH_SPEED_MAX rises: it is the reference speed for EVERY no-tunnel stress test (they fire at
  >= 2x it). Raising it RAISES the stress bar automatically where tests read the constant live; verify
  each stress test reads TableConfig.LAUNCH_SPEED_MAX (not a hardcoded literal) so the bar tracks.

### 13.5 No-tunnel re-confirm at the new max (physics + qa)
The North-Star gate. The ball stays continuous_cd at 240 Hz. The no-tunnel stress tests must fire at
>= 2x the (possibly raised) LAUNCH_SPEED_MAX and show ZERO tunneling, against REAL instanced bodies
measuring real position. Files that fire at 2x LAUNCH_SPEED_MAX and must stay green at the NEW max:
test_ball_tunneling.gd (flat wall, the headline gate), test_flipper_no_tunneling.gd, test_plunger_
launch.gd (face + pocket), test_target_no_tunneling.gd, test_active_kicker_no_tunneling.gd. Confirm
each reads LAUNCH_SPEED_MAX live; if MAX did not change, they hold unchanged.

### 13.6 File-ownership map (DISJOINT so coders work in parallel without conflict)

PHYSICS-PROGRAMMER (the measurement + the measured fix):
- tests/test_launch_diagnostic.gd  NEW. The measurement harness (scaffolded by lead, FILLED by
  physics): builds the real tilted lane, fires MIN/MID/MAX, gd-prints + asserts the measured
  delivered speed and apex. May stay as a permanent diagnostic (it asserts the floor clears).
- scripts/config/table_config.gd  the SPEED constants ONLY: LAUNCH_SPEED_MIN, LAUNCH_SPEED_MAX,
  PLUNGER_STROKE_SPEED_MIN, PLUNGER_STROKE_SPEED_MAX (and BALL_FRICTION only IF cause c is measured).
  WHY-comment every changed number with the measured value behind it. (Shared file; physics edits ONLY
  these scalars; the lead reviews. The lane-geometry block is the lead's if a widen is needed.)
- scripts/plunger.gd  ONLY IF cause (b) is measured: correct the impulse sizing in
  _try_apply_launch_impulse so delivered speed lands in range. Contract unchanged.
- scripts/ball.gd  ONLY IF lowering BALL_FRICTION needs a material tweak (reads BALL_FRICTION from
  config; likely no edit).
- scripts/table_geometry.gd  ONLY IF cause (c) needs a low-friction lane-wall material on the lane
  divider + right wall, OR a small widen build change. Likely untouched if the floor-raise suffices.
- Owns: test_launch_diagnostic.gd asserts; the no-tunnel re-confirm at the new max (13.5).

LEAD-PROGRAMMER (geometry constants IF a widen is needed; this doc; the test scaffolds):
- scripts/config/table_config.gd  the LANE geometry block (LANE_INNER_X / LANE_WIDTH and dependents)
  ONLY IF a small widen is the measured fix; re-derive every X-dependent dependent with a WHY-comment.
  Otherwise no lead edit to config.
- docs/ARCHITECTURE.md (this section), docs/BACKLOG.md, docs/DESIGN.md (designer owns intent).

GAMEPLAY-PROGRAMMER (contract re-verify only - no mechanism edit this slice):
- scripts/plunger.gd  re-verify the public contract is unchanged byte-for-byte after any tuning
  (signals power_changed/ball_launched; methods arm/disarm/set_ball/is_armed; power 0..1; the
  oscillating meter; launch from contact-impulse, never a code velocity set). NO code edit expected.
- Owns: confirming test_plunger.gd contract tests stay green.

TEST-BUILDER + QA-LEAD (the test gap - the reason it shipped):
- tests/test_launch_clears_lane.gd  NEW. The BEHAVIORAL lane-clear ORACLE (scaffolded by lead with
  pending() asserts spelled out; FILLED by test-builder). On the real tilted lane, a MIN-power launch
  (and a low/mid power) drives the ball's apex up-table PAST LAUNCH_REACHED_PLAY_Z into the open
  playfield, then settles in play (NOT back in the lane). Independent oracle: ball.position. Written
  to FAIL against today's floor and PASS after the fix (intended red-to-green).
- tests/test_plunger_launch.gd, tests/test_plunger_lane_size.gd  KEEP GREEN (no regression).
- The no-tunnel stress UPDATES at the new max (with physics, 13.5) if MAX rises.

### 13.7 Test matrix (independent oracle: ball.position / current_speed, never a counter)

| File | Class | Proves | Owner |
|------|-------|--------|-------|
| test_launch_diagnostic.gd | DIAGNOSTIC | delivered speed + apex at MIN/MID/MAX measured; the floor clears the lane | physics + test-builder |
| test_launch_clears_lane.gd | BEHAVIORAL | a MIN (and low/mid) launch apex crosses LAUNCH_REACHED_PLAY_Z into play, settles in the open field not the lane | test-builder + qa |
| test_plunger_launch.gd | BEHAVIORAL+STRESS | KEEP GREEN: strike from rest, full >= 1.5x weak, in-range, no-ball no-op, no tunnel of face/pocket; re-fire at 2x NEW max | physics + test-builder |
| test_plunger_lane_size.gd | STRUCTURAL | KEEP GREEN: lane + face stay a snug ball-width chute (re-verify if a small widen lands) | test-builder |
| test_ball_tunneling.gd | STRESS | KEEP GREEN at 2x the NEW max: flat-wall headline gate, zero tunnel, CCD on | physics + qa |
| test_flipper_no_tunneling.gd / test_target_no_tunneling.gd / test_active_kicker_no_tunneling.gd | STRESS | KEEP GREEN at 2x the NEW max through every body | physics + qa |
| test_plunger.gd | CONTRACT | KEEP GREEN: meter + power->stroke mapping monotonic, contract intact | gameplay + test-builder |
