extends Node
## TableConfig - the WORLD-SCALE CONTRACT for the whole table (autoload singleton).
##
## WHY THIS EXISTS: the design (docs/DESIGN.md) mandates a single chosen world scale that every
## element honors. This file IS that decision, written down once. Ball radius, playfield extents,
## flipper geometry, gravity, and table tilt all live here so no two elements drift out of scale.
##
## OWNERSHIP: lead-programmer owns these numbers. Physics-programmer TUNES forces/springs in the
## flipper/ball scripts, but reads geometry and scale from HERE. If a number below needs to change,
## change it here (one edit) and tell the team, because it re-scales the whole table.
##
## ============================================================================================
## THE DECISION (do not re-litigate per element - DESIGN.md "World scale"):
##   - Larger pinhead-style scale with HIGH gravity (magnitude 200), NOT the old tiny
##     0.013 m ball / 9.8 gravity scale. Rationale: the force-driven flipper/solenoid tuning is
##     calibrated for this range, it keeps Jolt's solver well behaved, and it avoids the precision
##     fragility of sub-centimeter rigid bodies.
##   - Units are abstract "world units" (treat 1 unit ~= 1 cm of a real table for intuition only;
##     nothing depends on a real-world meter mapping).
## ============================================================================================

## ---- GRAVITY AND TILT --------------------------------------------------------------------------
## Gravity MAGNITUDE. Mirrors physics/3d/default_gravity in project.godot (keep in sync).
const GRAVITY: float = 200.0
## Table tilt in degrees. A real table tilts back ~6-7 deg so the ball rolls toward the flippers.
## We model the table as a flat playfield rotated by this around X; gravity stays world-down (-Y),
## so the down-slope component pulls the ball toward the drain end. See gravity_along_table().
const TILT_DEG: float = 7.0

## ---- BALL --------------------------------------------------------------------------------------
const BALL_RADIUS: float = 0.6      ## World units. ~0.5-1.0 per the DESIGN brief; 0.6 chosen.
const BALL_MASS: float = 0.6        ## Kept near unity at this scale for stable solver behavior.
const BALL_BOUNCE: float = 0.15     ## PhysicsMaterial bounce. Low: a steel ball is not bouncy.
const BALL_FRICTION: float = 0.4

## ---- PLAYFIELD EXTENTS -------------------------------------------------------------------------
## The play area is an upright rectangle on the tilted plane. Local coords on the playfield node:
##   +X = right, -X = left, -Z = up-table (toward the arch), +Z = down-table (toward the drain).
## HALF_WIDTH/HALF_LENGTH are measured from playfield center to the inner wall faces.
## WIDEN (SLICE "Table reshape + playtest fixes", 2026-06-19): HALF_WIDTH 12 -> 16 (~33% wider).
## WHY: developer playtest feedback - the field felt cramped and the furniture had no room to
## breathe. This is a WIDEN ONLY: HALF_LENGTH stays 25 (the table does not get longer - DESIGN cut
## list). The lead re-derives EVERY X-dependent constant below from HALF_WIDTH / LANE_INNER_X so the
## proportions hold and nothing ends up in a wall, off the field, or crossing the centerline.
## Constants written as expressions of HALF_WIDTH auto-follow; the few hardcoded X LITERALS
## (BALL_START.x, the furniture position arrays, the slingshot X) are re-derived by hand below with
## a WHY-comment on each. The rescale is re-validated by tools/table_viz.py + test_world_scale.gd
## + test_furniture_layout.gd + test_shot_geometry.gd before the slice ships.
const HALF_WIDTH: float = 16.0      ## => 32 units wide (was 24). The WIDEN.
const HALF_LENGTH: float = 25.0     ## => 50 units long (UNCHANGED - widen only, not longer).
const WALL_HEIGHT: float = 2.4      ## How tall the perimeter/arch walls stand off the surface.
const WALL_THICKNESS: float = 0.8

## Launch lane up the RIGHT side. The lane is a narrow channel between the right outer wall and an
## inner divider; the plunger sits at its bottom and shoots the ball up into the arch.
## RESIZE (SLICE "Playtest fixes 2", 2026-06-20): LANE_INNER_X 10.5 -> 14.0 so the lane SHRINKS to a
## SNUG ~ball-width chute. Developer playtest feedback: the launch ramp/plunger were too wide/bulky
## and did not line up with the ball. The lane was 5.5 units wide (LANE_INNER_X 10.5) - over four
## ball diameters; the ball rattled and the oversized plunger face read as a box. WHY 14.0: it gives
## LANE_WIDTH = 16 - 14 = 2.0 units (~1.7 ball diameters), so the ball (radius 0.6, spanning a
## 1.2-unit diameter) sits squarely in the chute with ~0.4 units clearance on each side - snug, not
## sloppy. The plunger face (LANE_WIDTH - 0.6 = 1.4, a ball-and-a-bit) then strikes the ball square.
## The lane center moves to (LANE_INNER_X + HALF_WIDTH)/2 = 15.0; BALL_START.x + PLUNGER_REST_POS.x
## (both the lane center) auto-follow there so the ball/plunger stay aligned (BALL_START.x is a
## hardcoded literal re-derived below). The divider at 14.0 stays well inside the +16 right wall
## (ball at x=15.0 spans [14.4, 15.6], inside [14, 16]). This is NOT a table rescale: HALF_WIDTH 16
## and HALF_LENGTH 25 are UNCHANGED (DESIGN cut list). The OPEN center drain region [-16, 14.0]
## widens slightly (the divider moved outboard), and the drain math (all expressed off LANE_INNER_X
## HALF_W) follows automatically. The right lane-guide divider (LANE_GUIDE_RIGHT_DIVIDER_X = 9.0)
## still sits inboard of the new lane (between flipper pivot 7.2 and the divider 14.0), so it needs
## no change. Re-validated by tools/table_viz.py + test_world_scale/test_furniture_layout.
const LANE_INNER_X: float = 14.0    ## X of the inner divider wall (lane lives to its right).
const LANE_WIDTH: float = HALF_WIDTH - LANE_INNER_X  ## +HALF_WIDTH minus the divider (= 2.0).

