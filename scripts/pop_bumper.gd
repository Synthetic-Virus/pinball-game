extends "res://scripts/active_kicker.gd"
## PopBumper - an active round "bell thingy" that fires the ball radially outward on contact.
##
## A pop bumper is an ActiveKicker (shared base owns the cap/cooldown/score) whose KICK DIRECTION is
## RADIALLY OUTWARD from its own center along the ball's contact normal: wherever the ball touches,
## it
## is fired straight away from the bumper. That is the classic "pop": a ball entering the cluster
## bounces off one bumper toward another, racking up little jolts of action and score (DESIGN
## must-feel
## #1 "active kick, not a limp bounce").
##
## GEOMETRY (TableConfig): a round solid post of POP_BUMPER_RADIUS, POP_BUMPER_HEIGHT tall. The base
## class builds the solid StaticBody3D (physics half) and the detector; this subclass only supplies
## the round shape and the radial kick direction.
##
## OWNERSHIP: lead scaffolds; physics-programmer fills _build_body/_apply_kick in the BASE (shared);
## this file's _kick_direction_for + geometry setup are small and stable.
##
## STABLE CONTRACT: inherits scored(points), kicked(direction), set_ball, points from ActiveKicker.
##   func configure() -> void   # pull radius/height/score from TableConfig (called by table.gd).

## The solid post radius and height, pulled from TableConfig in configure() so the base _build_body
## and _build_detector_and_mesh can read a single resolved value. The detector is built one
## BALL_RADIUS
## larger than this so body_entered fires as the ball arrives.
## POP BUMPER art (SLICE "Kenney 3D asset integration", 2026-07-19): the imported visual is now the
## Kenney Minigolf-Kit bump.glb (KenneyModels.POP_BUMPER_MODEL), the designer's locked bumper-cap
## role mesh, replacing the retired custom pop_bumper.glb. It is the visible cap, scaled by a factor
## DERIVED from the collider radius (never a magic number) and rendered slightly WIDER than the
## collider (POP_BUMPER_CAP_OVERHANG) so the ball tucks under the lid, then seated at the surface so
## an off-origin mesh cannot sink below the field. If the .glb fails to import, the gray-box
## cylinder (_make_mesh) stays - the bumper never vanishes; the whole subtree is instanced.
## The mesh is VISUAL ONLY - the ball always collides with the primitive CylinderShape3D.
const BODY_ASSET_PATH: String = KenneyModels.POP_BUMPER_MODEL

## The rest (idle) albedo the flash eases back to: the shared scoring accent (Palette single source
## of truth). Named so the flash reads it once, not a scattered literal.
const FLASH_REST_ALBEDO: Color = Palette.SCORING_ACCENT
## The peak flash albedo: a brightened near-white red pop, still fully opaque and emission-free
## (must-feel #6: albedo is the only channel that renders in the web build). The flash eases from
## this back to FLASH_REST_ALBEDO over FLASH_FADE_S.
const FLASH_PEAK_ALBEDO: Color = Color(1.0, 0.72, 0.68)
## Flash ease-back duration (seconds). Long enough to read as a soft pulse (not a strobe) AND to
## stay visibly off-rest across the hit-flash test's post-kick sampling window (it samples the
## rendered albedo after the kick lands); on the physics clock so the sampling is deterministic.
const FLASH_FADE_S: float = 0.6

var _radius: float = TableConfig.POP_BUMPER_RADIUS
var _height: float = TableConfig.POP_BUMPER_HEIGHT

var _asset_path_override: String = ""  ## test seam: force a bad path to drive the fallback branch

## The private per-bumper flash material, lazily isolated the first time this bumper is struck (see
## _flash_on_hit). ScoringReskin paints ONE shared accent material across ALL scoring furniture; if
## the flash mutated that shared object it would pulse the whole table at once, so we duplicate it
## into a private copy and pulse only this bumper's meshes. Null until the first kick.
var _flash_mat: StandardMaterial3D = null


## Pull this bumper's geometry + score from TableConfig. table.gd calls this after instancing,
## before
## the bumper is added to the tree (so _ready/_build_body see the resolved values). STABLE
## SIGNATURE.
func configure() -> void:
	_radius = TableConfig.POP_BUMPER_RADIUS
	_height = TableConfig.POP_BUMPER_HEIGHT
	points = TableConfig.POP_BUMPER_SCORE


