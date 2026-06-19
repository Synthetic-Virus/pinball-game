# Pinball - Design Document
Owner: gamedev-game-designer. Status: SEEDED from Andrew's inspiration set (docs/REFERENCES.md);
the designer sharpens and fills the rest.

## North star
A modern reimagining of the 1990s Sierra "3-D Ultra Pinball" series (Creep Night, Lost Continent,
Thrillride, the original) and kin (Hyper 3-D Pinball): themed, mission-driven pinball on MULTI-BOARD
tables connected by ramps, rebuilt with smooth high-FPS physics, modern UI/UX, and ORIGINAL IP.
Full reference: docs/REFERENCES.md.

## One-sentence pitch (seed - designer to sharpen)
"A modern multi-board pinball adventure: themed worlds and mission-driven tables in the spirit of
90s 3-D Ultra Pinball, rebuilt to feel buttery-smooth and contemporary."

## Core loop (the 30-second loop)
The gray-box core loop (Gate 0 target, ZERO art/audio, ONE board):
1. PLUNGE: hold to charge an oscillating power meter, release to launch. The skill is releasing at
   the right power - too weak dribbles back, too hard rattles the arch. A clean launch is the first
   small win of every ball.
2. SETTLE: the rounded top arch feeds the ball down into the playfield; it falls toward the flippers.
3. FLIP: the player catches the ball and chooses a shot. Every flip must feel like THEIR decision -
   force-driven flippers that impart real momentum, so a cradled ball and a full-swing flip feel
   different. Hitting a bumper/target gives an immediate, legible response (a clear knock + score tick).
4. RISK THE DRAIN: an OPEN center drain means a missed flip or a dead ball is lost. The tension of
   "do I let it roll to the other flipper or stab it now" is the entire game at Gate 0.
5. NEXT BALL: drain decrements the ball count; the plunger re-arms. You reach for the plunger because
   you believe the NEXT ball you will launch cleaner and hold longer.
