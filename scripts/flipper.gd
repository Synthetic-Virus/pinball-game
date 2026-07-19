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
##          +-- FlipperMesh       (procedural 2-tone gray-box fallback mesh)
##          +-- FlipperVisual     (imported flipper_bat.glb, shown on success)
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
## whole feel lives in these numbers. PHYSICS-PROGRAMMER tunes them to the measured targets in the
## WHY
## above (38.21 rad/s peak sweep, ~50-80 ms snap, tap << full-swing by >= 1.5x). The values below
## are
## a structurally-correct FIRST CUT; confirm/tune headless against test_flipper_momentum.gd.

## Peak angular speed the driven swing may reach (rad/s), about the surface normal. WHY 38.21: the
## measured peak of the real full-swing sweep that imparts 29.96 u/s to a resting ball. The driven
## angular velocity is capped here so the swing is snappy but bounded (the up-stop clamp bounds the
## ANGLE; this bounds the SPEED so the imparted momentum stays inside the measured-safe envelope).
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

## --- FIRST REAL 3D ASSET (SLICE "first-real-3d-asset", 2026-06-20) -------------------------------
## The VISIBLE bat mesh is the imported assets/models/flipper_bat.glb (vbousquet/pinball-parts,
## CC BY-SA 4.0, modified - see CREDITS.md), NOT the procedural gray-box ArrayMesh. The collider,
## the drive, the material, and the bounce are ALL untouched by the asset swap: a COSMETIC swap
## behind
## the frozen physics. The procedural mesh (FlipperMesh) stays as the crash-proof fallback (hidden
## on
## success, shown on fail), so a missing or failed asset is a one-line visibility downgrade, never a
## crash (DESIGN must-feel: the flipper never vanishes).
const FLIPPER_BAT_ASSET_PATH: String = "res://assets/models/flipper_bat.glb"

## The node name the imported .glb visual is instanced under (the handoff NODE CONTRACT). Tests find
## the imported visual by this name; the procedural fallback keeps its legacy name "FlipperMesh".
const FLIPPER_VISUAL_NODE_NAME: String = "FlipperVisual"

## Sentinel for _asset_path_override meaning "no test override, use FLIPPER_BAT_ASSET_PATH". Kept
## with the other consts (gdlint class-definitions-order: consts precede vars). See the test hook.
const _ASSET_PATH_NO_OVERRIDE: String = "__use_default__"

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

## TEST HOOK (mirrors _force_energized): force the imported-asset load to use a different path so a
## test can drive the graceful-fallback branch WITHOUT deleting the real .glb. INERT in production:
## table.gd never calls set_asset_path_for_test, so the real FLIPPER_BAT_ASSET_PATH is the one used
## in
## play. An "" or bogus path makes the load fail and the procedural FlipperMesh shows. See
## test_flipper_asset_visual.test_fallback_to_procedural_when_asset_missing. The
## _ASSET_PATH_NO_OVERRIDE
## sentinel (a const above) means "use the default"; any other value (incl "") overrides.
var _asset_path_override: String = _ASSET_PATH_NO_OVERRIDE

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
## The imported .glb visual (named FLIPPER_VISUAL_NODE_NAME). Null when the asset failed to load (so
## the procedural fallback shows). Built once in _build_flipper, re-oriented per handedness in
## _rebuild_bat_geometry so the right bat is a clean 180-degree rotation of the left (not a mirror).
var _visual_instance: MeshInstance3D
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
	_body.add_child(_mesh_instance)

	# The IMPORTED .glb visual. On success it is shown and the procedural FlipperMesh is hidden; on
	# failure (missing/bogus asset) the procedural mesh stays shown and _visual_instance stays null.
	# Built BEFORE _apply_handedness so the latter can orient it for the correct side.
	_build_visual()

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


## TEST HOOK (fallback seam): override the .glb path the visual load uses, so a test can force the
## asset-load failure WITHOUT deleting the real file (an "" or bogus path makes the load fail and
## the
## procedural FlipperMesh shows). Call this BEFORE configure()/_ready() builds the flipper. INERT in
## production: table.gd never calls it, so the real FLIPPER_BAT_ASSET_PATH is the path in play. See
## test_flipper_asset_visual.test_fallback_to_procedural_when_asset_missing.
func set_asset_path_for_test(path: String) -> void:
	_asset_path_override = path


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
## A flipper's dimensions, rest/up angles, and visible asset are read through these getters so a
## SUBCLASS (scripts/mini_flipper.gd) can make a SMALLER flipper WITHOUT duplicating the drive in
## this
## file. The defaults return the existing TableConfig constants, so the two MAIN flippers behave
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


