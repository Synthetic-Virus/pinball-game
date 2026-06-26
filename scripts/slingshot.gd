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
## from a box to the triangle; both AGREE (same outline points). The DETECTOR is a thin slab in
## front of the KICKING FACE only (the edge whose outward normal points along the kick direction),
## so the active kick fires when a ball strikes that band - NOT when it merely touches the back, the
## apex, or the top post (developer fix). The solid triangle body still bounces those passive
## contacts.
##
## OWNERSHIP: lead scaffolds the triangle outline + the shape/mesh hooks; physics-programmer fills
## _build_body/_apply_kick in the BASE (shared) and owns the no-tunnel gate on the triangular face;
## this file's _kick_direction_for + configure are small and stable.
##
## STABLE CONTRACT: inherits scored(points), kicked(direction), set_ball, points from ActiveKicker.
##   func configure(mirrored: bool) -> void   # mirrored = true builds the RIGHT slingshot.

## Corner rounding: a real slingshot's corners are rubber-wrapped posts, ROUNDED, not sharp triangle
## points. We replace each of the 3 sharp corners with a small arc. CORNER_RADIUS is how far the
## round trims in along each edge; CORNER_SEGMENTS is the arc resolution. Both the collider hull and
## the visible mesh are built from the rounded outline, so they stay in agreement.
const CORNER_RADIUS: float = TableConfig.SLINGSHOT_LENGTH * 0.18
const CORNER_SEGMENTS: int = 4

## SLICE "Low-poly slingshot asset" (2026-06-24): the imported low-poly model that REPLACES the
## procedural gray-box triangle + posts/rubber as the VISIBLE art. Visual-only: the ball still
## collides with the ConvexPolygonShape3D body built by _make_body_shape (see ARCHITECTURE.md 14.1).
## If the .glb fails to import, the gray-box triangle (_make_mesh / _add_posts_and_rubber) STAYS so
## the sling never vanishes (copy of the pop_bumper.gd fallback guard). The model is authored as the
## LEFT slingshot; the RIGHT instance mirrors the visual by a negative-X scale (see _mirror_visual).
const SLINGSHOT_ASSET_PATH: String = "res://assets/models/left_slingshot.glb"

## The RIGHT slingshot uses a PRE-MIRRORED .glb (baked in Blender with recalculated outward
## normals), so it renders correct-side-out without a runtime negative-X scale. The old
## negative-scale mirror flipped the normals and shaded the right sling dark/inside-out. The
## collider mirror stays a position/rotation mirror via SLINGSHOT_RIGHT_CORNERS in configure().
const SLINGSHOT_RIGHT_ASSET_PATH: String = "res://assets/models/right_slingshot.glb"

## The node name the imported .glb visual is instanced under. Tests resolve the imported visual by
## this name; the procedural fallback keeps its base name "KickerMesh" (built by active_kicker.gd).
const SLINGSHOT_VISUAL_NODE_NAME: String = "SlingshotVisual"

## Object names inside the .glb the cosmetic flex animation drives (visual-only; see _play_flex).
## The kicker finger + its red tip jab outward and snap back; the rubber ring flexes and snaps back.
const KICKER_FINGER_NODE: String = "Kicker_Finger"
const KICKER_TIP_NODE: String = "Kicker_Tip"
const RUBBER_RING_NODE: String = "Sling_Rubber_Ring"

## Flex animation timing (seconds): a quick jab out, then a snap back. Cosmetic only - decoupled
## from the impulse (the behavioral test asserts the ball velocity is identical with this anim or
## stubbed). Total round-trip ~110 ms reads as a crisp solenoid jab without lingering.
const FLEX_JAB_TIME_S: float = 0.045
const FLEX_RETURN_TIME_S: float = 0.065
## How far (world units) the kicker finger jabs along the kick direction at full extension. Small -
## the finger only pokes; the rubber band does the visible work. Sized off the ball radius so it
## scales with the world, never a bare literal.
const FLEX_JAB_DISTANCE: float = TableConfig.BALL_RADIUS * 0.6
## How far the rubber ring stretches (extra scale on its long axis) at the peak of the flex.
const FLEX_RUBBER_STRETCH: float = 0.18

## TEST SEAM (copy of pop_bumper.gd): force the imported-asset load to use a different path so a
## test can drive the fallback branch (a bad path leaves the gray-box visible). "" means "use
## SLINGSHOT_ASSET_PATH" (the production path).
var _asset_path_override: String = ""

