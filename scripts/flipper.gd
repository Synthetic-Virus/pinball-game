extends Node3D
## Flipper - ONE flipper on the KINEMATIC AnimatableBody3D drive (scripted, input-duration-sensitive
## angle sweep). This is the rebuild that fixes the dead resting-face rebound.
##
## OWNERSHIP: physics-programmer owns the drive (the swing integration, the sync_to_physics seam,
## the
## tuning that makes a full swing out-throw a tap and the resting face rebound live). The lead owns
## the
## kinematic-layer seam + the constants audit. Geometry comes from TableConfig via the overridable
## getters so mini_flipper.gd can be a thin subclass.
##
## WHY A KINEMATIC ANIMATABLEBODY, NOT A FORCE-DRIVEN RIGIDBODY (SETTLED BY EXPERIMENT 2026-07, do
## NOT
## re-litigate): the old RigidBody3D + HingeJoint3D bat had a dead resting-face rebound (~5% of a
## 50 u/s ball). Root cause is a MASS-RATIO problem, NOT shape/friction/restitution:
##   - With bat mass 0.4 == ball mass 0.4, a ball striking the RESTING face shoves the bat aside and
##     the bat ABSORBS the hit. Measured: a FROZEN ideal target with the identical rubber material
##     rebounds 84.8%; a FREE 0.4-mass body returns 0%; the hinge adds almost nothing back.
## - Shape (box vs real hull) and friction (0 vs 0.7) were RULED OUT - identical rebound either way.
##   - Restitution in this Jolt setup combines ADDITIVELY, clamped to 1.0 (0.15 ball + 0.70 bat =
##     0.846 measured).
## THE FIX is to make the bat effectively INFINITE mass so it never recoils. An AnimatableBody3D is
## a
## KINEMATIC body: the solver treats it as immovable, so a ball striking the RESTING face rebounds
## at
## the full material restitution (measured 84.8%, the target the rubber test asserts). The SWING
## momentum comes from sync_to_physics: when we move the body by setting its transform each physics
## frame, Godot reports the motion-derived velocity to the solver, so the moving face imparts real
## momentum to the ball (measured 29.96 u/s to a RESTING ball at the 38.21 rad/s peak sweep).
## Because
## the drive is a SCRIPTED angle that ACCELERATES over the hold, a 1-frame tap reaches the ball
## slower
## than a full-held swing - the >= 1.5x differentiation is a real, measured behavior, not a canned
## sweep (this is why the old "no AnimatableBody" ban is superseded by the hard feel test, not
## broken).
##
## NO TUNNELING: the bat has NO continuous_cd (an AnimatableBody3D has no such property). Safety
## rests
## on the BALL's unconditional continuous_cd (ball.gd) plus the post-contact 120 u/s speed clamp in
## ball.gd. Measured 0/30 tunneling at 232 u/s (2x LAUNCH_SPEED_MAX) ball vs a full-speed sweep.
##
## STRUCTURE (built in code from TableConfig so it stays in scale and needs no scene authoring):
##   Flipper (this Node3D, sits AT the pivot - table.gd places it)
##     +-- FlipperBody (AnimatableBody3D, KINEMATIC_OBSTACLES layer, sync_to_physics on)
##          +-- CollisionShape3D  (the tapered convex-hull bat)
##          +-- FlipperMesh       (procedural 2-tone black-body / white-rubber-top bat - the visual)
##   The swing angle is integrated + applied to FlipperBody every physics frame in _physics_process.
##
## COORDINATE CONVENTION (local to this Flipper node, which lives on the tilted Playfield):
##   The bat lies FLAT on the surface and swings about the surface normal (this node's local +Y).
##   The bat extends from the pivot along the rotating bat's local +X. Angle 0 = bat pointing along
##   the Flipper's local +X. The rest/up angles come from TableConfig; "mirrored" negates them and
##   the swing direction so the right flipper is a true mirror of the left.
##
## INPUT: reads the action assigned via configure(). Flip MUST register on the SAME physics frame as
## the press (DESIGN.md "Input feel: no input lag"); poll the action in _physics_process, do not
## wait
## for _input event routing.
##
## STABLE CONTRACT (table.gd / tests depend on these; keep the signatures BYTE-FOR-BYTE):
##   func configure(action_name: String, mirrored: bool) -> void
##       # action_name in {"left_flipper","right_flipper"}; mirrored = true for the right flipper.
##   func is_energized() -> bool                 # true while the flip action is held.
##   func force_energized(on: bool) -> void      # test hook: force energized/released.
##   func clear_force_energized() -> void        # test hook: return control to the input action.
##   func tip_speed() -> float                   # linear speed of the flipper tip (momentum test).
##   func editor_move(local_pos: Vector3) -> void  # layout editor: move the whole flipper.
##   func editor_pick_radius() -> float          # layout editor: click radius (the bat length).

