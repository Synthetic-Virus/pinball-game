extends "res://scripts/active_kicker.gd"
## Slingshot - an active angled kicker above a flipper that fires the ball UP-table and toward
## center.
##
## A slingshot is an ActiveKicker (shared base owns the cap/cooldown/score) whose KICK DIRECTION is
## FIXED: its face normal, pointing into play. A ball dropping down the side and grazing the sling
## is
## kicked back UP and toward center (DESIGN must-feel: "saved by the slings"), NEVER down toward the
## drain. Unlike the pop bumper (radial), the direction is constant so the ball always returns into
## play regardless of exactly where it touched the angled face.
##
## GEOMETRY (SLICE "Playtest fixes 2", fix 3 - TRIANGLE, not a box): the slingshot solid body AND
## its visible mesh are now a TRIANGULAR prism (footprint = a right triangle), left-handed above
## the LEFT flipper and mirrored (right-handed) above the RIGHT flipper, like a real pinball
## slingshot. The long KICKING FACE (the hypotenuse the ball strikes) lies along the body's local +X
## at +Z (the face whose normal _body_yaw rotates to the kick direction), so the EXISTING kick is
## UNCHANGED: same SLINGSHOT_LEFT/RIGHT_KICK_DIR, same score, same cooldown, same CCD-safe cap (all
## owned by the ActiveKicker base). Only the SHAPE the ball bounces off and the visible mesh change
## from a box to the triangle; both AGREE (same outline points). The DETECTOR keeps the BUG-018
## corner-contact guarantee (it stays padded + yawed to match the body so a ball striking near a
## corner of the angled face still trips body_entered and gets the active kick + score).
##
## OWNERSHIP: lead scaffolds the triangle outline + the shape/mesh hooks; physics-programmer fills
## _build_body/_apply_kick in the BASE (shared) and owns the no-tunnel gate on the triangular face;
## this file's _kick_direction_for + configure are small and stable.
##
## STABLE CONTRACT: inherits scored(points), kicked(direction), set_ball, points from ActiveKicker.
##   func configure(mirrored: bool) -> void   # mirrored = true builds the RIGHT slingshot.

## How far the triangle extends BACK (away from the kicking face, local -Z) from the face to its
## apex. A real slingshot is a shallow-ish triangle; we use SLINGSHOT_THICKNESS scaled up so the
## triangle reads clearly as a triangle (not a sliver) while staying a compact body that does not
## intrude into the flipper/lane-guide space. WHY a local constant (not TableConfig): it is a pure
## visual/collision proportion of the existing SLINGSHOT_LENGTH/THICKNESS, not a world-scale or
## placement number, so it lives with the shape it describes (no TableConfig edit needed for fix 3).
const TRIANGLE_BACK_DEPTH: float = TableConfig.SLINGSHOT_LENGTH * 0.55

## Box dimensions of the kicker face, from TableConfig (resolved in configure()).
var _length: float = TableConfig.SLINGSHOT_LENGTH
var _thickness: float = TableConfig.SLINGSHOT_THICKNESS
var _height: float = TableConfig.SLINGSHOT_HEIGHT
## The FIXED kick direction (unit, playfield-local XZ). Set per side in configure(): the left sling
## kicks toward +X/-Z, the right toward -X/-Z. Both point INTO play (positive up-table component).
var _kick_dir: Vector3 = TableConfig.SLINGSHOT_LEFT_KICK_DIR
## Handedness, for the face angle and the kick direction. table.gd sets it via configure().
var _mirrored: bool = false


## Configure this slingshot's side. table.gd calls configure(false) for the left, configure(true)
## for
## the right, after instancing and before adding to the tree. STABLE SIGNATURE.
func configure(mirrored: bool) -> void:
	_mirrored = mirrored
	_length = TableConfig.SLINGSHOT_LENGTH
	_thickness = TableConfig.SLINGSHOT_THICKNESS
	_height = TableConfig.SLINGSHOT_HEIGHT
	points = TableConfig.SLINGSHOT_SCORE
	# The kick direction is the load-bearing "into play, never the drain" guarantee. Pick per side.
	_kick_dir = (
		TableConfig.SLINGSHOT_RIGHT_KICK_DIR if _mirrored
		else TableConfig.SLINGSHOT_LEFT_KICK_DIR
	).normalized()


