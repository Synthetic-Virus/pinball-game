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