## ---- ARCH (rounded top) ------------------------------------------------------------------------
## A half-arch across the top turns the ball launched up the lane back over into the playfield.
const ARCH_CENTER_Z: float = -HALF_LENGTH + 6.0  ## How far down from the very top the arch curves.
const ARCH_RADIUS_X: float = HALF_WIDTH          ## Spans the table width.
const ARCH_RADIUS_Z: float = 6.0
const ARCH_SEGMENTS: int = 16                    ## Polyline segments approximating the curve.

## ---- FLIPPERS ----------------------------------------------------------------------------------
## Two flippers form an inverted V near the drain end. Pivot positions are on the playfield plane.
const FLIPPER_LENGTH: float = 7.0   ## Pivot to tip. Drives reach and the momentum it can impart.
const FLIPPER_WIDTH: float = 1.4
const FLIPPER_HEIGHT: float = 1.2   ## Thickness off the surface (must exceed BALL_RADIUS overlap).
## Half-distance between the two pivots (so pivots sit at +/-FLIPPER_PIVOT_SPREAD on X).
## CONSTRAINT (verified by tests/test_world_scale.gd test_flippers_do_not_overlap_at_pivots):
## the two bats, each reaching FLIPPER_LENGTH*cos(|REST_ANGLE|) in X toward center from its pivot,
## must leave a POSITIVE gap at the centerline (an inverted V, not an X). With FLIPPER_LENGTH 7 and
## REST_ANGLE -0.55 the x-reach is ~5.97, so the spread must exceed that.
##
## WIDEN (drain mouth stays ~1-ball-plus, NOT a chasm): the drain mouth is
##   gap = 2*SPREAD - 2*FLIPPER_LENGTH*cos(|REST_ANGLE|) = 2*SPREAD - 11.94.
## Scaling SPREAD by the full 16/12 would blow the mouth out to ~6.7 units (a chasm a ball cannot be
## cradled over - DESIGN forbids "a chasm"). So we DO NOT scale the gap with the width; we keep a
## sane ~2.4-unit mouth (~2 ball diameters: a missed flip can drain, a cradle still holds) and move
## the pivots out only enough to deliver it: SPREAD = (gap + 11.94)/2 = (2.4 + 11.94)/2 = 7.17 ->
## 7.2. This nudges the flippers slightly outward on the wider field (so the lower field is not a
## tiny island in the middle) while the drain mouth stays the proven-playable size. Pivots at +/-7.2
## stay well inside the +/-16 side walls, leaving the wider side channels for the lane guides.
const FLIPPER_PIVOT_SPREAD: float = 7.2
const FLIPPER_PIVOT_Z: float = HALF_LENGTH - 5.0  ## How far up from the drain the pivots sit.
## Resting and energized angles (radians) of the flipper about its pivot, measured on the playfield
## plane. Left flipper points up-right at rest and swings up; right is mirrored. Physics-programmer
## may refine these as the hinge limits, but the geometry above is the contract.
const FLIPPER_REST_ANGLE: float = -0.55
const FLIPPER_UP_ANGLE: float = 0.15

## The MAXIMUM down-table (greatest +Z) a flipper BAT reaches at any swing angle, in playfield-local
## Z. This is the DOWN-TABLE EDGE of the "catch zone" the drain volume must stay clear of (QA
## BUG-023): if the drain's up-table edge sits above (less than) this, the drain swallows the ball a
## player was about to cradle/flip, breaking the core loop. DERIVATION (independent oracle, QA
## BUG-023): a bat of length FLIPPER_LENGTH and half-width FLIPPER_WIDTH/2, pivoted at
## FLIPPER_PIVOT_Z and rotated through the rest..up sweep, reaches at most ~21.74 by the precise
## corner math; QA's bounding-box oracle put a far corner at 23.66. We take the LARGER (pessimistic)
## value PLUS a clearance margin so the drain edge clears the bat with room to spare regardless of
## which oracle is tighter. The test_world_scale config assert pins DRAIN_Z - DRAIN_DEPTH/2 above
## this value, so the boundary is machine-checked the way BUG-022's was.
const FLIPPER_BAT_MAX_Z: float = 23.66
## Clearance the drain's up-table edge keeps ABOVE FLIPPER_BAT_MAX_Z. Half a ball diameter is a
## comfortable, readable buffer (a ball whose CENTER is still above the bat zone cannot trip the
## drain). Increase if a future flipper resize pushes the bat zone further down-table.
const DRAIN_BAT_CLEARANCE: float = 0.6