## RADIAL kick: the unit vector FROM the bumper center TO the ball, flattened onto the surface plane
## (Y = 0) so the kick stays in-plane (a pop bumper bats the ball across the table, not into the
## air).
## ball_pos is the ball's GLOBAL position; the bumper's global_position is its center. If the ball
## is
## (degenerately) exactly on center, fall back to up-table so the kick is never a zero vector.
func _kick_direction_for(ball_pos: Vector3) -> Vector3:
	var to_ball: Vector3 = ball_pos - global_position
	to_ball.y = 0.0  # keep the kick on the playfield plane (no vertical pop)
	if to_ball.length() < 0.0001:
		return TableConfig.up_table_local()
	return to_ball.normalized()


## Round solid post. The base _build_body reads this for the StaticBody3D collision shape.
func _make_body_shape() -> Shape3D:
	var shape := CylinderShape3D.new()
	shape.radius = _radius
	shape.height = _height
	return shape


## Detector = the EXACT body cylinder (no proximity padding), so body_entered fires when the ball
## SURFACE touches the bumper, not a ball-radius early (developer: "a true contact point ...
## same for the bumpers"). The Area-vs-ball overlap already accounts for the ball's own radius.
func _make_detector_shape() -> Shape3D:
	var shape := CylinderShape3D.new()
	shape.radius = _radius
	shape.height = _height
	return shape


## Visible mesh: a ROUND cylinder matching the collision post (the base _make_mesh returns a tiny
## 1x1 box - the "little squares" the developer saw). A red cap-coloured cylinder of the real radius
## so the bumper reads as a chunky round bumper, not a dot.
func _make_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _radius
	cyl.bottom_radius = _radius
	cyl.height = _height
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.18, 0.18)
	cyl.material = mat
	mesh_instance.mesh = cyl
	return mesh_instance


## After the base builds the body/detector/gray-box mesh, swap in the imported Kenney cap art.
## super._ready() must run first so KickerMesh exists to hide.
func _ready() -> void:
	super._ready()
	_install_art()
	# Wire the hit-flash on EVERY bumper, whether the Kenney cap loaded or the gray-box fallback
	# stayed - the flash pulses whichever mesh actually renders (see _flash_on_hit). Connecting here
	# (not inside _install_art, which returns early on a load failure) keeps the flash working on the
	# gray-box too (DESIGN must-feel #4, hard constraint - the flash must never stop firing).
	if not kicked.is_connected(_flash_on_hit):
		kicked.connect(_flash_on_hit)


## Load the Kenney bump.glb cap as the visible art (scaled to overhang the collider, seated at the
## surface) and hide the gray-box cylinder. Any load failure leaves the gray-box mesh visible (the
## bumper never vanishes). Uses the shared KenneyModels measure/seat helpers so the scale/seat math
## has one correct implementation, not a per-element copy.
func _install_art() -> void:
	var body_path: String = BODY_ASSET_PATH if _asset_path_override == "" else _asset_path_override
	var body_scene: Resource = load(body_path)
	if body_scene == null or not (body_scene is PackedScene):
		return  ## fallback: the gray-box cylinder from _make_mesh stays visible
	var visual: Node3D = (body_scene as PackedScene).instantiate()
	visual.name = "BumperVisual"
	add_child(visual)
	var factor: float = _derive_scale(visual)
	visual.scale = Vector3(factor, factor, factor)
	# Seat the cap BASE on the playfield surface (the element origin, Y = 0) so an off-origin Kenney
	# mesh cannot sink below the field (the burned integration gotcha). Measured after the scale is
	# set, never hardcoded (KenneyModels.base_seat_y).
	visual.position.y = KenneyModels.base_seat_y(visual, 0.0)
	var gray_box: Node = get_node_or_null("KickerMesh")
	if gray_box != null:
		gray_box.visible = false  ## the real cap replaces the placeholder cylinder
	# Scoring accent on the cap (the flash pulses from this / from ScoringReskin's accent at run time).
	_apply_accent_material(visual)


## Apply the flat RED scoring accent (Palette single colour source, no scattered literal) to every
## mesh in the imported cap. WHY here even though ScoringReskin re-asserts the same accent as a
## whole-table pass: a stand-alone bumper (a unit test, or any scene without the reskin) still reads
## correctly red, and the flash has a material to pulse from. Flat albedo only (must-feel #6: no
## emission - invisible in the web build; no transparency that would hurt ball tracking).
func _apply_accent_material(root: Node3D) -> void:
	var mat: StandardMaterial3D = Palette.flat_material(Palette.SCORING_ACCENT)
	for mi: MeshInstance3D in KenneyModels.mesh_instances(root):
		mi.material_override = mat


