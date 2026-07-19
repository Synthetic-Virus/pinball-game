extends Area3D
## Target - one rewarding upper-playfield scoring obstacle (gray-box bumper/target).
##
## OWNERSHIP (SLICE "make-the-core-interactions-physics-based"):
##   Gameplay-programmer: the DETECTOR half - this Area3D shell, body_entered, scored.emit,
##     RETRIGGER_COOLDOWN_S. Owns the kick-deletion and the score-on-contact logic.
##   Physics-programmer: the DEFLECTOR half - the child StaticBody3D "Deflector", its shape,
##     its PhysicsMaterial bounce tuning, and the no-trap/no-tunnel guarantee.
##   Land the gameplay half FIRST (kick deleted), then the physics half (deflector added), on
##   the same slice branch in sequence. See ARCHITECTURE.md section 9.4 for the full decision.
##
## WHAT CHANGED AND WHY:
##   The old design was an Area3D pass-through that rewrote ball.linear_velocity with a coded
##   kick (the "manual kick"). That violated the physics-first design pillar: a fast ball crawled
##   out at a fixed kick speed, and the target was invisible to the physics solver (no solid body).
##
##   The new design keeps the Area3D as a DETECTOR (monitoring the BALLS layer so body_entered
##   still fires on contact, preserving the public contract and table.gd's Array[Area3D] typing).
##   A child StaticBody3D "Deflector" on STATIC_OBSTACLES is the SOLID POST: the ball physically
##   collides with it and the Jolt solver bounces it via a near-elastic PhysicsMaterial. The
##   manual velocity kick is DELETED - the solver does the momentum transfer now. This preserves a
##   fast ball's speed (the designer's #1 fun risk: a target that kills speed ends the loop). The
##   Area3D detector shape is a slightly LARGER cylinder (deflector radius + BALL_RADIUS) so it
##   fires body_entered before the ball center crosses the deflector face.
##
##   WHY keep the Area3D root rather than swap to a StaticBody root: a StaticBody3D emits NO
##   body_entered (it detects nothing). Wrapping the deflector inside the existing Area3D gives
##   BOTH a real physics bounce AND a clean contact event without any change to the public contract.
##
## PUBLIC CONTRACT (STABLE - table.gd and tests depend on these byte-for-byte):
##   signal scored(points: int)         # emitted when the ball first contacts this target.
##   func set_ball(ball: RigidBody3D) -> void
##   var points: int                    # flat score value (default 100, placeholder per DESIGN).

signal scored(points: int)

## Radius of the solid deflector post (the StaticBody3D cylinder the ball bounces off).
## The Area3D detector shell is built LARGER by BALL_RADIUS so body_entered fires on approach,
## before the ball center reaches the post surface. Physics-programmer may retune but must keep
## this constant in sync so the detector shell stays consistent with actual deflector geometry.
##
## SIZE (MARKUP rebuild, 2026-06-21): 0.7. The developer's plan places targets in tight groups (a
## right vertical BANK of 4 about 1.4 apart, plus an upper pair and a left single), so a small post
## is needed - a 2.0-radius post would overlap its neighbours into one blob. Small standup posts also
## read distinctly from the radius-2 pop bumpers. The detector shell and the solid deflector below
## both read from this constant, so they stay in sync automatically.
const POST_RADIUS: float = 0.7

## Re-trigger cooldown (seconds). After a hit, this target ignores further contacts briefly so a
## ball resting or grinding against the post on the tilted plane cannot score every physics frame
## (QA BUG-007 score farm). One legible hit, then a short dead time, matches real bumper behavior.
## The cooldown guards the SCORE only; the solver bounce is always physical (not cooldown-gated).
const RETRIGGER_COOLDOWN_S: float = 0.20

## Deflector restitution (bounce). This is the ONE genuinely new feel knob in this slice and
## the load-bearing value for the designer's "the ball must come OFF the target keeping its
## momentum". WHY 0.8 (near-elastic, NOT a full 1.0 trampoline): Jolt combines restitution by
## taking the MAX of the two bodies, so the effective bounce against the steel ball (BALL_BOUNCE
## 0.15) is 0.8. A head-on ball arriving at speed v leaves at ~0.8v - clearly a bounce, clearly
## still fast. A value of 1.0 would ADD energy each hit; 0.8 keeps momentum without manufacturing
## it. This is what replaces the deleted manual velocity kick: the solver bounces, not code.
const DEFLECTOR_BOUNCE: float = 0.8
## Deflector friction. Low so a glancing ball slides off cleanly (crisp redirect, not a grab).
## A post should turn the ball away, not grip it like a flipper bat.
const DEFLECTOR_FRICTION: float = 0.2