## ---- DRAIN -------------------------------------------------------------------------------------
## Open center drain: a trigger volume below the flippers. A ball entering it is lost.
## DRAIN_Z sits BELOW the flipper bat catch zone (the drain up-table edge clears FLIPPER_BAT_MAX_Z)
## but its center stays INSIDE the playfield bottom edge (HALF_LENGTH = 25), so a ball that gets
## past the flippers falls into the drain BEFORE it reaches the open bottom edge. table_geometry.gd
## deliberately leaves the bottom perimeter OPEN (no bottom wall) so nothing blocks the drain.
## Earlier this was HALF_LENGTH + 2 = 27, placing the trigger 2 units OUTSIDE the playfield - if a
## naive bottom wall were ever built it would block the drain (QA BUG-004). Keeping the CENTER
## inside the field removes that dependency.
##
## QA BUG-023 FIX: the previous DRAIN_Z (HALF_LENGTH - 1 = 24) with DRAIN_DEPTH 6 spanned z
## [21.0, 27.0]. Its up-table edge (21.0) sat ABOVE the flipper bats (which reach down-table to
## ~23.66), so the drain volume overlapped the flipper catch zone: a ball falling toward the
## flippers crossed the drain up-table edge ~2.66 units BEFORE reaching the bat faces and drained
## while the player was about to flip it (a Gate-0 core-loop break). The drain is the gap BELOW the
## not OVER them. FIX: shrink DRAIN_DEPTH and place DRAIN_Z so the up-table edge sits a clearance
## margin BELOW the bat zone, while the center stays inside the field. The down-table edge may
## extend a little past the open bottom (the ball simply falls into it there), which is fine.
##   up_table_edge = DRAIN_Z - DRAIN_DEPTH/2  must be  > FLIPPER_BAT_MAX_Z + DRAIN_BAT_CLEARANCE
## We size DRAIN_DEPTH first (a slim catch band is enough below the flippers), then place DRAIN_Z so
## the up-table edge lands exactly at FLIPPER_BAT_MAX_Z + DRAIN_BAT_CLEARANCE.
const DRAIN_DEPTH: float = 1.6
## Up-table edge = FLIPPER_BAT_MAX_Z + DRAIN_BAT_CLEARANCE = 24.26; center = edge + DRAIN_DEPTH/2 =
## 25.06. The center sits a hair past HALF_LENGTH (25.0); the down-table half of the slim band hangs
## just below the open bottom mouth (where the ball is already lost), and the trigger fires on the
## up-table edge at 24.26, cleanly below the bats and above the open bottom. The test_world_scale
## config assert (DRAIN_Z - DRAIN_DEPTH/2 > FLIPPER_BAT_MAX_Z) machine-checks this boundary.
const DRAIN_Z: float = FLIPPER_BAT_MAX_Z + DRAIN_BAT_CLEARANCE + DRAIN_DEPTH * 0.5
## DRAIN spans ONLY the CENTER MOUTH between the flipper tips - the actual gap a ball falls through
## (QA BUG-023 behavioral fix, SLICE "Table reshape + playtest fixes", 2026-06-19).
##
## ROOT CAUSE this replaces: the drain previously spanned the WHOLE open-center width
## (x in [-HALF_WIDTH, LANE_INNER_X], ~26.5 units). DESIGN says "open CENTER drain between/below the
## flippers", but a volume that wide also covered the X under the flipper BODIES (the pivots sit at
## +/-FLIPPER_PIVOT_SPREAD = +/-7.2). The BUG-023 fix only cleared the drain in Z (up-table edge
## below the bats), but a ball seated in the catch zone at the LEFT pivot X (-7.2) is NOT on the
## angled bat there (near the pivot the bat sits up at z~PIVOT_Z=20, far up-table of the ball),
## so it rolls straight down-table and the over-wide drain swallowed it - the exact core-loop break
## behavioral oracle (a real ball dropped at z~23.06) still caught after the Z-only math fix.
##
## THE FIX (geometry, not a guard): a real ball only LEAVES the table through the GAP BETWEEN THE
## FLIPPER TIPS (the inverted-V mouth). The drain must be exactly that mouth, centered on the table
## centerline (x = 0, between the symmetric flippers), NOT the whole open width. A ball over a
## flipper body (x ~= +/-7.2) is the flipper's to catch/flip; it can never be in the drain volume
## now, so the cradle/catch-zone ball cannot drain (BUG-023). A ball that slips through the center
## gap still drains; a ball lost down a side channel is caught by the OOB failsafe (OOB_DRAIN_Y).
## The launch lane (far +X) is also far outside this central mouth, so a lane/dribble ball never
## drains here (QA B3 stays honored by geometry, no GameFlow state guard needed).
##
## WIDTH = the inter-tip mouth (2*(SPREAD - FLIPPER_LENGTH*cos|REST_ANGLE|)) PLUS one ball diameter
## of capture margin so a ball entering the mouth slightly off-center is still caught cleanly. With
## SPREAD 7.2, reach ~5.97 the mouth is ~2.46; +1.2 gives ~3.66 (span ~ +/-1.83), comfortably inside
## the +/-7.2 flipper zone (no catch-zone overlap) and wide enough to read as the drain mouth.
const _DRAIN_MOUTH: float = 2.0 * (
	FLIPPER_PIVOT_SPREAD - FLIPPER_LENGTH * cos(absf(FLIPPER_REST_ANGLE))
)
const DRAIN_WIDTH: float = _DRAIN_MOUTH + 2.0 * BALL_RADIUS  ## Mouth + ball-diameter capture slack.
## Centered on the table centerline (x = 0): the drain is the symmetric gap BETWEEN the flippers,
## NOT the full open region. This keeps a ball over a flipper body (x ~= +/-7.2) out of the drain.
const DRAIN_CENTER_X: float = 0.0

## Out-of-bounds failsafe (defense in depth, QA BUG-006): if the ball ever escapes the playfield
## sideways or pops over a wall, it would fall forever and soft-lock the game in BALL_IN_PLAY. A
## large
## low catch-plane well below the surface drains ANY ball that falls past it, regardless of X/Z. In
## normal play the ball never reaches it; it only fires when something has already gone wrong.
const OOB_DRAIN_Y: float = -20.0

## ---- LAUNCH-LANE BOTTOM POCKET -----------------------------------------------------------------
## The table is tilted (drain end, +Z, down) and the perimeter has NO bottom wall (the center drain
## lives at the open bottom). Without a stop the ball placed at BALL_START rolls down +Z and falls
## off the open bottom edge of the LAUNCH LANE (QA: "ball falls out the bottom of the lane").
## The fix is a short static wall that closes ONLY the bottom of the launch lane (x in
## [LANE_INNER_X, HALF_WIDTH]); the center drain region (x in [-HALF_WIDTH, LANE_INNER_X]) stays
## OPEN so a drained ball still falls into the drain. table_geometry.gd builds this from these.
##
## The pocket wall stands at the lane's bottom edge. Its up-table face must sit BELOW (greater Z
## than) the ball's rest position so the resting ball leans against it. We place the wall's INNER
## face at LANE_POCKET_FACE_Z and give it a small thickness; it stands WALL_HEIGHT tall.
const LANE_POCKET_FACE_Z: float = HALF_LENGTH - 0.5  ## Inner (up-table) face of the pocket wall.
const LANE_POCKET_THICKNESS: float = WALL_THICKNESS  ## Same stock as the perimeter walls.

