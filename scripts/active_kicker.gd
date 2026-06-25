extends Area3D
## ActiveKicker - SHARED base for the active-kick furniture (pop bumpers AND slingshots).
##
## WHY THIS BASE EXISTS: pop bumpers and slingshots are the SAME mechanical family - an element
## that,
## on ball contact, fires the ball AWAY with a coded outward impulse (the developer's "contracts to
## shoot the ball away"), capped CCD-safe, with a minimum outgoing speed, scored once, behind a
## per-element cooldown. They differ ONLY in the KICK DIRECTION (a pop bumper kicks radially outward
## from its center; a slingshot kicks along a fixed face normal into play). Putting the shared cap +
## cooldown + score logic here means that load-bearing physics is written and tested ONCE, and the
## two concrete elements (pop_bumper.gd, slingshot.gd) only override _kick_direction_for(ball_pos).
##
## This mirrors the proven target.gd pattern (Area3D detector wrapping a solid StaticBody3D the ball
## bounces off) and extends it from PASSIVE (target: solver bounce only) to ACTIVE (this: solver
## bounce PLUS a coded impulse). See docs/ARCHITECTURE.md section 10 and docs/REFERENCES.md (the
## active-vs-passive finding).
##
## OWNERSHIP SPLIT (the one file two roles touch - kept DISJOINT by function, like target.gd):
##   Physics-programmer owns: _build_body() (the solid StaticBody3D + shape + PhysicsMaterial + the
##     no-tunnel guarantee), and _apply_kick() (the impulse math: direction * speed, the
##     KICK_MIN/MAX cap so the post-kick speed is inside the CCD-safe envelope). This is the
##     load-bearing correctness half.
##   Gameplay-programmer owns: _on_body_entered() detection, the KICK_COOLDOWN_S gating, and
##     scored.emit (the score-on-contact half).
## Concrete subclasses (pop_bumper.gd, slingshot.gd) own ONLY _kick_direction_for() and configure().
##
## STABLE CONTRACT (table.gd / tests depend on these byte-for-byte):
##   signal scored(points: int)              # emitted once per kick (cooldown-gated).
## signal kicked(direction: Vector3)       # emitted with the unit kick direction (for tests/juice).
##   func set_ball(ball: RigidBody3D) -> void
##   var points: int                         # flat score value.

signal scored(points: int)
signal kicked(direction: Vector3)

## Solid-body restitution for the KickerBody. The ACTIVE kick (_apply_kick) does the real work;
## this material only makes the instant of contact feel clean and live rather than dead. A moderate
## bounce gives the contact a crisp knock the same physics frame the kick fires. Not a trampoline:
## the velocity SET in _apply_kick is authoritative on the next step regardless.
const KICKER_BOUNCE: float = 0.5
## Solid-body friction. Low so a glancing ball slides off the face cleanly and the coded kick
## direction is not muddied by surface grip (a slingshot face should redirect, not grab).
const KICKER_FRICTION: float = 0.2

## Flat score value awarded per kick. Subclasses set this from their TableConfig score constant in
## configure(); default 100 keeps a stand-alone instance scoring something sane in a test.
@export var points: int = 100

## The live ball this kicker acts on. Only this body triggers a kick (set by table.gd via set_ball).
var _ball: RigidBody3D = null
## Absolute time (ms, Time.get_ticks_msec) before which new contacts are ignored. 0 = ready to fire.
## Gates BOTH the kick and the score (an active element re-kicking every frame would launch a
## resting ball at escape velocity - see KICK_COOLDOWN_S in TableConfig).
var _cooldown_until_ms: float = 0.0
## The solid body the ball physically bounces off, built by _build_body() (physics-programmer's
## half). Named "KickerBody" so the structural test resolves it via find_child("KickerBody", ...).
var _body: StaticBody3D = null


func _ready() -> void:
	# Detector setup, identical pattern to target.gd: the Area3D is on NO collision layer (the solid
	# the physics solver sees is the child StaticBody3D), and monitors the BALLS layer so body_entered
	# fires on ball contact. The score-and-kick event is that body_entered.
	collision_layer = 0
	collision_mask = PhysicsLayers.BALLS

	# Build the detector volume (slightly larger than the solid body so body_entered fires as the ball
	# approaches), the gray-box mesh, and the solid bounce body. Subclasses may have set geometry via
	# configure() before _ready; _build_detector_and_mesh reads the resolved geometry.
	_build_detector_and_mesh()
	_build_body()

	body_entered.connect(_on_body_entered)


## Register the live ball. Only this body triggers a kick/score. STABLE SIGNATURE.
func set_ball(ball: RigidBody3D) -> void:
	_ball = ball


