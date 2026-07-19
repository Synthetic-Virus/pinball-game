extends Node3D
## Plunger - the launch control: hold to charge an OSCILLATING power meter, release to STRIKE.
##
## OWNERSHIP: gameplay-programmer owns the charge/oscillation logic and the power->stroke mapping;
## physics-programmer owns the physical strike (the AnimatableBody3D stroke + no-tunneling).
##
## WHAT CHANGED (and WHY): the plunger used to be a bare Node3D that called ball.launch(), which SET
## the ball's velocity directly in code (a fake plunger). The developer wanted a PHYSICAL device
## that STRIKES the ball and transfers momentum through the collision. So the plunger now builds an
## AnimatableBody3D face (KINEMATIC_OBSTACLES layer, like the flippers' kinematic-but-driven bats)
## seated in the launch lane just down-table of the resting ball. On release it is DRIVEN up-table
## (local -Z) at a stroke speed mapped from the power meter; the moving face collides with the ball
## and throws it. No code ever sets the ball's velocity now - the contact does, like a real plunger.
##
## LAUNCH MECHANISM FIX (SLICE "Table reshape + playtest fixes", 2026-06-19, ARCHITECTURE.md 11.2):
## ROOT CAUSE of the dead plunger in the deployed build: the face relied on sync_to_physics to shove
## the resting ball during its forward stroke. In Godot's built-in Jolt that transform-derived
## velocity does NOT reliably transfer to a resting (or sleeping) body in contact, so the ball never
## moved. FIX (option (c) in 11.2 - an IMPULSE ON CONTACT): we keep the physical face stroking
## forward (it is the CCD-safe solid barrier that also stops the ball tunnelling backward), and on
## the forward stroke we apply a central IMPULSE to the ball SIZED from the stroke speed, but ONLY
## once we have CONFIRMED the face is actually TOUCHING the ball (the ball's own contact monitor
## reports the PlungerFace as a contact). This is a genuine CONTACT event, not a free velocity set:
## no contact => no launch (a release with no ball, or a ball not seated against the face, does
## nothing). We never call ball.launch() (QA BUG-017 stays honored). The impulse is the
## deterministic momentum transfer Jolt's animated-body contact does not give us for free.
##
## FEEL TARGET (DESIGN.md "LAUNCH SKILL"): the meter sweeps fast enough to matter, slow enough to
## aim - a full 0..1..0 sweep on the order of 0.5-1.0 s. Released power visibly maps to launch
## strength (the resulting ball speed lands in TableConfig.LAUNCH_SPEED_MIN..MAX). Polled each
## physics frame (same pattern as flipper input, zero lag).
##
## OSCILLATION MATH: _charge_phase advances by delta * CHARGE_RATE each frame while the button is
## held. pingpong(_charge_phase, 1.0) maps the unbounded phase to a 0..1..0 triangle wave. One full
## triangle (0->1->0) completes when phase crosses 2.0, which takes 2.0 / CHARGE_RATE seconds.
## At CHARGE_RATE = 2.5: full sweep = 2.0/2.5 = 0.8 s. This sits in the 0.5-1.0 s target range.
##
## STROKE MODEL: on release we latch a target stroke speed (from power) and a stroke direction
## (up-table), then in _physics_process we move the AnimatableBody3D face forward at that speed each
## frame until it has travelled PLUNGER_STROKE_LENGTH, then drive it back to rest. While the face is
## stroking forward AND is confirmed in contact with the ball, we apply ONE central impulse to the
## ball (sized from the stroke speed) so the launch momentum comes from that contact (see the LAUNCH
## MECHANISM FIX note above; the old sync_to_physics transfer was unreliable in Jolt). The signal
## ball_launched fires the moment the stroke begins (the player committed the launch), as before.
##
## STATE: the plunger is only active when ARMED (a fresh ball is waiting in the lane). GameFlow arms
## it via arm(); a release fires the stroke, disarms, and emits ball_launched.
##
## STABLE CONTRACT (table.gd / GameFlow / tests depend on these - signatures unchanged):
##   signal power_changed(power: float)   # 0..1 each frame while charging, for the HUD meter.
##   signal ball_launched()               # emitted the frame the strike begins.
##   func arm() -> void                    # enable charging for the waiting ball.
##   func disarm() -> void                 # disable (e.g. on drain mid-charge).
##   func set_ball(ball: RigidBody3D) -> void  # the ball this plunger strikes.
##   func is_armed() -> bool

