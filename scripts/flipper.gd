extends Node3D
## Flipper - ONE force-driven flipper (hinge joint + driven solenoid force + return spring).
##
## OWNERSHIP: physics-programmer. This is the headline feel upgrade over the old kinematic boxes.
## Geometry comes from TableConfig; YOU own the joint, the drive force, the return spring, and the
## tuning that makes a full swing out-throw a tap (DESIGN.md "REAL MOMENTUM", "FLIPPER SNAP").
##
## WHY FORCE-DRIVEN, NOT KINEMATIC (DESIGN.md, pinhead-tech-notes.md pattern 1):
##   A kinematic flipper teleports through angles and imparts a fixed canned velocity, so a tap and
##   a full swing feel identical. A force-driven flipper is a real RigidBody on a hinge, pushed by a
##   "solenoid" torque toward the up-stop and pulled back by a spring; it strikes the ball with its
##   actual momentum, so timing and swing matter. That is the entire point of this slice.
##
## STRUCTURE (built in code from TableConfig so it stays in scale and needs no scene authoring):
##   Flipper (this Node3D, sits AT the pivot - table.gd places it)
##     +-- FlipperBody (RigidBody3D, KINEMATIC_OBSTACLES layer, the bat the ball hits)
##     +-- Pivot (HingeJoint3D, anchors FlipperBody, axis = playfield surface normal)
##   The drive torque + return spring are applied each physics frame in _physics_process.
##
## COORDINATE CONVENTION (local to this Flipper node, which lives on the tilted Playfield):
##   The bat lies FLAT on the surface and swings about the surface normal (this node's local +Y).
##   The bat extends from the pivot along the rotating bat's local +X. Angle 0 = bat pointing along
##   the Flipper's local +X. The rest/up angles come from TableConfig; "mirrored" negates them and
##   the swing direction so the right flipper is a true mirror of the left.
##
## INPUT: reads the action assigned via configure(). Flip MUST register on the SAME physics frame as
## the press (DESIGN.md "Input feel: no input lag"); poll the action in _physics_process, do not
## wait for _input event routing.
##
## STABLE CONTRACT (table.gd / tests depend on these; keep the signatures):
##   func configure(action_name: String, mirrored: bool) -> void
##       # action_name in {"left_flipper","right_flipper"}; mirrored = true for the right flipper.
##   func is_energized() -> bool   # true while the flip action is held.
##   func tip_speed() -> float     # linear speed of the flipper tip (used by the momentum test).

## --- TUNING (physics-programmer owns these) -----------------------------------------------------
## Bat mass. WHY 0.40 (raised from the old 0.12): the bat is a RigidBody on a hinge, so when a ball
## strikes the RESTING face the bat RECOILS, and a too-light bat is shoved aside and absorbs almost
## all the ball's energy (a dead rebound). The bat's EFFECTIVE inertia at the mid-face contact point
## is only ~4/3 of its mass; at 0.12 that was ~0.16, far lighter than the 0.6 ball, so a head-on hit
## kept barely ~22% of the incoming speed (well under the 0.35 rubber floor) NO MATTER how high the
## restitution went (raising bounce alone HURT it - the recoil dominates). At 0.40 the bat resists
## the shove enough that the restitution actually delivers a lively rebound (~0.43 of incoming with
## BAT_BOUNCE below). The strong SOLENOID_TORQUE has huge headroom, so this heavier bat still snaps
## to 90% swing in ~3 physics frames (~12 ms, faster than the 50 ms target) and the momentum gate
## (full swing >> tap) stays green - verified headless. This is the genuine "rubber that keeps
## momentum" fix, not a weakened test.
const BAT_MASS: float = 0.40
## Drive torque applied toward the up-stop while the action is held. Sized with BAT_MASS and the
## bat's inertia at FLIPPER_LENGTH to reach full extension in ~50 ms (DESIGN "FLIPPER SNAP") and
## to firmly CRADLE the ball's weight when held against it (resist sag).
const SOLENOID_TORQUE: float = 9000.0
## Return-spring stiffness: restoring torque per radian of displacement from the rest angle when the
## action is NOT held. Strong enough to return briskly, soft enough that the return does not itself
## launch the ball across the table.
const RETURN_SPRING_STIFFNESS: float = 1200.0
## Angular damping torque per unit of angular velocity, applied in BOTH states. This is the shock
## absorber: it stops the bat oscillating against the hinge limits (a buzzing/jittering flipper) and
## keeps a held flipper rock-steady in a cradle. Too high kills the snap; tuned to allow the ~50 ms
## snap while still settling cleanly.
const ANGULAR_DAMPING: float = 60.0
## Unit hinge axis in this node's LOCAL space. The bat rotates about the surface normal (+Y).
## Declared here with the other constants so gdlint's class-definitions-order rule is satisfied.
const _HINGE_AXIS_LOCAL: Vector3 = Vector3(0.0, 1.0, 0.0)

