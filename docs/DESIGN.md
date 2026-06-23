# Pinball - Design Document
Owner: game-designer. Status: SEEDED from Andrew's inspiration set (docs/REFERENCES.md);
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
product-strategist + producer own this.

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

## Slice design intent: "real pinball furniture" (gray-box, 2026-06-19)
This slice adds the first REAL pinball FURNITURE on top of the physics foundation: rubber-wrapped
flippers, active pop bumpers, slingshots, a standup target bank, and inlane/outlane guides, in a
representative (NOT commercial-complete) layout. It is the slice that turns "a ball, two flippers and
three posts" into something that reads as a pinball table and gives the ball somewhere to go when it
leaves a flipper. Every interaction is PHYSICS-BASED; nothing is faked. The designer confirms the
intent below. The physics-programmer owns correctness and the tunneling stress tests; the lead owns
the shared-physics layers and the TableConfig placement constants; the test-builder/QA own the
independent-oracle behavioral suite. References consulted: docs/REFERENCES.md (the two open-source
repos, the CAD-shot-planning discipline). Build on what is already on main (force-driven flippers,
physical striking plunger, lane pocket, physical bouncing targets, auto-framed camera).

### Player-facing goal (what the player should be able to do and feel)
- LIVELY PLAY: a ball that reaches the upper-middle field gets BATTED AROUND by pop bumpers - it does
  not just trickle back down. Each bumper hit is a little jolt of action and a score tick. The bumper
  cluster is the "something worth shooting for" up top.
- SAVED BY THE SLINGS: a ball dropping toward the gap between a flipper and the side gets KICKED back
  up into play by a slingshot, so the lower field feels active and a near-drain can be rescued by the
  table itself (not only by the player's flip). The slings also add chaos: a ball can rattle between
  a sling and a flipper, which is classic pinball texture.
- A SHOT WORTH MAKING: from a flipper at rest, a well-timed flip can reach the standup target bank
  (a deliberate, makeable shot), and can feed the ball up toward the bumper cluster. The player can
  AIM, not just survive.
- LANES THAT FUNNEL: a ball coming down the side is guided down an inlane/outlane past the flipper.
  An outlane that feeds the drain is a risk; an inlane that feeds back to the flipper is a save. This
  is the first time the lower field has structured paths instead of one open mouth.
- RUBBER THAT REBOUNDS: the ball bounces off the flipper face/edge like a real rubber-sleeved flipper
  (a live, slightly springy contact), not like a dead board. A ball can be bounced off a flipper, not
  only swung at.

### Must-feel qualities (the bar the engineers hit, gray boxes only)
1. ACTIVE KICK, NOT A LIMP BOUNCE. A pop bumper and a slingshot fire the ball AWAY with authority on
   contact, even if the ball arrived slowly. The developer's words: it "contracts to shoot the ball
   away" - a solenoid kick, not a passive rubber bounce. The OUTGOING speed off an active element has
   a clear floor (a crawl in still comes out fast enough to travel), and the kick direction is
   legibly AWAY from the element (pop bumper: radially outward from its center along the ball's
   contact normal; slingshot: outward and UP-table, back into play, never down toward the drain).
   PASSIVE-ONLY (PhysicsMaterial restitution alone) is explicitly NOT acceptable for these elements -
   that is the prior-art pattern we are deliberately improving on (docs/REFERENCES.md).
2. NO MACHINE-GUN FARMING. A ball resting against or jittering on a pop bumper or slingshot must NOT
   re-fire every physics frame and rack up points. Each active element has a short re-trigger cooldown
   (the same family as the target BUG-007 cooldown): one legible kick + score, then a brief dead time
   before it can fire again. A resting ball gets pushed off ONCE, not strobed.
3. RUBBER FLIPPER REBOUND THAT KEEPS MOMENTUM. A ball striking a flipper face rebounds off it with a
   live, slightly-springy feel (a rubber-sleeve PhysicsMaterial / rubber edge on the flipper
   collider), not a dead thud and not an energy-adding trampoline. A fast ball that glances a flipper
   stays fast; the rebound preserves the ball's momentum (the same fun risk as the targets: a contact
   that kills speed ends the loop). This is layered on the EXISTING force/hinge/return-spring drive
   WITHOUT touching that drive.
4. NO REGRESSION IN FLIPPER FEEL. The slice's standing #1 feel test stays true: a full swing still
   noticeably out-throws a tap. Adding a rubber surface/material to the flipper collider must not
   change the force drive, the snap timing (~50 ms), the cradle, or the merged momentum tests. Those
   tests stay GREEN exactly as they are.
5. SHOTS ARE GEOMETRICALLY MAKEABLE (validated, not eyeballed). The standup target bank and the pop
   bumper cluster sit where a flipper-tip sweep can actually REACH them, and the slingshots kick the
   ball into play, not into a wall or the drain. This is asserted deterministically by the extended
   table_viz tool + geometry tests, in the spirit of CAD shot-planning - NOT by looking at a picture.
6. NOTHING TUNNELS, EVER. At the top ball speed the table produces (a full flip, a full plunge, a
   stacked bumper/sling kick - so >= ~2x LAUNCH_SPEED_MAX), the ball never passes through a flipper
   (now with its rubber surface), a pop bumper body, a slingshot body, a standup target, a lane
   guide, a wall, or the arch. Hard gate, proven by GUT stress tests against REAL instanced bodies
   measuring real position/velocity, not a soft target. The active kick must not be tuned so hot that
   it shoves the ball through a neighbouring wall before CCD resolves; the physics-programmer caps the
   kick impulse so the post-kick speed stays inside the CCD-safe envelope the stress tests cover.

### Layout intent (representative subset - the GUIDE, not the full board)
Follow the shared flame-skull CAD reference as a GUIDE for PLACEMENT and FEEL only (the image is not
in the repo; if docs/reference/playfield-guide.png is later added, the engineers may open it). Build a
BASIC subset, NOT a commercial board. The lead-programmer picks exact positions in TableConfig within
this intent and validates them with table_viz:
- FLIPPERS at the bottom forming the inverted V (UNCHANGED geometry: FLIPPER_PIVOT_SPREAD/Z,
  REST/UP angles, length all stay as the existing world-scale contract; only the rubber surface is
  added). Keep the existing ~2.1-unit drain mouth.
- SLINGSHOTS: ONE above each flipper, on the outer side, angled so a ball falling down that side is
  kicked back UP and toward center (into play), never down into the drain. Two slingshots total.