signal power_changed(power: float)
signal ball_launched()

## Stroke phase machine. IDLE = parked at rest; FORWARD = driving up-table into the ball; RETURN =
## driving back down-table to the rest position. (Declared here so the gdlint definitions-order rule
## is satisfied: enums precede consts.)
enum StrokeState { IDLE, FORWARD, RETURN }

## --- PROCEDURAL LAUNCHER ART + COSMETIC JUICE (SLICE "Kenney 3D asset integration", 2026-07) ---
## The launch lane shows a PROCEDURAL low-poly launcher built in code (the imported launcher.glb was
## RETIRED this slice): a static HOUSING channel behind the ball plus a moving plunger GROUP (rod +
## tip) and a compressible SPRING. It is styled from Palette.HARDWARE (a single grey colour source;
## table_reskin.gd deliberately never repaints the plunger, so this material is authoritative). The
## art is VISUAL ONLY and DECOUPLED from the physics strike: the AnimatableBody3D _face (above) is
## the ONLY thing that touches the ball (QA BUG-017/025 honored - no ball.launch(), no velocity).
## The juice below animates only the moving-group / spring Node3Ds; a behavioral test asserts the
## launched ball's velocity is IDENTICAL with the juice on vs off (the decoupling oracle).
##
## CHARGE/RELEASE JUICE (script-driven from the charge value, interactive, NOT an AnimationPlayer):
##   - While charging, the moving group slides BACK (down-table) proportional to the live power, and
##     the spring compresses (scales down its long axis). The player sees the plunger pull back as
##     they charge - the visible analogue of the meter.
##   - On release, the moving group + spring FOLLOW the real physical stroke each frame (see
##     _drive_launch_visual), so the visible plunger fires WITH the launch. Decoupled: cannot move
##     the ball.

## The node name the procedural launcher visual is instanced under (tests resolve the visual by it).
const LAUNCHER_VISUAL_NODE_NAME: String = "LauncherVisual"

## Names of the procedural Node3Ds the juice drives (visual only). Plunger_Anim is the empty
## parenting the moving rod + tip; Plunger_Spring is the coil that compresses. Built by
## _build_launcher_art; if either is absent the juice degrades to a safe no-op (launch unchanged).
const PLUNGER_ANIM_NODE: String = "Plunger_Anim"
const PLUNGER_SPRING_NODE: String = "Plunger_Spring"

## How far (world units) the moving plunger group slides BACK at full charge. Sized off the ball
## radius so it scales with the world, never a bare literal. The slide is purely cosmetic.
const JUICE_PULL_BACK: float = TableConfig.BALL_RADIUS * 1.6
## How much the spring compresses (fraction of its rest long-axis scale removed) at full charge.
const JUICE_SPRING_COMPRESS: float = 0.45

## How fast the meter oscillates. CHARGE_RATE of 2.5 makes a full 0->1->0 sweep take 0.8 s,
## which sits comfortably in the DESIGN feel target of 0.5-1.0 s.
## Formula: sweep_time = 2.0 / CHARGE_RATE.
const CHARGE_RATE: float = 2.5
## Return-stroke speed: brisk but never fast enough to itself re-hit and re-launch a ball that has
## already left, and slow enough that the returning face cannot tunnel anything (it moves into an
## empty lane). Half the max stroke speed is a safe, simple choice.
const RETURN_SPEED: float = TableConfig.PLUNGER_STROKE_SPEED_MAX * 0.5

## DECOUPLING SEAM: when true, the cosmetic juice is suppressed (the visual never animates). A
## behavioral test launches once with this false and once with it true and asserts the launched ball
## velocity is IDENTICAL, proving the juice never moves the ball. INERT in play (never set).
var _suppress_juice: bool = false
## The procedural launcher visual root (built in _build_launcher_art). The juice drives the moving
## group + spring UNDER this; nothing here is ever a collider (VISUAL only).
var _launcher_visual: Node3D = null
## The launcher is built at world scale (1.0), kept as a field so the juice math divides world-unit
## slide distances into the visual's own local space consistently (see _apply_charge_visual).
var _launcher_scale: float = 1.0
## Handles to the moving group + spring built by _build_launcher_art. Their authored rest transforms
## are captured as the baseline the juice animates from and returns to.
var _anim_group: Node3D = null
var _spring: Node3D = null
var _anim_rest_pos: Vector3 = Vector3.ZERO
var _spring_rest_scale: Vector3 = Vector3.ONE