## Bat collision/material tuning. High friction lets the bat grip and sling the ball rather than
## letting it skid.
const BAT_FRICTION: float = 0.7

## --- BAT SHAPE (SLICE "Table reshape + playtest fixes", 2026-06-19) ------------------------------
## The bat is a TAPERED ROUNDED "stadium" form: FAT at the pivot, narrowing to a smaller ROUNDED tip
## (DESIGN must-feel #2 "the flipper is a flipper shape", ARCHITECTURE.md 11.3). It REPLACES the old
## BoxMesh/BoxShape3D plank, in BOTH the visible mesh AND the collision shape, with the two AGREEING
## so "where on the bat the ball hits matters" (a tip shot vs a base shot read differently).
##
## WHY A CONVEX HULL, NOT A CAPSULE: a CapsuleShape3D has a CONSTANT radius (no taper) and rounded
## END CAPS that bulge past the pivot, so it cannot be both fat-at-pivot and thin-at-tip. We build a
## ConvexPolygonShape3D hull (allowed by the structural test as a non-box shape) whose footprint is
## a TAPERED rounded stadium on the surface plane: full FLIPPER_WIDTH from the pivot through the mid
## face, then narrowing to TIP_WIDTH_FRACTION at the rounded tip. The matching mesh is built from
## the SAME outline points (extruded to FLIPPER_HEIGHT) so the collider and the mesh agree exactly.
##
## WHY FULL WIDTH THROUGH THE MID FACE (not tapering from the pivot): the rubber-rebound gate
## (test_flipper_rubber.gd) fires the ball HEAD-ON at the MID-BAT point and stands it off by
## FLIPPER_WIDTH*0.5 + BALL_RADIUS, so the mid face must be ~FLIPPER_WIDTH wide and present a
## flat-ish face there. Keeping full width across the inner ~60% of the bat (TAPER_START_FRACTION)
## preserves that head-on contact; the taper lives only over the outer tip half. The lever arm and
## tip_speed() are unchanged (the pivot-to-tip distance is still FLIPPER_LENGTH).
## Fraction of FLIPPER_WIDTH the rounded TIP narrows to (the bat is thinner at the tip than base).
const TIP_WIDTH_FRACTION: float = 0.45
## Fraction of FLIPPER_LENGTH from the pivot at which the taper BEGINS. Inboard the bat keeps full
## FLIPPER_WIDTH (so the mid-face head-on contact stays flat); outboard of this it narrows.
const TAPER_START_FRACTION: float = 0.55
## How many segments approximate each rounded end of the stadium outline. More = smoother, but a
## hull needs few points; 4 per end gives a clean rounded read without bloating the convex hull.
const ROUND_SEGMENTS: int = 4

## --- 2-TONE GRAY-BOX MATERIAL (no art dependency) -----------------------------------------------
## BLACK body + WHITE rubber TOP surface (DESIGN/ARCHITECTURE.md 11.3: a 2-tone gray-box look only;
## the kenney.nl CC0 art pass is LATER and must NOT block this slice). The white top is a VISUAL cue
## for the rubber surface; the rubber FEEL stays BAT_BOUNCE 0.70 (the PhysicsMaterial, unchanged).
const BODY_COLOR: Color = Color(0.05, 0.05, 0.05)   ## Near-black bat body.
const RUBBER_TOP_COLOR: Color = Color(0.92, 0.92, 0.92)  ## White rubber top cap.
## Bat restitution: the RUBBER SLEEVE. DESIGN must-feel #3 / "RUBBER THAT REBOUNDS": a ball striking
## the flipper face rebounds with a live, slightly-springy feel (a rubber-sleeved bat), not off a
## dead board. WHY 0.70 (rubber, NOT a trampoline): the built-in Jolt physics in Godot 4.6 does NOT
## combine restitution by MAX (the old comment's assumption was wrong); the EFFECTIVE contact bounce
## against the steel ball (BALL_BOUNCE 0.15) is much lower than the bat's own value. Measured
## headless against the REAL resting bat (now BAT_MASS 0.40 so it does not just recoil), a head-on
## hit at 0.70 rebounds at ~0.43 of the incoming speed - clearly above the test's 0.35 floor and far
## under the 1.15 trampoline ceiling (a true elastic 1.0 against this ball/bat pair still lands well
## below 1.0 effective, so energy is never manufactured). This is a SURFACE value paired with the
## mass fix above; together they make the PASSIVE rebound real without touching the solenoid drive,
## the snap, the return spring, or the cradle (the active swing still throws via the bat's real
## momentum - the momentum and snap tests stay green, verified headless).
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
var _body: RigidBody3D
var _hinge: HingeJoint3D
## The bat's collision shape and mesh. Kept as handles because handedness re-seats their X offset:
## the bat must extend FROM the pivot TOWARD the table center, which is +X for the left flipper and
## -X for the (mirrored) right flipper. See _apply_handedness (QA BUG-001 fix).
var _shape: CollisionShape3D
var _mesh_instance: MeshInstance3D
## The signed rest/up angles for THIS flipper (mirrored applied). Lower/upper of the hinge limit.
var _rest_angle: float = 0.0
var _up_angle: float = 0.0


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