## ---- LAUNCH / PLUNGER --------------------------------------------------------------------------
## Ball rest position at the bottom of the launch lane (local playfield coords). It sits just
## up-table of the pocket wall (LANE_POCKET_FACE_Z) so the resting ball is trapped between the
## pocket and the plunger face. WHY z here: with ball radius 0.6 and the pocket face at
## HALF_LENGTH - 0.5 = 24.5, a rest z of HALF_LENGTH - 2.0 = 23.0 leaves the ball's down-table
## surface (z ~= 23.6) just shy of the pocket face, so it settles against the pocket, no overlap.
## RESIZE (SLICE "Playtest fixes 2", 2026-06-20): the lane narrowed (LANE_INNER_X 10.5 -> 14.0), so
## the lane CENTER moved from 13.25 to (LANE_INNER_X + HALF_WIDTH) * 0.5 = (14.0 + 16) / 2 = 15.0.
## BALL_START.x is re-derived to 15.0, the same X the plunger face centers on (PLUNGER_REST_POS.x),
## so the resized face strikes the ball head-on in the snug chute. (Before this edit x=13.25 would
## sit OUTSIDE the narrowed lane, on the divider / in the open field, and the ball would never seat
## against the plunger.) Written as the literal 15.0 (not the expression) so the thin-client
## tools/table_viz.py parser, which reads single-line Vector3 literals, stays simple; the derivation
## is the comment above.
const BALL_START: Vector3 = Vector3(15.0, BALL_RADIUS + 0.2, HALF_LENGTH - 2.0)

## Resulting ball speed range we WANT a launch to produce, mapped from the power meter (0..1). Tuned
## at this scale/gravity so a min launch dribbles and a max launch clears the arch. This is the FEEL
## target the physical plunger strike is calibrated against; the HUD/tests still read these bounds.
##
## FIX (SLICE "Fix the launch", REVISED 2026-06-20): the first attempt mis-diagnosed this as a
## speed-floor problem and raised MIN 30->60 / MAX 90->110. That was WRONG on both counts, proven by
## the suite running locally:
##
## THE REAL BUG IS GEOMETRIC, not speed. The diagnostic harness (tests/test_launch_diagnostic.gd)
## measured AMPLE delivered speed (MIN 60 -> apex z=-11, well up the lane) - the ball was never
## starved. But test_launch_clears_lane proved the ball came to REST back in the cradle (x=15,
## z=23): it rises up the lane, and ABOVE the LaneDivider top (z=-13) the symmetric arch dome does
## NOT turn a ball rising in the RIGHT lane - at x ~ lane center the dome face is near-vertical, so
## the ball reflects straight back DOWN and rolls home. No amount of speed fixes a missing turn.
##
## THE REAL FIX: a LaneExitDeflector (scripts/table_geometry.gd _build_lane_exit_deflector) - a
## ~45-degree wall at the lane top that reflects the rising ball's up-velocity into LEFT velocity,
## releasing it into the open playfield so it cannot fall back down the channel. The speeds now only
## need to carry the ball UP TO the deflector (z ~ -13.5), a ~37-unit climb (~43 u/s frictionless).
##
## SPEED FLOOR/CEILING: MIN delivered 70 (clears the ~43 u/s climb to the deflector with margin for
## the snug-lane friction loss the diagnostic measures). MAX 90 - REVERTED from the mistaken 110.
## WHY NOT 110: every no-tunnel stress test fires at 2.0 * LAUNCH_SPEED_MAX (read LIVE), so MAX 110
## fired the stress at 220 u/s, and a restitution bounce off an element returned ~141 u/s - ABOVE
## the 120 KICK_MAX_OUTGOING_SPEED CCD-safe cap, a tunneling-safety regression the suite caught. MAX
## 90 keeps the stress at 180 u/s (bounce ~115 < 120), the proven-safe band. Spread 90/70 = 1.29x is
## modest; widen the FEEL later by lowering the deflector turn point, NOT by raising MAX past the
## CCD-safe ceiling.
const LAUNCH_SPEED_MIN: float = 70.0
const LAUNCH_SPEED_MAX: float = 90.0

## ---- PHYSICAL PLUNGER STROKE -------------------------------------------------------------------
## The plunger is now a PHYSICAL body (AnimatableBody3D on KINEMATIC_OBSTACLES, like the flippers)
## that STRIKES the ball and transfers momentum through the collision, instead of code setting the
## ball's velocity directly. On release the plunger body is driven up-table (local -Z) at a stroke
## speed mapped from the power meter; the moving face collides with the resting ball and throws it.
##
## WHY these stroke speeds (mapped from power 0..1): for a head-on strike of a kinematic face into
## a low-restitution steel ball (BALL_BOUNCE 0.15), the ball leaves at roughly the face speed (a
## little more from the slight bounce, a little less from contact losses), so the stroke-speed range
## is set CLOSE TO the desired ball-speed range LAUNCH_SPEED_MIN..MAX but trimmed at the top so a
## max strike does not overshoot the 90 u/s feel target. The transfer is solver-dependent, so these
## are the first on-device tuning knobs: verify in the browser build that a full strike clears the
## arch and a min strike dribbles, and nudge these two numbers (only) if needed. Tests assert the
## MAPPING is monotonic and meaningful and that the ball lands in-range, not an exact value.
## The stroke speeds FEED the delivered ball speed (the launch impulse is mass * stroke_speed applied
## to a ball at rest, so the ball leaves at ~the stroke speed - see scripts/plunger.gd
## _try_apply_launch_impulse), so these track LAUNCH_SPEED_MIN..MAX. REVISED with the launch fix:
## MIN 70 so even the weakest plunge carries the ball up to the LaneExitDeflector and turns into the
## field; MAX 88 (just under LAUNCH_SPEED_MAX 90) so a full strike stays inside the CCD-safe band
## (see the LAUNCH_SPEED_MAX WHY note - 110 broke the no-tunnel cap). Spread is modest by design.
const PLUNGER_STROKE_SPEED_MIN: float = 70.0   ## Power 0.0: carries the ball to the lane deflector.
const PLUNGER_STROKE_SPEED_MAX: float = 88.0   ## Power 1.0: hard strike, just under LAUNCH_SPEED_MAX.