## FIXED kick: always the face normal into play, independent of the contact point (ball_pos unused).
## This is why a slingshot reliably returns the ball into play: the direction never depends on where
## the ball hit the angled face. The vector is validated by table_viz to have a positive up-table
## component and a toward-center X sign (never aimed at the drain or the side wall).
func _kick_direction_for(_ball_pos: Vector3) -> Vector3:
	return _kick_dir


## The TRIANGULAR solid body the ball bounces off (fix 3: was a BoxShape3D). A ConvexPolygonShape3D
## hull whose top-down footprint is a right triangle: the long KICKING FACE runs along local +X at
## +Z (its normal is +Z, which _body_yaw rotates to the kick direction - so the kick is UNCHANGED),
## tapering back to an apex on -Z, offset per handedness so the left and right slings are mirrored.
## The hull is extruded to _height. The structural test asserts this is NOT a BoxShape3D.
func _make_body_shape() -> Shape3D:
	var hull := ConvexPolygonShape3D.new()
	hull.points = _extrude_triangle_to_hull(_triangle_outline(), _height)
	return hull


## Detector shape: a triangle outline PADDED by one BALL_RADIUS so body_entered fires as the ball
## arrives anywhere on the face, including near the CORNERS of the angled face (QA BUG-018). The
## base yaws this detector by _detector_yaw() (== _body_yaw) to stay concentric with the body, so a
## corner contact still trips body_entered (no silent "limp bounce"). We pad by inflating the tri
## outline outward (a simple uniform expand: scale each point away from the triangle centroid by one
## BALL_RADIUS-worth), keeping the same triangular footprint a ball-radius larger.
func _make_detector_shape() -> Shape3D:
	var hull := ConvexPolygonShape3D.new()
	hull.points = _extrude_triangle_to_hull(
		_padded_triangle_outline(TableConfig.BALL_RADIUS), _height
	)
	return hull


## The TRIANGULAR visible mesh (fix 3: was a box), built from the SAME outline as the collider so
## the visible slingshot AGREES with the body it bounces off. The base adds this to the kicker root;
## we bake the body yaw into the mesh here so the visible triangle angles into play exactly like the
## (yawed) solid body. The structural test asserts the mesh is not a BoxMesh.
func _make_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_triangle_mesh(_triangle_outline(), _height)
	# The solid body is yawed by _body_yaw() in the base; yaw the visible mesh the same so they agree.
	mesh_instance.transform = Transform3D(Basis(Vector3(0.0, 1.0, 0.0), _body_yaw()), Vector3.ZERO)
	return mesh_instance


## The triangle footprint in the body's LOCAL X-Z plane (before _body_yaw). The long KICKING FACE is
## the edge A to B along +X at +Z (its outward normal is +Z, which _body_yaw turns into the kick
## direction). The apex C sits BACK on -Z, offset toward one end per handedness so the left sling is
## a left-handed triangle and the right (mirrored) sling a right-handed one. Returned CCW so the cap
## fan/winding is consistent. Three (x, z) points.
func _triangle_outline() -> PackedVector2Array:
	var half_l: float = _length * 0.5
	var face_z: float = _thickness * 0.5            ## the kicking face sits at +Z (its normal is +Z).
	var apex_z: float = -TRIANGLE_BACK_DEPTH         ## the apex points back, away from play.
	# Apex X offset per handedness: a real slingshot's apex sits toward the OUTER (side-wall) end. The
	# mirror flips which end. hand_sign is +1 for the left sling, -1 for the right (mirror).
	var hand_sign: float = -1.0 if _mirrored else 1.0
	var apex_x: float = half_l * hand_sign
	var pts := PackedVector2Array()
	pts.append(Vector2(-half_l, face_z))   ## A: kicking-face end 1
	pts.append(Vector2(half_l, face_z))    ## B: kicking-face end 2
	pts.append(Vector2(apex_x, apex_z))    ## C: apex (back, offset per side)
	return pts