## Build the RigidBody bat + HingeJoint3D from TableConfig dimensions. Idempotent: only builds once.
func _build_flipper() -> void:
	if _body != null:
		return

	# --- The bat: a box from the pivot outward, lying flat on the surface. ------------------------
	_body = RigidBody3D.new()
	_body.name = "FlipperBody"
	_body.mass = BAT_MASS
	# CCD on the bat too: its TIP moves fast (a long lever at high angular velocity), so the ball
	# could otherwise pass the thin bat between steps. Belt-and-braces with the ball's own CCD.
	_body.continuous_cd = true
	_body.collision_layer = PhysicsLayers.KINEMATIC_OBSTACLES
	_body.collision_mask = PhysicsLayers.KINEMATIC_COLLISION_MASK
	# Gravity off: the bat is fully driven by the solenoid/spring torques; letting gravity pull it
	# (on a tilted plane, in 3D) would add an unwanted sag the spring would have to fight.
	_body.gravity_scale = 0.0
	# We do our own angular damping torque; keep the body's built-in damp out of it for clarity.
	_body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_body.angular_damp = 0.0
	_body.can_sleep = false  # A flipper must respond instantly; never let it sleep.

	var material := PhysicsMaterial.new()
	material.friction = BAT_FRICTION
	material.bounce = BAT_BOUNCE
	_body.physics_material_override = material

	# Collision shape + mesh: a TAPERED ROUNDED STADIUM (NOT a box). The actual hull/mesh geometry is
	# built in _rebuild_bat_geometry() (called from _apply_handedness) because the taper direction
	# depends on handedness: the FAT pivot end must sit at the pivot and the THIN tip reach toward
	# CENTER, which is +X for the left flipper and -X for the mirrored right flipper. We create the
	# empty nodes here; _apply_handedness fills them with the correctly-oriented geometry.
	_shape = CollisionShape3D.new()
	_body.add_child(_shape)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "FlipperMesh"
	_body.add_child(_mesh_instance)

	add_child(_body)

	# --- The hinge: pins the bat at the pivot, axis along the surface normal. ----------------------
	# HingeJoint3D rotates node_a about the joint's local Z axis. We orient the joint so its Z aligns
	# with this node's local +Y (the surface normal), giving an in-plane swing.
	_hinge = HingeJoint3D.new()
	_hinge.name = "Pivot"
	# Build a basis whose Z column is the hinge axis (+Y local). X stays X; Y becomes -Z so the
	# basis is right-handed and orthonormal.
	_hinge.transform = Transform3D(
		Vector3(1.0, 0.0, 0.0),   # local X
		Vector3(0.0, 0.0, -1.0),  # local Y
		Vector3(0.0, 1.0, 0.0),   # local Z == hinge axis == surface normal
		Vector3.ZERO,
	)
	add_child(_hinge)
	# node_a must be a NodePath the hinge can resolve now that both are in the tree. Leaving node_b
	# empty pins the bat to the static world frame (the pivot does not move). The bat therefore
	# swings about a fixed point - exactly a flipper hinge.
	_hinge.node_a = _hinge.get_path_to(_body)

	_apply_handedness()