## --- SWING DRIVE (physics-programmer owns + TUNES these) -----------------------------------------
## The bat is a KINEMATIC AnimatableBody3D; we integrate a swing angle in the script each physics
## frame and SET the body transform from it, so sync_to_physics imparts the motion to the ball. The
## whole feel lives in these numbers. PHYSICS-PROGRAMMER tunes them to the DESIGN feel gates: a
## ~50-80 ms snap, a full swing out-throwing a tap by >= 1.5x, a firm sag-free cradle, no tunneling.
##
## PHYSICS-PROGRAMMER VERIFICATION (2026-07). The laptop is a thin client with NO local Godot, so
## the on-device GUT suite / the browser build is the ground-truth oracle; the values below are
## validated ANALYTICALLY against the exact constants in test_flipper_momentum.gd, and each sits at
## a defensible operating point (every one is a feel trade-off, so none is changed on a guess):
##   - SWEEP = FLIPPER_UP_ANGLE - FLIPPER_REST_ANGLE = 0.50 - (-0.30) = 0.80 rad, at 240 Hz.
##   - SNAP: the bat covers the 0.80 rad rest->up sweep in ~40 ms, well inside the 80 ms snap gate
##     (which only needs tip_speed() > 0 in that window - so the snap has comfortable margin).
##   - DIFFERENTIATION: a 1-frame TAP reaches only ~4.7 rad/s; the return spring then hauls it back
##     so the tip peaks near -0.14 rad, FAR short of the momentum test's ball seat at
##     lerp(rest, up, 0.85) = 0.38 rad. So a tap never reaches the seated ball (imparts ~0) while a
##     FULL swing arrives at ~36 rad/s: the full/tap speed ratio clears the 1.5x floor by a wide,
##     non-flaky margin. DRIVE_ANG_ACCEL is the knob that governs THIS gate (raise it far enough and
##     even a tap reaches the ball, collapsing the margin); MAX_SWING_SPEED does not (see below).
##   - CRADLE + RETURN: firm and ring-free by construction (see ANG_DAMPING / RETURN_SPRING below).
##   - SAFETY: the bat carries no CCD (AnimatableBody has none); no-tunnel rests on the BALL's
##     unconditional continuous_cd + ball.gd's post-contact clamp. Cross-check: the fastest bat tip
##     is ~36 * 3.8 = ~140 u/s = ~0.58 u/step at 240 Hz, under both the ball diameter (1.2) and the
##     bat width (0.9), so the non-CCD bat cannot sweep THROUGH a resting ball in one step (overlap
##     persists for several steps, and the ball's own CCD catches the fast-ball direction).

## Peak angular speed the driven swing may reach (rad/s), about the surface normal. This is a SAFETY
## CEILING, NOT the flip-strength knob. WHY 38.21: it is the measured peak of the real full-swing
## sweep (see the class header). With DRIVE_ANG_ACCEL below, the natural swing peaks at ~36 rad/s
## and reaches the up-stop just BEFORE this value, so the ceiling does not bind in normal play - it
## only catches a runaway (a mis-tuned accel or an accumulation) so the imparted momentum stays
## inside the CCD-safe envelope the stress tests prove (tip = 38.21 * 3.8 = ~145 u/s = ~0.60
## u/step). The up-stop clamp bounds the ANGLE; this bounds the SPEED. Retune flip STRENGTH via the
## sweep angle and where the ball is caught, never by raising this ceiling.
const MAX_SWING_SPEED: float = 38.21
## Angular acceleration (rad/s^2) applied toward the up-stop while the action is held. This is the
## INPUT-DURATION knob: a moderate accel means a 1-frame tap only reaches a small angular velocity
## before release (a slow, weak contact), while a full hold ramps all the way to MAX_SWING_SPEED (a
## fast contact). Too HIGH and even a tap reaches full speed (the >= 1.5x differentiation collapses
## -
## the exact "canned feel" the old AnimatableBody ban feared). Too LOW and a full swing misses the
## 50-80 ms snap window. PHYSICS-TUNE so BOTH feel gates pass: tap-vs-full-swing >= 1.5x AND the
## full
## swing snaps in 50-80 ms.
const DRIVE_ANG_ACCEL: float = 1200.0
## Return-spring stiffness (rad/s^2 per rad of displacement from rest) applied while the action is
## NOT
## held, hauling the bat back to the rest angle. Firm enough to return crisply, soft enough that the
## return itself does not fling the ball across the table. PHYSICS-TUNE.
const RETURN_SPRING_STIFFNESS: float = 900.0
## Angular damping (per unit of angular velocity) applied in BOTH states. The shock absorber: keeps
## the bat from oscillating at the stops and holds a firm, sag-free CRADLE (the ball's weight cannot
## push a held bat down because the bat is kinematic - the cradle is inherently rock-steady, this
## only
## settles the swing). Too high kills the snap; too low reads as floppy. PHYSICS-TUNE.
const ANG_DAMPING: float = 14.0