func _flipper_asset_path() -> String:
	return FLIPPER_BAT_ASSET_PATH


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

	# Orient the IMPORTED .glb visual for this handedness too. Unlike the procedural mesh (rebuilt
	# with
	# mirrored points), the imported visual is mirrored by a 180-degree ROTATION about the surface
	# normal (+Y), never a negative-scale reflection (which would invert the normals and bury the
	# rubber
	# top). See _orient_visual / the handoff MIRROR section.
	_orient_visual(hand_sign)


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


## --- IMPORTED .glb VISUAL (the asset swap; collider/drive untouched) -----------------------------
## Load the imported flipper bat .glb and instance its WHOLE mesh subtree under FlipperVisual, sized
## to
## the collider. On ANY failure (missing file, unimported LFS pointer, no mesh in the scene) this
## leaves _visual_instance null and the procedural FlipperMesh shown, so play continues (graceful
## fallback, test_fallback_to_procedural_when_asset_missing). Idempotent.
##
## WHY THE WHOLE SCENE, NOT JUST THE FIRST MESH: our custom flipper_bat.glb is TWO meshes - the body
## (Flipper_Bat) AND a separate RUBBER sleeve (Flipper_Rubber). The old code took only the FIRST
## MeshInstance3D, dropping the rubber. DESIGN requires the rubber surface on BOTH flippers. So we
## instance the ENTIRE imported subtree (every named mesh) and parent it under one FlipperVisual
## node,
## the same pattern pop_bumper.gd / slingshot.gd use for their multi-part .glb. The mirror is a
## ROTATION
## (not a negative-scale reflection) applied to that one parent, so the right bat shows the
## identical
## body+rubber two-tone (the right-flipper rubber-drop bug cannot recur - it is the same node tree).
func _build_visual() -> void:
	if _visual_instance != null:
		return

	var path: String = _resolve_asset_path()
	var imported: Node3D = _load_asset_subtree(path)
	if imported == null:
		# Fallback: keep the procedural mesh visible, no imported visual. NOT a crash.
		_mesh_instance.visible = true
		return

	# The .glb has MULTIPLE named meshes (the bat body + the rubber sleeve). The NODE CONTRACT
	# (test_flipper_asset_visual) expects FlipperVisual to BE a MeshInstance3D with a non-null mesh,
	# so
	# we make FlipperVisual the FIRST imported mesh (the body) and RE-PARENT every OTHER imported
	# mesh
	# (the rubber) as a child of it. That way: (a) FlipperVisual.mesh is non-null (contract held),
	# and
	# (b) the rubber renders too (no drop) and inherits FlipperVisual's scale+mirror as one unit.
	# The
	# .glb is modelled in REAL METRES; we enlarge by a factor DERIVED from the merged mesh AABB,
	# never
	# a hand-typed literal.
	var meshes: Array = _mesh_instances(imported)
	_visual_instance = MeshInstance3D.new()
	_visual_instance.name = FLIPPER_VISUAL_NODE_NAME
	_visual_instance.mesh = (meshes[0] as MeshInstance3D).mesh  ## the body = the long-axis mesh
	_body.add_child(_visual_instance)
	# Re-parent the remaining imported meshes (the rubber sleeve etc.) under FlipperVisual at their
	# ORIGINAL local transforms relative to the imported root, so they sit correctly on the body and
	# follow the wrapper's scale+mirror. We dup each as a fresh MeshInstance3D to avoid moving nodes
	# that are still parented in the throwaway imported tree.
	for i in range(1, meshes.size()):
		var src: MeshInstance3D = meshes[i] as MeshInstance3D
		var extra := MeshInstance3D.new()
		extra.mesh = src.mesh
		extra.transform = imported.global_transform.affine_inverse() * src.global_transform
		_visual_instance.add_child(extra)
	# The throwaway imported tree has served its purpose (we copied its meshes); free it.
	imported.queue_free()

	# On a successful import the imported visual is the shown bat; the procedural mesh becomes the
	# hidden fallback (kept in the tree so a later failure can re-show it with one visibility
	# toggle).
	_visual_instance.visible = true
	_mesh_instance.visible = false