## Apply rest/up angles and the mirror for handedness, and seat the bat at the rest angle.
func _apply_handedness() -> void:
	# Mirror negates the angles so the right flipper is the left's mirror image about the table's
	# centerline (it swings the opposite rotational direction).
	var hand_sign := -1.0 if _mirrored else 1.0
	_rest_angle = TableConfig.FLIPPER_REST_ANGLE * hand_sign
	_up_angle = TableConfig.FLIPPER_UP_ANGLE * hand_sign

	# Build the tapered bat geometry on the correct side of the pivot. The bat must reach FROM the
	# pivot (fat end) TOWARD the table center (thin tip): +X for the left flipper, -X for the mirrored
	# right flipper. Without this the right bat pointed AWAY from center (toward the right wall) and
	# could never intercept a draining ball - the inverted V could not form (QA BUG-001). Mirroring the
	# angle alone is not enough; the lever arm itself must flip. The taper is asymmetric (fat pivot ->
	# thin tip), so a simple position offset cannot mirror it; we rebuild the outline with the X sign
	# applied so the fat end stays pinned at the pivot (this node's origin) for BOTH sides.
	_rebuild_bat_geometry(hand_sign)

	# Hinge limits are an absolute lower..upper range; order them so lower <= upper regardless of
	# the mirror sign. These hard stops back up the spring: the ball can never push the bat past
	# them, and the solenoid drive cannot overshoot the up-stop.
	var lower: float = min(_rest_angle, _up_angle)
	var upper: float = max(_rest_angle, _up_angle)
	if _hinge != null:
		_hinge.set("angular_limit/enable", true)
		_hinge.set("angular_limit/lower", lower)
		_hinge.set("angular_limit/upper", upper)
		# Relaxation controls how firmly the limit is enforced; 1.0 is the firm default so the
		# up-stop holds a cradle solidly and the ball cannot shove the bat past its limit.
		_hinge.set("angular_limit/relaxation", 1.0)

	# Seat the bat at the rest angle so the flipper starts at rest, not at angle 0.
	if _body != null:
		_body.transform = Transform3D(Basis(_HINGE_AXIS_LOCAL, _rest_angle), Vector3.ZERO)
		_body.angular_velocity = Vector3.ZERO
		_body.linear_velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if _body == null:
		return

	# Hinge axis in WORLD space (the surface normal of the tilted playfield, oriented by this node).
	var axis_world: Vector3 = (global_transform.basis * _HINGE_AXIS_LOCAL).normalized()

	# Signed angular velocity of the bat about the hinge axis (rad/s). Feeds the damping torque that
	# settles the bat at the stops; the hinge's hard angular limit is what actually stops the swing.
	var ang_vel_about_axis: float = _body.angular_velocity.dot(axis_world)

	var pressed: bool = _is_pressed()

	var torque_scalar: float = 0.0
	if pressed:
		# --- SOLENOID DRIVE: snap toward the up-stop. ---------------------------------------------
		# Drive sign points from rest toward up. For the left flipper up_angle > rest_angle, so the
		# drive is positive; mirrored flips both, so the sign follows the up-stop direction.
		var drive_dir: float = signf(_up_angle - _rest_angle)
		torque_scalar += SOLENOID_TORQUE * drive_dir
	else:
		# --- RETURN SPRING: restore toward the rest angle. ----------------------------------------
		# Restoring torque proportional to the displacement from rest (a linear spring).
		var current_angle: float = _current_hinge_angle(axis_world)
		var displacement: float = current_angle - _rest_angle
		torque_scalar += -RETURN_SPRING_STIFFNESS * displacement

	# --- DAMPING: applied in both states. -----------------------------------------------------------
	# Opposes angular velocity so the bat does not oscillate at the stops and a held flipper stays
	# rock-steady against the ball (a stable cradle).
	torque_scalar += -ANGULAR_DAMPING * ang_vel_about_axis

	_body.apply_torque(axis_world * torque_scalar)