- POP BUMPERS: 2-3 in the UPPER-MIDDLE field (above the flippers, below the arch), clustered so a ball
  entering the cluster bounces between them a few times. Each scores on its kick.
- ONE STANDUP TARGET BANK: a small bank (reuse/extend the existing physical target body) of standup
  targets, placed on the mid-field where a deliberate flip can reach it. This MAY reuse / re-home the
  existing 3 targets into a readable bank rather than adding a fourth element type, at the lead's
  discretion - the requirement is "a standup bank that is a makeable shot", not a new target class.
- INLANE/OUTLANE GUIDES: minimal lane guides down BOTH sides that funnel a ball past the flippers -
  an outlane (outer, feeds the drain = risk) and an inlane (inner, feeds back toward the flipper =
  save) per side. Keep them minimal; do not light them, gate them, or add ball-save logic.
- The launch lane, lane pocket, arch, plunger, and drain are UNCHANGED from the foundation.

### Design constraints the engineers must honor (do NOT re-litigate)
- SCOPE IS REPRESENTATIVE, NOT COMMERCIAL. Build exactly: rubber flippers + 2-3 pop bumpers + 2
  slingshots + 1 standup bank + minimal inlane/outlane guides, in a representative layout. NO ramps,
  no second board, no rollover SCORING modes, no spinners, no drop-target drop logic, no kickback, no
  magnets, no multiball, no multipliers, no mode toggles, no art, no audio. Rollover lanes appear in
  the reference image; they are OUT of this slice (the cut list keeps "outlanes/inlanes with lights"
  and "rollovers" deferred - we add only the unlit physical guide walls, not scoring rollovers).
- ACTIVE KICK IS AN IMPULSE, CAPPED AND COOLED. Pop bumpers and slingshots apply a coded outward
  IMPULSE on contact (not pure PhysicsMaterial restitution), directed away from the element, with
  (a) a minimum outgoing speed so a slow ball still travels, (b) a CAP so the post-kick speed stays
  inside the CCD-safe envelope (no tunneling), and (c) a per-element re-trigger cooldown so a resting
  ball cannot farm. Reuse the target BUG-007 cooldown pattern; do not invent a new one.
- RUBBER IS A SURFACE, NOT A REDESIGN. The rubber feel is added via the flipper collider's
  PhysicsMaterial / a rubber edge, NOT by changing the force/hinge/return-spring drive. The merged
  flipper momentum/snap/no-overlap tests stay green unchanged. If the rubber material would alter
  those numbers, tune the material - not the drive - until they pass.
- WORLD SCALE IS LOCKED. Every new body honors the TableConfig world-scale contract (gravity 200,
  ball radius 0.6, half-width 12, half-length 25, the existing flipper geometry). New placement
  constants (bumper centers/radius, sling positions/angles, standup bank positions, lane-guide
  geometry, kick impulse magnitudes, cooldown seconds) are ADDED to TableConfig by the lead; no
  existing value changes. Once written, those numbers are the contract for the slice.
- SCORE-ON-CONTACT, MOMENTUM-PRESERVED. Pop bumpers, slingshots, and standup targets score on the
  physics contact (a flat placeholder value each, e.g. ~100; bumpers may use their own flat value but
  no multipliers). The contact must PRESERVE/IMPART momentum (active kick), never kill the ball's
  speed. A green suite that never asserts outward velocity is a FAIL.
- VALIDATE SHOTS DETERMINISTICALLY (CAD discipline). Extend tools/table_viz.py to PLOT and VALIDATE:
  the flipper-tip sweep arc (does it reach the standup bank / feed the bumper cluster?), each pop
  bumper and slingshot kick DIRECTION vector (does it point into play, not into the drain/a wall?),
  and the inlane/outlane feed paths. Add geometry/behavioral GUT tests that assert reachability and
  return-to-play where practical, using REAL bodies and measured position/velocity (independent
  oracle), not eyeballing the rendered PNG.
- INDEPENDENT-ORACLE TESTS (3 classes, all required). STRUCTURAL: the new bodies exist on the correct
  collision layers (pop bumpers, slingshots, standup bank, lane guides) and in the right positions.
  BEHAVIORAL: a pop bumper imparts OUTWARD velocity on contact and scores once (cooldown blocks
  per-frame farming); a slingshot imparts UP-and-into-play velocity on contact; the rubber flipper
  rebounds the ball preserving momentum; a standup target scores on contact. STRESS: no tunneling at
  >= ~2x LAUNCH_SPEED_MAX through every new body, including after an active kick. Behavior judged by
  the ball's REAL measured position/velocity, never a self-reported counter.
- House style: typed GDScript, snake_case, document the WHY, no emojis, no em-dash characters; lines
  <= 100 chars; gdlint clean.
- DELIVERY: commit ALL changes, verify a clean tree, push to a branch, open a PR (do NOT merge to
  main). CI on the homelab godot runner is the source of truth for "green"; the producer must see
  GREEN CI on the pushed sha (the artifact, not a doc claim) before PASS.

## Slice design intent: "Table reshape + playtest fixes" (gray-box, 2026-06-19)
This slice is the FIRST one driven by real developer playtest feedback on the deployed homelab build,
not by a feature plan. The developer played the current table and reported five concrete problems.
This slice fixes all five in one pass. It adds NO new mechanics or element TYPES: it makes the launch
actually work, gives the flippers their real shape, widens the table and re-spaces what is already
there. Everything stays physics-based. The designer confirms the intent below. The physics-programmer
owns launch correctness, the capsule collider, and the no-tunneling stress gate; the lead owns the
world-scale rescale (HALF_WIDTH) and every dependent constant; the test-builder/QA own the independent-
oracle suite. References: docs/REFERENCES.md (CAD shot-planning), docs/pinhead-tech-notes.md.

### Why this slice matters (the core-loop stakes)
At Gate 0 the question is "does one ball make the player want the next ball". Right now the answer is
NO for a control reason, not a fun reason: the LAUNCH DOES NOT FIRE. A player who cannot get the ball
into play never reaches the loop. That is the #1 fix; everything else is making the table the player
DOES reach read and play like pinball (real flipper shape, a wider field with breathing room, gutters
on both sides so a drain feels earned, targets/bumpers big enough to aim at). A clean launch is "the
first small win of every ball" (core loop step 1); this slice is what makes that win real.

### Player-facing goal (what the player should be able to do and feel)
- LAUNCH FOR REAL. Hold to charge the oscillating meter, release, and the ball LEAVES THE LANE every
  time. Release power maps to launch strength (weak dribbles, full clears the arch). The launch is the
  reliable first beat of every ball; a dead plunger is a broken game.