## STANDUP TARGET art (SLICE "Kenney 3D asset integration", 2026-07-19): the visible post is the
## Kenney Minigolf-Kit obstacle-block.glb (KenneyModels.STANDUP_TARGET_MODEL), the designer's locked
## standup-bank role mesh, instanced as a CHILD OF THE DEFLECTOR so it reads as the solid post the
## ball bounces off. The architecture handoff keeps the "Deflector" scoring MARKER unchanged (no new
## "*Visual" marker name) so ScoringReskin still finds the target and paints the whole subtree - the
## obstacle-block included - the red scoring accent. VISUAL ONLY: the ball always collides with the
## primitive CylinderShape3D (POST_RADIUS); it is never a collider. On a failed import, the gray-box
## cylinder on the Area3D root stays visible (the target never vanishes).
const TARGET_ASSET_PATH: String = KenneyModels.STANDUP_TARGET_MODEL

## The node name the imported obstacle-block visual is instanced under (child of the Deflector).
const TARGET_VISUAL_NODE_NAME: String = "TargetVisual"

@export var points: int = 100  ## Flat value per hit (placeholder, DESIGN.md scoring).

var _ball: RigidBody3D = null
## Absolute time (ms, from Time.get_ticks_msec) before which new contacts are ignored. 0 = ready.
var _cooldown_until_ms: float = 0.0

func _ready() -> void:
	# Area3D detector setup: monitor bodies on the BALLS layer only. The Area3D does not need to
	# be on any collision layer itself for detection; setting collision_mask to BALLS ensures the
	# broadphase only wakes this area for ball contacts. collision_layer = 0 (no layer) because
	# the solid post the physics solver sees is the child Deflector (StaticBody3D), not this Area.
	collision_layer = 0
	collision_mask = PhysicsLayers.BALLS

	# Build the detector shape: a cylinder slightly larger than the post by one ball radius so
	# the detector fires as the ball approaches, not only after the ball center passes the surface.
	# The SOLID physics shape lives on the Deflector child (physics-programmer's half).
	var detector_shape := CylinderShape3D.new()
	detector_shape.radius = POST_RADIUS + TableConfig.BALL_RADIUS
	detector_shape.height = TableConfig.WALL_HEIGHT

	var col := CollisionShape3D.new()
	col.shape = detector_shape
	add_child(col)

	# Gray-box visual mesh: shows the inner POST_RADIUS (the solid surface the player aims at),
	# not the detector radius, so the visible obstacle matches what the player expects to bounce off.
	var mesh_instance := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = POST_RADIUS
	cylinder_mesh.bottom_radius = POST_RADIUS
	cylinder_mesh.height = TableConfig.WALL_HEIGHT
	# Purple, matching the developer's markup and distinct from the red pop bumpers.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.24, 0.72)
	cylinder_mesh.material = mat
	mesh_instance.mesh = cylinder_mesh
	add_child(mesh_instance)

	# Wire the contact signal. The area's body_entered fires when the ball enters the detector
	# volume (which wraps the deflector), so scoring is triggered by the same physics contact.
	body_entered.connect(_on_body_entered)

	# Physics half: build the solid deflector post the ball bounces off.
	_build_deflector()

## Register the live ball. Only this body triggers the score. STABLE SIGNATURE.
func set_ball(ball: RigidBody3D) -> void:
	_ball = ball