## How far (world units) the plunger face travels up-table on a full stroke before it returns home.
## It only needs to travel far enough to stay in solid contact with the ball through the strike; a
## short firm stroke avoids the face overshooting up the lane and re-hitting the ball it just threw.
const PLUNGER_STROKE_LENGTH: float = 2.0

## Plunger face box dimensions (local). It must be WIDER than the ball so an off-center rest still
## gets struck squarely, and TALLER than the ball center so it cannot slip over/under. The face is
## seated IN CONTACT with the resting ball (no gap), so the strike pushes an already-touching ball
## and there is no gap to tunnel across on the first step. At 240 Hz a 78 u/s face moves 0.325
## u/step, so a 0.8 u thickness still gives ~2.5 steps of overlap depth AND the ball's own
## continuous_cd sweeps against the face; head-on tunneling is not possible. The thickness is also
## chosen so the plunger rest body sits just UP-TABLE of the lane pocket (no overlap, see REST_POS).
## RESIZE (SLICE "Playtest fixes 2", 2026-06-20): with the narrowed lane (LANE_WIDTH 2.0) this is
## 2.0 - 0.6 = 1.4 units - a snug ball-and-a-bit face (ball diameter 1.2), down from the old 4.9. It
## still spans WIDER than the ball so an off-center rest is struck square, and fits inside the lane
## (face at lane center 15.0 spans [14.3, 15.7], inside the [14, 16] lane) with clearance. The
## structural test (tests/test_plunger_lane_size.gd) asserts this value matches the resized lane.
const PLUNGER_FACE_WIDTH: float = LANE_WIDTH - 0.6  ## Snug ball-width face inside the lane (= 1.4).
const PLUNGER_FACE_HEIGHT: float = 2.0              ## Spans the ball center (ball center y ~= 0.8).
const PLUNGER_FACE_THICKNESS: float = 0.8           ## Tiles between the ball and the lane pocket.

## The plunger's REST position (local playfield coords). It seats in the lane just DOWN-TABLE of the
## ball (greater Z) so its up-table face is in light contact with the ball's down-table surface. The
## face sits at ball_down_surface_z = BALL_START.z + BALL_RADIUS; the body center is half a
## thickness further down-table. With BALL_START.z 23.0, radius 0.6, thickness 0.8: face up-edge =
## 23.6 (touches the ball), body center z = 24.0, body back edge = 24.4 - just up-table of the lane
## pocket front face (LANE_POCKET_FACE_Z = 24.5), so kinematic plunger and static pocket do not
## overlap. X is centered in the lane; Y centers the face on the ball.
const PLUNGER_REST_POS: Vector3 = Vector3(
	(LANE_INNER_X + HALF_WIDTH) * 0.5,                          ## Centered across the lane width.
	BALL_RADIUS + 0.2,                                         ## Same height as the ball center.
	BALL_START.z + BALL_RADIUS + PLUNGER_FACE_THICKNESS * 0.5  ## Face just behind the ball.
)

## ---- FAILED-LAUNCH RECOVERY (soft-lock fix, SLICE "Playtest fixes 2", 2026-06-20) ---------------
## THE BUG: when a launch is too weak (the ball dribbles back into the lane) or the ball stalls in
## the chute and never reaches the playfield, the game SOFT-LOCKS. The plunger fires ball_launched
## (-> GameFlow BALL_IN_PLAY, plunger disarmed), but the ball never crosses into play and never
## drains, so GameFlow never re-arms: the player is stuck with a dead ball in the lane and no way
## forward. This is a Gate-0 control failure (the session is dead), so the recovery below is needed.
##
## THE FIX (a positional watchdog, NOT a new mechanic - see ARCHITECTURE.md 12): after a launch we
## watch the ball for LAUNCH_SETTLE_TIME_S. If, when that timer expires, the ball is STILL in the
## launch region (it never reached play), we treat the launch as FAILED: re-seat the ball at the
## cradle and RE-ARM the plunger for the SAME ball, WITHOUT spending a ball. A ball that DID reach
## play (crossed up-table of LAUNCH_REACHED_PLAY_Z) cancels the watchdog and plays normally; a
## genuine drain after reaching play is unchanged. The watchdog lives in table.gd (it owns the ball
## flow handles); GameFlow owns the state transition; the constants here are the CONTRACT.
##
## LAUNCH_REACHED_PLAY_Z: the playfield-local Z line (up-table is -Z) the ball CENTER must cross to
## count as "reached play". WHY this value: the ball rests at BALL_START.z (HALF_LENGTH - 2.0 = 23)
## and a successful launch carries it up the lane and over the arch into the field.
##
## QA BUG-031 HARDENING (2026-06-20): the line was the flipper pivot row (FLIPPER_PIVOT_Z = 20.0).
## That was too close to the lane: a ball rolling down a SIDE channel (e.g. the field band between a
## slingshot and the launch-lane divider) can TRANSIENTLY dip its center across z=20 while it is
## really just draining down the side, never having reached play. The watchdog would then falsely
## promote LAUNCHING -> BALL_IN_PLAY on that transient crossing; if the ball then rolled back into
## the launch lane (z ~= 23) the plunger was dead (disarmed, watchdog stopped) and the original
## soft-lock returned by a different path. FIX: move the reached-play line UP-TABLE of the slingshot
## row (FLIPPER_PIVOT_Z - 3.5 = 16.5) so only a ball genuinely up in the field counts as "in play".
## A ball that climbed the lane and came over the arch is at z far up-table of 16.5; a dribble or a
## side-roll stays down-table of it. WHY this exact line: the slingshots sit at
## FLIPPER_PIVOT_Z - 3.5 (SLINGSHOT_*_POS.z), so this line is the slingshot row - the down-table
## edge of the open mid-field.
## A side-draining ball can reach the slingshot Z but not cross UP-TABLE of it without being kicked
## back into play (which is itself "reached play"); a transient dip toward the flippers cannot reach
## this far up. The gap from the lane (23) to this line (16.5) is ~5 ball diameters, still a clean,
## unambiguous split between "dribbled / draining" and "in play".
const LAUNCH_REACHED_PLAY_Z: float = FLIPPER_PIVOT_Z - 3.5
## LAUNCH_SETTLE_TIME_S: how long after ball_launched we wait before judging a launch failed. WHY
## 2.0 s: a full-power launch (LAUNCH_SPEED_MAX 90 u/s) clears the lane and crosses the reached-play
## line in a fraction of a second; even a marginal launch that just barely clears does so well under
## a second. A ball that has NOT crossed the line after 2.0 s has demonstrably failed to reach play
## (it dribbled back or stalled). The window is generous enough that a slow-but-successful launch is
## never falsely recovered, and short enough that a real soft-lock is broken almost immediately. The
## watchdog re-checks each physics frame after the timer expires until the ball is recovered or
## reaches play, so a ball that crawls up after the window is still handled (recovered if still in
## the lane, left alone once it crosses the line).
const LAUNCH_SETTLE_TIME_S: float = 2.0

