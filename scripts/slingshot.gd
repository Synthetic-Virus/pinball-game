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
## from a box to the triangle; both AGREE (same outline points). The DETECTOR is a thin slab in front
## of the KICKING FACE only (the edge whose outward normal points along the kick direction), so the
## active kick fires when a ball strikes that band - NOT when it merely touches the back, the apex, or
## the top post (developer fix). The solid triangle body still bounces those passive contacts.
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

## Corner rounding: a real slingshot's corners are rubber-wrapped posts, ROUNDED, not sharp triangle
## points. We replace each of the 3 sharp corners with a small arc. CORNER_RADIUS is how far the
## round trims in along each edge; CORNER_SEGMENTS is the arc resolution. Both the collider hull and
## the visible mesh are built from the rounded outline, so they stay in agreement.
const CORNER_RADIUS: float = TableConfig.SLINGSHOT_LENGTH * 0.18
const CORNER_SEGMENTS: int = 4

## Extra rotation applied to the whole sling (its kick direction, and therefore its visible triangle
## and collision, all follow this). Tuning knob for "rotate the slings more" - mirrored per side, so
## both turn symmetrically. Change this one number to dial the angle; flip its sign to turn the other
## way. The kick still points INTO play (a modest rotation keeps the up-table component).
const EXTRA_KICK_ROT_DEG: float = 0.0

## Box dimensions of the kicker face, from TableConfig (resolved in configure()).
var _length: float = TableConfig.SLINGSHOT_LENGTH
var _thickness: float = TableConfig.SLINGSHOT_THICKNESS
var _height: float = TableConfig.SLINGSHOT_HEIGHT
## The FIXED kick direction (unit, playfield-local XZ). Set per side in configure(): the left sling
## kicks toward +X/-Z, the right toward -X/-Z. Both point INTO play (positive up-table component).
var _kick_dir: Vector3 = TableConfig.SLINGSHOT_LEFT_KICK_DIR
## Handedness, for the kick direction. table.gd sets it via configure().
var _mirrored: bool = false
## The THREE triangle corners in ABSOLUTE table coords (x, z), from TableConfig. The sling node sits
## at the origin, so these place the triangle exactly where specified - read straight off the in-game
## grid. This REPLACES the old parametric length/angle/apex shape (which could not honor exact coords).
var _corners: PackedVector2Array = PackedVector2Array()


## Configure this slingshot's side. table.gd calls configure(false) for the left, configure(true)
## for
## the right, after instancing and before adding to the tree. STABLE SIGNATURE.
func configure(mirrored: bool) -> void:
	_mirrored = mirrored
	_thickness = TableConfig.SLINGSHOT_THICKNESS
	_height = TableConfig.SLINGSHOT_HEIGHT
	points = TableConfig.SLINGSHOT_SCORE
	# SHAPE: the three corner posts at EXACT coords (no parametric approximation).
	var src: Array[Vector2] = (
		TableConfig.SLINGSHOT_RIGHT_CORNERS if _mirrored else TableConfig.SLINGSHOT_LEFT_CORNERS
	)
	_corners = PackedVector2Array(src)
	# KICK direction (separate from the shape): the load-bearing "into play, never the drain" guarantee.
	var raw_dir: Vector3 = (
		TableConfig.SLINGSHOT_RIGHT_KICK_DIR if _mirrored else TableConfig.SLINGSHOT_LEFT_KICK_DIR
	)
	_kick_dir = raw_dir.normalized()


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


