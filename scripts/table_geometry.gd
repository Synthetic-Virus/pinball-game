class_name TableGeometry
extends RefCounted
## TableGeometry - builds the STATIC gray-box geometry of the table (surface, walls, arch, lane).
##
## OWNERSHIP: lead-programmer. This is the fixed shell the ball lives in. It is intentionally NOT a
## behaviour script: it is a builder called by table.gd so the geometry math lives in one place and
## reads every dimension from TableConfig (the world-scale contract). No game rules here.
##
## All collision bodies created are StaticBody3D on the STATIC_OBSTACLES layer (the flat surface is
## on
## the PLAYFIELD layer). Everything is added under the tilted Playfield node passed in by table.gd.
##
## DESIGN LAYOUT honored (DESIGN.md): upright frame, launch lane up the RIGHT side, a rounded top
## ARCH that turns the launched ball into the playfield, perimeter walls, and an OPEN bottom for the
## drain. The bottom edge is deliberately left WALL-LESS so the ball can fall into the drain volume
## (scripts/drain.gd) that table.gd places at TableConfig.DRAIN_Z. Do not add a full-width bottom
## wall here. The ONE exception is _build_lane_pocket: a short stop that closes ONLY the bottom of
## the
## launch lane (x in [LANE_INNER_X, HALF_WIDTH]) so the resting ball does not roll off the open lane
## bottom, while the center drain region (x in [-HALF_WIDTH, LANE_INNER_X]) stays OPEN for the
## drain.
##
## COORDINATE CONVENTION (local to the tilted Playfield, per TableConfig):
##   +X = right, -X = left, -Z = up-table (toward the arch), +Z = down-table (toward the drain).
##   Y = up off the surface. The surface sits at Y = 0; walls stand up to TableConfig.WALL_HEIGHT.

## Entry point. table.gd calls TableGeometry.build(playfield_node).
static func build(playfield: Node3D) -> void:
	_build_surface(playfield)
	_build_perimeter_walls(playfield)
	_build_lane_divider(playfield)
	_build_lane_pocket(playfield)
	_build_arch(playfield)
	_build_lane_guides(playfield)


## A shared gray-box material so every static body reads as the same neutral surface. Built fresh
## per
## call (cheap) so there is no shared mutable global state.
static func _gray_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	return mat


## Create one box StaticBody3D wall: a collision box + a matching gray mesh, on a given layer,
## placed
## at a local position. Centralizes the boilerplate so each wall is one readable call.
static func _make_box_body(
	parent: Node3D,
	body_name: String,
	size: Vector3,
	local_pos: Vector3,
	layer: int
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	# Static geometry detects nothing; it is only detected. Empty mask avoids needless broadphase work.
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
	box_mesh.material = _gray_material()
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)

	parent.add_child(body)
	return body


## The flat table surface: a thin box on the PLAYFIELD layer the ball rolls on. Its top face sits at
## Y = 0 so every element placed at Y = 0 (BALL_START etc.) sits ON the surface.
static func _build_surface(parent: Node3D) -> void:
	# The surface spans the full inner play area plus a little margin so it never has a gap at the
	# wall feet. A small thickness keeps it solid without wasting collision volume.
	var thickness: float = 1.0
	var size := Vector3(
		TableConfig.HALF_WIDTH * 2.0 + TableConfig.WALL_THICKNESS,
		thickness,
		TableConfig.HALF_LENGTH * 2.0 + TableConfig.WALL_THICKNESS
	)
	# Centered at Y = -thickness/2 so the TOP face is at Y = 0.
	_make_box_body(
		parent,
		"Surface",
		size,
		Vector3(0.0, -thickness * 0.5, 0.0),
		PhysicsLayers.PLAYFIELD
	)


## The perimeter walls: LEFT, RIGHT, and TOP. The BOTTOM is intentionally OPEN (the drain lives
## there).
## Walls stand from the surface (Y = 0) up to WALL_HEIGHT, centered at WALL_HEIGHT/2.
static func _build_perimeter_walls(parent: Node3D) -> void:
	var t: float = TableConfig.WALL_THICKNESS
	var h: float = TableConfig.WALL_HEIGHT
	var hw: float = TableConfig.HALF_WIDTH
	var hl: float = TableConfig.HALF_LENGTH
	var wall_y: float = h * 0.5
	var layer: int = PhysicsLayers.STATIC_OBSTACLES

	# Side walls run the FULL length (top to bottom edge) so a ball can never escape sideways. Their
	# length includes the thickness overlap at the top corner so there is no gap with the top wall.
	var side_size := Vector3(t, h, hl * 2.0)
	_make_box_body(parent, "WallLeft", side_size, Vector3(-hw, wall_y, 0.0), layer)
	_make_box_body(parent, "WallRight", side_size, Vector3(hw, wall_y, 0.0), layer)

	# Top wall closes the up-table end. It spans the width plus the corner overlap so the corners seal.
	var top_size := Vector3(hw * 2.0 + t, h, t)
	_make_box_body(parent, "WallTop", top_size, Vector3(0.0, wall_y, -hl), layer)

	# NO bottom wall: the open bottom edge is where a missed ball drains. The drain Area3D (table.gd)
	# sits just inside this edge so the ball is caught before it falls off the open end.