- FEEL THE FLIPPER SHAPE. The flippers look and collide like real flippers (fat at the pivot, tapering
  to a rounded tip), so where on the bat the ball hits matters (tip shots vs base shots read
  differently) and the bat reads instantly as a flipper, not a plank.
- A TABLE WITH ROOM. The wider field gives the ball space to travel and the furniture room to breathe,
  so shots are legible and the lower field is not cramped.
- A DRAIN YOU EARN, EITHER SIDE. Both side gutters/outlanes read clearly as drain risks; losing the
  ball down either side feels like the player's miss, never an invisible quirk.
- TARGETS AND BUMPERS WORTH AIMING AT. The standup bank and the pop-bumper cluster are big enough and
  spaced well enough on the wider table that a timed flip can actually pick them out and hit them.

### Must-feel qualities (the bar the engineers hit, gray boxes only)
1. THE PLUNGER ACTUALLY LAUNCHES, MONOTONICALLY. From a ball at rest in the lane, a release imparts
   REAL velocity (more meter => faster ball, every time) and the resulting ball speed lands in
   ~LAUNCH_SPEED_MIN..MAX so a weak launch dribbles and a full one clears the arch. A release with no
   ball is a no-op. This is judged by the ball's MEASURED velocity, never by a fired-signal counter.
2. THE FLIPPER IS A FLIPPER SHAPE, NO REGRESSION IN FEEL. The bat is a tapered rounded "stadium"
   form (fatter at the pivot, smaller rounded tip) in BOTH the mesh and the collider. The existing
   force/hinge/return-spring drive, the ~50 ms snap, the cradle, and "a full swing out-throws a tap"
   all stay true, and the rubber rebound keeps >= 35% of incoming speed. Changing the shape must not
   change the feel.
3. THE WIDER TABLE STAYS IN PROPORTION. After widening, the inverted-V drain mouth is still a sane
   ~1-ball-plus gap (not crossed, not a chasm), the lane reads as a lane, the arch still spans the
   width and turns the ball over, and no furniture sits in a wall or off the field. Widening is a
   RESCALE, not a stretch-one-number-and-hope.
4. BOTH GUTTERS READ AS GUTTERS. Down EACH side, an outer outlane (feeds the drain = risk) and an
   inner inlane (feeds back toward the flipper = save) are present and legible after the widen. A
   player can see both sides are live.
5. TARGETS/BUMPERS ARE BIGGER, BETTER SPACED, AND STILL MAKEABLE. The 3 standup targets and the 3 pop
   bumpers are re-sized up and re-spaced for the wider field, and a flipper-tip sweep can still REACH
   the standup bank and feed the bumper cluster (validated deterministically by table_viz, not
   eyeballed).
6. NOTHING TUNNELS, EVER. At the top ball speed the table produces (a full launch, a full flip, a
   stacked kick - so >= ~2x LAUNCH_SPEED_MAX) the ball never passes through the plunger face, the
   capsule flipper, a target, a pop bumper, a slingshot, a lane guide, a wall, or the arch. Hard gate
   on the ball's REAL measured position/velocity, proven by GUT against real instanced bodies.

### Design constraints the engineers must honor (do NOT re-litigate)
- SCOPE: FIX, DO NOT ADD. Exactly the five reported fixes. NO new element types, ramps, modes,
  multiball, multipliers, rollover scoring, art, or audio. Same element COUNTS (3 targets, 3 pop
  bumpers, 2 slingshots, 2 lane-guide gutters, 2 flippers, 1 plunger) - only their shape, size,
  spacing, and the table width change.
- PRESERVE THE PLUNGER CONTRACT EXACTLY. Signals power_changed(power)/ball_launched; methods
  arm/disarm/set_ball/is_armed; power stays 0..1; the oscillating meter and its power->launch-speed
  mapping (PLUNGER_STROKE_SPEED_MIN..MAX -> LAUNCH_SPEED_MIN..MAX) are unchanged in CONTRACT. The
  fix is INTERNAL: replace the unreliable sync_to_physics momentum transfer with a mechanism that
  genuinely imparts velocity on the plunger-ball contact (an impulse on contact, a constant_linear_
  velocity / reported velocity on the kinematic face, or move_and_collide), at the physics-
  programmer's discretion. The plunger body stays visible and seated in the lane behind the ball.
  Production launch must still come FROM the contact/impulse, not from a code velocity set on the ball
  (test_plunger_launch.gd asserts this).
- PRESERVE THE FLIPPER CONTRACT AND DRIVE. configure()/is_energized()/tip_speed()/force_energized()
  unchanged. Keep BAT_MASS 0.40 / BAT_BOUNCE 0.70 (the rubber-rebound >= 35% retention) and the
  force/hinge/return-spring drive. The new collider is a CapsuleShape3D or a convex hull that MATCHES
  the visible tapered mesh (collider and mesh agree); both keep one end at the pivot and taper to the
  tip, on the SAME handedness logic (_apply_handedness must still seat the bat toward center for both
  sides). Material: black body + white rubber top surface (a 2-tone gray-box material only; the
  kenney.nl CC0 art pass is LATER and must NOT block this slice).
- WIDEN IS A WORLD-SCALE RESCALE. TableConfig.HALF_WIDTH 12.0 -> 16.0 (~33% wider). HALF_LENGTH stays
  25.0 (widen only). The lead RE-DERIVES every X-dependent constant so proportions hold: LANE_INNER_X
  / LANE_WIDTH, FLIPPER_PIVOT_SPREAD (keep the inverted V with a ~1-ball-plus drain gap, NOT crossed),
  DRAIN_WIDTH / DRAIN_CENTER_X, ARCH_RADIUS_X (spans the new width), LANE_GUIDE_DIVIDER_X, the
  slingshot/pop-bumper/standup X positions, and the lane-pocket/plunger lane math. WHY-comments on
  every changed constant. Nothing may end up inside a wall, off the field, or crossing the centerline.
- GUTTERS ON BOTH SIDES (VERIFY FIRST, THEN FIX). table_geometry._build_lane_guides already builds
  LaneGuideLeft AND LaneGuideRight and test_furniture_layout asserts both, so the developer's
  "only a left gutter" report is most likely a STALE CACHED BUILD. VERIFY both exist and read as
  gutters after the widen; only if the right one is genuinely missing/weak, fix it. Do not invent a
  new gutter system if the existing symmetric one is correct - confirm with table_viz + the layout
  test on the rebuilt scene.