## Unit swing axis in this node's LOCAL space. The bat rotates about the surface normal (+Y).
## Declared
## with the other constants so gdlint's class-definitions-order rule is satisfied.
const _SWING_AXIS_LOCAL: Vector3 = Vector3(0.0, 1.0, 0.0)

## Bat collision/material tuning. High friction lets the bat grip and sling the ball rather than
## letting it skid.
const BAT_FRICTION: float = 0.7

## --- VISIBLE BAT MESH (procedural, SLICE "Kenney 3D asset integration", 2026-07) ----------------
## The VISIBLE bat is the PROCEDURAL 2-tone ArrayMesh (FlipperMesh) built below from the SAME
## tapered stadium outline as the collider - black body + white rubber top. The flipper_bat.glb was
## RETIRED this slice: the low-poly procedural bat is the primary (and only) visual, so there is no
## asset load to fail and no fallback branch to maintain. The collider, drive, material, and bounce
## are untouched - this only changed WHICH mesh renders (the procedural one, which the collider and
## the keep-green rubber-top / shape tests already agree with by name). See _build_bat_mesh.

## --- BAT SHAPE (tapered rounded "stadium" - UNCHANGED by the drive rebuild) ----------------------
## The bat is a TAPERED ROUNDED "stadium" form: FAT at the pivot, narrowing to a smaller ROUNDED tip
## (DESIGN "the flipper is a flipper shape"). BOTH the visible mesh AND the collision shape are the
## SAME outline, so "where on the bat the ball hits matters". The drive rebuild does NOT touch this
## geometry (the shape was proven no-tunnel + rubber-rebound already); only the BODY TYPE and the
## DRIVE
## changed.
##
## WHY A CONVEX HULL, NOT A CAPSULE: a CapsuleShape3D has a CONSTANT radius (no taper) and rounded
## END
## CAPS that bulge past the pivot, so it cannot be both fat-at-pivot and thin-at-tip. We build a
## ConvexPolygonShape3D hull whose footprint is a TAPERED rounded stadium on the surface plane: full
## FLIPPER_WIDTH from the pivot through the mid face, then narrowing to TIP_WIDTH_FRACTION at the
## rounded tip. The matching mesh is built from the SAME outline points (extruded to FLIPPER_HEIGHT)
## so
## the collider and the mesh agree exactly.
##
## WHY FULL WIDTH THROUGH THE MID FACE: the rubber-rebound gate (test_flipper_rubber.gd) fires the
## ball
## HEAD-ON at the MID-BAT point and stands it off by FLIPPER_WIDTH*0.5 + BALL_RADIUS, so the mid
## face
## must be ~FLIPPER_WIDTH wide and present a flat-ish face there. Keeping full width across the
## inner
## ~60% of the bat (TAPER_START_FRACTION) preserves that head-on contact; the taper lives only over
## the
## outer tip half. The lever arm and tip_speed() are unchanged (pivot-to-tip distance =
## FLIPPER_LENGTH).
## Fraction of FLIPPER_WIDTH the rounded TIP narrows to (the bat is thinner at the tip than base).
const TIP_WIDTH_FRACTION: float = 0.45
## Fraction of FLIPPER_LENGTH from the pivot at which the taper BEGINS. Inboard the bat keeps full
## FLIPPER_WIDTH (so the mid-face head-on contact stays flat); outboard of this it narrows.
const TAPER_START_FRACTION: float = 0.55
## How many segments approximate each rounded end of the stadium outline. More = smoother, but a
## hull
## needs few points; 4 per end gives a clean rounded read without bloating the convex hull.
const ROUND_SEGMENTS: int = 4

## --- 2-TONE GRAY-BOX MATERIAL (no art dependency) -----------------------------------------------
## BLACK body + WHITE rubber TOP surface (a 2-tone gray-box look). The white top is a VISUAL cue for
## the rubber surface; the rubber FEEL stays BAT_BOUNCE 0.70 (the PhysicsMaterial, unchanged).
const BODY_COLOR: Color = Color(0.05, 0.05, 0.05)  ## Near-black bat body.
const RUBBER_TOP_COLOR: Color = Color(0.92, 0.92, 0.92)  ## White rubber top cap.
## Bat restitution: the RUBBER SLEEVE. WHY 0.70 KEPT from the old drive: restitution combines
## ADDITIVELY in this Jolt setup, clamped to 1.0. Against the steel ball (BALL_BOUNCE 0.15) the
## effective contact bounce is 0.15 + 0.70 = 0.85 (measured 0.846 = 84.8% rebound). The old
## RigidBody bat threw that away by RECOILING (the mass-ratio absorption); the new KINEMATIC bat
## does
## not recoil, so the ball actually gets the full 84.8% - clearly above the 0.35 rubber floor and
## under the 1.15 trampoline ceiling (0.846 < 1.0, so energy is never manufactured). This value is
## now
## delivered by the body TYPE (kinematic = no recoil), not by a mass fix.
const BAT_BOUNCE: float = 0.70