var _armed: bool = false
var _charging: bool = false
var _charge_phase: float = 0.0
var _power: float = 0.0
var _ball: RigidBody3D = null
## Release latch (QA BUG-008): when a ball arms while the player still happens to be holding
## "launch" (e.g. held through the previous ball draining), we must NOT start charging on a held key
## the player never pressed for THIS ball. We require a release first: charging is blocked until the
## action has been seen released once since arm(). Set false by arm(), true on the first release.
var _release_seen: bool = false
## --- Physical strike state ---------------------------------------------------------------------
## The driven face. An AnimatableBody3D on KINEMATIC_OBSTACLES: the player cannot push it, but its
## scripted motion is reported to the solver so it strikes the ball with real momentum.
var _face: AnimatableBody3D = null
var _stroke_state: int = StrokeState.IDLE
## Speed (u/s) of the current forward stroke, latched from power on release.
var _stroke_speed: float = 0.0
## How far the face has travelled up-table from rest this stroke (world units).
var _stroke_travelled: float = 0.0
## Whether the launch impulse has already been delivered this stroke. The impulse fires EXACTLY ONCE
## per forward stroke, the first frame the face is confirmed in contact with the ball, so a long
## stroke cannot pump the ball repeatedly (no machine-gun launch). Reset at the start of a stroke.
var _impulse_applied: bool = false


func _ready() -> void:
	_build_face()
	_build_launcher_art()


## Build the physical plunger face: an AnimatableBody3D box on the KINEMATIC_OBSTACLES layer, seated
## at TableConfig.PLUNGER_REST_POS in the launch lane just down-table of the resting ball. Built in
## code (like the flippers) so it stays in scale with TableConfig and needs no scene authoring.
## Idempotent: only builds once.
func _build_face() -> void:
	if _face != null:
		return

	_face = AnimatableBody3D.new()
	_face.name = "PlungerFace"
	# KINEMATIC_OBSTACLES, mask = balls only: it pushes the ball, nothing else (matches flippers).
	_face.collision_layer = PhysicsLayers.KINEMATIC_OBSTACLES
	_face.collision_mask = PhysicsLayers.KINEMATIC_COLLISION_MASK
	# sync_to_physics is deliberately OFF (QA BUG-025). The launch momentum comes SOLELY from the
	# explicit impulse in _try_apply_launch_impulse (the reliable mechanism this slice adopted because
	# Jolt's animated-body contact transfer is unreliable - see the LAUNCH MECHANISM FIX note above).
	# Leaving sync_to_physics ON would ADD the solver's contact-velocity transfer ON TOP of that
	# impulse whenever Jolt DOES resolve the contact, double-counting the launch energy: at full power
	# the ball could leave at ~2x PLUNGER_STROKE_SPEED_MAX (~216 u/s after the "Fix the launch" slice
	# raised the stroke max to 108), far above the intended LAUNCH_SPEED_MIN..MAX band. With sync OFF
	# the face is still a SOLID moving barrier (its collision shape blocks the ball and backs up the
	# ball's CCD so the struck ball cannot tunnel backward); it simply does not report velocity to the
	# solver, so the impulse is the one and only momentum source. ONE mechanism, no double-count.
	_face.sync_to_physics = false

	# Low bounce, some friction: a clean momentum transfer, not a trampoline (mirrors the steel ball).
	var material := PhysicsMaterial.new()
	material.bounce = 0.1
	material.friction = 0.4
	_face.physics_material_override = material

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		TableConfig.PLUNGER_FACE_WIDTH,
		TableConfig.PLUNGER_FACE_HEIGHT,
		TableConfig.PLUNGER_FACE_THICKNESS
	)
	col.shape = box
	_face.add_child(col)

	# Gray-box mesh matching the collision box so the plunger is visible without art.
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PlungerMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh_instance.mesh = box_mesh
	_face.add_child(mesh_instance)

	add_child(_face)
	# Seat at rest. PLUNGER_REST_POS is a playfield-local coordinate; table.gd parents this Plunger
	# node at the playfield origin (position ZERO), so the face's local position IS the field coord.
	_face.position = TableConfig.PLUNGER_REST_POS