## Build the child StaticBody3D "Deflector" - the solid post the ball physically bounces off.
##
## PHYSICS-PROGRAMMER's half (ARCHITECTURE.md 9.7 split). The structural test resolves the child
## by name: find_child("Deflector", true, false).
##
## NO-TUNNEL: the deflector is STATIC and the ball carries continuous_cd, so the ball's swept CCD
## test catches the post even at >= 2x LAUNCH_SPEED_MAX (tests/test_target_no_tunneling.gd).
## WALL_HEIGHT keeps the post as tall as the perimeter so a ball cannot ride up and over it.
##
## NO-TRAP: the deflector sits on STATIC_OBSTACLES, which BALL_COLLISION_MASK already includes,
## so the ball can never pass INTO it. DEFLECTOR_BOUNCE rebounds the ball with its momentum
## (designer: "the ball must come OFF the target"), so a fast ball stays fast and a crawl still
## pops off legibly rather than being killed to a fixed speed.
func _build_deflector() -> void:
	var deflector := StaticBody3D.new()
	deflector.name = "Deflector"
	# STATIC_OBSTACLES: exactly like the walls/arch/lane divider/lane pocket. The ball already
	# collides with this layer via BALL_COLLISION_MASK; no mask edit needed anywhere (this is the
	# shared-physics audit result: no layer/mask change means the flipper tests cannot regress).
	# collision_mask = 0: a static post is only collided with, it scans nothing.
	deflector.collision_layer = PhysicsLayers.STATIC_OBSTACLES
	deflector.collision_mask = 0

	# Near-elastic material: this makes the bounce momentum-preserving via the solver, replacing
	# the deleted manual kick. LOCAL to this body - not shared or mutated globally.
	var material := PhysicsMaterial.new()
	material.bounce = DEFLECTOR_BOUNCE
	material.friction = DEFLECTOR_FRICTION
	deflector.physics_material_override = material

	# The solid post: a cylinder standing upright (axis Y) so its round profile faces the ball
	# from every approach angle - the same POST_RADIUS post the player has always aimed at, solid.
	var shape := CylinderShape3D.new()
	shape.radius = POST_RADIUS
	shape.height = TableConfig.WALL_HEIGHT

	var col := CollisionShape3D.new()
	col.shape = shape
	deflector.add_child(col)

	add_child(deflector)

	# Swap in the Kenney obstacle-block cap as the visible post (VISUAL ONLY - the collider above is
	# the sole physics shape). Done after the deflector is in the tree so the mesh AABB measures.
	_install_target_art(deflector)

## Instance the Kenney obstacle-block as the visible post under the Deflector, scaled to the post
## footprint and seated on the surface. COPIES the proven pop_bumper.gd / wall_element.gd install:
## load the path, bail to the gray box on any failure, instance the WHOLE subtree under a named
## child, scale from the merged AABB to the post diameter (DERIVED, not a literal), seat the base at
## the surface. The art is pure mesh - it is never a collider (the Deflector's CylinderShape3D is).
func _install_target_art(deflector: StaticBody3D) -> void:
	if TARGET_ASSET_PATH == "" or not ResourceLoader.exists(TARGET_ASSET_PATH):
		return  ## fallback: the gray-box cylinder on the root stays visible
	var scene: Resource = load(TARGET_ASSET_PATH)
	if scene == null or not (scene is PackedScene):
		return  ## fallback (bad/absent asset)
	var visual: Node3D = (scene as PackedScene).instantiate()
	visual.name = TARGET_VISUAL_NODE_NAME
	deflector.add_child(visual)
	var factor: float = _derive_scale(visual)
	visual.scale = Vector3(factor, factor, factor)
	# Seat the post BASE at the surface (the Deflector origin, Y = 0) so an off-origin mesh cannot
	# sink below the field (the burned integration gotcha). Measured after the scale is set.
	visual.position.y = KenneyModels.base_seat_y(visual, 0.0)

## Uniform scale so the obstacle-block's top-down FOOTPRINT (the wider of X/Z) matches the post
## diameter (2 * POST_RADIUS), so the visible post tracks the collider the player bounces off.
## Measured from the merged mesh AABB (KenneyModels.merged_aabb), never hardcoded: a re-exported
## model self-corrects and no scale literal is typed. The structural test asserts the footprint
## tracks POST_RADIUS.
func _derive_scale(visual: Node3D) -> float:
	var box: AABB = KenneyModels.merged_aabb(visual)
	var footprint: float = maxf(box.size.x, box.size.z)
	if footprint < 0.0001:
		return 1.0
	return (POST_RADIUS * 2.0) / footprint

func _on_body_entered(body: Node) -> void:
	# Guard: only the tracked ball matters. Any other physics body is silently ignored.
	if body != _ball:
		return

	# Cooldown guard (QA BUG-007): a ball grinding against the post on the tilted plane re-fires
	# body_entered every time it dips in and out of the detector volume. Without this the player
	# could farm points every frame. One hit, then a dead time, before scoring again.
	# The BOUNCE is not gated here: the solver deflects the ball on every contact regardless of
	# whether we score. Only the scored() emission is rate-limited by the cooldown.
	var now_ms: float = float(Time.get_ticks_msec())
	if now_ms < _cooldown_until_ms:
		return
	_cooldown_until_ms = now_ms + RETRIGGER_COOLDOWN_S * 1000.0

	# Score fires on the physics contact frame so the HUD ticks the instant the ball touches.
	# No manual velocity rewrite: the solver handles the bounce via the Deflector's PhysicsMaterial.
	# The old manual kick is deleted (it was rewriting linear_velocity, discarding the ball's
	# incoming speed - the opposite of the momentum pillar and the designer's #1 fun risk).
	scored.emit(points)
