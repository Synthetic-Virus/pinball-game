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
const FLIPPER_PIVOT_SPREAD: float = 5.0  ## Half-distance between the two pivots (inverted-V gap).
const FLIPPER_PIVOT_Z: float = HALF_LENGTH - 5.0  ## How far up from the drain the pivots sit.
## Resting and energized angles (radians) of the flipper about its pivot, measured on the playfield
## plane. Left flipper points up-right at rest and swings up; right is mirrored. Physics-programmer
## may refine these as the hinge limits, but the geometry above is the contract.
const FLIPPER_REST_ANGLE: float = -0.55
const FLIPPER_UP_ANGLE: float = 0.15

## ---- DRAIN -------------------------------------------------------------------------------------
## Open center drain: a trigger volume below/between the flippers. A ball entering it is lost.
const DRAIN_Z: float = HALF_LENGTH + 2.0  ## Just past the flippers, off the bottom edge.
const DRAIN_WIDTH: float = HALF_WIDTH * 2.0
const DRAIN_DEPTH: float = 6.0

## ---- LAUNCH / PLUNGER --------------------------------------------------------------------------
## Ball rest position at the bottom of the launch lane (local playfield coords).
const BALL_START: Vector3 = Vector3(10.0, BALL_RADIUS + 0.2, HALF_LENGTH - 2.0)
## Launch impulse speed range mapped from the power meter (0..1). Tuned at this scale/gravity so a
## min launch dribbles and a max launch clears the arch. Physics/gameplay may retune within reason.
const LAUNCH_SPEED_MIN: float = 30.0
const LAUNCH_SPEED_MAX: float = 90.0

## ---- HELPERS -----------------------------------------------------------------------------------

## Direction "up the table" (toward the arch) in the playfield node's LOCAL space.
## The plunger launches the ball along this axis.
func up_table_local() -> Vector3:
	return Vector3(0.0, 0.0, -1.0)

## The full gravity vector in WORLD space (straight down). The tilt is applied by ROTATING the
## playfield node, not by tilting gravity, so callers that need world-down gravity use this.
func gravity_vector_world() -> Vector3:
	return Vector3(0.0, -GRAVITY, 0.0)