## Register the ball that this plunger will strike. Called by table.gd when it builds the scene.
## STABLE SIGNATURE.
func set_ball(ball: RigidBody3D) -> void:
	_ball = ball


## Arm for a fresh ball. Resets oscillation so every launch starts from the same baseline.
## Called by GameFlow via table.gd when request_new_ball fires. STABLE SIGNATURE.
func arm() -> void:
	_armed = true
	_charging = false
	_charge_phase = 0.0
	_power = 0.0
	# Require the player to RELEASE before this ball can charge. If "launch" is already held at arm
	# time (held through the previous drain), _physics_process will wait for a release rather than
	# auto-charging a key the player never pressed for this ball (QA BUG-008). A press from a clean
	# released state is allowed immediately.
	_release_seen = not Input.is_action_pressed("launch")
	# Emit immediately so the HUD meter resets to zero on the same frame the ball resets.
	power_changed.emit(0.0)
	# Cosmetic: seat the moving plunger group at rest (no pull-back) when a fresh ball arms.
	_apply_charge_visual(0.0)


## Disarm the plunger. Called if the ball drains before it was launched (rare but possible if a
## stray ball reaches the drain during a charge), or on game over. STABLE SIGNATURE.
func disarm() -> void:
	_armed = false
	_charging = false
	# Zero the meter so the HUD bar does not freeze at its last power reading.
	power_changed.emit(0.0)


## True when a ball is waiting and the player can charge. STABLE SIGNATURE.
func is_armed() -> bool:
	return _armed


func _physics_process(delta: float) -> void:
	# Always advance an in-progress stroke FIRST, even after disarm: once the player releases we have
	# committed the strike and the face must finish driving forward and returning to rest, regardless
	# of armed state. The charge/input handling below only runs while armed.
	if _stroke_state != StrokeState.IDLE:
		_advance_stroke(delta)

	# Only handle input when a ball is actually waiting in the lane.
	if not _armed:
		return

	# Null guard: if table.gd has not called set_ball() yet, do nothing rather than crashing.
	if _ball == null:
		return

	var holding: bool = Input.is_action_pressed("launch")

	# Latch the first release after arm(). Until we have seen the key released once, a held key is
	# stale input from before this ball armed and must not charge (QA BUG-008).
	if not holding:
		_release_seen = true

	if holding and _release_seen:
		# Build up the oscillating charge phase each physics frame.
		# pingpong maps the unbounded _charge_phase to a triangle wave on [0, 1].
		_charging = true
		_charge_phase += delta * CHARGE_RATE
		_power = pingpong(_charge_phase, 1.0)
		# Emit every frame so the HUD meter animates smoothly.
		power_changed.emit(_power)
		# COSMETIC: slide the moving plunger group back + compress the spring proportional to the live
		# power. Visual only - this drives nodes under the imported subtree, never the ball.
		_apply_charge_visual(_power)
	elif _charging:
		# The player just released (was holding last frame, no longer holding this frame).
		# This is the launch moment: use whatever power the meter is at right now.
		_do_launch()