## Detector shape: a thin slab ONLY in front of the KICKING FACE, not the whole triangle (developer:
## the sling fired when the ball merely reached the top post). The kicking face is the edge whose
## OUTWARD normal points along the kick direction - the band a ball strikes to be fired into play. The
## slab spans that face from post to post, a little behind it (to catch contact) out to ~one ball-
## diameter in front. A ball touching the BACK, the apex, or the top post is now outside the detector,
## so it just bounces off the solid triangle body (which is unchanged) WITHOUT triggering an active
## kick. The behavioral + no-tunnel tests fire INTO this face from the front, so they still trip it.
func _make_detector_shape() -> Shape3D:
	var face: Array = _kicking_face()
	var a: Vector2 = face[0]
	var b: Vector2 = face[1]
	var n: Vector2 = face[2]
	# The Area-vs-ball overlap ALREADY adds the ball's radius, so the Area fires when the ball SURFACE
	# reaches the Area edge. Put the front edge exactly AT the face (front = 0): the kick then fires at
	# true surface contact, with no forward cone of early triggering (developer: "triggering in a cone
	# before it hits"). `back` runs into the solid body (unreachable from the front) so a fast ball
	# still trips the thin Area between physics frames. The slab spans the full face post-to-post so a
	# corner contact still kicks (QA BUG-018).
	var back: float = TableConfig.BALL_RADIUS  ## depth into the body (catches fast contact)
	var front: float = 0.0                     ## exactly at the face: kick fires on contact, not before
	var quad := PackedVector2Array([a - n * back, b - n * back, b + n * front, a + n * front])
	var hull := ConvexPolygonShape3D.new()
	hull.points = _extrude_triangle_to_hull(quad, _height)
	return hull


## The KICKING FACE among the three corner posts: the edge whose OUTWARD normal best aligns with the
## kick direction. Returns [a, b, normal] in local X-Z, the normal a unit vector pointing toward play.
## This is the band the ball strikes; the apex/back edges are not active.
func _kicking_face() -> Array:
	var c: PackedVector2Array = _raw_corners()
	var centroid := Vector2.ZERO
	for p: Vector2 in c:
		centroid += p
	centroid /= float(c.size())
	var kick2 := Vector2(_kick_dir.x, _kick_dir.z)
	var best_dot: float = -1.0e20
	var result: Array = [c[0], c[1], Vector2(0.0, 1.0)]
	for i: int in range(c.size()):
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % c.size()]
		var edge: Vector2 = b - a
		if edge.length() < 0.0001:
			continue
		var nrm := Vector2(edge.y, -edge.x).normalized()  ## perpendicular to the edge
		var mid: Vector2 = (a + b) * 0.5
		if (mid - centroid).dot(nrm) < 0.0:
			nrm = -nrm  ## ensure the normal points OUTWARD (away from the triangle centre)
		var d: float = nrm.dot(kick2)
		if d > best_dot:
			best_dot = d
			result = [a, b, nrm]
	return result


## The TRIANGULAR visible mesh (fix 3: was a box), built from the SAME outline as the collider so
## the visible slingshot AGREES with the body it bounces off. The base adds this to the kicker root;
## we bake the body yaw into the mesh here so the visible triangle angles into play exactly like the
## (yawed) solid body. The structural test asserts the mesh is not a BoxMesh.
func _make_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_triangle_mesh(_triangle_outline(), _height)
	# The solid body is yawed by _body_yaw() in the base; yaw the visible mesh the same so they agree.
	mesh_instance.transform = Transform3D(Basis(Vector3(0.0, 1.0, 0.0), _body_yaw()), Vector3.ZERO)
	# A real slingshot is THREE rubber posts with bands stretched between them. Add those as children of
	# the (yawed) mesh so they inherit its orientation and sit exactly on the collider's three corners.
	_add_posts_and_rubber(mesh_instance)
	return mesh_instance


## Build the visible 3-post-and-rubber assembly (posts at the triangle corners, bands along the edges)
## as children of the yawed mesh. PURELY visual - the collider and active kick are unchanged - so this
## gives the slingshot its real look without touching the proven physics.
func _add_posts_and_rubber(parent: Node3D) -> void:
	var corners: PackedVector2Array = _raw_corners()
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.72, 0.10, 0.10)  ## red rubber, like the reference posts
	var post_r: float = _thickness * 0.6
	# Posts: short cylinders standing a little taller than the rubber band, one per corner.
	for c: Vector2 in corners:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = post_r
		cyl.bottom_radius = post_r
		cyl.height = _height * 1.15
		cyl.material = rubber
		post.mesh = cyl
		post.position = Vector3(c.x, 0.0, c.y)
		parent.add_child(post)
	# Rubber bands: a thin bar along each edge, between consecutive posts, at mid height.
	for i: int in range(corners.size()):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var edge: Vector2 = b - a
		var mid: Vector2 = (a + b) * 0.5
		var band := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(edge.length(), _height * 0.55, post_r * 0.8)
		bar.material = rubber
		band.mesh = bar
		band.position = Vector3(mid.x, 0.0, mid.y)
		# Align the bar's local +X with the edge direction (about +Y): X -> (cos, 0, -sin).
		band.rotation.y = atan2(-edge.y, edge.x)
		parent.add_child(band)