## The lane divider: an inner wall that, with the right outer wall, forms the launch lane up the
## right
## side. It runs from the bottom up to where the arch takes over, so the launched ball is channeled
## up
## the lane and over the arch instead of leaking into the playfield early.
static func _build_lane_divider(parent: Node3D) -> void:
	var t: float = TableConfig.WALL_THICKNESS
	var h: float = TableConfig.WALL_HEIGHT
	var hl: float = TableConfig.HALF_LENGTH
	# The divider's TOP end stops at the arch start so the ball can curve over the top into the field.
	var top_z: float = TableConfig.ARCH_CENTER_Z + TableConfig.ARCH_RADIUS_Z
	# The divider's BOTTOM end stops short of the drain so it does not block the open bottom.
	var bottom_z: float = hl - 1.0
	var length: float = bottom_z - top_z
	var center_z: float = (top_z + bottom_z) * 0.5
	_make_box_body(
		parent,
		"LaneDivider",
		Vector3(t, h, length),
		Vector3(TableConfig.LANE_INNER_X, h * 0.5, center_z),
		PhysicsLayers.STATIC_OBSTACLES
	)


## The launch-lane bottom POCKET: a short static wall that closes ONLY the bottom of the launch lane
## so the ball placed at BALL_START rests in the chute instead of rolling off the open bottom edge
## (the table is tilted drain-end-down and there is deliberately NO bottom perimeter wall). It spans
## ONLY the lane in X (from the lane divider at LANE_INNER_X out to the right wall at HALF_WIDTH);
## the center drain region (x in [-HALF_WIDTH, LANE_INNER_X]) is left OPEN so a drained ball still
## falls into the drain. The wall stands WALL_HEIGHT tall like the perimeter; its up-table face sits
## at TableConfig.LANE_POCKET_FACE_Z, just down-table of the ball's rest, so the ball rests on it.
##
## ADOPTED from prototype/physical-plunger (see BACKLOG LEAD task / ARCHITECTURE.md 9.3). This
## builder was the half dropped during the original slice integration (QA BUG-012); restored here so
## the launch mechanic actually works in the integrated game, not just in the unit tests.
static func _build_lane_pocket(parent: Node3D) -> void:
	var h: float = TableConfig.WALL_HEIGHT
	var t: float = TableConfig.LANE_POCKET_THICKNESS
	var inner_x: float = TableConfig.LANE_INNER_X
	var hw: float = TableConfig.HALF_WIDTH
	# Width spans the lane plus the wall thickness on each side so it seals against the right wall and
	# the lane divider with no corner gap a ball could squeeze through.
	var width: float = (hw - inner_x) + t
	var center_x: float = (inner_x + hw) * 0.5
	# Center the box in Z so its UP-TABLE face lands exactly at LANE_POCKET_FACE_Z.
	var center_z: float = TableConfig.LANE_POCKET_FACE_Z + t * 0.5
	_make_box_body(
		parent,
		"LanePocket",
		Vector3(width, h, t),
		Vector3(center_x, h * 0.5, center_z),
		PhysicsLayers.STATIC_OBSTACLES
	)