## Map the current power level to a STROKE SPEED and begin the physical strike.
## Called on the frame the player releases the launch button. STABLE behaviour (still disarms and
## emits ball_launched on this frame), but it no longer sets the ball's velocity: it starts the face
## driving up-table so the CONTACT throws the ball.
func _do_launch() -> void:
	# Clamp _power to [0,1] defensively; pingpong should never exceed this but clamp is cheap.
	var clamped_power: float = clampf(_power, 0.0, 1.0)

	# Map power to the forward stroke speed: 0.0 -> STROKE_SPEED_MIN (dribble), 1.0 -> STROKE_SPEED_MAX
	# (hard strike). The resulting BALL speed after the contact lands roughly in LAUNCH_SPEED_MIN..MAX
	# (see TableConfig WHY notes); tests assert the mapping is monotonic and the ball ends up in-range.
	_stroke_speed = lerpf(
		TableConfig.PLUNGER_STROKE_SPEED_MIN,
		TableConfig.PLUNGER_STROKE_SPEED_MAX,
		clamped_power
	)
	# Begin the forward stroke. _advance_stroke() drives the face from _physics_process each frame and
	# delivers the launch impulse once the face is confirmed touching the ball.
	_stroke_travelled = 0.0
	_impulse_applied = false
	_stroke_state = StrokeState.FORWARD

	# Release JUICE is driven by _drive_launch_visual() each stroke frame: the rod + spring follow the
	# REAL stroke (the collision face moving forward), so the visible plunger moves WITH the launch
	# (developer: "the launcher isn't moving enough"). This is the ONLY release-juice path - it drives
	# only visual nodes, never the ball, so the launch stays decoupled (the decoupling oracle).

	# Wake the ball if it has fallen asleep resting against the face, so the moving face's contact is
	# registered this step. This does NOT set the ball's velocity (the contact still does that, keeping
	# the plunger physical); it only clears the sleep flag so a cradled ball cannot be struck while
	# asleep and miss the momentum transfer.
	if _ball != null:
		_ball.sleeping = false

	# Disarm before emitting so any listener that checks is_armed() sees the correct state.
	_armed = false
	_charging = false
	_charge_phase = 0.0
	_power = 0.0

	# Zero the meter bar immediately on launch.
	power_changed.emit(0.0)

	# Notify GameFlow (-> BALL_IN_PLAY) and any other listener. Fired as the strike begins: the player
	# has committed the launch, matching the old timing where launch() was called on this frame.
	ball_launched.emit()


## Drive the AnimatableBody3D face one physics frame of its stroke. Called from _physics_process
## while a stroke is active. FORWARD moves the face up-table (-Z) at _stroke_speed until it has
## travelled PLUNGER_STROKE_LENGTH; on the first forward frame the face is confirmed TOUCHING the
## ball, it delivers the launch impulse (see _try_apply_launch_impulse). RETURN drives it to rest.
## The moving face also remains a solid physical barrier (KINEMATIC_OBSTACLES + the ball's CCD), so
## the struck ball cannot tunnel backward through the plunger.
func _advance_stroke(delta: float) -> void:
	if _face == null:
		_stroke_state = StrokeState.IDLE
		return

	# Up-table is local -Z. We move along the playfield-local axis; the face's parent (this node) sits
	# at the playfield origin so local motion is playfield-space motion.
	var up_table: Vector3 = TableConfig.up_table_local()

	if _stroke_state == StrokeState.FORWARD:
		# Deliver the launch impulse on the contact (once per stroke), BEFORE moving the face this
		# frame: the ball starts seated against the face, so the contact is already present on frame 1.
		_try_apply_launch_impulse(up_table)

		var step: float = _stroke_speed * delta
		# Do not overshoot the full stroke length in the final frame.
		var remaining: float = TableConfig.PLUNGER_STROKE_LENGTH - _stroke_travelled
		if step >= remaining:
			step = remaining
			_stroke_state = StrokeState.RETURN
		_face.position += up_table * step
		_stroke_travelled += step
	elif _stroke_state == StrokeState.RETURN:
		# Drive back down-table toward the rest position at the (gentler) return speed.
		var rest: Vector3 = TableConfig.PLUNGER_REST_POS
		var to_rest: Vector3 = rest - _face.position
		var step: float = RETURN_SPEED * delta
		if step >= to_rest.length():
			# Snap exactly to rest and finish; the small final correction is below any tunneling risk.
			_face.position = rest
			_stroke_state = StrokeState.IDLE
		else:
			_face.position += to_rest.normalized() * step
	# Drive the VISIBLE rod/tip/clip + spring to follow the stroke (developer: the push rod must move
	# WITH the spring during the launch, not stay still while only the collision face moves).
	_drive_launch_visual()


## Make the visible rod + tip group + spring follow the launch stroke, so the plunger moves WITH the
## launch instead of staying still while only the invisible collision face strokes. Driven from the
## face's forward offset from rest, mapped into the launcher's local +X (up-table). VISUAL only.
func _drive_launch_visual() -> void:
	if _anim_group == null or _face == null or _launcher_scale < 0.0001:
		return
	var fwd_world: float = TableConfig.PLUNGER_REST_POS.z - _face.position.z
	_anim_group.position = _anim_rest_pos + Vector3(fwd_world / _launcher_scale, 0.0, 0.0)
	if _spring != null:
		_spring.scale = _spring_rest_scale  ## the coil relaxes back to its rest length as it fires