## The instanced .glb visual root (null until _install_art succeeds). The flex animation drives the
## nodes UNDER this; the mirror (negative-X scale) is applied to this node for the RIGHT sling.
var _visual: Node3D = null

## The currently-running flex Tween (null when idle). QA BUG-044: a node-bound Tween in Godot 4 runs
## to completion; it is NOT garbage-collected just because the local handle is dropped. So a rapid
## double-kick would leave the FIRST tween still driving the same node properties while the second
## one fights it. We keep the handle and kill() the prior tween when each flex starts, so just one
## ever animates a node, ending the stacked drift the old "orphaned, reclaimed" comment assumed.
var _flex_tween: Tween = null

## The AUTHORED rest state of the flex nodes, captured ONCE after the art installs (before any flex
## runs). QA BUG-044: the snap-back target must be the AUTHORED rest, not the node's live position
## when _play_flex is called - on a rapid double-kick that live read returns the mid-jab spot, so
## the node would creep out by up to FLEX_JAB_DISTANCE per overlapping kick. Caching the true rest
## once makes every snap-back land exactly home regardless of timing.
var _finger_rest: Vector3 = Vector3.ZERO
var _tip_rest: Vector3 = Vector3.ZERO
var _ring_rest_scale: Vector3 = Vector3.ONE

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
## at the origin, so these place the triangle exactly where specified - read straight off the
## in-game grid. This REPLACES the old parametric length/angle/apex shape (which could not honor
## exact coords).
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
	# KICK direction (separate from the shape): the "into play, never the drain" guarantee.
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


## Detector = the EXACT triangle body (same hull as _make_body_shape), so body_entered fires at real
## contact anywhere on the triangle. WHERE the contact landed is then judged by
## _contact_should_kick: only a contact on the kicking BAND fires the solenoid; the posts/back
## bounce passively. This is the "true contact point" behavior the developer asked for, no proximity
## padding to cause an early cone of triggering.
func _make_detector_shape() -> Shape3D:
	return _make_body_shape()


## CONTACT GATE: kick ONLY when the ball contacts the kicking BAND (the face edge), not the posts or
## the back of the triangle. We judge from the ball's contact position in the sling's local X-Z: it
## must be on the FRONT (play) side of the face line AND projected within the face span (post-post),
## allowing ~half a ball past each end so a genuine end-of-band hit still kicks (QA BUG-018) while a
## ball out past a post (the top post the developer circled) does not.
func _contact_should_kick(ball_pos: Vector3) -> bool:
	# Only the CENTER of the long FRONT face (the rubber band facing play) fires the kick - not the
	# posts, the short sides, or the back (developer: "kicking at more than just the single kick point
	# in the center of the long side facing the play area"). Gate in world XZ off the ACTUAL kick
	# direction (reliable - it is what _apply_kick uses): the ball must be IN FRONT of the slingshot
	# center along the kick, and within a lateral band of the center line. This replaces the old
	# corner-triangle face gate, which no longer matched the visual-derived hull and rejected every hit.
	var rel: Vector3 = ball_pos - global_position
	rel.y = 0.0
	var kd: Vector3 = _kick_dir
	kd.y = 0.0
	if kd.length() < 0.0001:
		return true
	kd = kd.normalized()
	var forward: float = rel.dot(kd)
	if forward <= 0.0:
		return false  ## behind / beside the front face - passive bounce only
	var lateral: float = (rel - kd * forward).length()
	return lateral <= TableConfig.BALL_RADIUS * 2.5