## TEST HOOK (DESIGN.md feel gate is validated headlessly): GUT cannot synthesize persistent Input
## events across physics frames, so a test cannot hold a real flipper key. This override lets a test
## force the flipper energized/de-energized for a span of physics frames and measure the resulting
## tip_speed()/ball speed. It is INERT in normal play: production code never sets it, so the action
## poll in _physics_process is the only path the player ever drives. See test_flipper_momentum.gd.
##   -1 = no override (read the input action, the normal path)
##    0 = forced released (return spring)
##    1 = forced energized (solenoid drive)
var _force_energized: int = -1

## Internal handles, built in _ready().
var _action_name: String = ""
var _mirrored: bool = false
var _body: AnimatableBody3D
## The bat's collision shape and mesh. Kept as handles because handedness re-seats their geometry:
## the
## bat must extend FROM the pivot TOWARD the table center, which is +X for the left flipper and -X
## for
## the (mirrored) right flipper. See _apply_handedness (QA BUG-001 fix).
var _shape: CollisionShape3D
var _mesh_instance: MeshInstance3D
## The signed rest/up angles for THIS flipper (mirrored applied). The script clamps the swing angle
## to
## the [min, max] of these each frame (the hard stops the old hinge limit used to enforce).
var _rest_angle: float = 0.0
var _up_angle: float = 0.0
## The live swing state, integrated in _physics_process and applied to the kinematic body. _angle is
## the current swing angle (rad); _swing_speed is its angular velocity (rad/s), which tip_speed()
## reads.
var _angle: float = 0.0
var _swing_speed: float = 0.0


func _ready() -> void:
	_build_flipper()


## Bind this flipper to an input action and set handedness. Called by table.gd. STABLE SIGNATURE.
## table.gd may call this before or after _ready() depending on instancing order, so building is
## idempotent and re-applies handedness if the body already exists.
func configure(action_name: String, mirrored: bool) -> void:
	_action_name = action_name
	_mirrored = mirrored
	if _body == null:
		_build_flipper()
	else:
		_apply_handedness()


## Move the flipper to a new playfield-local pivot. STABLE SIGNATURE. The bat is an AnimatableBody3D
## whose LOCAL transform is a pure rotation about the pivot (origin ZERO), so moving THIS node moves
## the whole flipper (node + bat) together - unlike the old RigidBody, which the physics server left
## behind. We re-seat the body's local rotation defensively so the bat lands at its current angle.
## Used by the layout editor (a plain position set moves the whole kinematic flipper cleanly).
func editor_move(local_pos: Vector3) -> void:
	position = local_pos
	if _body != null:
		_body.transform = Transform3D(Basis(_SWING_AXIS_LOCAL, _angle), Vector3.ZERO)


## Editor click radius. The flipper node sits at the PIVOT, but the BAT extends a full
## flipper-length
## away from it, so a pivot-only pick (SELECT_RADIUS) makes the flipper feel unselectable when you
## click the bat. Returning the bat length lets a click anywhere along the bat select the flipper.
## STABLE SIGNATURE (the layout editor calls this if present). Mini flipper inherits it (smaller
## len).
func editor_pick_radius() -> float:
	return _flipper_length()


## Build the AnimatableBody3D bat from TableConfig dimensions. Idempotent: only builds once.
func _build_flipper() -> void:
	if _body != null:
		return

	# --- The bat: a KINEMATIC AnimatableBody3D swept by the scripted angle drive.
	# ------------------
	_body = AnimatableBody3D.new()
	_body.name = "FlipperBody"
	_body.collision_layer = PhysicsLayers.KINEMATIC_OBSTACLES
	_body.collision_mask = PhysicsLayers.KINEMATIC_COLLISION_MASK
	# sync_to_physics ON is the load-bearing mechanism of the rebuild: we move the body by setting
	# its
	# transform each physics frame (in _physics_process), and Godot reports the motion-derived
	# velocity
	# to the solver so the moving face imparts real momentum to the ball (the swing throw). A
	# RESTING
	# face reports zero velocity, so a ball striking it rebounds off the pure rubber restitution -
	# the
	# 84.8% fix (see the class header WHY). This is the plunger's sync_to_physics pattern used the
	# OTHER
	# way round: the plunger deliberately turns it OFF because its launch is an explicit impulse;
	# here
	# the swing momentum IS the body motion, so we need it ON.
	_body.sync_to_physics = true

	var material := PhysicsMaterial.new()
	material.friction = BAT_FRICTION
	material.bounce = BAT_BOUNCE
	_body.physics_material_override = material

	# Collision shape + mesh: a TAPERED ROUNDED STADIUM (NOT a box). The actual hull/mesh geometry
	# is
	# built in _rebuild_bat_geometry() (called from _apply_handedness) because the taper direction
	# depends on handedness: the FAT pivot end must sit at the pivot and the THIN tip reach toward
	# CENTER, which is +X for the left flipper and -X for the mirrored right flipper. We create the
	# empty nodes here; _apply_handedness fills them with the correctly-oriented geometry.
	_shape = CollisionShape3D.new()
	_body.add_child(_shape)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "FlipperMesh"
	_mesh_instance.visible = true  ## the procedural 2-tone bat is the primary (and only) visual
	_body.add_child(_mesh_instance)

	add_child(_body)

	_apply_handedness()