## GAMEPLAY-PROGRAMMER's half: detection + cooldown gating + score, then ASK physics to kick.
## On the ball's contact, if the cooldown is clear: start the cooldown, compute the kick direction
## (subclass), apply the impulse (physics half), emit kicked + scored. The cooldown gates BOTH so a
## resting ball is pushed off once, not strobed (no machine-gun farming - DESIGN must-feel #2).
func _on_body_entered(body: Node) -> void:
	if body != _ball:
		return

	var now_ms: float = float(Time.get_ticks_msec())
	if now_ms < _cooldown_until_ms:
		return

	# CONTACT GATE: the detector is now the EXACT body shape (no proximity padding), so body_entered
	# fires at real contact. A subclass may still REJECT a contact by where it landed - a slingshot
	# only kicks off its band, not its posts/back (developer: "it should be a true contact point").
	if not _contact_should_kick(_ball.global_position):
		return

	_cooldown_until_ms = now_ms + TableConfig.KICK_COOLDOWN_S * 1000.0

	# Direction is the ONLY thing that differs between a pop bumper and a slingshot.
	var direction: Vector3 = _kick_direction_for(_ball.global_position)
	_apply_kick(direction)
	kicked.emit(direction)
	scored.emit(points)


## SUBCLASS OVERRIDE: given where the ball is at contact (global), should this contact fire a kick?
## The base accepts every contact (a pop bumper kicks off any point of its round body). The
## slingshot overrides this to accept only contacts on its kicking BAND, so a ball touching the
## posts or the back of the triangle bounces passively instead of triggering the solenoid.
func _contact_should_kick(_ball_pos: Vector3) -> bool:
	return true


## SUBCLASS OVERRIDE: the unit kick direction for a contact at ball_pos (playfield-local or world
## per
## the subclass's convention; both subclasses compute in the same space the ball reports). The base
## returns up_table_local() as a safe default so an un-overridden kicker still fires INTO play,
## never
## at the drain. pop_bumper.gd returns radially outward from its center; slingshot.gd returns its
## fixed face normal.
func _kick_direction_for(_ball_pos: Vector3) -> Vector3:
	return TableConfig.up_table_local()


## PHYSICS-PROGRAMMER's half (TODO): apply the active impulse along `direction` (a unit vector).
##
## REQUIRED BEHAVIOR (the behavioral + stress tests assert all of these against the REAL ball's
## measured velocity - independent oracle):
##   1. ACTIVE: even a ball arriving SLOWLY leaves FAST along `direction`. Set/boost the ball's
##      velocity so its component along `direction` is at least TableConfig.KICK_MIN_OUTGOING_SPEED.
##      Target TableConfig.KICK_IMPULSE_SPEED as the nominal outgoing speed.
##   2. CAPPED (CCD-SAFE): the resulting speed must NOT exceed TableConfig.KICK_MAX_OUTGOING_SPEED.
##      Clamp it. This is the no-tunneling guarantee for a STACKED kick (ball already fast, then
##      kicked): the cap keeps the post-kick speed strictly inside the band the stress tests prove
##      safe (stress fires at >= 2x LAUNCH_SPEED_MAX = 180; the cap is well under that).
##   3. DIRECTED: the outgoing velocity points along `direction` (into play), so the kicked test
##      can assert vz < 0 (up-table) and the toward-center X sign.
##
## IMPLEMENTATION NOTE: prefer setting the ball's velocity to direction * clamp(target, MIN, MAX)
## rather than apply_central_impulse, because a fixed impulse on a fast incoming ball can overshoot
## the cap or, head-on, leave net speed below the floor. A direct velocity set along `direction`
## makes the floor and cap exact and keeps the kick LEGIBLE (always away from the element). The
## solid
## body's PhysicsMaterial still gives the contact a clean feel; this set is the ACTIVE part on top.
## Document the WHY of whatever you choose. Do NOT leave this as a velocity helper the plunger-style
## "fake launch" - here a coded velocity IS the intended physical kick (an active solenoid).
func _apply_kick(direction: Vector3) -> void:
	# PHYSICS-PROGRAMMER's half. The active solenoid: SET the ball's velocity along `direction` at a
	# clamped target speed. WHY a velocity SET, not apply_central_impulse (the scaffold note's
	# recommendation, confirmed): a fixed impulse on a fast incoming ball overshoots the CCD-safe cap,
	# and a head-on impulse can leave the net speed below the floor (the impulse fighting the incoming
	# velocity). A direct velocity set makes the floor and cap EXACT and the kick LEGIBLE - the ball
	# always leaves AWAY from the element at a known speed, which is what an active kicker is.
	if _ball == null:
		return

	# Guard a degenerate direction so the kick is never a zero/NaN velocity (the subclasses already
	# fall back to up_table for a zero vector, but normalize defensively here too).
	var dir: Vector3 = direction
	if not is_finite(dir.x) or not is_finite(dir.y) or not is_finite(dir.z) or dir.length() < 0.0001:
		dir = TableConfig.up_table_local()
	dir = dir.normalized()

	# Target outgoing speed = the nominal kick speed, clamped into [MIN, MAX]. The clamp is the
	# load-bearing safety: MAX is the CCD-safe cap (well under the 2x-LAUNCH stress band), so even a
	# STACKED kick (a ball that arrived fast and is kicked again) can never leave above the speed the
	# no-tunneling stress test proves safe. MIN is the design's "a crawl still comes out fast enough
	# to travel" floor - because we SET (not add) the speed, the floor is guaranteed regardless of how
	# fast or slow, or in what direction, the ball arrived.
	var target_speed: float = clampf(
		TableConfig.KICK_IMPULSE_SPEED,
		TableConfig.KICK_MIN_OUTGOING_SPEED,
		TableConfig.KICK_MAX_OUTGOING_SPEED,
	)

	# Wake the ball (a ball that fell asleep resting against the element must move on the kick) and
	# set the outgoing velocity. Angular velocity is zeroed so the kick is a clean directed launch,
	# not a launch-plus-spin that could send the ball off-line.
	_ball.sleeping = false
	_ball.linear_velocity = dir * target_speed
	_ball.angular_velocity = Vector3.ZERO