## The KICKING FACE of the slingshot. Returns [a, b, normal] in local X-Z: a and b are the two ends
## of the face band the ball strikes, normal a unit vector toward play.
##
## WHY the face EDGE is selected from _raw_corners() and NOT the rounded _triangle_outline(): the
## raw triangle has exactly THREE clean edges, so "the edge whose outward normal best aligns with
## the kick" picks the real long kicking face unambiguously. On the ROUNDED outline a short
## corner-ARC segment can sweep a normal that aligns with the kick even BETTER than the true face
## edge, so a best-edge search over the rounded outline would wrongly pick an arc, not the face. The
## raw face is therefore the correct source for the face DIRECTION and NORMAL.
##
## QA BUG-043 FIX (2026-06-24): the SPAN (the a..b band) is then CLAMPED to the rounded hull the
## ball actually collides with. The solid body and the detector are both built from
## _triangle_outline() (the rounded hull); the raw corner posts sit up to CORNER_RADIUS (0.72 u)
## OUTSIDE that hull, so using the raw corners as the band ends let a contact past the rounded post
## pass the span gate even though the ball never touched the rounded hull there - the inverse of the
## BUG-018 intent. We trim each raw end inward along the face by the corner-trim so the trimmed band
## matches the rounded face the ball can really strike. _contact_should_kick still adds a half-ball
## margin for a genuine end-of-band hit (BUG-018), now measured from the correct hull-matched ends.
func _kicking_face() -> Array:
	var c: PackedVector2Array = _raw_corners()
	var centroid := Vector2.ZERO
	for p: Vector2 in c:
		centroid += p
	centroid /= float(c.size())
	var kick2 := Vector2(_kick_dir.x, _kick_dir.z)
	var best_dot: float = -1.0e20
	var face_a: Vector2 = c[0]
	var face_b: Vector2 = c[1]
	var face_nrm := Vector2(0.0, 1.0)
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
			face_a = a
			face_b = b
			face_nrm = nrm
	# Trim each end inward along the face by the corner-trim distance so the band ends land on the
	# ROUNDED hull (which the ball collides with), not on the sharp raw posts that sit CORNER_RADIUS
	# outside it. The trim mirrors _round_corners' own clamp (radius capped at 0.49 * the shorter
	# adjacent edge), so a short face is never over-trimmed to a zero-length band.
	var edge_vec: Vector2 = face_b - face_a
	var elen: float = edge_vec.length()
	if elen < 0.0001:
		return [face_a, face_b, face_nrm]
	var dir: Vector2 = edge_vec / elen
	var trim: float = minf(CORNER_RADIUS, elen * 0.49)
	return [face_a + dir * trim, face_b - dir * trim, face_nrm]


## The TRIANGULAR visible mesh (fix 3: was a box), built from the SAME outline as the collider so
## the visible slingshot AGREES with the body it bounces off. The base adds this to the kicker root;
## we bake the body yaw into the mesh here so the visible triangle angles into play exactly like the
## (yawed) solid body. The structural test asserts the mesh is not a BoxMesh.
func _make_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_triangle_mesh(_triangle_outline(), _height)
	# The solid body is yawed by _body_yaw() in the base; yaw the visible mesh the same so they agree.
	mesh_instance.transform = Transform3D(Basis(Vector3(0.0, 1.0, 0.0), _body_yaw()), Vector3.ZERO)
	# A real slingshot is THREE rubber posts with bands stretched between them. Add those as children
	# of the (yawed) mesh so they inherit its orientation and sit exactly on the collider's corners.
	_add_posts_and_rubber(mesh_instance)
	return mesh_instance


## Build the visible 3-post-and-rubber assembly (posts at the triangle corners, bands along the
## edges) as children of the yawed mesh. PURELY visual - the collider and active kick are unchanged,
## so this gives the slingshot its real look without touching the proven physics.
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
## stand (a real slingshot is three posts with rubber stretched between them), so the collider and
## the posts share one definition. Apex X is offset per handedness so the pointed corner aims at the
## GUTTER (outer end): hand_sign +1 for the left sling, -1 for the right (mirror).
func _raw_corners() -> PackedVector2Array:
	# The three corner posts exactly as specified in TableConfig (absolute table coords). No parametric
	# length/angle/apex - what the developer gives is what gets built.
	return _corners


## Replace each sharp corner of a CCW (x, z) polygon with a rounded arc. For each vertex we trim in
## along both adjacent edges by `radius` (clamped so we never overrun a short edge) and sweep a
## quadratic-Bezier arc through the original corner. Winding (CCW/CW) is preserved, so the
## cap-orient and signed-area logic still work. Returns the expanded outline (same convex shape).
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


# ==================================================================================================
# SLICE "Low-poly slingshot asset" (2026-06-24): VISUAL + cosmetic anim ONLY (physics untouched).
# Mirrors the proven pop_bumper.gd / flipper.gd discipline: art mesh never a collider, scale DERIVED
# from the collider, gray-box fallback never vanishes, cosmetic anim decoupled from the ball.
# Ownership: LEAD scaffolds; LEAD+PHYSICS fill install/scale/mirror; GAMEPLAY fills the flex anim.
# ==================================================================================================