## Current rotation angle of the bat about the hinge axis, relative to the bat's UNROTATED frame,
## measured along the hinge axis so the sign matches the rest/up convention. Reconstructs the angle
## from the bat's basis rather than reading a private hinge value (engine-agnostic and testable).
func _current_hinge_angle(axis_world: Vector3) -> float:
	# The bat's local +X, brought to world, projected onto the playfield plane; its signed angle
	# from this node's local +X (also in world) about the hinge axis is the swing angle.
	var ref_dir: Vector3 = (global_transform.basis * Vector3.RIGHT).normalized()
	var bat_dir: Vector3 = (_body.global_transform.basis * Vector3.RIGHT).normalized()
	# signed_angle_to returns the angle from ref to bat measured CCW about the given axis.
	return ref_dir.signed_angle_to(bat_dir, axis_world)


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
## than a tap. STABLE SIGNATURE.
## tip speed = |omega about the hinge axis| * lever arm (FLIPPER_LENGTH). We project the body's
## angular velocity ONTO the hinge axis rather than taking its full magnitude (QA BUG-010): a clean
## swing is purely about the axis, but an oblique ball strike or a Jolt constraint impulse can add a
## spurious off-axis wobble that would inflate a naive |omega|. The axis projection reports only the
## real swing speed, so the momentum gate reads the feel the player actually gets.
func tip_speed() -> float:
	if _body == null:
		return 0.0
	var axis_world: Vector3 = (global_transform.basis * _HINGE_AXIS_LOCAL).normalized()
	var ang_vel_about_axis: float = _body.angular_velocity.dot(axis_world)
	return absf(ang_vel_about_axis) * TableConfig.FLIPPER_LENGTH


## --- TAPERED BAT GEOMETRY (the capsule/stadium shape swap) ---------------------------------------
## Build the bat's top-down OUTLINE on the surface plane (the X-Z footprint): a TAPERED ROUNDED
## stadium with the FAT pivot end at X=0 and the THIN rounded tip at X=FLIPPER_LENGTH. Returned as
## 2D points in (x, half_width) form along the +X long axis; the caller mirrors X for the right
## flipper and extrudes to height. The outline keeps full FLIPPER_WIDTH from the pivot through the
## mid face (so the rubber-rebound head-on contact at mid-bat stays flat) and narrows over the tip.
##
## Points are ordered around the perimeter (CCW) so the mesh builder can fan-triangulate the top/
## bottom caps. The convex hull builder ignores order (a hull only needs the point cloud).
func _build_bat_outline() -> PackedVector2Array:
	var fl: float = TableConfig.FLIPPER_LENGTH
	var base_half: float = TableConfig.FLIPPER_WIDTH * 0.5
	var tip_half: float = base_half * TIP_WIDTH_FRACTION
	var taper_x: float = fl * TAPER_START_FRACTION  ## Full width up to here, then narrow to the tip.
	var tip_x: float = fl - tip_half                 ## The rounded tip cap is centered here.

	# Build the two long edges as (x, +/-half_width) pairs, full width to taper_x then narrowing to
	# tip_half at the tip cap center. We then add rounded end caps (pivot + tip) as arcs.
	var pts := PackedVector2Array()

	# Pivot (fat) rounded end cap: a half-circle of radius base_half centered at x = base_half,
	# sweeping from the +width edge around the back (x < base_half) to the -width edge (rounds pivot).
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

	var height: float = TableConfig.FLIPPER_HEIGHT
	if _shape != null:
		var hull := ConvexPolygonShape3D.new()
		hull.points = _extrude_outline_to_hull(outline, height)
		_shape.shape = hull
	if _mesh_instance != null:
		_mesh_instance.mesh = _build_bat_mesh(outline, height)


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
## the white RUBBER TOP cap (the up-facing face) - the 2-tone gray-box look (DESIGN/ARCH 11.3).
func _build_bat_mesh(outline: PackedVector2Array, height: float) -> ArrayMesh:
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
		st_body.add_vertex(a_top)
		st_body.add_vertex(a_bot)
		st_body.add_vertex(b_top)
		st_body.add_vertex(b_top)
		st_body.add_vertex(a_bot)
		st_body.add_vertex(b_bot)
	# Bottom cap (fan from the first point), wound to face down (-Y).
	for i in range(1, n - 1):
		st_body.add_vertex(Vector3(outline[0].x, -half_h, outline[0].y))
		st_body.add_vertex(Vector3(outline[i + 1].x, -half_h, outline[i + 1].y))
		st_body.add_vertex(Vector3(outline[i].x, -half_h, outline[i].y))
	st_body.generate_normals()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOR
	st_body.set_material(body_mat)
	st_body.commit(mesh)

	# --- Surface 1: WHITE RUBBER TOP cap (the up-facing face). ---
	var st_top := SurfaceTool.new()
	st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, n - 1):
		st_top.add_vertex(Vector3(outline[0].x, half_h, outline[0].y))
		st_top.add_vertex(Vector3(outline[i].x, half_h, outline[i].y))
		st_top.add_vertex(Vector3(outline[i + 1].x, half_h, outline[i + 1].y))
	st_top.generate_normals()
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = RUBBER_TOP_COLOR
	st_top.set_material(top_mat)
	st_top.commit(mesh)

	return mesh