## Apply rest/up angles and the mirror for handedness, rebuild the bat geometry, and seat the bat at
## the rest angle. No hinge: the swing angle is clamped to the [min, max] rest..up range each frame.
func _apply_handedness() -> void:
	# Mirror negates the angles so the right flipper is the left's mirror image about the table's
	# centerline (it swings the opposite rotational direction).
	var hand_sign := -1.0 if _mirrored else 1.0
	_rest_angle = _flipper_rest_angle() * hand_sign
	_up_angle = _flipper_up_angle() * hand_sign

	# Build the tapered bat geometry on the correct side of the pivot. The bat must reach FROM the
	# pivot (fat end) TOWARD the table center (thin tip): +X for the left flipper, -X for the
	# mirrored
	# right flipper. Without this the right bat pointed AWAY from center and could never intercept a
	# draining ball - the inverted V could not form (QA BUG-001). The taper is asymmetric (fat pivot
	# ->
	# thin tip), so a simple position offset cannot mirror it; we rebuild the outline with the X
	# sign
	# applied so the fat end stays pinned at the pivot (this node's origin) for BOTH sides.
	_rebuild_bat_geometry(hand_sign)

	# Seat the bat at the rest angle so the flipper starts at rest, not at angle 0. The kinematic
	# body
	# carries no velocity; the swing state starts still.
	_angle = _rest_angle
	_swing_speed = 0.0
	if _body != null:
		_body.transform = Transform3D(Basis(_SWING_AXIS_LOCAL, _angle), Vector3.ZERO)


## Integrate the swing angle and apply it to the kinematic bat. sync_to_physics turns the applied
## motion into the momentum the ball feels. This is the whole drive; the numbers are tuned above.
func _physics_process(delta: float) -> void:
	if _body == null:
		return

	# Drive sign points from rest toward up. For the left flipper up_angle > rest_angle (positive);
	# mirrored flips both, so the sign follows the up-stop direction for either side.
	var drive_dir: float = signf(_up_angle - _rest_angle)

	if _is_pressed():
		# SOLENOID DRIVE: accelerate the swing toward the up-stop. Because this ACCELERATES (does not
		# snap instantly to full speed), a 1-frame tap reaches only a small angular velocity before
		# release, while a full hold ramps to MAX_SWING_SPEED - the input-duration sensitivity that
		# gives the >= 1.5x tap-vs-full-swing feel.
		_swing_speed += DRIVE_ANG_ACCEL * drive_dir * delta
	else:
		# RETURN SPRING: restoring acceleration toward the rest angle (a linear spring).
		var displacement: float = _angle - _rest_angle
		_swing_speed += -RETURN_SPRING_STIFFNESS * displacement * delta

	# DAMPING (both states): the shock absorber that settles the bat and steadies the cradle.
	_swing_speed += -ANG_DAMPING * _swing_speed * delta

	# Cap the driven angular speed at the measured peak (preserving sign), so the imparted momentum
	# stays inside the measured-safe envelope even if the drive accel is tuned high.
	_swing_speed = clampf(_swing_speed, -MAX_SWING_SPEED, MAX_SWING_SPEED)

	# Integrate the angle and clamp to the hard rest..up range (the stops the old hinge limit gave).
	# When the bat hits a stop we zero only the component of velocity that would push it further past,
	# which works for BOTH handedness signs (lower/upper are absolute, not per-side).
	_angle += _swing_speed * delta
	var lower: float = minf(_rest_angle, _up_angle)
	var upper: float = maxf(_rest_angle, _up_angle)
	if _angle < lower:
		_angle = lower
		_swing_speed = maxf(_swing_speed, 0.0)
	elif _angle > upper:
		_angle = upper
		_swing_speed = minf(_swing_speed, 0.0)

	# Apply the swing angle to the kinematic body; sync_to_physics reports the motion to the solver.
	_body.transform = Transform3D(Basis(_SWING_AXIS_LOCAL, _angle), Vector3.ZERO)