## ================================================================================================
## SLICE "real pinball furniture" placement + feel constants (2026-06-19).
## ADDED by the lead-programmer; NO existing value above this block changed (the world-scale
## contract
## is frozen). Every new body in this slice reads its geometry/feel from here. These numbers are the
## CONTRACT for the slice: pop-bumper/slingshot/standup-bank positions, the active-kick impulse
## (with
## a CCD-safe cap and a minimum outgoing speed), and the per-element re-trigger cooldown.
##
## They are validated geometrically (CAD discipline) by tools/table_viz.py: every kick direction
## must
## point INTO play (up-table / toward center), never at the drain or a wall, and the standup bank
## must
## sit inside a flipper-tip sweep. See docs/ARCHITECTURE.md section 10.
## ================================================================================================

## ---- ACTIVE KICK (shared by pop bumpers AND slingshots) ----------------------------------------
## The developer's "bell thingy that contracts to shoot the ball away": on contact an active element
## applies a coded OUTWARD impulse, so even a ball that crawls in is fired away with authority. This
## is the deliberate divergence from the prior art (which is passive restitution only -
## REFERENCES.md).
##
## WHY AN IMPULSE, NOT JUST RESTITUTION: restitution scales the OUTGOING speed by the INCOMING
## speed,
## so a slow ball leaves slowly (limp). An impulse adds a fixed momentum kick regardless of incoming
## speed, so a slow ball still leaves fast. We layer BOTH: the solid body's PhysicsMaterial gives a
## clean bounce, and the script adds the impulse on top (the active part).
##
## KICK_IMPULSE_SPEED: the outgoing speed floor the kick targets, in world units/s. After a kick the
## ball leaves at AT LEAST this speed along the kick direction. Chosen below LAUNCH_SPEED_MAX (90)
## so
## a kick is lively but not a full plunge, and well inside the CCD-safe envelope the stress tests
## cover.
const KICK_IMPULSE_SPEED: float = 55.0
## KICK_MIN_OUTGOING_SPEED: a hard floor on the post-kick speed (the "minimum outgoing speed" the
## design mandates). The physics-programmer guarantees the ball leaves at >= this along the kick
## direction even if the incoming speed partly cancels the impulse. Tests assert against this.
const KICK_MIN_OUTGOING_SPEED: float = 40.0
## KICK_MAX_OUTGOING_SPEED: the CCD-SAFE CAP. The post-kick speed is clamped to this so a stacked
## kick (ball already fast, then kicked) can never exceed the speed the no-tunneling stress tests
## prove safe. The stress tests fire at >= 2x LAUNCH_SPEED_MAX (180); this cap (well under that)
## keeps
## every kicked ball strictly inside the proven-safe band. The physics-programmer owns this
## guarantee.
const KICK_MAX_OUTGOING_SPEED: float = 120.0
## Per-element re-trigger cooldown (seconds). Same family as the target RETRIGGER_COOLDOWN_S
## (BUG-007):
## after a kick + score, the element is dead for this long so a ball resting/jittering against it is
## pushed off ONCE, not strobed every physics frame (no machine-gun farming). The kick AND the score
## are both gated by this (unlike the target, where only the score is gated): an active element that
## re-kicked every frame would launch a resting ball at escape velocity.
const KICK_COOLDOWN_S: float = 0.25

