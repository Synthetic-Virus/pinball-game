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
## POP BUMPER art (custom low-poly model, SLICE "Custom low-poly asset integration", 2026-06-24).
## The imported pop_bumper.glb is the matched-family stack of Bumper_Base + Bumper_Body + Bumper_Cap
## (replacing the older borrowed bumper_body.glb). It is the visible mushroom, scaled by a factor
## DERIVED from the collider radius (never a magic number) so the art follows the physics, and
## rendered slightly WIDER than the collider (POP_BUMPER_CAP_OVERHANG) so the ball tucks under the
## lid. If the .glb fails to import, the gray-box cylinder (_make_mesh) stays - the bumper never
## vanishes. The whole .glb subtree (all three named parts) is instanced, so no part is dropped.
const BODY_ASSET_PATH: String = "res://assets/models/pop_bumper.glb"

var _radius: float = TableConfig.POP_BUMPER_RADIUS
var _height: float = TableConfig.POP_BUMPER_HEIGHT

var _asset_path_override: String = ""  ## test seam: force a bad path to drive the fallback branch

## The blue translucent-plastic material applied to the imported bumper, kept as a handle so the
## hit-flash can pulse its emission. Same family blue as the posts/flippers. Emission idles at 0 and
## flashes briefly when the bumper is struck - a SUBTLE light, not a strobe (developer's note).
var _bumper_mat: StandardMaterial3D = null
## The rest (idle) albedo, captured so the hit-flash can brighten the albedo and ease back to it.
var _rest_albedo: Color = Color(0.10, 0.30, 0.90, 0.85)


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


## After the base builds the body/detector/gray-box mesh, swap in the imported mushroom art.
## super._ready() must run first so KickerMesh exists to hide.
func _ready() -> void:
	super._ready()
	_install_art()


## Load the mushroom body+cap as the visible art (scaled to overhang the collider) and hide the
## gray-box cylinder. Any load failure leaves the gray-box mesh visible (the bumper never vanishes).
func _install_art() -> void:
	var body_path: String = BODY_ASSET_PATH if _asset_path_override == "" else _asset_path_override
	var body_scene: Resource = load(body_path)
	if body_scene == null or not (body_scene is PackedScene):
		return  ## fallback: the gray-box cylinder from _make_mesh stays visible
	var visual: Node3D = body_scene.instantiate()
	visual.name = "BumperVisual"
	add_child(visual)
	var factor: float = _derive_scale(visual)
	visual.scale = Vector3(factor, factor, factor)
	var gray_box: Node = get_node_or_null("KickerMesh")
	if gray_box != null:
		gray_box.visible = false  ## the real mushroom replaces the placeholder cylinder
	# Blue plastic look + a subtle light-up on hit. The base fires `kicked` on each contact.
	_apply_blue_material(visual)
	if not kicked.is_connected(_flash_on_hit):
		kicked.connect(_flash_on_hit)


## Apply the family blue translucent-plastic material to every mesh in the imported bumper, set up
## with emission so the hit-flash can pulse it. Idle emission is 0 (no glow at rest); _flash_on_hit
## briefly raises it. Pure cosmetic - no physics or collider touched.
func _apply_blue_material(root: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	_rest_albedo = Color(0.10, 0.30, 0.90, 0.85)
	mat.albedo_color = _rest_albedo
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.30, 0.55, 1.0)
	mat.emission_energy_multiplier = 0.0  ## dark at rest; the hit-flash raises this
	_bumper_mat = mat
	for mi: MeshInstance3D in _mesh_instances(root):
		mi.material_override = mat


## SUBTLE light-up when the bumper is hit: pop the emission, then fade it back over ~0.18 s. Takes
## no args so it can connect to `kicked` regardless of that signal's parameters. Cosmetic only.
func _flash_on_hit() -> void:
	if _bumper_mat == null:
		return
	# Pulse the ALBEDO (the base color, always rendered), not just emission. Emission alone showed NO
	# light in the web build (developer: "there's no light at all") because the material is translucent
	# and there is no glow/HDR, so emission washed out. Brighten the albedo to a near-white blue, then
	# ease back to rest. Emission is still raised for any renderer that does bloom.
	_bumper_mat.albedo_color = Color(0.55, 0.80, 1.0, 0.95)
	_bumper_mat.emission_energy_multiplier = 3.0
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_bumper_mat, "albedo_color", _rest_albedo, 0.28)
	tw.tween_property(_bumper_mat, "emission_energy_multiplier", 0.0, 0.28)


## Uniform scale so the cap's footprint matches the CAP diameter (2 * cap_radius), where cap_radius
## is POP_BUMPER_CAP_OVERHANG WIDER than the collision post. This is what makes the ball tuck under
## the lid: the visible mushroom cap overhangs the CylinderShape3D collider (which stays at _radius,
## the true contact), so a ball stopping at the collider edge sits visually under the overhanging
## lip. Measured from the merged mesh AABB, not hardcoded - an independent oracle on the scale (see
## test_flipper_asset_visual for the same discipline).
func _derive_scale(visual: Node3D) -> float:
	var box: AABB = _merged_aabb(visual)
	var width: float = maxf(box.size.x, box.size.z)
	if width < 0.0001:
		return 1.0
	var cap_radius: float = _radius * (1.0 + TableConfig.POP_BUMPER_CAP_OVERHANG)
	return (cap_radius * 2.0) / width


## Merge every descendant MeshInstance3D's AABB into the visual root's local space.
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


func _mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c: Node in node.get_children():
		found.append_array(_mesh_instances(c))
	return found