- RESIZE/RESPACE, KEEP IT MAKEABLE. Bigger standup targets (raise the post/target size) and bigger
  pop bumpers (POP_BUMPER_RADIUS up) and wider, sensible spacing across the new field
  (STANDUP_BANK_POSITIONS, POP_BUMPER_POSITIONS). The standup bank MUST stay inside the flipper-tip
  sweep window and the bumpers must stay clear of walls/arch - asserted by tools/table_viz.py +
  tests/test_shot_geometry.gd, never by eyeballing the PNG.
- VALIDATE SHOTS DETERMINISTICALLY (CAD discipline, Mission Pinball method). Use/extend
  tools/table_viz.py to re-validate the NEW layout: flipper-tip reach to the resized targets/bumpers,
  the lane feeds, the drain mouth, both gutter feed paths. The tool must EXIT NON-ZERO if a shot is
  unmakeable or a kick aims at the drain on the new constants. The GUT twin (test_shot_geometry.gd)
  is the CI source of truth.
- INDEPENDENT-ORACLE TESTS (three classes, all required, "test the game like a web app").
  STRUCTURAL: the flipper collider is a CAPSULE / convex hull (NOT a BoxShape3D); both gutters exist
  on the correct layers at the new spacing; furniture is on the correct layers at the new positions;
  the table width equals the new HALF_WIDTH. BEHAVIORAL: a plunger release imparts REAL measured
  velocity to the ball and launches it (monotonic, in-range, no-ball is a no-op); rubber rebound
  >= 35%; targets and bumpers kick AND score on contact. STRESS: no tunneling at >= ~2x
  LAUNCH_SPEED_MAX on EVERY interaction. Update the existing furniture/layout/world-scale tests for
  the new width. Real instanced bodies, measured position/velocity, never a self-reported counter.
- PHYSICS NORTH-STAR: ball continuous_cd at 240 Hz; zero tunneling anywhere. The capsule flipper and
  the widened/rescaled bodies must all hold the no-tunnel gate.
- House style: typed GDScript, snake_case, document the WHY, no emojis, no em-dash characters; lines
  <= 100 chars; gdlint clean.
- DELIVERY: the team's Setup phase creates the slice branch. Build/QA agents COMMIT but do NOT push.
  Deliver verifies GREEN locally (fetch headless Godot 4.x, run GUT) BEFORE pushing, then opens ONE
  PR and confirms GREEN on the homelab runner. Do NOT touch main. The producer requires green CI on
  the pushed sha to PASS; the human merges.

## Slice design intent: "Playtest fixes 2" (gray-box, physics-based, 2026-06-20)
This is the SECOND playtest-driven slice. The developer played the deployed wider table (main
286356e) and reported a fresh batch of problems. Like the last one, this is a FIX pass, not a feature
pass: it adds NO new element TYPES, keeps the same element COUNTS, and keeps every interaction
physics-based. Two of the fixes are CORRECTNESS (a soft-lock that ends the session, and a launch lane
sized wrong); two are SHAPE/MATERIAL legibility (a flipper that renders wrong, slingshots that read
as boxes); four are the UX-clarity items the producer has already ruled in scope for Gate-0 readiness
(prompt on every ball, name the restart key, colorblind-safe meter, bigger HUD font). The designer
confirms the intent below. The physics-programmer owns the soft-lock recovery, the resized plunger
launch, the no-tunnel gate on the new shapes; the lead owns the TableConfig geometry edits; the
gameplay-programmer owns the game-state recovery + the HUD/prompt wiring; the test-builder/QA own the
independent-oracle suite. References: docs/REFERENCES.md, docs/ARCHITECTURE.md, docs/pinhead-tech-notes.md.

### Why this slice matters (the core-loop stakes)
Gate 0 asks "does one ball make the player want the next ball." Two of these bugs make that
impossible to even evaluate. The SOFT-LOCK is the worst: a weak launch that leaves the ball dribbling
in the lane FREEZES the whole game - the player cannot relaunch, the ball count never moves, the
session is dead. That is not a fun problem, it is a "the game stopped" problem, and it fails Gate 0 on
a control failure before fun is ever in question. The undersized/oversized launch furniture is the
adjacent risk: the launch is "the first small win of every ball" (core loop step 1), and a lane that
does not line up with the ball undermines the reliability of that first beat. The flipper-material and
slingshot-shape fixes make the table READ correctly (a player must instantly recognise a flipper and a
slingshot as what they are), and the four UX items make the controls legible so a player can launch
ball 2 and ball 3 and knows how to restart. All gray-box; no art, no audio.

### Player-facing goal (what the player should be able to do and feel)
- NEVER BE STUCK. If a launch is too weak and the ball never reaches play (it dribbles back into the
  lane or stalls below the arch), the player can ALWAYS launch again. The plunger re-arms (and/or the
  ball returns to the cradle) so there is no dead state where the ball is sitting in the lane and the
  game has stopped responding. A failed launch costs the player nothing but a re-pull.
- READ THE TABLE INSTANTLY. BOTH flippers look the same: a black bat with a white rubber top. The two
  active kickers above the flippers look like real SLINGSHOTS - angled triangles whose long face
  points into play - not little boxes. A player recognises every piece of furniture for what it is.
- A LAUNCH LANE THAT FITS THE BALL. The plunger and launch lane are sized to the ball (about its
  width), so the ball sits squarely in the lane and the plunger face strikes it head-on. The lane
  reads as a snug chute, not a bulky oversized box, and the launch still fires reliably on the first
  pull.
- KNOW HOW TO PLAY EVERY BALL. On every ball (not just the first), the "HOLD LAUNCH - release to fire"
  prompt appears. On game over the screen names the actual key to restart (SPACE / the launch action).
- READ THE HUD WITHOUT STRAINING OR GUESSING AT COLOR. The HUD text is large enough to read at a
  glance, and the launch power meter is legible without relying on color (the bar WIDTH already encodes
  power; that must be the primary cue so a colorblind player reads it fine).

### Must-feel qualities (the bar the engineers hit, gray boxes only)
1. A FAILED LAUNCH IS ALWAYS RECOVERABLE (the headline correctness fix). If the ball does NOT reach
   play after a launch (it is still in the launch lane / below the arch, e.g. it dribbled back or
   stalled), the game returns the player to a launchable state: the plunger is RE-ARMED and/or the
   ball is returned to the cradle, so another launch is always possible. There is NO state where a
   live ball sits in the lane and the plunger is dead. CRITICAL: a too-weak launch must NOT silently
   cost the player a ball - re-arming for the same ball is the correct behavior, not spending a ball
   the player never got into play. (Whether a true drain still spends a ball is unchanged; this is
   specifically the "ball never left the lane" recovery.) Judged by a behavioral test that drives a
   too-weak launch and asserts the ball is recoverable (plunger re-armed and/or ball back at the
   cradle), never a soft-lock.