## ---- POP BUMPERS (the "bell thingys") ----------------------------------------------------------
## 2-3 round active bumpers clustered in the UPPER-MIDDLE field (above the flippers, below the arch)
## so a ball entering the cluster bounces between them a few times. Each scores on its kick. The
## kick
## direction is RADIALLY OUTWARD from the bumper center along the ball's contact normal (computed at
## runtime by pop_bumper.gd from the ball position; no fixed direction constant needed).
##
## POP_BUMPER_RADIUS: the solid round post radius the ball bounces off (like the standup
## POST_RADIUS).
## RESIZE (SLICE "Table reshape"): 1.6 -> 2.0. Developer feedback "slots too small". A bigger bumper
## reads clearly as a target on the wider field and is easier to aim at, while staying clear of the
## side walls (clearance HALF_WIDTH - RADIUS = 14.0 vs the +/-6.0 bumper X) and below the arch.
const POP_BUMPER_RADIUS: float = 2.0
## POP_BUMPER_HEIGHT: stands as tall as the perimeter so a ball cannot ride up and over it.
const POP_BUMPER_HEIGHT: float = WALL_HEIGHT
## POP_BUMPER_SCORE: flat points per kick (placeholder, no multipliers - DESIGN scope).
const POP_BUMPER_SCORE: int = 100
## Cluster centers (local playfield coords, Y resolved on the surface by table.gd). Three bumpers in
## a triangle in the upper-middle: two lower spread across the width, one higher at center. Z is
## up-table (negative). Chosen ABOVE the standup bank and BELOW the arch start so the cluster is the
## "something worth shooting for" up top. Validated reachable by table_viz (a flipped ball can feed
## it)
## and clear of walls/arch (radius + clearance inside +/-HALF_WIDTH and above the arch base).
## WIDEN + RESPACE (SLICE "Table reshape"): the two lower bumpers spread from +/-4.5 to +/-6.0 to
## use the wider field (developer feedback "not spaced well"); the apex bumper stays centered. Z
## unchanged (the widen does not change HALF_LENGTH). Clearance to the side wall is
## HALF_WIDTH - POP_BUMPER_RADIUS = 16 - 2 = 14, far outside +/-6, so the bigger bumpers do not foul
## a wall (asserted by test_shot_geometry + table_viz). Still up-table of the flippers and below the
## arch base, so a flipped ball can feed the cluster.
const POP_BUMPER_POSITIONS: Array[Vector3] = [
	Vector3(-6.0, 0.0, -13.0),
	Vector3(6.0, 0.0, -13.0),
	Vector3(0.0, 0.0, -16.5),
]

## ---- SLINGSHOTS (active kickers above each flipper) --------------------------------------------
## One angled active kicker above each flipper, on the OUTER side, so a ball falling down that side
## is
## kicked UP-table and toward CENTER (back into play), NEVER down toward the drain. Two total.
## Unlike
## the pop bumper (radial outward), a slingshot has a FIXED kick direction (its face normal) so it
## always returns the ball into play regardless of the exact contact point.
##
## SLINGSHOT positions: just up-table of and outboard of each flipper pivot, inside the side wall.
## The left sling sits left-of-center; the right is its mirror. Y resolved on the surface by
## table.gd.
## WIDEN: slings move from +/-8.5 to +/-10.5 to stay just OUTBOARD of the widened flipper pivots
## (+/-7.2) and inside the side walls (+/-16), so a ball falling down the wider side channel grazes
## the sling and is kicked back into play. Z unchanged (off the unchanged flipper pivot row).
const SLINGSHOT_LEFT_POS: Vector3 = Vector3(-10.5, 0.0, FLIPPER_PIVOT_Z - 7.0)
const SLINGSHOT_RIGHT_POS: Vector3 = Vector3(10.5, 0.0, FLIPPER_PIVOT_Z - 7.0)
## The slingshot is a short angled wall (a flat kicker face). These are its box dimensions (local,
## before the per-side angle is applied). Long axis is X; it stands WALL_HEIGHT tall.
const SLINGSHOT_LENGTH: float = 7.0
const SLINGSHOT_THICKNESS: float = 0.8
const SLINGSHOT_HEIGHT: float = WALL_HEIGHT
## Kick direction per side, as a UNIT vector in playfield-local XZ (Y = 0, on the surface plane).
## LEFT sling kicks toward +X (right, toward center) and -Z (up-table): into play, away from the
## drain.
## RIGHT sling is the mirror: -X (toward center) and -Z (up-table). Both have a POSITIVE up-table
## (-Z)
## component and a toward-center X component, which is exactly what the behavioral test asserts.
## (These are stored as the kick direction the body imparts; the visual angle of the face mirrors
## it.)
const SLINGSHOT_LEFT_KICK_DIR: Vector3 = Vector3(0.6, 0.0, -0.8)
const SLINGSHOT_RIGHT_KICK_DIR: Vector3 = Vector3(-0.6, 0.0, -0.8)
## SLINGSHOT_SCORE: flat points per kick (placeholder).
const SLINGSHOT_SCORE: int = 50

## ---- STANDUP TARGET BANK -----------------------------------------------------------------------
## A small bank of standup targets on the mid-field where a deliberate flip can REACH it (validated
## by
## table_viz against the flipper-tip sweep). This REUSES the existing physical target body
## (target.gd)
## re-homed into a readable bank, per DESIGN (not a new target class). These REPLACE the old
## scattered
## TARGET_POSITIONS in table.gd: three posts in a row across the mid-field, makeable from the
## flippers.
##
## WHY here (z = -7): the existing flipper-tip sweep (validated in table_viz) reaches roughly this
## far
## up-table from the flipper at full swing, so a timed flip can hit the bank - "a shot worth
## making".
## They are spread across the center so a flip from either flipper can reach the bank.
## WIDEN + RESPACE (SLICE "Table reshape"): the bank spreads from +/-3.0 to +/-4.5 across the wider
## mid-field so the three targets read as a spaced bank, not a tight clump (developer "not spaced
## well"), while every target stays inside the makeable window (between the flipper-tip reach and
## arch base) - asserted by test_shot_geometry + table_viz. Z unchanged (the widen does not move the
## makeable window in Z). The individual target POST size is raised in scripts/target.gd (gameplay).
const STANDUP_BANK_POSITIONS: Array[Vector3] = [
	Vector3(-4.5, 0.0, -7.0),
	Vector3(0.0, 0.0, -7.5),
	Vector3(4.5, 0.0, -7.0),
]