## Whether the solenoid should drive this physics frame: the test override if set, else the action.
func _is_pressed() -> bool:
	if _force_energized != -1:
		return _force_energized == 1
	return _action_name != "" and Input.is_action_pressed(_action_name)


## TEST HOOK: force the flipper energized (true) or released (false) regardless of input. Inert in
## normal play (never called by production code). Callers state intent explicitly. Use
## clear_force_energized() to return control to the input action.
func force_energized(on: bool) -> void:
	_force_energized = 1 if on else 0


## TEST HOOK: stop overriding and return to reading the input action.
func clear_force_energized() -> void:
	_force_energized = -1


## True while the flip is being driven (action held, or the test override). STABLE SIGNATURE.
func is_energized() -> bool:
	return _is_pressed()


## Linear speed of the flipper tip. The momentum test reads this to confirm a full swing is faster
## than a tap. STABLE SIGNATURE. tip speed = |scripted swing angular velocity| * lever arm
## (FLIPPER_LENGTH). We read the SCRIPTED _swing_speed (the authoritative source of the swing
## motion)
## rather than the kinematic body's reported angular velocity, so the momentum gate reads the exact
## swing speed the drive commands - the same value sync_to_physics imparts to the ball.
func tip_speed() -> float:
	return absf(_swing_speed) * _flipper_length()


## --- OVERRIDABLE GEOMETRY SEAMS (SLICE "Custom low-poly asset integration", 2026-06-24) ----------
## A flipper's dimensions and rest/up angles are read through these getters so a SUBCLASS
## (scripts/mini_flipper.gd) can make a SMALLER flipper WITHOUT duplicating the drive in this file.
## The defaults return the existing TableConfig constants, so the two MAIN flippers behave
## byte-for-byte as before (these getters only relocate where the same numbers are read). The mini
## flipper is a REAL flipper: same kinematic AnimatableBody + scripted angle drive, only smaller.
func _flipper_length() -> float:
	return TableConfig.FLIPPER_LENGTH


func _flipper_width() -> float:
	return TableConfig.FLIPPER_WIDTH


func _flipper_height() -> float:
	return TableConfig.FLIPPER_HEIGHT


func _flipper_rest_angle() -> float:
	return TableConfig.FLIPPER_REST_ANGLE


func _flipper_up_angle() -> float:
	return TableConfig.FLIPPER_UP_ANGLE


## --- TAPERED BAT GEOMETRY (UNCHANGED by the drive rebuild) ---------------------------------------
## Build the bat's top-down OUTLINE on the surface plane (the X-Z footprint): a TAPERED ROUNDED
## stadium with the FAT pivot end at X=0 and the THIN rounded tip at X=FLIPPER_LENGTH. Returned as
## 2D points in (x, half_width) form along the +X long axis; the caller mirrors X for the right
## flipper and extrudes to height. The outline keeps full FLIPPER_WIDTH from the pivot through the
## mid
## face (so the rubber-rebound head-on contact at mid-bat stays flat) and narrows over the tip.
##
## Points are ordered around the perimeter (CCW) so the mesh builder can fan-triangulate the top/
## bottom caps. The convex hull builder ignores order (a hull only needs the point cloud).
func _build_bat_outline() -> PackedVector2Array:
	var fl: float = _flipper_length()
	var base_half: float = _flipper_width() * 0.5
	var tip_half: float = base_half * TIP_WIDTH_FRACTION
	var taper_x: float = fl * TAPER_START_FRACTION  ## Full width up to here, then narrow to the tip.
	var tip_x: float = fl - tip_half  ## The rounded tip cap is centered here.

	# Build the two long edges as (x, +/-half_width) pairs, full width to taper_x then narrowing to
	# tip_half at the tip cap center. We then add rounded end caps (pivot + tip) as arcs.
	var pts := PackedVector2Array()

	# Pivot (fat) rounded end cap: a half-circle of radius base_half centered at x = base_half,
	# sweeping from the +width edge around the back (x < base_half) to the -width edge (rounds
	# pivot).
	var pivot_cx: float = base_half
	for i in range(ROUND_SEGMENTS + 1):
		var t: float = float(i) / float(ROUND_SEGMENTS)
		var ang: float = PI * 0.5 + t * PI  # from +90 deg (top) around the back to +270 deg (bottom)
		pts.append(Vector2(pivot_cx + cos(ang) * base_half, sin(ang) * base_half))

	# Bottom long edge from the pivot toward the tip: full width to the taper start, then narrowing.
	pts.append(Vector2(taper_x, -base_half))
	pts.append(Vector2(tip_x, -tip_half))

	# Tip (thin) rounded end cap: a half-circle of radius tip_half centered at x = tip_x, sweeping
	# from the -width edge around the front (x > tip_x) to the +width edge.
	for i in range(ROUND_SEGMENTS + 1):
		var t: float = float(i) / float(ROUND_SEGMENTS)
		var ang: float = -PI * 0.5 + t * PI  # from -90 deg (bottom) around the front to +90 deg (top)
		pts.append(Vector2(tip_x + cos(ang) * tip_half, sin(ang) * tip_half))

	# Top long edge back from the tip to the taper start (closing the loop toward the pivot cap).
	pts.append(Vector2(tip_x, tip_half))
	pts.append(Vector2(taper_x, base_half))

	return pts


