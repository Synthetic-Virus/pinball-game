class_name TableGeometry
extends RefCounted
## TableGeometry - builds the STATIC geometry of the table.
##
## RESET (2026-06-21): the previous table (procedural walls, arch, lane guides, and all furniture)
## was thrown out at the developer's request - the generated objects overlapped and did not play.
## This now builds ONLY a clean FLAT PLAY AREA plus the main BORDER lines, traced from the reference
## render (docs/REFERENCE_LAYOUT.md). It is a deliberate blank slate: we build the table back up
## from here, one verified piece at a time. No furniture, no arch - just the surface + the outline.
##
## OWNERSHIP: lead-programmer. Called by table.gd. Reads its dimensions from TableConfig.
##
## COORDINATE CONVENTION (local to the tilted Playfield, per TableConfig):
##   +X = right, -X = left, -Z = up-table (top), +Z = down-table (drain). Y = up off the surface.
##   The surface top sits at Y = 0; borders stand up to TableConfig.WALL_HEIGHT.

## DEV AID: draw the coordinate grid + axis numbers ON the playfield so positions can be read
## straight off the running 3D table (developer: "idk where those coords are"). Set false to hide.
const SHOW_COORD_GRID: bool = true

## Border skinning (SLICE "Kenney 3D asset integration", 2026-07-19): each border box is SKINNED
## with a scaled copy of a Kenney wall_border mesh so the outline reads as one designed frame, not
## plain white boxes. The designer's locked role split (see _wall_model_for): the PERIMETER rails
## get block-borders.glb (KenneyModels.WALL_BORDER_MODEL); the NARROW launch-lane divider gets the
## thinner narrow-block.glb (KenneyModels.NARROW_GUIDE_MODEL), better for a tight lane gap. The
## box COLLIDER is kept; only the visible mesh is swapped (the art is never a collider). TableReskin
## paints these the calm white frame colour as a final whole-table pass.

## Entry point. table.gd calls TableGeometry.build(playfield_node).
static func build(playfield: Node3D) -> void:
	_build_surface(playfield)
	_build_borders(playfield)
	# The lower gutter/outhole (funnel + outlane dividers) is built HERE, right after the borders, so
	# it always exists headlessly: the plunger-lane tests build TableGeometry directly and the bottom
	# of the table must collect a drained ball into the center drain instead of leaving it open.
	_build_lower_gutter(playfield)
	# The inlane/return GUIDES and top CHUTES are NOT built here anymore - they are editor-managed
	# EditRail elements (scripts/edit_rail.gd) created by table.gd so the developer can draw/reshape
	# them. table.gd seeds the same default shapes via TableConfig.DEFAULT_RAILS. The surface, outer
	# borders, and launch-lane divider stay here because the plunger-lane tests build TableGeometry
	# directly and depend on them. The coordinate GRID is built+managed by table.gd (build_coord_grid)
	# so it can be shown only in BUILD mode and rebuilt with finer units as the developer zooms in.


