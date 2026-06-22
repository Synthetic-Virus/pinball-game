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

## Entry point. table.gd calls TableGeometry.build(playfield_node).
static func build(playfield: Node3D) -> void:
	_build_surface(playfield)
	_build_borders(playfield)
	_build_lane_guides(playfield)
	if SHOW_COORD_GRID:
		_build_coord_grid(playfield)


## Inlane guide rails (markup piece 4, FIRST PASS for the developer to refine off the grid). One rail
## per side, angling in from below the slingshot toward the flipper, forming the return inlane. Given
## as start/end coords in absolute table space (read straight off the grid); replace with the exact
## line the developer marks. Built as white wall segments via _add_border_segment.
static func _build_lane_guides(parent: Node3D) -> void:
	# Left rail then right (mirror). a = top (near sling bottom), b = down toward the flipper.
	_add_border_segment(parent, Vector3(-10.0, 0.0, 13.0), Vector3(-8.0, 0.0, 20.5), "InlaneGuideL")
	_add_border_segment(parent, Vector3(10.0, 0.0, 13.0), Vector3(8.0, 0.0, 20.5), "InlaneGuideR")


## Draw a faint coordinate grid on the surface, brighter axis lines through (0,0), and floating number
## labels along the edges, so the developer can read (x, z) straight off the 3D board. Visual only -
## no collision, no gameplay effect. Lines sit a hair above the surface (y) so they show on the dark
## top. Grid step is 4 world units; labels every 4 along the bottom (x) and left (z) edges.
static func _build_coord_grid(parent: Node3D) -> void:
	var hw: float = TableConfig.HALF_WIDTH
	var hl: float = TableConfig.HALF_LENGTH
	var y: float = 0.06  ## just above the surface top (y=0)
	var minor := StandardMaterial3D.new()
	minor.albedo_color = Color(0.30, 0.32, 0.40)  ## very faint, the every-2 lines
	var major := StandardMaterial3D.new()
	major.albedo_color = Color(0.45, 0.48, 0.58)  ## brighter, the every-4 lines
	var axis := StandardMaterial3D.new()
	axis.albedo_color = Color(0.20, 0.65, 1.0)  ## bright blue for the x=0 / z=0 axes

	# Vertical grid lines (constant x, running in z), every 2 units; every-4 brighter; x=0 is the axis.
	var x: int = -16
	while x <= 16:
		var mat: StandardMaterial3D = axis if x == 0 else (major if x % 4 == 0 else minor)
		var w: float = 0.18 if x == 0 else (0.08 if x % 4 == 0 else 0.05)
		_grid_strip(parent, Vector3(float(x), y, 0.0), Vector3(w, 0.04, hl * 2.0), mat)
		x += 2
	# Horizontal grid lines (constant z, running in x), every 2 units; every-4 brighter; z=0 is axis.
	var z: int = -24
	while z <= 24:
		var mat2: StandardMaterial3D = axis if z == 0 else (major if z % 4 == 0 else minor)
		var t: float = 0.18 if z == 0 else (0.08 if z % 4 == 0 else 0.05)
		_grid_strip(parent, Vector3(0.0, y, float(z)), Vector3(hw * 2.0, 0.04, t), mat2)
		z += 2

	# Number labels: x values along the bottom edge, z values along the left edge.
	var xl: int = -16
	while xl <= 16:
		_grid_label(parent, "%d" % xl, Vector3(float(xl), y, hl - 1.0))
		xl += 4
	var zl: int = -24
	while zl <= 24:
		_grid_label(parent, "%d" % zl, Vector3(-hw + 1.0, y, float(zl)))
		zl += 4
	_grid_label(parent, "0,0", Vector3(1.2, y, 1.2))


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
	var outline: Array[Vector3] = [
		Vector3(-16.4, 0.0, 24.0),    ## bottom-left (left wall, near the drain)
		Vector3(-16.4, 0.0, -17.0),   ## up the left wall to where the corner begins
		Vector3(-15.2, 0.0, -21.0),   ## rounded top-left corner (3 short chords)
		Vector3(-13.0, 0.0, -23.6),
		Vector3(-10.6, 0.0, -25.0),   ## top edge begins
		Vector3(10.6, 0.0, -25.0),    ## top edge ends (symmetric)
		Vector3(13.0, 0.0, -23.6),    ## rounded top-right corner (3 short chords)
		Vector3(15.2, 0.0, -21.0),
		Vector3(16.4, 0.0, -17.0),    ## down to where the right wall begins
		Vector3(16.4, 0.0, 24.0),     ## down the right wall toward the drain
	]
	for i: int in range(outline.size() - 1):
		_add_border_segment(parent, outline[i], outline[i + 1], "Border%d" % i)

	# The launch-lane divider: the inner right wall forming the shooter lane (x ~ +14.5), parallel to
	# the right wall. It STOPS short of the top (z -16) so the top of the lane is OPEN: a launched ball
	# clears the divider and curves left into the field around the rounded top-right corner, instead of
	# being sealed in the corner (developer feedback).
	_add_border_segment(
		parent, Vector3(14.5, 0.0, -16.0), Vector3(14.5, 0.0, 23.0), "LaneDivider"
	)


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