## Apply the launch impulse to the ball ONCE per forward stroke, the first frame the face is
## confirmed TOUCHING the ball. This is the launch (ARCHITECTURE.md 11.2 option (c)): the momentum
## comes from a physics impulse gated on the real contact, NOT from a velocity set on the ball
## (ball.launch() stays unused - QA BUG-017) and NOT from the unreliable sync_to_physics transfer
## that left the deployed plunger dead.
##
## SIZING: the ball starts at rest, so an impulse of mass * target_speed leaves it moving at
## target_speed. We target the ball speed = _stroke_speed (a head-on strike of a low-restitution
## steel ball leaves at ~the face speed), preserving the existing power -> ball-speed mapping
## (PLUNGER_STROKE_SPEED_MIN..MAX -> ~LAUNCH_SPEED_MIN..MAX). Direction is up-table (the stroke
## direction), so the launch is straight up the lane into the arch.
##
## NO-CONTACT IS A NO-OP: if there is no ball, or the ball is not seated against the face (e.g. a
## release with the ball already gone), is_touching() is false and no impulse is applied - exactly
## the "a release with no ball does nothing" contract.
func _try_apply_launch_impulse(up_table: Vector3) -> void:
	if _impulse_applied:
		return
	if _ball == null or _face == null:
		return
	# Confirm a REAL physics contact between the ball and this plunger face (independent oracle: the
	# contact physically exists or it does not). Requires the ball's contact_monitor (ball.gd._ready).
	if not _ball.has_method("is_touching") or not _ball.is_touching(_face):
		return

	# Wake the ball so the impulse takes effect this step (a cradled ball may have slept).
	_ball.sleeping = false
	# apply_central_impulse expects a WORLD-space vector, but up_table is a PLAYFIELD-LOCAL direction
	# (0,0,-1). The playfield is tilted TILT_DEG about X, so we must rotate the local up-table axis
	# into world space through this node's global basis (the Plunger sits at the playfield origin with
	# no local rotation, so its global basis IS the tilted playfield's basis). Without this the impulse
	# would point along world -Z and ignore the tilt, nudging the ball into/out of the surface.
	var up_table_world: Vector3 = (global_transform.basis * up_table).normalized()
	# impulse = mass * desired_velocity_change; from rest this yields a launch speed of _stroke_speed.
	var impulse: Vector3 = up_table_world * (_ball.mass * _stroke_speed)
	_ball.apply_central_impulse(impulse)
	_impulse_applied = true


## TEST HOOK (headless GUT cannot hold a key across physics frames, mirroring the flipper hook).
## Begin a strike at an explicit power [0,1], exactly as a release at that power would. Inert in
## play: production code never calls it; the input poll in _physics_process is the only player path.
## Returns nothing; the caller steps physics frames and measures the REAL ball (independent oracle).
func test_strike_at_power(power: float) -> void:
	_power = clampf(power, 0.0, 1.0)
	_do_launch()


## TEST HOOK: read the face's current local position so a test can assert no-tunneling positionally
## (the ball must end up up-table of the face, never behind it). Returns the rest position if the
## face has not been built yet.
func face_position() -> Vector3:
	if _face == null:
		return TableConfig.PLUNGER_REST_POS
	return _face.position


## TEST HOOK: true while a strike stroke (forward or return) is still in progress. A test waits on
## this going false to know the strike has fully resolved before measuring.
func is_stroking() -> bool:
	return _stroke_state != StrokeState.IDLE


## TEST HOOK: the forward-stroke speed latched from power on the last strike (u/s). Lets a unit
## test (tests/test_plunger.gd) assert the power -> stroke-speed MAPPING is monotonic and in-range
## without a physics world, since the ball's resulting speed (the downstream effect) is solver-
## dependent and is measured against the real ball in tests/test_plunger_launch.gd. Inert in play.
func stroke_speed() -> float:
	return _stroke_speed