## ---- INLANE / OUTLANE GUIDES -------------------------------------------------------------------
## Minimal physical guide walls down BOTH sides that funnel a ball past the flippers. Per side: an
## OUTLANE (outer channel, feeds the drain = risk) and an INLANE (inner channel, feeds back toward
## the
## flipper = save), separated by a short divider post. NO rollover scoring, lights, or ball-save
## logic
## (DESIGN cut list) - these are unlit PHYSICAL guide walls only. Built as static geometry in
## table_geometry.gd from these constants.
##
## The guide divider is a short wall between the side wall and the flipper, splitting the side
## channel
## into an outer (outlane) and inner (inlane) lane. LANE_GUIDE_DIVIDER_X is the X of the divider on
## the
## LEFT side (mirror for the right); it sits between the side wall (-HALF_WIDTH) and the flipper
## pivot.
## WIDEN: kept as HALF_WIDTH - 3.0 (so the divider auto-follows to x=13.0 on the wider table). WHY
## this form survives the widen: it holds the OUTLANE (outer channel, divider..side wall) at a
## constant ~3.0-unit width - the classic narrow outlane that reads as drain-risk - while the INLANE
## (divider..flipper pivot at +/-7.2) widens to ~5.8 with the table, the save lane that funnels the
## ball back toward the flipper. Both gutters are built symmetrically (table_geometry._build_lane_
## guides, mirrored), so the widen gives BOTH sides a proper outlane+inlane (item #4: gutters both
## sides). Verified by test_furniture_layout + table_viz feed-path plot.
const LANE_GUIDE_DIVIDER_X: float = HALF_WIDTH - 3.0
## RIGHT-side guide divider X (SLICE "Table reshape + playtest fixes", 2026-06-19, launch-lane fix;
## comment corrected for the SLICE "Playtest fixes 2" lane resize, QA BUG-029, 2026-06-20).
## WHY THIS IS ASYMMETRIC (not +LANE_GUIDE_DIVIDER_X like the left): the LAUNCH LANE occupies the
## RIGHT edge (x in [LANE_INNER_X, HALF_WIDTH]). A symmetric guide at +13.0 would land INSIDE the
## launch lane, across the ball's spawn (BALL_START.x = 15.0) and its up-lane launch path, wedging
## the freshly-armed ball so it could not launch (the producer's "no kick on the first stroke"). The
## launch lane already has its own inner divider (LANE_INNER_X) and the right wall; it needs NO
## extra wall down its middle. The RIGHT inlane/outlane guide belongs INBOARD of the lane, in the
## open field between the right flipper pivot (FLIPPER_PIVOT_SPREAD = 7.2) and the right slingshot
## (SLINGSHOT_RIGHT_POS.x = 10.5): 9.0 sits cleanly between them, splitting that channel into an
## INLANE (7.2..9.0, feeds back toward the flipper = save) and an OUTLANE (9.0..the slingshot, the
## outer drain-risk channel), mirroring the LEFT guide's job on the field side of the lane.
##
## QA BUG-029 (2026-06-20) corrected the STALE part of the prior comment: it claimed the lane
## divider was at 10.5, but the "Playtest fixes 2" lane resize moved LANE_INNER_X to 14.0. The
## divider stays 9.0 (still the correct inlane/outlane split inboard of the slingshot) and stays
## clear of the new x=15.0 launch path. The widened field band between the slingshot (10.5) and the
## lane divider (14.0) is the right OUTLANE proper: a ball down it drains off the open bottom
## (caught and SPENT by the OOB failsafe, OOB_DRAIN_Y - correct outlane "drain = risk", DESIGN "A
## DRAIN YOU EARN, EITHER SIDE"), NOT a soft-lock. The transient-dip false-promotion that band could
## feed is closed
## independently by the BUG-031 reached-play-line hardening above (the line is now up-table of the
## slingshot row, so a side-draining ball cannot falsely count as "in play"). The LEFT guide is
## unchanged (no launch lane on the left, so its symmetric placement holds).
const LANE_GUIDE_RIGHT_DIVIDER_X: float = 9.0
## The divider runs from just above the flipper pivot row down toward the drain, length below.
## QA BUG-024 FIX: the offset was 2.0, putting LANE_GUIDE_TOP_Z at 18.0. The slingshot KickerBody is
## an angled box (SLINGSHOT_LENGTH x SLINGSHOT_THICKNESS, yawed by atan2(0.6,0.8) = 36.87 deg) whose
## OUTER (toward the side wall) corner reaches down-table to z = 18.32, 0.32 units PAST the old
## guide top. The two StaticBody3D bodies then shared the band z [18.0, 18.32] in the outlane ball
## path. Two static bodies do not collide with each other, but the OVERLAPPING surfaces form a
## concave seam: a ball (radius 0.6 > the 0.14/0.32 overlap) touching both at once gives the solver
## two conflicting contact normals, which can spike velocity or briefly clip (CCD does NOT guard a
## static-body seam). FIX: raise LANE_GUIDE_TOP_Z above the sling outer corner by at least one
## BALL_RADIUS so guide and sling never share volume. offset 1.0 -> top z = 19.0, clearing the sling
## corner (18.32) by 0.68 (> BALL_RADIUS 0.6). This does NOT change shot geometry (the divider just
## starts a unit higher up-table); test_furniture_layout asserts the static-body clearance.
const LANE_GUIDE_TOP_Z: float = FLIPPER_PIVOT_Z - 1.0
const LANE_GUIDE_BOTTOM_Z: float = HALF_LENGTH - 2.0
const LANE_GUIDE_THICKNESS: float = WALL_THICKNESS
const LANE_GUIDE_HEIGHT: float = WALL_HEIGHT

## ---- HELPERS -----------------------------------------------------------------------------------

## Direction "up the table" (toward the arch) in the playfield node's LOCAL space.
## The plunger launches the ball along this axis.
func up_table_local() -> Vector3:
	return Vector3(0.0, 0.0, -1.0)

## The full gravity vector in WORLD space (straight down). The tilt is applied by ROTATING the
## playfield node, not by tilting gravity, so callers that need world-down gravity use this.
func gravity_vector_world() -> Vector3:
	return Vector3(0.0, -GRAVITY, 0.0)
