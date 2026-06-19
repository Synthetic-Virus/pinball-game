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
const HALF_WIDTH: float = 12.0      ## => 24 units wide.
const HALF_LENGTH: float = 25.0     ## => 50 units long (tens of units, per the brief).
const WALL_HEIGHT: float = 2.4      ## How tall the perimeter/arch walls stand off the surface.
const WALL_THICKNESS: float = 0.8

## Launch lane up the RIGHT side. The lane is a narrow channel between the right outer wall and an
## inner divider; the plunger sits at its bottom and shoots the ball up into the arch.
const LANE_INNER_X: float = 8.0     ## X of the inner divider wall (lane lives to its right).
const LANE_WIDTH: float = HALF_WIDTH - LANE_INNER_X  ## Right wall at +HALF_WIDTH minus divider.

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
## REST_ANGLE -0.55 the x-reach is ~5.97, so the spread must exceed that. 7.0 leaves a ~2.1-unit
## drain mouth (a bit over one ball diameter) - a missed flip can drain, a cradle holds. The old 5.0
## made the tips CROSS the center (gap -1.9): that was the past inverted-V overlap bug (commit 6c64a7b
## territory), now guarded by the test. Pivots at +/-7 stay well inside the +/-12 side walls.
const FLIPPER_PIVOT_SPREAD: float = 7.0
const FLIPPER_PIVOT_Z: float = HALF_LENGTH - 5.0  ## How far up from the drain the pivots sit.
## Resting and energized angles (radians) of the flipper about its pivot, measured on the playfield
## plane. Left flipper points up-right at rest and swings up; right is mirrored. Physics-programmer
## may refine these as the hinge limits, but the geometry above is the contract.
const FLIPPER_REST_ANGLE: float = -0.55
const FLIPPER_UP_ANGLE: float = 0.15

## ---- DRAIN -------------------------------------------------------------------------------------
## Open center drain: a trigger volume below the flippers. A ball entering it is lost.
## DRAIN_Z sits BELOW the flipper pivot row (FLIPPER_PIVOT_Z = 20) but INSIDE the playfield bottom
## edge (HALF_LENGTH = 25), so a ball that gets past the flippers falls into the drain BEFORE it can
## reach the open bottom edge. table_geometry.gd deliberately leaves the bottom perimeter OPEN (no
## bottom wall) so nothing blocks the drain. Earlier this was HALF_LENGTH + 2 = 27, which placed the
## trigger 2 units OUTSIDE the playfield - if a naive bottom wall were ever built it would block the
## drain (QA BUG-004). Keeping it inside the field removes that dependency.
const DRAIN_Z: float = HALF_LENGTH - 1.0
const DRAIN_WIDTH: float = HALF_WIDTH * 2.0
const DRAIN_DEPTH: float = 6.0

## Out-of-bounds failsafe (defense in depth, QA BUG-006): if the ball ever escapes the playfield
## sideways or pops over a wall, it would fall forever and soft-lock the game in BALL_IN_PLAY. A large
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
const BALL_START: Vector3 = Vector3(10.0, BALL_RADIUS + 0.2, HALF_LENGTH - 2.0)

## Resulting ball speed range we WANT a launch to produce, mapped from the power meter (0..1). Tuned
## at this scale/gravity so a min launch dribbles and a max launch clears the arch. This is the FEEL
## target the physical plunger strike is calibrated against; the HUD/tests still read these bounds.
const LAUNCH_SPEED_MIN: float = 30.0
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
const PLUNGER_STROKE_SPEED_MIN: float = 30.0  ## Power 0.0: a gentle dribble out of the lane.
const PLUNGER_STROKE_SPEED_MAX: float = 78.0  ## Power 1.0: a hard strike that clears the arch.

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
const PLUNGER_FACE_WIDTH: float = LANE_WIDTH - 0.6  ## Fits inside the lane with clearance.
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

## ---- HELPERS -----------------------------------------------------------------------------------

## Direction "up the table" (toward the arch) in the playfield node's LOCAL space.
## The plunger launches the ball along this axis.
func up_table_local() -> Vector3:
	return Vector3(0.0, 0.0, -1.0)

## The full gravity vector in WORLD space (straight down). The tilt is applied by ROTATING the
## playfield node, not by tilting gravity, so callers that need world-down gravity use this.
func gravity_vector_world() -> Vector3:
	return Vector3(0.0, -GRAVITY, 0.0)