## The triangle footprint in the body's LOCAL X-Z plane (before _body_yaw). The long KICKING FACE is
## the edge A to B along +X at +Z (its outward normal is +Z, which _body_yaw turns into the kick
## direction). The apex C sits BACK on -Z, offset toward one end per handedness so the left sling is
## a left-handed triangle and the right (mirrored) sling a right-handed one. Returned CCW so the cap
## fan/winding is consistent. Three (x, z) points.
func _triangle_outline() -> PackedVector2Array:
	# Round the three sharp corners into small arcs (rubber-wrapped posts are round, not pointed).
	# Both the collider hull and the visible mesh consume this outline, so this rounds both at once.
	return _round_corners(_raw_corners(), CORNER_RADIUS, CORNER_SEGMENTS)


## The THREE raw corners of the slingshot triangle (local X-Z, before rounding) - A and B are the
## kicking-face ends at +Z, C is the apex back on -Z. These are also where the visible rubber POSTS
## stand (a real slingshot is three posts with rubber stretched between them), so the collider and the
## posts share one definition. Apex X is offset per handedness so the pointed corner aims at the
## GUTTER (outer end): hand_sign +1 for the left sling, -1 for the right (mirror).
func _raw_corners() -> PackedVector2Array:
	# The three corner posts exactly as specified in TableConfig (absolute table coords). No parametric
	# length/angle/apex - what the developer gives is what gets built.
	return _corners


## Replace each sharp corner of a CCW (x, z) polygon with a rounded arc. For each vertex we trim in
## along both adjacent edges by `radius` (clamped so we never overrun a short edge) and sweep a
## quadratic-Bezier arc through the original corner. Winding (CCW/CW) is preserved, so the cap-orient
## and signed-area logic still work. Returns the expanded outline (more points, same convex shape).
func _round_corners(poly: PackedVector2Array, radius: float, seg: int) -> PackedVector2Array:
	var n: int = poly.size()
	var out := PackedVector2Array()
	for i in range(n):
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % n]
		var to_prev: Vector2 = prev - cur
		var to_next: Vector2 = nxt - cur
		# Clamp the trim so a short edge can't be overrun (keeps the rounded shape valid + convex).
		var d: float = minf(radius, minf(to_prev.length() * 0.49, to_next.length() * 0.49))
		var p_start: Vector2 = cur + to_prev.normalized() * d
		var p_end: Vector2 = cur + to_next.normalized() * d
		out.append(p_start)
		for s in range(1, seg):
			var t: float = float(s) / float(seg)
			var u: float = 1.0 - t
			# Quadratic Bezier with the sharp corner as the control point = a smooth rounded corner.
			out.append(p_start * (u * u) + cur * (2.0 * u * t) + p_end * (t * t))
		out.append(p_end)
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
## AGREE. A single-surface gray-box mesh (sides + top cap + bottom cap).
##
## QA BUG-032 HARDENING (2026-06-20): the caps were emitted with a FIXED vertex order (A->B->C top,
## A->C->B bottom). QA flagged that the mirrored RIGHT slingshot could face the top cap DOWN (-Y)
## and be back-face-culled (the same class of mirrored-winding bug flipper.gd fixes). On THIS
## triangle the fixed order happens to face +Y for BOTH sides (the kicking-face vertices A and B are
## fixed and only
## the apex moves along the same z-line, so the mirror does NOT reverse the winding sign here - QA's
## analysis assumed a full X-negation like flipper.gd's). To make the cap orientation correct
## REGARDLESS of any future outline change, we now orient each cap from the outline's ACTUAL signed
## area in the X-Z plane so the TOP cap always faces +Y and the BOTTOM always faces -Y, with no
## per-side flag to thread. The side walls wrap the perimeter and read fine under generate_normals.
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
	# Caps: orient from the outline's signed area so the TOP faces +Y and the BOTTOM faces -Y for both
	# the left (CCW) and the mirrored right (CW) outlines (QA BUG-032). A CCW X-Z triangle's forward
	# fan normal (via (v1-v0)x(v2-v0)) points -Y, so a CCW outline needs the top cap REVERSED to face
	# +Y; a CW outline (the mirrored sling) needs it forward. _signed_area_xz < 0 means CW.
	var top_forward: bool = _signed_area_xz(outline) < 0.0
	# Caps as a triangle FAN from vertex 0 over the FULL outline (now rounded, so N > 3 points). The
	# old code fanned only the first 3 points, which left a rounded cap unfilled. Winding per the
	# signed area so TOP faces +Y and BOTTOM faces -Y for both the left (CCW) and mirrored (CW) slings.
	for i in range(1, n - 1):
		var a_t := Vector3(outline[0].x, half_h, outline[0].y)
		var i_t := Vector3(outline[i].x, half_h, outline[i].y)
		var j_t := Vector3(outline[i + 1].x, half_h, outline[i + 1].y)
		# Top cap (+Y).
		st.add_vertex(a_t)
		if top_forward:
			st.add_vertex(i_t)
			st.add_vertex(j_t)
		else:
			st.add_vertex(j_t)
			st.add_vertex(i_t)
		# Bottom cap (-Y): opposite winding of the top cap.
		var a_b := Vector3(outline[0].x, -half_h, outline[0].y)
		var i_b := Vector3(outline[i].x, -half_h, outline[i].y)
		var j_b := Vector3(outline[i + 1].x, -half_h, outline[i + 1].y)
		st.add_vertex(a_b)
		if top_forward:
			st.add_vertex(j_b)
			st.add_vertex(i_b)
		else:
			st.add_vertex(i_b)
			st.add_vertex(j_b)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	st.set_material(mat)
	st.commit(mesh)
	return mesh