## TEST HOOK: suppress the cosmetic juice so a behavioral test can launch with the juice OFF and
## compare the resulting ball velocity to a launch with it ON. Must be IDENTICAL (the decoupling
## oracle). Inert in play (table.gd never calls it). Mirrors the slingshot flex decoupling proof.
func set_suppress_juice_for_test(on: bool) -> void:
	_suppress_juice = on


## TEST HOOK: the instanced launcher visual root (null on fallback). Lets a structural test assert
## the art is pure mesh (zero CollisionShape3D under it) and resolve the moving group / spring.
func launcher_visual() -> Node3D:
	return _launcher_visual


# ==================================================================================================
# PROCEDURAL LAUNCHER ART + COSMETIC JUICE (visual only; the physical _face strike is untouched).
# Built in code from Palette.HARDWARE + TableConfig lane geometry, so it stays in scale and needs no
# imported asset. The art mesh is NEVER a collider (only _face is). Mirrors the flipper / slingshot
# procedural-primary decision this slice: no .glb to fail, no fallback branch.
# ==================================================================================================


## Build the PROCEDURAL launch hardware: a static HOUSING channel behind the ball, a moving plunger
## GROUP (rod + tip) that slides with the charge/stroke, and a compressible SPRING - all under one
## LauncherVisual root parented to THIS Plunger node (seated at the playfield origin by table.gd),
## NOT to the moving physical _face (art and collider are independent). Styled from Palette.HARDWARE
## (a single grey source; table_reskin.gd never repaints the plunger, so this material is truth).
## Idempotent via the _launcher_visual null guard.
##
## LOCAL FRAME: LauncherVisual is yawed so its local +X points UP-TABLE (playfield -Z). The moving
## group therefore slides along local +/-X (forward/back up the lane), which is exactly the axis the
## juice math (_apply_charge_visual / _drive_launch_visual) drives. Built at world scale
## (_launcher_scale = 1.0), so the juice moves it in world units directly.
func _build_launcher_art() -> void:
	if _launcher_visual != null:
		return

	_launcher_visual = Node3D.new()
	_launcher_visual.name = LAUNCHER_VISUAL_NODE_NAME
	# +90-deg yaw about +Y maps local +X -> playfield -Z (up-table), so the rod points up the lane and
	# the juice slides the group along its local X. Seated at the plunger rest so the visible tip meets
	# the resting ball at the collision face (the _face box also sits at PLUNGER_REST_POS).
	var yaw := Basis(Vector3(0.0, 1.0, 0.0), PI * 0.5)
	_launcher_visual.transform = Transform3D(yaw, TableConfig.PLUNGER_REST_POS)
	_launcher_scale = 1.0
	add_child(_launcher_visual)

	var hardware: StandardMaterial3D = Palette.flat_material(Palette.HARDWARE)

	# Geometry DERIVED from the ball + lane stroke so it scales with the world (no magic literal).
	var lane_half: float = TableConfig.BALL_RADIUS * 1.1  ## snug channel ~1 ball diameter wide
	var rod_len: float = TableConfig.PLUNGER_STROKE_LENGTH * 1.6
	var rod_r: float = TableConfig.BALL_RADIUS * 0.3
	var tip_r: float = TableConfig.BALL_RADIUS * 0.8
	var housing_len: float = TableConfig.PLUNGER_STROKE_LENGTH * 2.0
	var housing_cx: float = -housing_len * 0.5 - tip_r  ## housing sits BEHIND the tip (local -X)

	# --- STATIC HOUSING: a shooter channel behind the ball - a base plate + two side rails running the
	# length of the chute so the rod visibly sits in a housing. Static: never a collider (only _face).
	var base := _new_box_mesh(
		Vector3(housing_len, TableConfig.BALL_RADIUS * 0.4, lane_half * 2.0),
		Vector3(housing_cx, -tip_r * 0.9, 0.0),
		hardware
	)
	base.name = "Launcher_Housing"
	_launcher_visual.add_child(base)
	for side: float in [-1.0, 1.0]:
		var rail := _new_box_mesh(
			Vector3(housing_len, TableConfig.BALL_RADIUS, TableConfig.BALL_RADIUS * 0.35),
			Vector3(housing_cx, 0.0, side * lane_half),
			hardware
		)
		rail.name = "Launcher_Rail_%s" % ("L" if side < 0.0 else "R")
		_launcher_visual.add_child(rail)

	# --- MOVING GROUP (Plunger_Anim): the rod + tip that slide with the charge/launch. Rest at the
	# origin (tip at local x~=0, meeting the ball); the juice slides this whole group along local X.
	_anim_group = Node3D.new()
	_anim_group.name = PLUNGER_ANIM_NODE
	_launcher_visual.add_child(_anim_group)
	var rod := _new_cyl_x(rod_r, rod_len, Vector3(-rod_len * 0.5 - tip_r, 0.0, 0.0), hardware)
	rod.name = "Plunger_Rod"
	_anim_group.add_child(rod)
	var tip := _new_cyl_x(tip_r, tip_r * 0.5, Vector3(-tip_r * 0.25, 0.0, 0.0), hardware)
	tip.name = "Plunger_Tip"
	_anim_group.add_child(tip)
	_anim_rest_pos = _anim_group.position

	# --- SPRING: a low-poly coil-ish cylinder between the rod base and the housing back-stop. Wrapped
	# in a Node3D so the juice can compress it on its LONG (local X) axis via _spring.scale.x (scaling
	# the wrapper stretches the child cylinder along its length, which a bare rotated mesh would not).
	var spring_len: float = maxf(housing_len - rod_len - tip_r, rod_r)
	_spring = Node3D.new()
	_spring.name = PLUNGER_SPRING_NODE
	_spring.position = Vector3(-rod_len - tip_r - spring_len * 0.5, 0.0, 0.0)
	var coil := _new_cyl_x(rod_r * 1.8, spring_len, Vector3.ZERO, hardware)
	coil.name = "Plunger_Coil"
	_spring.add_child(coil)
	_launcher_visual.add_child(_spring)
	_spring_rest_scale = _spring.scale

	# Hide the gray-box PlungerMesh (the placeholder "square") - the procedural launcher is the plunger
	# now. The collision box itself stays (it is the physics striker at the tip); only its MESH hides.
	var face_mesh: Node = _face.get_node_or_null("PlungerMesh")
	if face_mesh != null:
		face_mesh.visible = false