## Rebuild the collision hull and visible mesh for the given handedness sign (+1 left, -1 right).
## The outline's long axis is +X; negating every X for the mirrored right flipper flips the whole
## tapered bat to the -X side, keeping the FAT end pinned at the pivot (origin) for BOTH sides.
func _rebuild_bat_geometry(hand_sign: float) -> void:
	var outline: PackedVector2Array = _build_bat_outline()
	if hand_sign < 0.0:
		var mirrored := PackedVector2Array()
		for p in outline:
			mirrored.append(Vector2(-p.x, p.y))
		outline = mirrored

	var height: float = _flipper_height()
	if _shape != null:
		var hull := ConvexPolygonShape3D.new()
		hull.points = _extrude_outline_to_hull(outline, height)
		_shape.shape = hull
	if _mesh_instance != null:
		# Pass hand_sign so the mesh builder can keep the cap windings correct for the mirrored bat.
		# For hand_sign < 0 every outline X was negated above, which REVERSES the perimeter winding
		# order. _build_bat_mesh winds the top cap (the WHITE rubber surface, surface 1) and the
		# side
		# walls assuming the +X (left) order, so on the RIGHT bat the top cap would otherwise wind
		# the
		# OTHER way and face DOWN (-Y) - backface-culled, the right flipper renders all black. The
		# mesh
		# builder corrects the winding for the mirrored side.
		_mesh_instance.mesh = _build_bat_mesh(outline, height, hand_sign)


## Convert the 2D surface outline into the 3D point cloud for a ConvexPolygonShape3D: each outline
## point becomes two 3D points, one at +height/2 and one at -height/2 (the outline is the X-Z
## footprint, height along Y, the surface normal). The convex hull of this cloud is the solid bat.
func _extrude_outline_to_hull(outline: PackedVector2Array, height: float) -> PackedVector3Array:
	var half_h: float = height * 0.5
	var cloud := PackedVector3Array()
	for p in outline:
		cloud.append(Vector3(p.x, half_h, p.y))
		cloud.append(Vector3(p.x, -half_h, p.y))
	return cloud