2. BOTH FLIPPERS RENDER IDENTICALLY (black body + white rubber top). The right (mirrored) flipper
   shows the SAME white rubber TOP surface as the left. The mirroring must not drop, hide, or
   wrong-face the rubber-top material (the mesh normals/UVs/material assignment must survive the X
   mirror). A side-by-side look shows two matching bats, not one black and one two-tone.
3. SLINGSHOTS ARE TRIANGLES (shape + collider). Each slingshot is a proper slingshot TRIANGLE: a
   left-handed triangle above the LEFT flipper and a right-handed (mirrored) triangle above the RIGHT
   flipper, with the long KICKING FACE angled INTO play (toward center-up), like a real pinball
   slingshot. BOTH the collision shape AND the visible mesh become triangular. The existing active
   kick is unchanged: same kick DIRECTION (into play, validated by table_viz), same score, same
   cooldown, same CCD-safe cap. The face the ball strikes is the long inner face of the triangle.
4. THE LAUNCH FURNITURE FITS THE BALL. The plunger face and the launch lane are sized to roughly the
   ball's WIDTH (ball diameter ~1.2, radius 0.6): a NARROW plunger face and a NARROWER lane that line
   up with the ball, replacing the current too-wide/bulky box. The launch must still fire reliably on
   the FIRST stroke (the plunger contract and the impulse-on-contact launch are preserved), and the
   resized face must still strike the ball head-on with no gap to tunnel across.
5. CONTROLS AND HUD ARE LEGIBLE EVERY BALL. The launch prompt re-issues on EVERY ball arm (balls 2
   and 3, not only ball 1). The game-over screen names the real restart key (SPACE / the launch
   action). The power meter reads without color (width is the primary cue). The HUD font is larger.
6. NOTHING TUNNELS, EVER. At the top ball speed the table produces (a full launch, a full flip, a
   stacked kick - so >= ~2x LAUNCH_SPEED_MAX) the ball never passes through the RESIZED plunger face,
   the NEW triangular slingshot face, a flipper, a target, a pop bumper, a lane guide, a wall, or the
   arch. Hard gate on the ball's REAL measured position/velocity, proven by GUT against real instanced
   bodies at 240 Hz with continuous_cd on. The new triangular slingshot face and the narrowed plunger
   face both hold the no-tunnel gate.

### Design constraints the engineers must honor (do NOT re-litigate)
- SCOPE: FIX, DO NOT ADD. Exactly the eight reported items (four functional/visual fixes + four UX
  items). NO new element TYPES, ramps, modes, multiball, multipliers, rollover scoring, art, or audio.
  Same element COUNTS: 3 pop bumpers, 3 standup targets, 2 slingshots, 2 flippers, 1 plunger, 2
  gutters. Only shape/size/material/state-logic change.
- SOFT-LOCK FIX IS A STATE-MACHINE + PLUNGER RECOVERY, NOT A NEW MECHANIC. The fix lives across
  scripts/game_flow.gd, scripts/plunger.gd, scripts/ball.gd, scripts/config/table_config.gd. The
  recovery condition is positional: if, some short settling time after a launch, the ball is still in
  the launch lane / below the arch (it never crossed into the playfield), treat the launch as FAILED
  and re-arm the plunger for the SAME ball (re-seat the ball at the cradle if needed). Do NOT decrement
  the ball count for a failed launch. Do NOT change the drain behavior for a ball that genuinely
  reached play and then drained. Add a behavioral test: a too-weak launch leaves the ball recoverable
  (plunger re-armed / ball back at cradle), never a soft-lock. The exact threshold (settle time, the Z
  / arch line that defines "reached play") is the physics/gameplay programmer's call, written down in
  TableConfig or the relevant script with a WHY-comment, then it is the contract.
- PRESERVE THE PLUNGER CONTRACT EXACTLY. Signals power_changed(power)/ball_launched; methods
  arm/disarm/set_ball/is_armed; power stays 0..1; the oscillating meter and the power->launch-speed
  mapping are unchanged in CONTRACT. The plunger-face RESIZE and the soft-lock re-arm are INTERNAL
  changes behind that contract. Production launch must still come FROM the contact/impulse, not a code
  velocity set on the ball (test_plunger_launch.gd asserts this).
- PRESERVE THE FLIPPER CONTRACT AND DRIVE. configure()/is_energized()/tip_speed()/force_energized()
  unchanged; BAT_MASS 0.40 / BAT_BOUNCE 0.70; the force/hinge/return-spring drive, the ~50 ms snap,
  the cradle, _apply_handedness untouched. The right-flipper fix is a MATERIAL/MESH correctness fix
  (the rubber-top surface must render on both sides after the X mirror), NOT a drive or shape change.
  The capsule/convex-hull collider and the tapered stadium mesh stay; only the material/mesh-normal/UV
  handling that drops the right rubber top is corrected.
- SLINGSHOT TRIANGLE IS A SHAPE SWAP BEHIND THE SAME KICK. Replace the slingshot BoxShape3D solid body
  AND its gray-box mesh with a TRIANGULAR form (a convex hull / prism whose top-down footprint is a
  right triangle), left-handed for the left sling and mirrored for the right, with the long hypotenuse
  / inner face angled INTO play along the existing SLINGSHOT_LEFT/RIGHT_KICK_DIR. The kick DIRECTION,
  score, cooldown, and CCD-safe cap are UNCHANGED (the active-kick base owns those). Both the
  collision shape and the visible mesh become triangular and must AGREE. The detector volume must
  still trip on contact anywhere along the long face (keep the BUG-018 corner-contact guarantee). Files:
  scripts/slingshot.gd (and scripts/active_kicker.gd if the body/mesh is built there). Re-validate the
  kick still points into play with table_viz; keep the no-tunnel stress test green for the triangular
  face.
- RESIZE THE LAUNCH FURNITURE, KEEP THE LAUNCH RELIABLE. The plunger face and launch lane shrink to ~
  the ball's width. Edit TableConfig (LANE_WIDTH / LANE_INNER_X / PLUNGER_FACE_WIDTH / lane-pocket and
  lane geometry) so the face is about a ball-and-a-bit wide and the lane is a snug chute, re-deriving
  every dependent constant with a WHY-comment (PLUNGER_REST_POS.x, BALL_START.x stay the lane center;
  nothing may end up in a wall or off the field). The launch must still fire on the FIRST stroke and
  the face must seat in contact with the resting ball (no gap to tunnel). Files: table_config.gd,
  plunger.gd, table_geometry.gd. Validate the resized lane geometry with tools/table_viz.py
  deterministically (do NOT eyeball); keep test_plunger_launch.gd green.
