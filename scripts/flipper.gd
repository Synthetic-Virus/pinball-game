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
##       # action_name in {"left_flipper","right_flipper"}; mirrored flips the geometry for the right.
##   func is_energized() -> bool          # true while the flip action is held (for tests/diagnostics).
##   func tip_speed() -> float            # linear speed of the flipper tip (momentum the test checks).

## --- TUNING (physics-programmer owns these) -----------------------------------------------------
## The bat is light so the solenoid can snap it fast but it still carries enough momentum to throw
## the heavier ball (BALL_MASS 0.6). A light bat + strong drive is how real solenoids feel: an
## almost-instant snap to the up-stop.
const BAT_MASS: float = 0.12
## Drive torque applied toward the up-stop while the action is held. Sized (with BAT_MASS and the
## bat's inertia at FLIPPER_LENGTH) to reach full extension in roughly ~50 ms (DESIGN "FLIPPER SNAP")
## and to firmly CRADLE the ball's weight when held against it (resist sag).
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

## Bat collision/material tuning. High friction lets the bat grip and sling the ball rather than
## letting it skid; low bounce keeps the strike a clean momentum transfer, not a trampoline.
const BAT_FRICTION: float = 0.7
const BAT_BOUNCE: float = 0.05

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
## Unit hinge axis in this node's LOCAL space. The bat rotates about the surface normal (+Y).
const _HINGE_AXIS_LOCAL: Vector3 = Vector3(0.0, 1.0, 0.0)


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

	# Collision shape: a box centered at half-length so one end sits at the pivot (this node's
	# origin) and the other end is the tip at distance FLIPPER_LENGTH. The X offset SIGN is set by
	# _apply_handedness so a mirrored (right) flipper extends along -X (QA BUG-001).
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TableConfig.FLIPPER_LENGTH, TableConfig.FLIPPER_HEIGHT, TableConfig.FLIPPER_WIDTH)
	_shape.shape = box
	_body.add_child(_shape)

	# Gray-box mesh matching the collision box so the flipper is visible without art.
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "FlipperMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	_mesh_instance.mesh = box_mesh
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

	# Seat the bat box on the correct side of the pivot. The bat must reach FROM the pivot TOWARD the
	# table center: +X for the left flipper, -X for the mirrored right flipper. Without this the right
	# bat pointed AWAY from center (toward the right wall) and could never intercept a draining ball -
	# the inverted V could not form (QA BUG-001). Mirroring the angle alone is not enough; the lever
	# arm itself must flip. half_len keeps one end pinned at the pivot (this node's origin).
	var bat_offset_x: float = TableConfig.FLIPPER_LENGTH * 0.5 * hand_sign
	if _shape != null:
		_shape.position = Vector3(bat_offset_x, 0.0, 0.0)
	if _mesh_instance != null:
		_mesh_instance.position = Vector3(bat_offset_x, 0.0, 0.0)

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
## normal play (never called by production code). Pass with no argument is not allowed; callers state
## intent explicitly. Use clear_force_energized() to hand control back to the input action.
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