## Build a flat-shaded BoxMesh MeshInstance3D of `size` at local `pos` with material `mat`. VISUAL
## only (no collider) - used for the procedural housing.
func _new_box_mesh(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	return mi


## Build a CylinderMesh MeshInstance3D whose axis lies along LOCAL +X (Godot's cylinder is +Y by
## default, so we rotate -90 deg about +Z: +Y -> +X). `length` runs along X; `pos` is the local
## centre. A low radial segment count keeps the low-poly read. VISUAL only (no collider).
func _new_cyl_x(radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 12
	cyl.material = mat
	mi.mesh = cyl
	mi.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), -PI * 0.5), pos)
	return mi


## COSMETIC: set the moving plunger group + spring to the visual state for `power` in [0,1]. At
## power 0 they sit at the authored rest; at power 1 the group is pulled BACK by JUICE_PULL_BACK and
## the spring is compressed by JUICE_SPRING_COMPRESS. WHY LOCAL -X for pull-back: the launcher's
## local +X is forward = up-table (the +90-deg yaw in _build_launcher_art), so retracting the rod is
## -X. This reads as the player drawing the plunger back as the meter charges. No ball is moved.
func _apply_charge_visual(power: float) -> void:
	if _suppress_juice:
		return
	var p: float = clampf(power, 0.0, 1.0)
	if _anim_group != null:
		# Pull back along the launcher's local -X (forward = up-table is +X), so the rod retracts as
		# charge rises. JUICE_PULL_BACK is a WORLD distance; the procedural launcher is built at world
		# scale (_launcher_scale = 1.0) so this divides by 1.0, but we keep the division so the juice
		# stays correct if the launcher is ever rescaled.
		var pull_local: float = JUICE_PULL_BACK / maxf(_launcher_scale, 0.0001)
		_anim_group.position = _anim_rest_pos + Vector3(-pull_local * p, 0.0, 0.0)
	if _spring != null:
		# Compress the coil on its long axis (local X) toward the housing as charge rises.
		var s: Vector3 = _spring_rest_scale
		s.x = _spring_rest_scale.x * (1.0 - JUICE_SPRING_COMPRESS * p)
		_spring.scale = s
