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