## After the base builds the body / detector / gray-box triangle (super._ready), swap in the
## imported low-poly art, mirror it for the right sling, and wire the cosmetic flex animation to the
## SAME kick event as the impulse - on a separate path that never moves the ball. super._ready() is
## first so the gray-box "KickerMesh" exists to hide.
func _ready() -> void:
	super._ready()
	_install_art()
	# The RIGHT sling now loads a PRE-MIRRORED .glb (right_slingshot.glb) with correct outward
	# normals, so NO runtime negative-X scale is applied here (that inverted the normals and shaded
	# the right sling dark). The collider mirror is still the position/rotation mirror set in
	# configure() via SLINGSHOT_RIGHT_CORNERS.
	# Cosmetic flex: the SAME kicked(direction) signal the impulse fires also drives _play_flex, on a
	# SEPARATE path that touches only the visual meshes. Removing this connection leaves the kick
	# byte-for-byte identical (the behavioral decoupling oracle).
	kicked.connect(_play_flex)


## LEAD + PHYSICS HALF: load the low-poly .glb as the visible art and hide the gray-box
## triangle. COPIES pop_bumper.gd._install_art (the proven pattern):
##   1. path = SLINGSHOT_ASSET_PATH unless _asset_path_override is set (the test seam).
##   2. load(path); if it is null or NOT a PackedScene, RETURN - the gray-box KickerMesh + the
##      procedural posts/rubber STAY visible (the sling never vanishes on a bad asset). Fallback.
##   3. instantiate under a child named SLINGSHOT_VISUAL_NODE_NAME; store it in _visual.
##   4. scale = _derive_scale(_visual) (uniform; DERIVED from the collider footprint, no literal).
##   5. on success, hide the gray-box "KickerMesh" (the procedural triangle + posts/rubber).
## The structural test asserts: _visual exists and is pure MeshInstance3D (zero CollisionShape3D),
## and its footprint TRACKS the collider (not a constant). See ARCHITECTURE.md 14.2.
func _install_art() -> void:
	# Path: the production asset unless a test forces the fallback branch via _asset_path_override.
	var override: String = _asset_path_override
	var path: String
	if override != "":
		path = override
	elif _mirrored:
		path = SLINGSHOT_RIGHT_ASSET_PATH  ## pre-mirrored asset (correct normals), no negative-scale
	else:
		path = SLINGSHOT_ASSET_PATH
	var scene: Resource = load(path)
	# FALLBACK GUARD (copy of pop_bumper.gd): if the .glb is missing or is not a scene, RETURN with
	# the gray-box triangle ("KickerMesh" + the procedural posts/rubber) STILL visible. The sling
	# never vanishes on a bad/absent asset - that is the load-failure contract the structural test
	# checks.
	if scene == null or not (scene is PackedScene):
		return
	# Instantiate the imported model under a named child so tests resolve it, and store it in _visual
	# (the flex anim drives nodes under this; the mirror scales this node for the right sling).
	_visual = scene.instantiate()
	_visual.name = SLINGSHOT_VISUAL_NODE_NAME
	add_child(_visual)
	# Scale DERIVED from the collider footprint (never a literal): the model is sized so its top-down
	# footprint matches the kicking-face span the ball actually collides with. _derive_scale measures
	# the model's own AABB (independent oracle) and divides the collider span by it.
	var factor: float = _derive_scale(_visual)
	_visual.scale = Vector3(factor, factor, factor)
	# COLLISION = VISUAL: rebuild the solid body + detector from the imported model's own geometry so
	# the ball bounces off EXACTLY the slingshot you see (the corner hull was a different shape, so the
	# ball passed through the visual - developer report).
	_rebuild_collider_from_visual()
	# On success, hide the gray-box placeholder (the procedural triangle + posts/rubber) so only
	# the imported model is seen. The collider is untouched - this is purely the VISIBLE swap.
	var gray_box: Node = get_node_or_null("KickerMesh")
	if gray_box != null:
		gray_box.visible = false
	# Capture the AUTHORED rest state of the flex nodes ONCE, now, before any kick can animate them
	# (QA BUG-044). Every flex snaps back to THESE values, never to a live (possibly mid-jab) read.
	_capture_flex_rest()


