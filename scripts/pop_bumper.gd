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
## Imported MUSHROOM art (vbousquet/pinball-parts, CC BY-SA 4.0, see CREDITS.md). The body+cap is the
## visible mushroom; the ring is the metal skirt that pops DOWN on a hit. Both scale by the SAME
## factor, DERIVED from the collider radius (never a magic number), so the art follows the physics.
## If the .glb fails to import, the gray-box cylinder (_make_mesh) stays - the bumper never vanishes.
const BODY_ASSET_PATH: String = "res://assets/models/bumper_body.glb"
const RING_ASSET_PATH: String = "res://assets/models/bumper_ring.glb"

var _radius: float = TableConfig.POP_BUMPER_RADIUS
var _height: float = TableConfig.POP_BUMPER_HEIGHT

var _ring_visual: Node3D = null    ## the metal skirt; null if the ring art failed to load
var _ring_rest_y: float = 0.0      ## the skirt's resting height; it dips below this on a pop
var _asset_path_override: String = ""  ## test seam: force a bad path to drive the fallback branch


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
## SURFACE touches the bumper, not a ball-radius early (developer: "a true contact point ... same for
## the bumpers"). The Area-vs-ball overlap already accounts for the ball's own radius.
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


## After the base builds the body/detector/gray-box mesh, swap in the imported mushroom art and the
## ring. super._ready() must run first so KickerMesh exists to hide and the kicked signal exists.
func _ready() -> void:
	super._ready()
	_install_art()


## Load the mushroom body+cap as the visible art (scaled to the collider), the ring as the animatable
## skirt, hide the gray-box cylinder, and arm the ring pop. Any load failure leaves the gray-box mesh.
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

	var ring_scene: Resource = load(RING_ASSET_PATH)
	if ring_scene is PackedScene:
		_ring_visual = ring_scene.instantiate()
		_ring_visual.name = "BumperRing"
		add_child(_ring_visual)
		_ring_visual.scale = Vector3(factor, factor, factor)  ## same factor keeps the ring proportional
		_ring_rest_y = _ring_visual.position.y
	if not kicked.is_connected(_on_kicked):
		kicked.connect(_on_kicked)


## Uniform scale so the art's footprint matches the collider diameter (2 * radius). Measured from the
## merged mesh AABB, not hardcoded - an independent oracle on the scale (see test_flipper_asset_visual
## for the same discipline).
func _derive_scale(visual: Node3D) -> float:
	var box: AABB = _merged_aabb(visual)
	var width: float = maxf(box.size.x, box.size.z)
	if width < 0.0001:
		return 1.0
	return (_radius * 2.0) / width


## Merge every descendant MeshInstance3D's AABB into the visual root's local space.
func _merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _mesh_instances(root):
		var local: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
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


## The "pop": on every kick, snap the metal ring DOWN sharply then let it spring back - the visual of
## the skirt slapping the ball away. Physics is unchanged (the base's capped radial impulse does the
## real work); this is pure juice tied to the kicked signal.
func _on_kicked(_direction: Vector3) -> void:
	if _ring_visual == null or not is_inside_tree():
		return
	var drop: float = _radius * 0.35
	var pop: Tween = create_tween()
	pop.tween_property(_ring_visual, "position:y", _ring_rest_y - drop, 0.04)
	pop.tween_property(_ring_visual, "position:y", _ring_rest_y, 0.12)