## INLANE / OUTLANE GUIDES (SLICE "real pinball furniture"): minimal physical guide walls down BOTH
## sides that funnel a ball past the flipper. Per side a short DIVIDER wall splits the side channel
## into an OUTER lane (the outlane, between the divider and the side wall, feeds the drain = risk)
## and
## an INNER lane (the inlane, between the divider and the flipper, feeds back toward the flipper =
## save). NO rollover scoring, lights, or ball-save (DESIGN cut list) - these are unlit STATIC guide
## walls only, on STATIC_OBSTACLES like the perimeter. The divider X comes from TableConfig
## (LANE_GUIDE_DIVIDER_X, mirrored for the right) and it runs from LANE_GUIDE_TOP_Z down to
## LANE_GUIDE_BOTTOM_Z. Geometry validated by tools/table_viz.py (the feed-path plot).
##
## OWNERSHIP: lead (static geometry). The standup bank, pop bumpers, and slingshots are dynamic
## elements built in table.gd; only these fixed guide walls live in the static geometry builder.
static func _build_lane_guides(parent: Node3D) -> void:
	var h: float = TableConfig.LANE_GUIDE_HEIGHT
	var t: float = TableConfig.LANE_GUIDE_THICKNESS
	var top_z: float = TableConfig.LANE_GUIDE_TOP_Z
	var bottom_z: float = TableConfig.LANE_GUIDE_BOTTOM_Z
	var length: float = bottom_z - top_z
	var center_z: float = (top_z + bottom_z) * 0.5
	var layer: int = PhysicsLayers.STATIC_OBSTACLES

	# One divider per side. The left divider sits at -LANE_GUIDE_DIVIDER_X, the right at +X (mirror).
	# A simple vertical wall (thin in X, long in Z) is enough to separate the two lanes; the outer/
	# inner distinction is purely which side of it the ball travels down.
	for sign: float in [-1.0, 1.0]:
		var divider_x: float = TableConfig.LANE_GUIDE_DIVIDER_X * sign
		var guide_name: String = "LaneGuideLeft" if sign < 0.0 else "LaneGuideRight"
		_make_box_body(
			parent,
			guide_name,
			Vector3(t, h, length),
			Vector3(divider_x, h * 0.5, center_z),
			layer
		)


## The rounded top arch: a polyline of short wall segments approximating a half-ellipse across the
## top
## of the table. It turns the ball, launched up the right lane, back over and DOWN into the
## playfield.
## Built solid: adjacent segments OVERLAP at their joints so there is no gap a fast ball squeezes
## through (DESIGN: the arch must actually redirect a full-speed launched ball, no leaks).
static func _build_arch(parent: Node3D) -> void:
	var h: float = TableConfig.WALL_HEIGHT
	var t: float = TableConfig.WALL_THICKNESS
	var cx: float = 0.0
	var cz: float = TableConfig.ARCH_CENTER_Z
	var rx: float = TableConfig.ARCH_RADIUS_X
	var rz: float = TableConfig.ARCH_RADIUS_Z
	var segments: int = TableConfig.ARCH_SEGMENTS

	# The arch is the UPPER half of an ellipse (angle pi..0 sweeps the top), so it spans the full width
	# at its base and curves up to the top center. We sample points along the ellipse and connect each
	# adjacent pair with a thin box segment, oriented to lie along the chord between them.
	var prev := _ellipse_point(cx, cz, rx, rz, PI)
	for i in range(1, segments + 1):
		var angle: float = lerpf(PI, 0.0, float(i) / float(segments))
		var curr := _ellipse_point(cx, cz, rx, rz, angle)
		_build_arch_segment(parent, prev, curr, h, t, i)
		prev = curr


## A point on the arch ellipse (top half) in local XZ at Y = 0. Up-table is -Z, so the arch curves
## toward -Z at its apex (sin term is subtracted from cz).
static func _ellipse_point(cx: float, cz: float, rx: float, rz: float, angle: float) -> Vector3:
	return Vector3(cx + rx * cos(angle), 0.0, cz - rz * sin(angle))


## One arch segment: a thin box spanning from point a to point b, standing WALL_HEIGHT tall. We make
## it slightly LONGER than the chord (plus one thickness) so consecutive segments overlap at the
## joints and leave no gap for the ball to slip through.
static func _build_arch_segment(
	parent: Node3D,
	a: Vector3,
	b: Vector3,
	height: float,
	thickness: float,
	index: int
) -> void:
	var chord: Vector3 = b - a
	var length: float = chord.length() + thickness
	var mid: Vector3 = (a + b) * 0.5
	mid.y = height * 0.5

	var body := _make_box_body(
		parent,
		"ArchSeg%d" % index,
		Vector3(length, height, thickness),
		mid,
		PhysicsLayers.STATIC_OBSTACLES
	)
	# Rotate the segment about Y so its long (local X) axis lies along the chord in the XZ plane.
	# atan2(-z, x) gives the heading from +X toward -Z, matching Godot's left-handed Y rotation.
	var heading: float = atan2(-chord.z, chord.x)
	body.rotation = Vector3(0.0, heading, 0.0)