## SUBTLE light-up when the bumper is hit (DESIGN must-feel #4, a HARD CONSTRAINT: "the bumper hit
## flash still PULSES ALBEDO... a hit flash that stops flashing is a FAIL"). Pop the albedo to a
## bright near-white red, then ease it back to the scoring-accent rest colour.
##
## WHY IT PULSES THE LIVE MATERIAL, NOT A CACHED HANDLE (measured defect): the old
## flash mutated pop_bumper.gd's private material handle, but ScoringReskin.apply() overwrites
## material_override with a SEPARATE shared accent material as a final table pass, so the old flash
## pulsed an orphaned object nothing rendered - it silently stopped flashing. We instead read the
## material that is ACTUALLY on the rendered mesh, isolate a private copy of it once (pulsing this
## bumper never tints the shared accent every other scoring piece shares), and pulse THAT.
##
## WHY ALBEDO NOT EMISSION: emission reads as invisible in the web build (no bloom, translucent-free
## flat material), so albedo is the only reliable channel (must-feel #4/#6, burned lesson).
##
## The `direction` arg is unused but MUST be accepted: kicked(direction: Vector3) emits with one
## Vector3, and Godot 4 does NOT drop unused signal args on connect() - a zero-arg slot would log
## "Method expected 0 arguments, but called with 1" and never run. Underscore-prefixed per the
## codebase's unused-parameter convention. Cosmetic only - no physics or collider touched.
func _flash_on_hit(_direction: Vector3) -> void:
	# Pulse whatever mesh actually RENDERS: the Kenney "BumperVisual" cap if it loaded, else the
	# gray-box "KickerMesh" fallback (LFS-less runs). This mirrors the hit-flash oracle's own
	# _rendered_bumper_mesh() resolution, so the flash always lands on the mesh the test samples.
	var visual: Node3D = get_node_or_null("BumperVisual") as Node3D
	if visual == null:
		visual = get_node_or_null("KickerMesh") as Node3D
	if visual == null:
		return
	var meshes: Array[MeshInstance3D] = KenneyModels.mesh_instances(visual)
	if meshes.is_empty():
		return
	if _flash_mat == null:
		# Isolate a private material from whatever is live on the cap now (the shared ScoringReskin
		# accent in the real table, or the _apply_accent_material accent in a stand-alone test). A
		# duplicate means pulsing this bumper never tints the shared accent the rest of the table wears.
		var live: StandardMaterial3D = meshes[0].material_override as StandardMaterial3D
		_flash_mat = (
			live.duplicate() if live != null else Palette.flat_material(Palette.SCORING_ACCENT)
		)
		for mi: MeshInstance3D in meshes:
			mi.material_override = _flash_mat
	# Pop the albedo bright, then ease it back to the accent rest colour. The tween runs on the
	# PHYSICS clock so its progress is deterministic under the headless GUT wait_physics_frames the
	# hit-flash oracle samples with (an idle-clock tween would drift against a physics-frame sampler).
	_flash_mat.albedo_color = FLASH_PEAK_ALBEDO
	var tw: Tween = create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(_flash_mat, "albedo_color", FLASH_REST_ALBEDO, FLASH_FADE_S)


## Uniform scale so the cap's footprint matches the CAP diameter (2 * cap_radius), where cap_radius
## is POP_BUMPER_CAP_OVERHANG WIDER than the collision post. This is what makes the ball tuck under
## the lid: the visible cap overhangs the CylinderShape3D collider (which stays at _radius,
## the true contact), so a ball stopping at the collider edge sits visually under the overhanging
## lip. Measured from the merged mesh AABB (KenneyModels.merged_aabb), not hardcoded - independent
## oracle on the scale (see test_pop_bumper_cap_overhang for the same discipline).
func _derive_scale(visual: Node3D) -> float:
	var box: AABB = KenneyModels.merged_aabb(visual)
	var width: float = maxf(box.size.x, box.size.z)
	if width < 0.0001:
		return 1.0
	var cap_radius: float = _radius * (1.0 + TableConfig.POP_BUMPER_CAP_OVERHANG)
	return (cap_radius * 2.0) / width