## The asset path the load uses: the test override if set (the fallback seam), else the real asset.
## INERT in production (set_asset_path_for_test is never called by table.gd).
func _resolve_asset_path() -> String:
	if _asset_path_override != _ASSET_PATH_NO_OVERRIDE:
		return _asset_path_override
	return _flipper_asset_path()


## Load the .glb and instantiate its WHOLE node subtree (body + rubber sleeve + any future parts).
## Returns null on ANY failure so the caller falls back to the procedural mesh. Reading the real
## instanced node (not a flag) is the independent oracle that the asset actually loaded. WHY return
## the
## subtree (not a single Mesh): our model has multiple named meshes; taking one would drop the rest
## (the rubber-drop bug). The caller scales/mirrors this whole subtree as one unit.
func _load_asset_subtree(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res == null or not (res is PackedScene):
		return null
	var packed: PackedScene = res as PackedScene
	var inst: Node = packed.instantiate()
	if inst == null:
		return null
	# Guard: a .glb with no mesh at all is treated as a failed load (fall back to the gray box) so a
	# truncated/empty asset cannot leave an invisible flipper.
	if _first_mesh_in(inst) == null:
		inst.queue_free()
		return null
	return inst as Node3D


## Depth-first search for the first MeshInstance3D with a non-null mesh in an instanced scene tree.
## Used only as a presence guard (does the asset contain ANY mesh) - the whole subtree is kept.
func _first_mesh_in(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child in node.get_children():
		var found: Mesh = _first_mesh_in(child)
		if found != null:
			return found
	return null


## Merge every descendant MeshInstance3D's AABB into `root`'s local space. The merged box is the
## independent oracle on the imported model's true footprint (across body + rubber), used to derive
## the
## uniform scale. Copy of the pop_bumper.gd / slingshot.gd discipline.
func _merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _mesh_instances(root):
		var local: Transform3D = TableConfig.relative_xform(root, mi)
		var a: AABB = local * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## Every MeshInstance3D under `node` (recursive). The imported .glb has named sub-meshes (bat,
## rubber); the merged AABB needs them all.
func _mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c: Node in node.get_children():
		found.append_array(_mesh_instances(c))
	return found


## Derive the uniform scale factor that fits the imported model to the collider, from the merged
## AABB -
## NEVER a hand-typed literal. factor = FLIPPER_LENGTH / (merged AABB longest axis). This
## self-corrects
## if the asset is re-exported at a different size or if FLIPPER_LENGTH changes: the measured AABB
## drives the fit. The structural test asserts the RESULTING world-space mesh length equals the
## collider
## length within tolerance, which a magic constant cannot satisfy.
func _derive_visual_scale(root: Node3D) -> float:
	var aabb: AABB = _merged_aabb(root)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.0001:
		# Degenerate AABB (should never happen for a real bat); 1.0 keeps the mesh visible, not
		# zeroed.
		return 1.0
	return _flipper_length() / longest


## Orient + scale the imported visual for the handedness sign (+1 left, -1 right). The asset is
## built
## with its long axis +X and its up axis +Y, matching the LEFT collider frame, so the left visual
## needs
## NO rotation. The RIGHT (mirrored) bat is a clean 180-degree ROTATION about the surface normal
## (local +Y), so the bat reaches toward center on -X like its collider, rubber still on TOP. WHY a
## rotation, not a negative-scale reflection: a reflection inverts the mesh normals and buries/flips
## the
## rubber (test_right_flipper_visual_is_not_inside_out asserts the visual basis determinant stays
## POSITIVE - a proper rotation). The uniform scale (derived from the merged AABB) is composed with
## the
## rotation so both sides keep identical proportions.
func _orient_visual(hand_sign: float) -> void:
	if _visual_instance == null:
		return
	var rot := Basis.IDENTITY
	if hand_sign < 0.0:
		# 180 degrees about +Y flips +X to -X while keeping +Y up (a proper rotation, det = +1).
		rot = Basis(Vector3(0.0, 1.0, 0.0), PI)
	var factor: float = _derive_visual_scale(_visual_instance)
	# Compose rotation then uniform scale; setting transform.basis directly keeps the determinant
	# positive (rotation * positive-uniform-scale), the independent oracle the mirror test reads.
	_visual_instance.transform = Transform3D(rot.scaled(Vector3.ONE * factor), Vector3.ZERO)


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