## PHYSICS-PROGRAMMER's half: build the solid StaticBody3D the ball physically bounces off.
##
## The structural test resolves this by name: find_child("KickerBody", true, false). It is on
## STATIC_OBSTACLES (collision_mask 0: a static body is only collided WITH), which the ball already
## hits via BALL_COLLISION_MASK - so NO layer/mask change anywhere (the shared-physics audit result:
## the flipper/wall tests cannot regress from a layer edit because there is none).
##
## NO-TUNNEL: the body is STATIC and the ball carries continuous_cd, so the swept CCD test catches
## the contact even at >= 2x LAUNCH_SPEED_MAX. The shape stands KICKER height (>= ball diameter) so
## the ball cannot ride up and over it. test_active_kicker_no_tunneling.gd proves this against the
## REAL instanced body. The post-kick speed is capped (see _apply_kick) so a STACKED kick can never
## re-launch the ball above the proven-safe band.
func _build_body() -> void:
	_body = StaticBody3D.new()
	_body.name = "KickerBody"
	# STATIC_OBSTACLES, exactly like the walls/arch/target deflector. collision_mask 0: it scans
	# nothing, it is only collided with.
	_body.collision_layer = PhysicsLayers.STATIC_OBSTACLES
	_body.collision_mask = 0

	# A slingshot's flat face must angle into play; _body_yaw() returns the yaw (0 for a round pop
	# bumper). Rotate the SOLID body about its local Y so the face normal aligns with the kick
	# direction. The DETECTOR shell is rotated to MATCH (by _detector_yaw, default = _body_yaw) in
	# _build_detector_and_mesh, so it encloses the yawed solid body at every contact angle (QA BUG-018:
	# an axis-aligned detector let a yawed corner poke past it and miss body_entered). For a round pop
	# bumper both yaws are 0, so nothing rotates.
	_body.transform = Transform3D(Basis(Vector3(0.0, 1.0, 0.0), _body_yaw()), Vector3.ZERO)

	# LOCAL PhysicsMaterial (not shared/global): a clean contact feel. The coded kick is the active
	# part on top.
	var material := PhysicsMaterial.new()
	material.bounce = KICKER_BOUNCE
	material.friction = KICKER_FRICTION
	_body.physics_material_override = material

	# The solid shape from the subclass: a CylinderShape3D for a pop bumper, a BoxShape3D for a sling.
	var col := CollisionShape3D.new()
	col.shape = _make_body_shape()
	_body.add_child(col)

	# TEMP DEBUG (remove after diagnosis): draw the ACTUAL collision hull as a bright unshaded mesh so
	# it can be compared to the visual slingshot in a screenshot (the ball-pass-through report).
	var dbg := MeshInstance3D.new()
	dbg.mesh = col.shape.get_debug_mesh()
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.0, 0.1, 0.1)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dbg.material_override = dm
	col.add_child(dbg)

	add_child(_body)