Pull-into-next-ball test: the loop earns the next ball if the player blames themselves ("I flipped
too early"), never the physics ("the ball went through the flipper"). That is why physics correctness
is non-negotiable in this slice.
Multi-board transitions are OUT for this slice (see cut list); the single board must be fun first.

## Pillars (3 max - seed)
1. MULTI-BOARD TABLES connected by ramps - the signature mechanic from the inspiration games.
2. THEME + MISSIONS over pure score - each table a place with characters and goals, a journey.
3. MODERN FEEL - smooth high FPS (the originals' worst flaw, our headline fix) plus clean modern UI/UX.

## Table (start with ONE)
For THIS slice: a single gray-box board, original generic geometry, no theme dressing yet. Layout
intent the engineers must honor:
- Standard upright pinball frame: a launch lane up the RIGHT side, a ROUNDED TOP ARCH that turns the
  launched ball over and feeds it into the playfield, two flippers at the bottom forming an inverted
  V, and an OPEN center drain between/below them.
- A small number of static obstacles in the upper-middle (e.g. a few bumpers/targets) so a flip has
  something worth aiming at and scoring is not empty. Exact count/placement is the engineers' call;
  the design requirement is only: at least one rewarding upper-playfield target the player can hit
  on purpose with a well-timed flip.
- No ramps, no second board, no outlanes-with-lights, no mode toggles in this slice.

### World scale (DECISION - engineers honor this, do not re-litigate per element)
Adopt the pinhead-style LARGER world scale with HIGH gravity, NOT the current tiny 0.013m-ball scale.
Decision: gravity magnitude 200 (project default_gravity), ball radius on the order of ~0.5-1.0 world
units, playfield on the order of tens of units long. Rationale: a larger scale with strong gravity is
what the pinhead force-driven flipper/solenoid tuning is calibrated for, keeps Jolt's solver in a
well-behaved range, and avoids the precision/tuning fragility of sub-centimeter bodies. The lead-
programmer picks and WRITES DOWN the exact numbers (ball radius, playfield extents, flipper length,
gravity vector with table tilt baked in) in the architecture doc; once written, that scale is the
contract for every element in the slice.

## Scoring and progression
Slice scope only (the journey/mission layer is deferred):
- Score starts at 0. Hitting a scoring obstacle adds a flat value (e.g. 100 per bumper/target hit).
  Numbers are placeholders; the requirement is that the HUD score visibly ticks the instant the ball
  hits a target, so the player connects their flip to a reward.
- Ball count starts at 3 (BALLS). A drain decrements it and re-arms the plunger for the next ball.
- Game over at 0 balls remaining: show final score and a clear way to restart. No ball-save, no
  bonus multipliers, no combos, no objective ladder in this slice - those are deferred.
- No high-score persistence yet (deferred to a later slice).

## Game feel / juice targets (Gate-0 targets the engineers aim for, gray boxes only)
These are FEEL targets, achievable with zero art/audio - hit them with geometry, physics, and HUD:
- FLIPPER SNAP: a flip reaches full extension fast (target on the order of ~50 ms from press to full
  swing) and holds firmly while the action is held, then returns under a spring. A held flipper must
  resist the ball's weight (cradle), not sag through it.
- REAL MOMENTUM: a full-swing flip on an incoming ball must noticeably out-throw a gentle/late flip.
  Different swing timing => different ball speed. This is the single most important feel test of the
  slice; if a tap and a full swing feel identical, the flippers are wrong.
- NO TUNNELING, EVER: at the highest ball speed a full-power flip produces, the ball never passes
  through a flipper, wall, or the arch. This is a hard correctness gate, asserted by the GUT stress
  test, not a soft target.
- LAUNCH SKILL: the plunger meter oscillates at a readable speed (fast enough to matter, slow enough
  to aim - target a full sweep on the order of ~0.5-1.0 s) so releasing at a chosen power is a real
  skill, and the released power visibly maps to launch strength.
- LEGIBLE DRAIN: when the ball drains it is obvious it was lost (clear message + ball-count tick), so
  the player owns the loss and reaches for the next ball.
- Input feel: flippers respond on the SAME physics frame as the press (no input lag); nudge is present
  as an action but its tuning can be minimal in this slice.

## Intellectual property (COMMERCIAL release - boundary)
Recreate the EXPERIENCE and MECHANICS, NOT the copyrighted names, themes, characters, art, or audio
of 3-D Ultra Pinball / Hyper 3-D Pinball / Pinball 2000. Original world, original IP.
gamedev-product-strategist + gamedev-producer own this.

## Slice design intent: "make the core interactions physics-based" (gray-box, 2026-06-19)
This slice converts three EXISTING fake/trigger interactions into REAL physics. It adds NO features.
The headline of the whole game is "real physics, not coded shortcuts", and this slice is where that
headline becomes literally true for launch, scoring contact, and (verifying) flippers. The designer
confirms the intent below; the physics-programmer owns correctness and the stress tests.

### Player-facing goal (what the player should be able to do and feel)
- LAUNCH a ball that is actually SITTING in the launch lane by physically driving a plunger into it.
  The ball leaves because it was STRUCK, and how hard depends on where the player released the meter.
- SCORE by physically HITTING a target: the ball collides, deflects, and the score ticks on contact.
  A target is a thing the ball bounces off, not a hole it passes through.
- Keep flipping with the same force-driven flippers that already feel like the player's own decision.

### Must-feel qualities (the bar the engineers hit, gray boxes only)
1. THE BALL RESTS, THEN IS STRUCK. Before launch the ball is visibly at rest in the chute (it does
   not fall out the bottom, it does not drift). The launch is a discrete physical EVENT: the plunger
   face moves into the stationary ball and the ball jumps because of that contact. A launch with no
   ball present does nothing.
2. POWER YOU CAN FEEL IN THE BALL. A release near the top of the meter visibly out-throws a release
   near the bottom. The mapping is monotonic: more meter at release => faster ball, every time. The
   resulting ball speed lands in LAUNCH_SPEED_MIN..MAX so a weak launch dribbles and a full one
   clears the arch. This is the same "skill of releasing at the right moment" the meter already gives;
   we are only changing HOW the speed is delivered (collision, not assignment).
3. TARGETS BOUNCE, NOT SWALLOW. On a hit the ball changes direction off the target like it hit a
   solid post, KEEPING its momentum (a fast ball stays fast, a crawl still pops legibly), and the
   HUD ticks on that same contact. Hitting a target on purpose with a timed flip is the reward; the
   ball must come back OFF the target so the player can keep playing it.
4. NO REGRESSION IN FLIPPER FEEL. A full swing still noticeably out-throws a tap (the slice's #1
   existing feel test). Whatever shared physics this slice touches (layers, masks, materials) must
   leave that true.
5. NOTHING TUNNELS, EVER. At the top ball speed a full launch or full flip produces, the ball never
   passes through the plunger face, the lane pocket, a target, a wall, the arch, or a flipper. This
   is a hard gate proven by GUT stress tests against REAL instanced bodies, not a soft target.

### Design constraints the engineers must honor (do NOT re-litigate)
- SCOPE IS LOCKED. No new bumpers, ramps, modes, multiball, multipliers, art, or audio. Exactly the
  same 3 targets at the same positions, same flat ~100-point value. The lane pocket must stop the
  ball in the lane (x in [LANE_INNER_X, HALF_WIDTH]) WITHOUT closing the center drain
  (x in [-HALF_WIDTH, LANE_INNER_X] stays open). A naive full-width bottom wall is wrong.
- PRESERVE THE PLUNGER CONTRACT EXACTLY. Signals power_changed(power)/ball_launched; methods
  arm/disarm/set_ball/is_armed; power stays 0..1. GameFlow, the HUD, and table.gd wiring depend on
  these byte-for-byte. The collision-driven strike is an internal change behind that contract.
- SCORE-ON-CONTACT, NOT PASS-THROUGH. Targets become physical bodies the ball collides with; the
  score fires on the physics contact. Keep the BUG-007 re-trigger cooldown (one legible hit, then a
  short dead time) and keep momentum preservation. Do not let a ball resting against a target farm
  points every frame.
- INDEPENDENT-ORACLE TESTS. Behavior is judged by the ball's REAL measured position/velocity, never
  a self-reported counter. Required test classes: STRUCTURAL (the lane pocket / plunger body / target
  bodies exist with the right collision layers), BEHAVIORAL (a strike imparts velocity from rest; a
  full strike out-throws a weak one; a target contact both scores AND bounces the ball; the ball
  rests in the lane and does not exit the bottom while the center drain still drains), and STRESS
  (no tunneling at >= ~2x LAUNCH_SPEED_MAX through every new body). A green suite that never asserts
  the physical behavior is a FAIL.
- ADOPT/IMPROVE/REPLACE the prototype/physical-plunger branch at the physics-programmer's discretion;
  it is not gate-passed and must go through QA + the review board + the producer like everything else.
- House style: typed GDScript, snake_case, document the WHY, no emojis, no em-dash characters.
- DELIVERY: push to a branch / open a PR. Do NOT merge to main inside the slice; the producer runs
  the scope/finish gate and CI on the runner is the source of truth for "green", not any doc claim.

## Out of scope for v1 (the cut list - keep honest)
v1 direction (producer + designer): ONE polished table before any others; defer extra worlds.

### Cut from THIS slice (Core 3D table rebuild) - defended, do not let scope creep back in:
- Multi-board / ramp-to-another-board transitions. The single board must pass Gate 0 first.
- Theme, art, models, textures, lighting polish, audio/SFX. Gray boxes only.
- Mission/objective ladder, wizard mode, multiball, combos, bonus multipliers, ball-save.
- DMD, leaderboards, high-score persistence, achievements, daily challenges.
- Outlanes/inlanes with lights, drop-target banks, spinners, kickbacks, magnets.
- Menus beyond a minimal start/restart and the score+balls HUD.
- Controller remap UI, accessibility options, settings menus (input is action-mapped so these are
  cheap to add LATER, but the UI is deferred).
Why hold the line: this slice exists to prove the PHYSICS FOUNDATION and the CORE LOOP are fun and
correct. Every cut item above is worthless if a full-power flip tunnels the ball or a flip does not
feel like the player's own decision. Build the foundation solid; add the rest only after Gate 0.