## Build the visible bat mesh from the SAME outline the collider uses (so mesh and collider AGREE).
## An ArrayMesh with two surfaces: surface 0 is the black BODY (sides + bottom cap); surface 1 is
## the
## white RUBBER TOP cap (the up-facing face) - the 2-tone gray-box look.
##
## hand_sign (+1 left, -1 right): the outline was X-mirrored upstream for the right bat, which
## REVERSES
## its perimeter winding order. The cap/side windings below assume the +X (left) order, so for the
## mirrored bat we FLIP each triangle's winding (via _emit_tri's flip flag) to keep the normals
## facing
## the SAME way as the left bat (top cap up +Y, sides outward, bottom cap down -Y). Without this the
## right bat's WHITE rubber top faces DOWN and is culled, so the right flipper renders all black.
##
## TWO SEPARATE WINDING CONCERNS, both handled here:
## (A) HANDEDNESS: hand_sign < 0 reverses the perimeter, so flip_winding swaps every triangle on the
##       mirrored bat. This makes the RIGHT bat's caps/sides face the SAME way as the LEFT bat.
##   (B) ABSOLUTE ORIENTATION: the outline is wound CCW in the X-Z plane, and a CCW X-Z loop's cap
## normal (via SurfaceTool.generate_normals' (v1-v0)x(v2-v0)) points -Y, NOT +Y. So the naive fan
##       order (outline[0], i, i+1) at +half_h faces the top cap DOWN. We emit the TOP cap REVERSED
##       (outline[0], i+1, i) so its normal faces +Y (the visible up face the camera sees), and the
##       BOTTOM cap in forward order so it faces -Y. The orientation is derived from the outline's
## signed area so it self-corrects for the mirrored bat (test_flipper_rubber_top asserts the top
##       cap's average normal Y is POSITIVE on BOTH bats).
func _build_bat_mesh(outline: PackedVector2Array, height: float, hand_sign: float) -> ArrayMesh:
	# Concern (A): the mirrored (right) bat has a reversed perimeter, so flip every triangle's
	# winding
	# to keep its normals facing the same direction as the left bat's. _emit_tri does the swap.
	var flip_winding: bool = hand_sign < 0.0
	var half_h: float = height * 0.5
	var mesh := ArrayMesh.new()

	# --- Surface 0: BLACK BODY (sides + bottom cap). ---
	var st_body := SurfaceTool.new()
	st_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Side walls: for each outline edge, a quad (top->bottom) connecting consecutive points.
	var n: int = outline.size()
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var a_top := Vector3(a.x, half_h, a.y)
		var b_top := Vector3(b.x, half_h, b.y)
		var a_bot := Vector3(a.x, -half_h, a.y)
		var b_bot := Vector3(b.x, -half_h, b.y)
		# Two triangles per side quad (wound so the normal faces outward).
		_emit_tri(st_body, a_top, a_bot, b_top, flip_winding)
		_emit_tri(st_body, b_top, a_bot, b_bot, flip_winding)
	# Bottom cap (fan from the first point), wound to face DOWN (-Y). We orient the cap from the
	# outline's ACTUAL signed area in the X-Z plane so the bottom always faces -Y for BOTH the left
	# (CCW) and the mirrored right (CW) outline, with no per-side flag to thread. The bottom cap is
	# the
	# OPPOSITE winding of the top cap below.
	var top_forward: bool = _cap_top_is_forward(outline)
	for i in range(1, n - 1):
		_emit_cap_tri(st_body, outline, i, -half_h, not top_forward)
	st_body.generate_normals()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOR
	st_body.set_material(body_mat)
	st_body.commit(mesh)

	# --- Surface 1: WHITE RUBBER TOP cap (the up-facing face). ---
	# Wound to face UP (+Y) - the face the top-down camera sees. Orientation is derived from the
	# outline's signed area (_cap_top_is_forward) so the top cap faces +Y on BOTH the left and the
	# mirrored right bat. test_flipper_rubber_top.gd asserts this (the cap's average normal Y must
	# be
	# POSITIVE on both bats).
	var st_top := SurfaceTool.new()
	st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, n - 1):
		_emit_cap_tri(st_top, outline, i, half_h, top_forward)
	st_top.generate_normals()
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = RUBBER_TOP_COLOR
	st_top.set_material(top_mat)
	st_top.commit(mesh)

	return mesh


## Emit one triangle to a SurfaceTool, flipping the winding (swapping v1/v2) when flip is true. Used
## by
## the SIDE WALLS: an X-mirrored outline reverses the perimeter order, so the mirrored bat flips
## every
## side triangle to keep its outward normals consistent. The CAPS use _emit_cap_tri instead (their
## orientation is derived from the outline's signed area, not from a per-side flag).
func _emit_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, flip: bool) -> void:
	st.add_vertex(v0)
	if flip:
		st.add_vertex(v2)
		st.add_vertex(v1)
	else:
		st.add_vertex(v1)
		st.add_vertex(v2)


## Signed area of the (x, z) outline in the X-Z plane (the shoelace formula). Positive = the points
## wind counter-clockwise (the left bat), negative = clockwise (the mirrored right bat). Used to
## orient
## the prism caps so the TOP always faces +Y regardless of the per-side mirror.
func _signed_area_xz(outline: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = outline.size()
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


## Whether the TOP cap fan should be emitted in FORWARD order (0, i, i+1) to face +Y. Derived from
## the
## outline's signed area so it self-corrects for the mirrored bat: a CCW outline (positive area, the
## left bat) needs the forward order to face the top cap +Y; a CW outline (negative area, the
## mirrored
## right bat) needs the reversed order. The mapping was pinned against the REAL mesh normals that
## test_flipper_rubber_top.gd reads from generate_normals() under Godot's built-in winding
## convention.
func _cap_top_is_forward(outline: PackedVector2Array) -> bool:
	return _signed_area_xz(outline) > 0.0


## Emit one cap fan triangle (apex outline[0], then outline[i], outline[i+1]) at height y. When
## forward
## is false the i / i+1 pair is swapped, flipping the cap's facing. Keeps the cap winding in one
## helper
## shared by the top (+Y) and bottom (-Y) caps of both bats.
func _emit_cap_tri(
	st: SurfaceTool, outline: PackedVector2Array, i: int, y: float, forward: bool
) -> void:
	st.add_vertex(Vector3(outline[0].x, y, outline[0].y))
	if forward:
		st.add_vertex(Vector3(outline[i].x, y, outline[i].y))
		st.add_vertex(Vector3(outline[i + 1].x, y, outline[i + 1].y))
	else:
		st.add_vertex(Vector3(outline[i + 1].x, y, outline[i + 1].y))
		st.add_vertex(Vector3(outline[i].x, y, outline[i].y))