## Build the Area3D DETECTOR shape (slightly larger than the solid body so body_entered fires on
## approach) and a gray-box mesh. Shared boilerplate (not a feel knob), so it lives in the base. The
## detector shape comes from _make_detector_shape() (overridden by the subclass). The physics-
## programmer may move this into _build_body if convenient; keep the detector at least one
## BALL_RADIUS
## larger than the solid body so body_entered fires before the ball center reaches the surface.
func _build_detector_and_mesh() -> void:
	# Detector volume: a CollisionShape3D from the subclass shape, so body_entered fires on contact.
	# This is shared boilerplate (mirrors target.gd), so the lead implements it here; the physics
	# half is _build_body (the solid the ball bounces off) and _apply_kick (the impulse). With this
	# built, the behavioral tests isolate the physics half cleanly: a missing kick shows up as "no
	# outgoing velocity", not as "no contact detected".
	var col := CollisionShape3D.new()
	col.shape = _make_detector_shape()
	# Rotate the detector to match the solid body's yaw (QA BUG-018). For a round pop bumper the yaw is
	# 0 (no effect). For a slingshot the SOLID body is a box rotated by _body_yaw so its face angles
	# into play; if the detector stayed axis-aligned, the rotated body's corners could poke up to ~0.8
	# units PAST the unrotated detector volume (larger than BALL_RADIUS), so a ball striking a corner
	# of the angled face entered the solid body WITHOUT tripping body_entered - the active kick + score
	# silently never fired (the dreaded "limp bounce" the active element exists to prevent). Rotating
	# the detector by the same yaw keeps it concentric with and enclosing the solid body at every
	# contact angle, so any corner contact also trips the detector.
	col.transform = Transform3D(Basis(Vector3(0.0, 1.0, 0.0), _detector_yaw()), Vector3.ZERO)
	add_child(col)

	# Gray-box mesh so the element is visible without art. The MESH comes from _make_mesh() so a
	# subclass can make the visible shape AGREE with its solid body (DESIGN: the slingshot mesh must be
	# the same TRIANGLE as its collider, not a generic box). The base returns a simple box (fine for a
	# round pop bumper at gray-box stage); slingshot.gd overrides it with a triangular prism mesh.
	# WHY the mesh is on the kicker root (not the rotated KickerBody): the base draws it axis-aligned;
	# a subclass whose mesh must follow the body yaw (the slingshot) bakes that yaw into _make_mesh or
	# rotates the returned MeshInstance - see slingshot.gd. Kept overridable so body and mesh agree.
	var mesh_instance: MeshInstance3D = _make_mesh()
	mesh_instance.name = "KickerMesh"
	add_child(mesh_instance)


## SUBCLASS OVERRIDE: the solid body collision shape (CylinderShape3D for a pop bumper, BoxShape3D
## for
## a slingshot), sized from the subclass's TableConfig geometry. The base returns a small cylinder
## so a
## bare instance is valid. The physics-programmer's _build_body reads this.
func _make_body_shape() -> Shape3D:
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = TableConfig.WALL_HEIGHT
	return shape


## SUBCLASS OVERRIDE: the detector shape (one BALL_RADIUS larger than the body shape so body_entered
## fires on approach). The base returns a slightly larger cylinder matching _make_body_shape
## default.
func _make_detector_shape() -> Shape3D:
	var shape := CylinderShape3D.new()
	shape.radius = 1.0 + TableConfig.BALL_RADIUS
	shape.height = TableConfig.WALL_HEIGHT
	return shape


## SUBCLASS OVERRIDE: the gray-box VISIBLE mesh, so the visible element AGREES with its solid body.
## The base returns a simple box MeshInstance3D (fine for a round pop bumper placeholder). The
## slingshot overrides this to return a TRIANGULAR prism mesh matching its triangular collider,
## yawed/mirrored per side (a slingshot must READ as a triangle, not a box). The returned
## MeshInstance3D is added to the kicker root by _build_detector_and_mesh (it sets the name).
func _make_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, TableConfig.WALL_HEIGHT, 1.0)
	mesh_instance.mesh = box_mesh
	return mesh_instance


## SUBCLASS OVERRIDE: yaw (radians, about local Y) to rotate the solid body so a flat slingshot face
## angles into play. A pop bumper is round, so the base returns 0 (no rotation needed).
func _body_yaw() -> float:
	return 0.0


## Yaw (radians, about local Y) applied to the DETECTOR shape so it tracks the solid body's
## orientation (QA BUG-018). The base ties it to _body_yaw() so the detector always encloses the
## body: a round pop bumper yields 0 (axis-aligned, unchanged); a rotated slingshot face yields its
## body yaw so corner contacts still trip body_entered. A subclass with a deliberately rotation-
## invariant detector (e.g. a cylinder) may override to 0; the default is the safe, enclosing one.
func _detector_yaw() -> float:
	return _body_yaw()