- WORLD SCALE STAYS LOCKED OTHERWISE. HALF_WIDTH 16, HALF_LENGTH 25, ball radius 0.6, gravity 200,
  FLIPPER geometry, the furniture positions all UNCHANGED. This slice narrows the LANE and resizes the
  PLUNGER FACE and the SLINGSHOT shape and fixes the flipper material; it does NOT re-rescale the
  table. Do not re-litigate the widen from the prior slice.
- UX ITEMS ARE WIRING, NOT FEATURES. Re-issue the "HOLD LAUNCH - release to fire" prompt on every ball
  arm (game_flow.gd request_new_ball path / message emit, or plunger.gd arm()). Name the real restart
  key in the game-over panel (hud.gd show_game_over: the launch action is SPACE). Make the meter
  colorblind-safe (hud.gd: width is the primary encoding; do not rely on the green->red color alone -
  a colorblind player must read the charge from the bar length, optionally a tick/outline, never color
  only). Raise the HUD font size (hud.gd: set a larger font size on the labels). These do not fail CI
  but ARE in scope for Gate-0 readiness; fold them in, do not defer.
- VALIDATE SHOTS DETERMINISTICALLY (CAD discipline). Use tools/table_viz.py to re-validate the resized
  plunger/lane geometry and confirm the new triangular slingshot kick still points into play. The tool
  must exit non-zero if the lane no longer lines up with the ball or a kick aims at the drain. The GUT
  twin (tests/test_shot_geometry.gd) is the CI source of truth.
- INDEPENDENT-ORACLE TESTS (three classes, all required, "test the game like a web app"). STRUCTURAL:
  both flippers carry the white-rubber-top material/mesh surface; the slingshot solid body + mesh are
  the triangular (non-box) shape; the plunger face width matches the resized constant; the lane width
  matches the resized constant. BEHAVIORAL: a too-weak launch leaves the ball recoverable (plunger
  re-armed and/or ball back at cradle) and does NOT spend a ball (the soft-lock test); the plunger
  still launches a ball from rest at full power on the first stroke (no regression); the slingshot
  still kicks into play and scores on contact. STRESS: no tunneling at >= ~2x LAUNCH_SPEED_MAX through
  the resized plunger face and the new triangular slingshot face. Real instanced bodies, measured ball
  position/velocity (independent oracle), never a self-reported counter.
- PHYSICS NORTH-STAR: ball continuous_cd at 240 Hz; zero tunneling anywhere, including the resized
  plunger face and the triangular slingshot.
- House style: typed GDScript, snake_case, document the WHY, no emojis, no em-dash characters; lines
  <= 100 chars; gdlint clean (~/.local/bin/gdlint).
- DELIVERY: the team's Setup phase creates the slice branch. Build/QA agents COMMIT but do NOT push.
  Deliver verifies GREEN locally (fetch headless Godot 4.x, run the FULL GUT suite) BEFORE pushing,
  then opens ONE PR and confirms GREEN on the homelab runner. Do NOT touch main. The producer requires
  green CI on the pushed sha to PASS; the human merges.

## Slice design intent: "Fix the launch" (gray-box, physics-based, 2026-06-20)
This slice fixes a CONFIRMED playability bug in the deployed build (main): the developer plunges and
the ball climbs partway up the launch chute, stalls, and rolls back, so play cannot start reliably.
It is a CORRECTNESS slice, not a feature slice: it adds NO new mechanics or element types, keeps every
element count, and keeps every interaction physics-based. It does ONE thing - make the launch actually
deliver the ball into the playfield on EVERY plunge across the WHOLE power meter - and closes the test
gap that let a non-clearing launch ship. The designer confirms the intent below; the physics-programmer
owns the measured diagnosis and the fix; the test-builder/QA own the behavioral lane-clear oracle.

### Why this slice matters (the core-loop stakes)
Gate 0 asks "does one ball make the player want the next ball." A launch that does not reach play
fails that on a control problem before fun is ever in question. The launch is "the first small win of
every ball" (core loop step 1): if the first beat of every ball is a dead dribble that rolls back, the
player never reaches the loop at all. The prior slices made the launch FIRE (impart velocity) but never
asserted the ball CLEARS THE LANE INTO PLAY - the test gap that let this ship. A green suite that proves
the ball has speed but not that the ball arrives is exactly the gap this slice closes.

### The diagnosis is geometry, confirmed before engineering (designer's read; physics MEASURES it)
The numbers are not a guess; they fall out of the locked TableConfig geometry:
- The ball rests at BALL_START.z = HALF_LENGTH - 2.0 = 23.0; the arch curves over at
  ARCH_CENTER_Z = -HALF_LENGTH + 6.0 = -19.0. The up-table climb from rest to the arch is ~42 units.
- The down-slope deceleration on the tilt is GRAVITY * sin(TILT_DEG) = 200 * sin(7 deg) = ~24.4 u/s^2.
- Clearing 42 units from rest therefore needs ~sqrt(2 * 24.4 * 42) = ~45.3 u/s at the ball, BEFORE any
  loss to wall rattle or friction.
- But LAUNCH_SPEED_MIN = 30 and PLUNGER_STROKE_SPEED_MIN = 30: the entire LOWER HALF of the power
  meter delivers a ball that physically cannot reach the arch. It climbs, stalls, and rolls back -
  exactly the reported symptom. The bottom of the meter is a DEAD ZONE.
This is primary cause (a): the speed FLOOR is below what the lane requires. The physics-programmer must
still MEASURE (headless, on the real tilted geometry) the delivered ball speed at MIN/MID/MAX and the
ball's apex (lowest Z reached before rollback) to confirm (a) and to size the fix, AND to rule in or
out the two secondary causes: (b) impulse under-delivery (does a full strike actually land the ball in
LAUNCH_SPEED_MIN..MAX?) and (c) the snug 2.0-unit lane (~1.7 ball diameters) bleeding energy to wall
rattle and BALL_FRICTION (0.4) so even mid power stalls. Report the measured numbers in the deliverable.

### Player-facing goal (what the player should be able to do and feel)
- EVERY PLUNGE STARTS THE BALL. Hold the meter, release at ANY power, and the ball leaves the lane,
  crosses the arch, and enters the playfield - every time. There is no dead bottom half of the meter
  where the ball climbs and rolls back; the WHOLE meter is useful.