## Signed area of a top-down (x, z) outline in the X-Z plane (the shoelace formula). Positive when
## the points wind counter-clockwise, negative when clockwise. Used to orient the prism caps so the
## top always faces +Y regardless of the per-side mirror (QA BUG-032).
func _signed_area_xz(outline: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = outline.size()
	for i in range(n):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


## Yaw the body (and, via _detector_yaw + _make_mesh, the detector and the visible mesh) so the
## KICKING FACE normal aligns with the kick direction. The triangle outline puts the long kicking
## face (edge A-B) at the body's LOCAL +Z, so its outward normal is local +Z; we rotate so that
## local +Z maps to _kick_dir (into play). The face then faces where the ball is fired, the visible
## triangle reads correctly (the player sees the ball strike the long inner face, not the
## apex), and the solid body + detector enclose that contact.
##
## QA BUG-030 FIX (2026-06-20): the prior formula atan2(x, -z) rotated local +Z to the OPPOSITE of
## the kick direction (it aligned +Z with -_kick_dir), so the visible kicking face pointed at the
## DRAIN while the ball was actually fired up-table. The physics outcome was already correct (the
## base _apply_kick SETS the velocity along _kick_dir, independent of this yaw), but the MESH and
## the solid body faced the wrong way, so the player saw the ball bounce off the BACK (apex) of the
## triangle. The correct heading that maps a body-local +Z column vector to _kick_dir under Godot's
## Y-basis is atan2(kick.x, kick.z) (verified against the arch's proven atan2(-chord.z, chord.x)
## heading convention). For the left kick (0.6, 0, -0.8) this yaw maps local +Z -> (0.6, 0, -0.8)
## exactly; the previous formula mapped it to (0.6, 0, +0.8), into the drain.
func _body_yaw() -> float:
	# ZERO: the triangle is now defined by EXACT corner coords in absolute table space (see
	# _raw_corners), so no extra rotation is applied - the shape is exactly what was specified. The
	# kick direction (_kick_direction_for) is separate and still fires into play.
	return 0.0