## The triangle outline expanded OUTWARD by `pad` (world units) for the detector, so the detector is
## one ball-radius larger than the solid body on every side + corner (QA BUG-018 corner guarantee).
## We push each vertex away from the centroid by `pad`; for a compact triangle this keeps the same
## shape a uniform margin larger, which is all the corner-contact detector needs.
func _padded_triangle_outline(pad: float) -> PackedVector2Array:
	var base: PackedVector2Array = _triangle_outline()
	var cx: float = (base[0].x + base[1].x + base[2].x) / 3.0
	var cz: float = (base[0].y + base[1].y + base[2].y) / 3.0
	var out := PackedVector2Array()
	for p: Vector2 in base:
		var dir := Vector2(p.x - cx, p.y - cz)
		if dir.length() > 0.0001:
			dir = dir.normalized()
		out.append(Vector2(p.x + dir.x * pad, p.y + dir.y * pad))
	return out


## Extrude a top-down (x, z) triangle outline to a 3D point cloud for a ConvexPolygonShape3D: each
## outline point becomes two 3D points at +/- height/2 (Y is the surface normal). The convex hull of
## the cloud is the solid triangular prism. Mirrors flipper.gd._extrude_outline_to_hull in spirit.
func _extrude_triangle_to_hull(outline: PackedVector2Array, height: float) -> PackedVector3Array:
	var half_h: float = height * 0.5
	var cloud := PackedVector3Array()
	for p: Vector2 in outline:
		cloud.append(Vector3(p.x, half_h, p.y))
		cloud.append(Vector3(p.x, -half_h, p.y))
	return cloud


## Build the visible triangular-prism mesh from the same (x, z) outline as the collider so the two
## AGREE. A single-surface gray-box mesh (sides + top cap + bottom cap). The exact normals are not
## load-bearing for a gray-box visual; generate_normals gives readable shading.
func _build_triangle_mesh(outline: PackedVector2Array, height: float) -> ArrayMesh:
	var half_h: float = height * 0.5
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = outline.size()
	# Side walls: a quad per outline edge (top -> bottom), wound outward.
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var a_top := Vector3(a.x, half_h, a.y)
		var b_top := Vector3(b.x, half_h, b.y)
		var a_bot := Vector3(a.x, -half_h, a.y)
		var b_bot := Vector3(b.x, -half_h, b.y)
		st.add_vertex(a_top)
		st.add_vertex(a_bot)
		st.add_vertex(b_top)
		st.add_vertex(b_top)
		st.add_vertex(a_bot)
		st.add_vertex(b_bot)
	# Top cap (face +Y) and bottom cap (face -Y) as single triangles (the footprint is a triangle).
	st.add_vertex(Vector3(outline[0].x, half_h, outline[0].y))
	st.add_vertex(Vector3(outline[1].x, half_h, outline[1].y))
	st.add_vertex(Vector3(outline[2].x, half_h, outline[2].y))
	st.add_vertex(Vector3(outline[0].x, -half_h, outline[0].y))
	st.add_vertex(Vector3(outline[2].x, -half_h, outline[2].y))
	st.add_vertex(Vector3(outline[1].x, -half_h, outline[1].y))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	st.set_material(mat)
	st.commit(mesh)
	return mesh


## Yaw the box so its flat face normal aligns with the kick direction (the face kicks the ball along
## its normal). The kick direction is in XZ; the face normal of an unrotated box (thin in Z) is
## +/-Z,
## so the yaw is the angle from -Z to the kick direction about Y. This keeps the visible angled wall
## consistent with where the ball is actually fired.
func _body_yaw() -> float:
	# atan2(x, -z): heading of the kick direction measured from the up-table (-Z) axis about +Y.
	return atan2(_kick_dir.x, -_kick_dir.z)