- POWER STILL MEANS SOMETHING. A soft release is a gentle entry; a hard release is a punchy one. The
  mapping stays monotonic (more meter => faster ball), and the spread between a soft and a hard launch
  stays clearly readable - the launch-skill of releasing at a chosen moment is preserved. We are
  raising the FLOOR so even a weak launch clears, not flattening the difference between weak and strong.
- THE CHUTE STILL LOOKS RIGHT. The snug ball-width lane the developer liked is kept. The ball does not
  rattle so hard it stalls; the launch reads as a clean, confident shot up the lane and over the arch.
- THE SAFETY NET STAYS A SAFETY NET. The failed-launch watchdog (re-serve) remains for genuine edge
  cases, but a NORMAL plunge at any power never trips it - a player should essentially never see a
  re-serve in normal play once the floor is fixed.

### Must-feel qualities (the bar the engineers hit, gray boxes only)
1. THE WHOLE METER CLEARS THE LANE. A launch at MINIMUM power drives the ball's apex PAST the lane exit
   / arch and into the open playfield, then the ball settles in the play area (not back in the lane).
   A low/mid launch does the same with more margin. This is judged by the ball's MEASURED apex position
   (lowest Z) and final resting region, never by a fired-signal counter. The floor is raised so even
   the weakest plunge clears with a sensible margin (the climb needs ~45 u/s; the floor must exceed that
   plus a margin for rattle/friction loss, the physics-programmer sizes the exact number from the
   measurement).
2. POWER YOU CAN STILL FEEL. A full plunge clearly out-throws a minimum plunge (the existing >= 1.5x
   feel floor in test_plunger_launch.gd stays true), and the resulting ball speed lands in the (possibly
   raised) LAUNCH_SPEED_MIN..MAX window. Raising the floor must not collapse the meter into one speed.