## Rebuild the solid bounce body AND the detector hull from the imported model's own vertices, in
## this node's frame (valid because _body_yaw is 0, so the model frame == the collider frame). The
## ball then collides with exactly the visible slingshot. The fixed kick direction is unchanged.
func _rebuild_collider_from_visual() -> void:
	if _visual == null or _body == null:
		return
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in _mesh_instances(_visual):
		if mi.mesh == null:
			continue
		var xf: Transform3D = _visual.transform * TableConfig.relative_xform(_visual, mi)
		for v: Vector3 in mi.mesh.get_faces():
			pts.append(xf * v)
	if pts.size() < 4:
		return
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	# Swap the SOLID body's shape (the ball bounces off this) and the DETECTOR's (fires the kick).
	for c: Node in _body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).shape = hull
	for c2: Node in get_children():
		if c2 is CollisionShape3D:
			(c2 as CollisionShape3D).shape = hull


## Cache the authored rest position/scale of the three flex-animated sub-nodes (QA BUG-044). Called
## once from _install_art after the model is instanced and before any flex runs, so the snap-back
## targets are the true rest even when a rapid double-kick re-enters _play_flex mid-animation. Any
## absent node keeps its default (the flex skips absent nodes anyway).
func _capture_flex_rest() -> void:
	if _visual == null:
		return
	var finger: Node3D = _visual.get_node_or_null(KICKER_FINGER_NODE) as Node3D
	var tip: Node3D = _visual.get_node_or_null(KICKER_TIP_NODE) as Node3D
	var ring: Node3D = _visual.get_node_or_null(RUBBER_RING_NODE) as Node3D
	if finger != null:
		_finger_rest = finger.position
	if tip != null:
		_tip_rest = tip.position
	if ring != null:
		_ring_rest_scale = ring.scale


## LEAD + PHYSICS HALF: uniform scale so the imported model's top-down footprint matches the
## collider's kicking-face span. COPIES pop_bumper.gd._derive_scale/_merged_aabb: measure the
## visual's merged-AABB width from the MESH (an independent oracle on the scale), and return
## (collider_span / visual_width). DERIVED, never hardcoded. The structural test asserts the
## returned scale TRACKS the collider span (change the corners, the scale changes), not a literal.
func _derive_scale(visual_root: Node3D) -> float:
	# Independent oracle on the scale: measure the imported model's OWN footprint from its merged
	# mesh AABB (the wider of X/Z, the top-down span), never trust a hardcoded model size.
	var box: AABB = _merged_aabb(visual_root)
	var visual_width: float = maxf(box.size.x, box.size.z)
	if visual_width < 0.0001:
		return 1.0
	# Target span = the collider's KICKING-FACE length, read live from the corner posts (the A-B face
	# the ball strikes). This TRACKS the gameplay collider, not a constant: if SLINGSHOT_LENGTH (and
	# therefore the corner placement) changes, this span changes and the scale follows. The structural
	# test asserts the returned scale moves when the collider span moves (no literal scale).
	var collider_span: float = _collider_footprint_span()
	return collider_span / visual_width


## The collider's top-down footprint span - the LONGEST distance between any two points of the REAL
## collision hull outline (the kicking face A-B is the long edge). WHY _triangle_outline() and NOT
## _raw_corners(): the ConvexPolygonShape3D body the ball collides with is built from
## _extrude_triangle_to_hull(_triangle_outline(), ...), i.e. the ROUNDED outline - the sharp corner
## posts are trimmed in by CORNER_RADIUS. Measuring the raw (pre-rounding) posts overshoots the real
## hull span by ~14% (raw 5.15 vs rounded 4.52 for the left sling), which would scale the imported
## visual ~14% WIDER than the shape that actually fires kicks, so a ball grazing the visual near the
## rounded corners would appear to touch the sling but fall outside the collision hull. Reading the
## rounded outline keeps the derived scale matched to the gameplay collider, not a magic literal.
## WHY the max pairwise distance and not just |B - A|: it is the true bounding span of the hull,
## robust to which point pair is longest.
func _collider_footprint_span() -> float:
	var outline: PackedVector2Array = _triangle_outline()
	if outline.size() < 2:
		return _length  # degenerate guard: fall back to the nominal face length
	var span: float = 0.0
	for i: int in range(outline.size()):
		for j: int in range(i + 1, outline.size()):
			span = maxf(span, (outline[j] - outline[i]).length())
	if span < 0.0001:
		return _length
	return span


## Merge every descendant MeshInstance3D's AABB into the visual root's LOCAL space (copy of
## pop_bumper.gd._merged_aabb). Used by _derive_scale to measure the imported model's footprint as
## an independent oracle on the scale, so the scale is DERIVED, never hardcoded.
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