## Sample a SMOOTH curve (Catmull-Rom) through the control points -> a denser polyline so a guide
## reads as a ROUNDED curve, not a few straight segments joined at hard corners (developer: the guides
## were "3 lines connected", "not rounded"). per_seg = samples between each pair of control points.
static func _smooth_curve(pts: Array[Vector3], per_seg: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n: int = pts.size()
	if n < 3:
		return pts
	for i: int in range(n - 1):
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		for s: int in range(per_seg):
			var t: float = float(s) / float(per_seg)
			var t2: float = t * t
			var t3: float = t2 * t
			out.append(
				0.5 * (
					2.0 * p1 + (p2 - p0) * t
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3
				)
			)
	out.append(pts[n - 1])
	return out


## Build the coordinate grid under a fresh "CoordGrid" node and return it, so table.gd can show it only
## in BUILD mode and rebuild it with a finer `step` as the developer zooms in. Lines run every `step`
## world units, brighter every 2*step, blue on the x=0 / z=0 axes; number labels every 4*step. Visual
## only (no collision). Pinned to a FIXED +/-16 / +/-25 frame so coordinates stay stable.
static func build_coord_grid(parent: Node3D, step: float) -> Node3D:
	var grid := Node3D.new()
	grid.name = "CoordGrid"
	parent.add_child(grid)
	var hw: float = 16.0
	var hl: float = 25.0
	var y: float = 0.06  ## just above the surface top (y=0)
	var major_step: float = step * 2.0
	var label_step: float = step * 4.0
	var minor := StandardMaterial3D.new()
	minor.albedo_color = Color(0.30, 0.32, 0.40)  ## faint, the every-step lines
	var major := StandardMaterial3D.new()
	major.albedo_color = Color(0.45, 0.48, 0.58)  ## brighter, the every-2*step lines
	var axis := StandardMaterial3D.new()
	axis.albedo_color = Color(0.20, 0.65, 1.0)  ## bright blue for the x=0 / z=0 axes

	# Vertical grid lines (constant x, running in z).
	var x: float = -hw
	while x <= hw + 0.001:
		var is_axis: bool = is_zero_approx(x)
		var is_major: bool = _near_multiple(x, major_step)
		var mat: StandardMaterial3D = axis if is_axis else (major if is_major else minor)
		var w: float = 0.18 if is_axis else (0.08 if is_major else 0.05)
		_grid_strip(grid, Vector3(x, y, 0.0), Vector3(w, 0.04, hl * 2.0), mat)
		x += step
	# Horizontal grid lines (constant z, running in x).
	var z: float = -hl
	while z <= hl + 0.001:
		var is_axis2: bool = is_zero_approx(z)
		var is_major2: bool = _near_multiple(z, major_step)
		var mat2: StandardMaterial3D = axis if is_axis2 else (major if is_major2 else minor)
		var t: float = 0.18 if is_axis2 else (0.08 if is_major2 else 0.05)
		_grid_strip(grid, Vector3(0.0, y, z), Vector3(hw * 2.0, 0.04, t), mat2)
		z += step

	# Number labels: x along the bottom edge, z along the left edge.
	var xl: float = -hw
	while xl <= hw + 0.001:
		_grid_label(grid, _grid_num(xl), Vector3(xl, y, hl - 1.0))
		xl += label_step
	var zl: float = -hl
	while zl <= hl + 0.001:
		_grid_label(grid, _grid_num(zl), Vector3(-hw + 1.0, y, zl))
		zl += label_step
	_grid_label(grid, "0,0", Vector3(1.2, y, 1.2))
	return grid


## True when v is a (near) multiple of m - tolerant of float drift at the 0.5/1/2 grid steps.
static func _near_multiple(v: float, m: float) -> bool:
	if m <= 0.0:
		return false
	var r: float = fmod(absf(v), m)
	return r < 0.01 or r > m - 0.01


## Format a grid coordinate: whole numbers as ints, otherwise one decimal (for the 0.5 fine grid).
static func _grid_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % int(roundf(v))
	return "%.1f" % v


## One thin flat grid strip (a flat box, no collision) centred at pos with the given size + material.
static func _grid_strip(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


## One floating number label that always faces the camera (billboard), for reading coords off the 3D.
static func _grid_label(parent: Node3D, text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos + Vector3(0.0, 0.4, 0.0)
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = Color(0.30, 0.75, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)


## A dark material for the flat surface so the white border lines read clearly against it.
static func _gray_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.22)
	return mat


## A bright material for the BORDER lines so the outline stands out against the dark surface.
static func _line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.90, 0.90, 0.93)
	return mat


## Create one box StaticBody3D: a collision box + a matching mesh, on a given layer, at a local
## position, with a material. Centralizes the boilerplate so each piece is one readable call.
static func _make_box_body(
	parent: Node3D,
	body_name: String,
	size: Vector3,
	local_pos: Vector3,
	layer: int,
	material: StandardMaterial3D
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	# Static geometry detects nothing; it is only detected. Empty mask avoids broadphase work.
	body.collision_mask = 0
	body.position = local_pos

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)

	parent.add_child(body)
	return body


## The flat table surface: a thin box on the PLAYFIELD layer the ball rolls on. Its top face sits at
## Y = 0 so elements placed at Y = 0 sit ON the surface. Sized a little past the borders so there
## is no gap at the outline feet.
static func _build_surface(parent: Node3D) -> void:
	var thickness: float = 1.0
	var size := Vector3(
		TableConfig.HALF_WIDTH * 2.0 + 3.0,
		thickness,
		TableConfig.HALF_LENGTH * 2.0 + 3.0
	)
	# Centered at Y = -thickness/2 so the TOP face is at Y = 0.
	_make_box_body(
		parent, "Surface", size, Vector3(0.0, -thickness * 0.5, 0.0),
		PhysicsLayers.PLAYFIELD, _gray_material()
	)


## The MAIN BORDER lines, traced from the reference (docs/REFERENCE_LAYOUT.md): left wall, a rounded
## top-left corner, the top edge, the right wall, and the launch-lane divider. The bottom is OPEN
## (the drain mouth). Each segment is a thin white wall: it contains the ball and reads as the
## outline. Points are the wall CENTERLINE in table coords (X, _, Z).
static func _build_borders(parent: Node3D) -> void:
	# Outer outline, walked as a polyline: up the left wall, around the rounded top-left corner, across
	# the top, around the rounded top-RIGHT corner, and down the right wall. Bottom open for the drain.
	# BOTH top corners are rounded (developer: the top-right was square and sealed the ball in).
	# Derived from the world-scale width so the shell narrows with HALF_WIDTH (NARROW 2026-06-21: the
	# developer's outline is ~x -13..+13). Left wall at -hw, right wall (lane outer) at +hw, both top
	# corners rounded, bottom open for the drain.
	var hw: float = TableConfig.HALF_WIDTH
	var hl: float = TableConfig.HALF_LENGTH
	var li: float = TableConfig.LANE_INNER_X
	# ROUNDED TOP (developer): the top is one smooth ARCH (half-ellipse) instead of a flat edge with
	# chamfers. The side walls run up to arch_base_z, then the arch sweeps from the left wall top, over
	# the apex at (0, -hl), to the right wall top. rx spans the full width; rz is the rise.
	var arch_base_z: float = -hl + 8.0
	var rx: float = hw
	var rz: float = arch_base_z - (-hl)  ## apex lands at z = -hl, the old top height
	var outline: Array[Vector3] = [Vector3(-hw, 0.0, hl - 2.0)]  ## bottom-left, then up the left wall
	var steps: int = 18
	for i: int in range(steps + 1):
		var ang: float = deg_to_rad(180.0 - 180.0 * float(i) / float(steps))
		outline.append(Vector3(rx * cos(ang), 0.0, arch_base_z - rz * sin(ang)))
	outline.append(Vector3(hw, 0.0, hl - 2.0))  ## down the right wall, bottom open for the drain
	for i: int in range(outline.size() - 1):
		_add_border_segment(parent, outline[i], outline[i + 1], "Border%d" % i)

	# Launch-lane divider at +LANE_INNER_X (the inner right wall forming the shooter lane, lane =
	# li..hw). It STOPS short of the top (TableConfig.LANE_DIVIDER_TOP_Z, the single source of truth
	# also used by LAUNCH_REACHED_PLAY_Z's soft-lock-watchdog derivation) so the lane is OPEN and a
	# launched ball curves into the field.
	_add_border_segment(
		parent,
		Vector3(li, 0.0, TableConfig.LANE_DIVIDER_TOP_Z),
		Vector3(li, 0.0, hl - 2.0),
		"LaneDivider"
	)


## Build the lower gutter / outhole (SLICE "Lower-third rebuild", Item 1): a two-sided funnel that
## visibly collects any ball past the flippers and feeds it to the EXISTING center drain, plus one
## narrow outlane divider per side. Every segment is a static wall built with _add_border_segment
## (the same box-wall class, STATIC_OBSTACLES layer, and Kenney skin as the perimeter). The gutter
## always exists even in the headless plunger-lane tests that build TableGeometry directly. The
## center drain mouth (x in [-1.8, 1.8]) is left OPEN so the drain Area3D still catches the ball; NO
## drain mechanic changes. Endpoint constants live in TableConfig (OUTHOLE_* / OUTLANE_DIVIDER_*).
static func _build_lower_gutter(parent: Node3D) -> void:
	# Four funnel segments: two steep OUTLANE catches (outer) plus two FLOOR sweeps (inner, below the
	# flippers) that hand the ball to the open center drain mouth. The paired endpoints meet at the
	# V vertex on each side (OUTLANE_B == FLOOR_A), so the joint has no gap.
	_add_border_segment(
		parent,
		_v3(TableConfig.OUTHOLE_LEFT_OUTLANE_A),
		_v3(TableConfig.OUTHOLE_LEFT_OUTLANE_B),
		"OutholeLeftOutlane"
	)
	_add_border_segment(
		parent,
		_v3(TableConfig.OUTHOLE_LEFT_FLOOR_A),
		_v3(TableConfig.OUTHOLE_LEFT_FLOOR_B),
		"OutholeLeftFloor"
	)
	_add_border_segment(
		parent,
		_v3(TableConfig.OUTHOLE_RIGHT_OUTLANE_A),
		_v3(TableConfig.OUTHOLE_RIGHT_OUTLANE_B),
		"OutholeRightOutlane"
	)
	_add_border_segment(
		parent,
		_v3(TableConfig.OUTHOLE_RIGHT_FLOOR_A),
		_v3(TableConfig.OUTHOLE_RIGHT_FLOOR_B),
		"OutholeRightFloor"
	)
	# Two outlane dividers: short walls splitting each side into an outer outlane (drain-risk) and an
	# inner inlane (save). NOT named "LaneDivider", so _wall_model_for skins them with the perimeter
	# wall model rather than the narrow launch-lane model.
	_add_border_segment(
		parent,
		_v3(TableConfig.OUTLANE_DIVIDER_LEFT_A),
		_v3(TableConfig.OUTLANE_DIVIDER_LEFT_B),
		"OutlaneDividerLeft"
	)
	_add_border_segment(
		parent,
		_v3(TableConfig.OUTLANE_DIVIDER_RIGHT_A),
		_v3(TableConfig.OUTLANE_DIVIDER_RIGHT_B),
		"OutlaneDividerRight"
	)


## Convert a playfield-local Vector2(x, z) endpoint (the explicit-corner style the gutter constants
## use) to the Vector3(x, 0.0, z) that _add_border_segment expects. Y is 0: walls stand on the
## surface top; _add_border_segment lifts the box to WALL_HEIGHT/2 itself.
static func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## One border line: a thin white wall box from a to b, standing WALL_HEIGHT tall, yawed along the
## chord. Slightly longer than the chord (plus one thickness) so consecutive segments overlap at the
## joints and leave no gap for the ball to slip through.
static func _add_border_segment(
	parent: Node3D, a: Vector3, b: Vector3, seg_name: String
) -> void:
	var h: float = TableConfig.WALL_HEIGHT
	var t: float = TableConfig.WALL_THICKNESS
	var chord: Vector3 = b - a
	var length: float = chord.length() + t
	var mid: Vector3 = (a + b) * 0.5
	mid.y = h * 0.5
	var body: StaticBody3D = _make_box_body(
		parent, seg_name, Vector3(length, h, t), mid,
		PhysicsLayers.STATIC_OBSTACLES, _line_material()
	)
	# Yaw the box so its local +X runs along the a->b chord about +Y.
	body.rotation.y = atan2(-chord.z, chord.x)
	# Skin the box with the Kenney wall model for this segment's ROLE (keeps the collider, hides the
	# white box mesh).
	_skin_with_wall(body, length, h, t, _wall_model_for(seg_name))


## The Kenney wall_border mesh for a border segment's ROLE (the designer's locked split): the NARROW
## launch-lane divider ("LaneDivider") gets the thinner narrow-block.glb; every PERIMETER rail
## ("Border*") gets the wider block-borders.glb. Named-based so table.gd's own segment naming in
## _build_borders is the single source of the role, no extra flag threaded through.
static func _wall_model_for(seg_name: String) -> String:
	if seg_name == "LaneDivider":
		return KenneyModels.NARROW_GUIDE_MODEL
	return KenneyModels.WALL_BORDER_MODEL


## Replace a border box's visible mesh with a scaled copy of the given Kenney wall model, keep the
## box collider. The model is measured (KenneyModels.merged_aabb - the shared, unit-tested helper)
## and fit to the segment (length x h x t) so a re-export self-corrects; its base is seated on the
## surface. Falls back to the white box if the asset is missing (the outline never vanishes).
static func _skin_with_wall(
	body: StaticBody3D, length: float, h: float, t: float, model_path: String
) -> void:
	var scene: Resource = load(model_path)
	if scene == null or not (scene is PackedScene):
		return
	var inst: Node3D = (scene as PackedScene).instantiate()
	var box: AABB = KenneyModels.merged_aabb(inst)
	if box.size.x < 0.0001 or box.size.y < 0.0001 or box.size.z < 0.0001:
		inst.queue_free()
		return
	# hide the gray-box mesh (keep the collider) now that the model is the visible wall
	for c: Node in body.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	inst.scale = Vector3(length / box.size.x, h / box.size.y, t / box.size.z)
	# seat the model base on the surface: the body sits at y = h/2, so drop the child by h/2 and
	# account for where the model's own minimum-Y sits after scaling.
	inst.position = Vector3(0.0, -h * 0.5 - box.position.y * (h / box.size.y), 0.0)
	body.add_child(inst)