3. THE CHUTE STAYS SNUG, THE BALL STILL FLOWS. The lane stays close to its current snug width (the
   developer's preference); if rattle/friction is measured to rob enough energy that mid power stalls,
   the preferred fixes are a LOW-FRICTION lane wall / lower ball-lane friction or a SMALL widen - never
   a return to a bulky box. The plunger face still strikes the ball square and head-on with no gap.
4. THE WATCHDOG STAYS QUIET IN NORMAL PLAY. The LAUNCH_SETTLE_TIME_S re-serve still recovers a genuine
   failed launch, but a normal plunge at ANY power crosses LAUNCH_REACHED_PLAY_Z well before the timer
   and never triggers it. (If raising the floor makes every normal plunge clear, the watchdog should
   essentially never fire outside contrived edge cases - that is the correct outcome.)
5. NOTHING TUNNELS, EVER. If LAUNCH_SPEED_MAX is raised, the no-tunnel stress tests must fire at
   >= ~2x the NEW max and still show zero tunneling through the plunger face, lane pocket, walls, arch,
   targets, bumpers, slings, lane guides, or flippers. Hard gate on the ball's REAL measured
   position/velocity at 240 Hz with continuous_cd on, against real instanced bodies.

### Design constraints the engineers must honor (do NOT re-litigate)
- SCOPE: FIX THE LAUNCH ONLY. No new element types, ramps, modes, multiball, multipliers, rollover
  scoring, art, or audio. Same element counts. The ONLY changes are: the launch SPEED tuning
  (LAUNCH_SPEED_MIN/MAX and the PLUNGER_STROKE_SPEED_MIN/MAX that feed it), optionally the lane-wall /
  ball-lane FRICTION or a SMALL lane widen if rattle is measured to be a real cause, and the NEW
  behavioral lane-clear test. Do not re-shape the table, re-home furniture, or touch the flipper drive.
- DIAGNOSE BY MEASUREMENT, NOT BY GUESS. Headless, on the REAL tilted Playfield with the REAL
  TableGeometry (the same build tests/test_plunger_launch.gd uses), fire MIN/MID/MAX and MEASURE
  (a) the delivered ball speed just after the strike and (b) the apex (lowest Z reached before
  rollback). Determine which of (a) floor-too-low, (b) impulse-under-delivers, (c) rattle/friction-
  stalls are actually true. Fix the MEASURED cause(s); report the numbers in the deliverable.
- RAISE THE FLOOR SO THE WHOLE METER IS USEFUL. LAUNCH_SPEED_MIN (and PLUNGER_STROKE_SPEED_MIN feeding
  it) must rise so EVEN A MINIMUM plunge clears the lane into play with margin over the ~45 u/s climb
  requirement plus measured rattle/friction loss. Keep LAUNCH_SPEED_MAX a satisfying hard plunge,
  clearly stronger than the new min (raise MAX too if needed to preserve a readable weak-vs-strong
  spread). The power->speed mapping still lives off TableConfig.LAUNCH_SPEED_MIN/MAX; the contract
  (power 0..1, monotonic) is unchanged.
- KEEP THE CHUTE SNUG. The developer liked the ball-width look (LANE_WIDTH 2.0). Prefer a low-friction
  lane wall / lower ball-lane friction, or a SMALL widen, over a fat lane, IF AND ONLY IF the
  measurement shows rattle/friction is a real contributor. If the floor-raise alone makes the whole
  meter clear cleanly, do not touch the lane geometry at all. The plunger face stays square to the ball.
- PRESERVE EVERY EXISTING CONTRACT. The plunger contract (power_changed/ball_launched; arm/disarm/
  set_ball/is_armed; power 0..1; the oscillating meter; impulse-on-contact launch, NOT a code velocity
  set on the ball) is unchanged - this is a TUNING + TEST slice behind the same contract. The flipper
  drive, the soft-lock watchdog, the lane pocket, the furniture, and the world scale are all unchanged.
- CLOSE THE TEST GAP (this is why it shipped). ADD a BEHAVIORAL launch test that asserts the ball
  actually CLEARS THE LANE INTO THE PLAYFIELD, not merely that it has speed. On the real tilted lane:
  a launch at MIN power (and at a low/mid power) drives the ball's apex up-table PAST the lane exit /
  arch and crosses into the play area (the ball center crosses up-table of LAUNCH_REACHED_PLAY_Z / the
  lane-divider top), then settles in the OPEN playfield, NOT back in the lane. Use the ball's MEASURED
  position as the oracle (position cannot lie). KEEP test_plunger_launch.gd (speed + no-fall-out-bottom)
  and test_plunger_lane_size.gd GREEN. A speed-only green suite that never asserts lane-clear is a FAIL.
- PHYSICS NORTH-STAR (do not regress). Ball continuous_cd at 240 Hz; the no-tunnel stress tests
  (fire >= ~2x LAUNCH_SPEED_MAX at flippers/walls/furniture) stay green; if LAUNCH_SPEED_MAX rises, the
  stress tests fire at >= 2x the NEW max and still show zero tunneling. Do not break the flipper/ball/
  plunger asset visuals already on main (PR #12 flipper).
- VALIDATE DETERMINISTICALLY. tools/table_viz.py side/projected view can sanity-check the lane-to-arch
  path if helpful; the homelab CI is the source of truth for green.
- House style: typed GDScript, snake_case, document the WHY (especially the MEASURED numbers behind any
  tuning change), no emojis, no em-dash characters; lines <= 100 chars; gdlint clean (~/.local/bin/gdlint).
- DELIVERY: the team's Setup phase creates the slice branch. Build/QA agents COMMIT but do NOT push.
  Deliver verifies the FULL GUT suite GREEN locally (fetch headless Godot 4.x, run GUT) BEFORE pushing
  ONE PR. Do NOT touch main. The producer requires green CI on the pushed sha to PASS; the human merges.

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

### Cut from the "real pinball furniture" slice (2026-06-19) - defended:
The developer scoped this slice as "mechanics + representative layout", NOT a commercial board. The
flame-skull CAD image is a placement GUIDE only. Explicitly cut and held out, even though they appear
in the reference image:
- ROLLOVER SCORING / lit lanes: we build the physical inlane/outlane GUIDE WALLS only (so the ball is
  funneled), but NO rollover triggers, lights, lane completion, or ball-save logic. (Matches the v1
  cut list "outlanes/inlanes with lights".)
- RAMPS and any second board, multiball, modes, multipliers, wizard mode, combos.
- DROP-TARGET drop/reset logic, spinners, kickbacks, magnets, the one-way plunger gate as a scoring
  element (the lane already rests the ball physically).
- ART, models, textures, lighting, audio/SFX. Gray boxes only.
Why hold the line: the whole point of "representative" is to prove the FURNITURE FEELS RIGHT (active
kicks, rubber rebound, makeable shots) on a basic layout before committing art/scope to a full board.
A complete commercial board with limp bumpers would be a worse outcome than three bumpers that truly
fire the ball away. One great table first.

### Cut from the "Table reshape + playtest fixes" slice (2026-06-19) - defended:
The developer chose ONE big slice of FIVE concrete fixes. It is a fix/reshape pass, not a feature
pass. Explicitly held OUT (creep that the five reported items could pull in):
- NEW element types or counts: no new bumpers/targets/ramps/spinners/kickbacks/magnets. Same counts;
  only shape/size/spacing/width change.
- The kenney.nl CC0 ART pass: the developer pointed at it for LATER. This slice is gray-box materials
  only (2-tone black-body/white-rubber flipper). Do NOT block on or pull in external art now.
- HALF_LENGTH change / making the table longer: this is a WIDEN only (HALF_WIDTH 12 -> 16).
- Re-tuning the launch FEEL numbers (speed range, meter sweep) or the flipper drive: the launch fix is
  a MECHANISM swap behind the same contract/feel targets; the flipper change is a SHAPE swap behind the
  same drive. Do not re-litigate the tuned constants while fixing the mechanism/shape.
- Rollover scoring, lights, ball-save, modes, multiball - still deferred (v1 cut list stands).
Why hold the line: the player cannot even launch the ball today. The win is making the EXISTING table
launch, read, and play correctly - not adding more to a table that does not yet start. One great
table first.

### Cut from the "Playtest fixes 2" slice (2026-06-20) - defended:
A second fix pass on developer playtest feedback against the deployed wider table. Eight items, no new
mechanics. Explicitly held OUT (creep the eight items could pull in):
- NEW element types or counts: no new bumpers/targets/slingshots/ramps/spinners/kickbacks/magnets.
  Same counts; only shape/size/material/state-logic change.
- RE-RESCALING the table: HALF_WIDTH 16 / HALF_LENGTH 25 / ball radius / gravity / flipper geometry /
  furniture positions all STAY. This slice narrows the LANE and resizes the PLUNGER FACE and the
  SLINGSHOT shape only; it is not another widen/length change.
- The kenney.nl CC0 ART pass: still LATER. Gray-box materials only (the flipper stays the 2-tone
  black-body/white-rubber-top look; the fix is making that render on BOTH bats, not adding art).
- RE-TUNING the launch FEEL numbers (speed range, meter sweep) or the flipper DRIVE: the plunger
  resize is geometry behind the same contract/feel; the flipper fix is material/mesh correctness
  behind the same drive. Do not re-litigate the tuned constants while fixing the geometry/material.
- A general ball-save / outlane-save system: the soft-lock fix is specifically "a ball that NEVER
  reached play is recoverable", not a ball-save for a ball that genuinely drained. Rollover scoring,
  lights, ball-save, modes, multiball - still deferred (v1 cut list stands).
Why hold the line: a soft-lock that ends the session and a launch lane that does not fit the ball are
control failures that block Gate 0 outright. Fix the EXISTING table so a failed launch is always
recoverable, every piece reads as what it is, and the controls/HUD are legible every ball - then judge
the fun. One great table first.

### Cut from the "Fix the launch" slice (2026-06-20) - defended:
A single-bug correctness slice: the ball does not clear the launch chute into play. Explicitly held
OUT (creep this one bug could pull in):
- ANY new element types or counts, table re-shape, furniture re-home, or world rescale. This is a
  launch SPEED tuning + a behavioral lane-clear TEST, plus a small friction/lane tweak ONLY IF the
  measurement proves rattle is a real cause. Same table, same furniture.
- A general re-tune of the FLIPPER feel, the meter sweep, the soft-lock watchdog, or the plunger
  mechanism. The plunger contract and the impulse-on-contact launch stay; we change the speed FLOOR
  (and ceiling if needed), not the launch MECHANISM.
- Returning to a bulky launch lane. The developer liked the snug ball-width chute; the fix keeps it
  (a low-friction lane wall or a small widen is the most we touch geometry, and only if measured).
- Art/audio, rollover scoring, lights, ball-save, modes, multiball - still deferred (v1 cut list stands).
Why hold the line: the player cannot start a ball today on a launch at low/mid power. The win is the
narrowest possible: make EVERY plunge reach play and lock that with a test that asserts the ball
ARRIVES, not just that it has speed. Fix the one bug, close the one gap, do not reopen the table. One
great table first.