## Every MeshInstance3D under `node` (recursive). The imported .glb has many named sub-meshes
## (posts, rubber, shield, kicker finger); the merged AABB needs them all (copy of pop_bumper.gd).
func _mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c: Node in node.get_children():
		found.append_array(_mesh_instances(c))
	return found


## LEAD + PHYSICS HALF: mirror the RIGHT sling's VISUAL by a NEGATIVE-X SCALE on _visual (the
## mesh node) - NOT a negative-scale on any CollisionShape3D (the collider mirror is already done by
## SLINGSHOT_RIGHT_CORNERS in configure(), a position/rotation mirror). GOTCHA: a negative-X scale
## flips the basis determinant negative, inverting triangle winding so the model can render
## INSIDE-OUT. GUARD: set every imported material's cull_mode = CULL_DISABLED on _visual so the
## double-sided render survives the determinant flip with correct-looking faces. The structural test
## asserts _visual's basis determinant < 0 (the mirror is really applied) AND the KickerBody basis
## determinant stays > 0 (the collider was NOT negative-scaled). If the cull-disabled mirror still
## reads wrong in the deployed web shot, FLAG the producer for a baked mirrored .glb (do NOT
## hand-tune per-mesh normals). See ARCHITECTURE.md 14.3.
func _mirror_visual() -> void:
	# If the asset failed to load, there is nothing to mirror (the gray-box fallback is already
	# mirrored by the right-handed SLINGSHOT_RIGHT_CORNERS in configure(), a position/rotation mirror).
	if _visual == null:
		return
	# Mirror the VISUAL by a NEGATIVE-X scale on the mesh node ONLY. We do NOT negative-scale any
	# CollisionShape3D: the collider mirror is already a position/rotation mirror (the right sling
	# reads its own SLINGSHOT_RIGHT_CORNERS in configure()), and a negative-scaled collider is
	# undefined for the physics solver. So this touches the imported mesh node, never the KickerBody.
	var s: Vector3 = _visual.scale
	_visual.scale = Vector3(-absf(s.x), s.y, s.z)
	# GOTCHA: a negative-X scale flips the basis determinant negative, reversing triangle winding so
	# the model can render INSIDE-OUT (front faces become back faces and get culled). GUARD: force
	# every imported material to render double-sided (CULL_DISABLED) so the mirror reads
	# correct-side-out regardless of the determinant flip. This is the documented in-engine mirror; if
	# it still reads wrong on the deployed web shot, the producer bakes a mirrored .glb.
	_disable_culling(_visual)


## Force CULL_DISABLED on every material under `root` so a negative-X-scaled (mirrored) visual
## renders double-sided and does not look inside-out. We handle BOTH the per-surface override slot
## and the mesh's own surface materials, since an imported .glb may carry either. Visual-only: no
## collider or ball state is touched.
func _disable_culling(root: Node) -> void:
	for mi: MeshInstance3D in _mesh_instances(root):
		var mesh: Mesh = mi.mesh
		var surface_count: int = 0 if mesh == null else mesh.get_surface_count()
		for i: int in range(surface_count):
			# Prefer the MeshInstance override slot so we never mutate the shared imported Mesh resource
			# (the left sling shares the same Mesh; mutating it would make the LEFT double-sided too).
			var mat: Material = mi.get_active_material(i)
			if mat == null:
				continue
			var dup: Material = mat.duplicate()
			if dup is BaseMaterial3D:
				(dup as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(i, dup)


## GAMEPLAY HALF: the cosmetic flex animation. Triggered by the SAME kicked(direction) signal as
## the impulse, but on a SEPARATE path that animates ONLY the visual meshes under _visual.
##
## WHY DECOUPLED: the ball velocity after a kick is set by _apply_kick (physics half). This function
## is called on the same kicked() signal emission but only animates Node3D.position/scale on
## sub-nodes of _visual. No ball method is called, no ball property is read or written. The
## behavioral oracle asserts ball velocity is identical whether this runs or is stubbed. If _visual
## is null (gray-box fallback or .glb absent), this is a safe no-op. See ARCHITECTURE.md 14.4.
##
## ANIMATION:
##   Phase 1 (JAB OUT, FLEX_JAB_TIME_S ~45 ms): Kicker_Finger + Kicker_Tip translate forward along
##     the kick direction by FLEX_JAB_DISTANCE. Sling_Rubber_Ring stretches on its local X axis by
##     FLEX_RUBBER_STRETCH (additive fraction, ~18%).
##   Phase 2 (SNAP BACK, FLEX_RETURN_TIME_S ~65 ms): all nodes return to their authored rest state.
##   Total ~110 ms reads as a crisp solenoid snap without lingering.
func _play_flex(direction: Vector3) -> void:
	# GUARD: no visual means no animation nodes to drive. The gray-box procedural fallback has no
	# KICKER_FINGER_NODE / KICKER_TIP_NODE / RUBBER_RING_NODE children. Safe no-op.
	if _visual == null:
		return

	# Resolve the three visual-only target nodes from under _visual. Any absent node (stripped
	# import, future model variant) is skipped so the animation degrades without error - the kick
	# is already done and the ball is already moving; this is purely cosmetic.
	var finger: Node3D = _visual.get_node_or_null(KICKER_FINGER_NODE) as Node3D
	var tip: Node3D = _visual.get_node_or_null(KICKER_TIP_NODE) as Node3D
	var ring: Node3D = _visual.get_node_or_null(RUBBER_RING_NODE) as Node3D

	# Flatten the kick direction onto the playfield plane (Y = 0) so the jab stays in-plane and
	# does not push nodes vertically. _kick_direction_for already returns Y=0, but we guard here
	# so a future change to the base kick contract cannot break the visual anim.
	var jab_dir: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if jab_dir.length() < 0.0001:
		return  # degenerate direction - nothing to jab toward, skip safely.
	jab_dir = jab_dir.normalized()

	# The jab translation in LOCAL visual space: forward along jab_dir by FLEX_JAB_DISTANCE.
	var jab_offset: Vector3 = jab_dir * FLEX_JAB_DISTANCE

	# QA BUG-044: kill any in-flight flex first. A node-bound Tween in Godot 4 runs to completion even
	# after the local handle is dropped, so without this kill() a rapid double-kick (interval < the
	# ~110 ms round-trip) leaves the prior tween still driving these properties while the new one
	# fights it. Killing the old tween, plus snapping back to the CACHED authored rest (not a live
	# read), means every flex starts clean from a known state with no stacked positional drift.
	if _flex_tween != null and _flex_tween.is_valid():
		_flex_tween.kill()
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	_flex_tween = tween

	# ---- PHASE 1: JAB OUT (FLEX_JAB_TIME_S) -------------------------------------------------------
	# Kicker_Finger and Kicker_Tip translate forward along jab_dir by FLEX_JAB_DISTANCE.
	# WHY .position not .global_position: these are children of _visual; their authored local
	# position IS their rest and the correct base for a local-space animation. The jab/snap-back are
	# anchored to the CACHED rest (_finger_rest/_tip_rest), captured once in _capture_flex_rest, so an
	# overlapping kick cannot drift the snap-back target off the true rest (QA BUG-044).
	if finger != null:
		tween.tween_property(finger, "position", _finger_rest + jab_offset, FLEX_JAB_TIME_S)
		# Phase 2: snap back to the authored rest after the jab duration elapses.
		tween.tween_property(
			finger, "position", _finger_rest, FLEX_RETURN_TIME_S
		).set_delay(FLEX_JAB_TIME_S)

	if tip != null:
		tween.tween_property(tip, "position", _tip_rest + jab_offset, FLEX_JAB_TIME_S)
		tween.tween_property(
			tip, "position", _tip_rest, FLEX_RETURN_TIME_S
		).set_delay(FLEX_JAB_TIME_S)

	# Sling_Rubber_Ring: scale the X axis (the ring's long axis in the .glb coordinate frame) by
	# (1 + FLEX_RUBBER_STRETCH) so the rubber band visually stretches as the kicker punches out.
	# FLEX_RUBBER_STRETCH is additive: 0.18 means 1.18x the rest scale at peak flex. The snap-back
	# target is the CACHED authored rest scale (_ring_rest_scale) so the return is exact regardless of
	# floating-point drift or an interrupted earlier tween (QA BUG-044).
	if ring != null:
		var stretched: Vector3 = _ring_rest_scale
		stretched.x *= (1.0 + FLEX_RUBBER_STRETCH)
		tween.tween_property(ring, "scale", stretched, FLEX_JAB_TIME_S)
		tween.tween_property(
			ring, "scale", _ring_rest_scale, FLEX_RETURN_TIME_S
		).set_delay(FLEX_JAB_TIME_S)
