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

## SLICE "Gate 0 polish" (2026-07-19): the slingshot renders a SOLID authored Kenney-style wedge
## (DESIGN "saved by the slings"; developer note: "rebuild them as solid models instead of the
## design I had originally"). The previous build read as an open truss - raised corner posts plus
## thin rubber bands with a see-through middle; this replaces that with a filled, slightly-domed
## triangular body whose FOOTPRINT TRACES the collider outline, so the visible face sits exactly
## where the ball bounces. Two separately-authored, PRE-MIRRORED glbs (left_slingshot.glb /
## right_slingshot.glb, baked in Blender with outward-recalculated normals) are the primary visual,
## loaded per handedness in _install_art and seated base-at-Y=0. WHY two baked glbs and not one
## negative-X-scaled at runtime: a negative scale REFLECTS the mesh, flipping its normals so
## the right sling shades dark/inside-out (the mirror gotcha); a pre-mirrored glb keeps a positive-
## determinant transform. The ball ALWAYS hits the frozen ConvexPolygonShape3D hull (_make_body_
## shape); the wedge is never a collider (art is never a collider). If a glb fails to import (an
## LFS-less run), the solid gray-box prism from _make_mesh stays visible so the sling still shows.

## The two pre-mirrored wedge assets, one per handedness. _install_art loads by _mirrored.
const LEFT_ASSET_PATH: String = "res://assets/models/left_slingshot.glb"
const RIGHT_ASSET_PATH: String = "res://assets/models/right_slingshot.glb"
## The imported visual's node name (the "art is never a collider" structural oracle resolves it).
const VISUAL_NODE_NAME: String = "SlingshotVisual"

## ON-HIT JAB (restored feedback). When the kick fires the visible wedge briefly lunges along the
## kick direction (the solenoid firing), then eases back to its AUTHORED rest. Cosmetic ONLY - it
## moves the visual node, NEVER the ball or the collider (the decoupling oracle proves the ball's
## outgoing velocity is byte-for-byte identical with the jab wired or stripped).
const JAB_DISTANCE: float = 0.28   ## world units the wedge lunges along the kick direction
const JAB_OUT_S: float = 0.045     ## snap-out time (fast, like a solenoid firing)
const JAB_BACK_S: float = 0.13     ## ease-back time to the authored rest

## Test seam (fallback oracle): force a bad asset path to drive the gray-box fallback. Read by
## _install_art (mirrors pop_bumper.gd's seam); "" means load the real per-side asset.
var _asset_path_override: String = ""

## The imported wedge visual root (set by _install_art on a successful load, else null). The
## structural / mirror / derived-scale oracles read `_sling._visual` directly. Null when the glb did
## not import (an LFS-less run) - which is exactly the fallback oracle's asserted post-condition.
var _visual: Node3D = null

## The node the on-hit jab moves and the AUTHORED rest position it always returns to. Captured ONCE
## at install time and never re-read live mid-tween (QA BUG-044: a live read latches a mid-tween
## position as the new rest and makes the wedge drift). Defaults to the gray-box KickerMesh so the
## feedback still plays if the glb did not load.
var _jab_node: Node3D = null
var _visual_rest_pos: Vector3 = Vector3.ZERO
## The live jab tween, killed before a new jab so overlapping kicks never fight over the position.
var _jab_tween: Tween = null

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


## Detector = the triangle body's rounded outline, INFLATED outward by BALL_RADIUS (see
## _offset_outline). WHERE the contact landed is then judged by _contact_should_kick: only a contact
## on the kicking BAND fires the solenoid; the posts/back bounce passively.
##
## DETECTOR MARGIN - PHYSICS-PROGRAMMER FIX (measured defect, a QA-BUG-018-class regression): this
## used to return the EXACT body shape with zero margin ("no proximity padding to cause an early cone
## of triggering" - the original developer intent). Measured headless: a ball fired into the trimmed
## band-end near a rounded post genuinely contacts the solid KickerBody (confirmed via the real
## ball's get_colliding_bodies(), an independent oracle) but a coincident, non-inflated Area3D
## detector never registered the overlap - 0 kicks, 0 scores across 120 physics frames, even though
## _contact_should_kick's own gate evaluated true throughout. Root cause: the ball's continuous_cd
## sweep resolves the solid-body contact at (near) zero penetration depth, and a same-shape Area3D
## overlap check can miss that at a shallow/tangential (grazing/corner) angle even though a squarer,
## more perpendicular hit (the face center, which already worked) does register. Padding the detector
## outward by BALL_RADIUS - the same magnitude the ActiveKicker base class already uses as its
## default padding for a round element (_make_detector_shape in active_kicker.gd) - gives the Area3D
## volume enough clearance past the solid surface that a grazing contact overlaps it before or as the
## ball's CCD resolves the solid contact, closing the gap without reopening the "early cone of
## triggering" the zero-margin design was trying to avoid (the padding is bounded to one ball radius,
## and _contact_should_kick's forward/lateral band gate still has the final say on whether a contact
## fires the active kick).
func _make_detector_shape() -> Shape3D:
	var hull := ConvexPolygonShape3D.new()
	hull.points = _extrude_triangle_to_hull(
		_offset_outline(_triangle_outline(), TableConfig.BALL_RADIUS), _height
	)
	return hull


## Inflate a CCW (x, z) outline outward by `margin`, used ONLY by _make_detector_shape (never the
## solid body or the visible mesh, which must stay the true, un-padded geometry). For each vertex the
## outward direction is the average of its two adjacent edge normals (both oriented away from the
## outline's centroid, mirroring _round_corners' own normal convention) - an accurate approximation
## of a true parallel (Minkowski) offset for a densely-sampled, smoothly rounded outline like
## _triangle_outline() (15 points for CORNER_SEGMENTS=4). Falls back to a radial (vertex-to-centroid)
## direction if the two adjacent edges are degenerate/anti-parallel, so the offset never collapses to
## a zero vector.
func _offset_outline(outline: PackedVector2Array, margin: float) -> PackedVector2Array:
	var n: int = outline.size()
	if n < 3 or margin <= 0.0:
		return outline
	var centroid := Vector2.ZERO
	for p: Vector2 in outline:
		centroid += p
	centroid /= float(n)
	var out := PackedVector2Array()
	for i in range(n):
		var prev: Vector2 = outline[(i - 1 + n) % n]
		var cur: Vector2 = outline[i]
		var nxt: Vector2 = outline[(i + 1) % n]
		var edge_in: Vector2 = cur - prev
		var edge_out: Vector2 = nxt - cur
		var n1 := Vector2(edge_in.y, -edge_in.x)
		var n2 := Vector2(edge_out.y, -edge_out.x)
		var avg: Vector2 = n1.normalized() + n2.normalized()
		if avg.length() < 0.0001:
			avg = cur - centroid  # degenerate (near-antiparallel adjacent edges): fall back to radial
		avg = avg.normalized()
		if (cur - centroid).dot(avg) < 0.0:
			avg = -avg  # keep the normal pointing OUTWARD (away from the outline centroid)
		out.append(cur + avg * margin)
	return out


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
	# This is now the FALLBACK gray-box only: a SOLID triangular prism (no truss). On a normal run
	# _install_art hides it and shows the authored wedge glb; if that glb fails to import this solid
	# prism stays visible so the sling never vanishes. The old raised-post + rubber-band truss (the
	# "see-through middle" the developer flagged) is removed - a solid model replaces it.
	return mesh_instance


## Load the SOLID authored wedge glb (per handedness) as the visible art, scale it to trace the
## collider outline, seat its base at Y=0, and hide the gray-box prism. Any load failure leaves the
## gray-box visible and _visual null (the sling never vanishes - the fallback oracle asserts this).
## Mirrors pop_bumper.gd._install_art. The imported subtree is VISUAL ONLY (never a collider).
func _install_art() -> void:
	var default_path: String = RIGHT_ASSET_PATH if _mirrored else LEFT_ASSET_PATH
	var path: String = default_path if _asset_path_override == "" else _asset_path_override
	var scene: Resource = load(path)
	if scene == null or not (scene is PackedScene):
		return  ## fallback: the solid gray-box prism from _make_mesh stays visible, _visual stays null
	var visual: Node3D = (scene as PackedScene).instantiate()
	visual.name = VISUAL_NODE_NAME
	add_child(visual)
	# Scale DERIVED from the frozen collider outline (never hardcoded): fit the glb footprint to the
	# rounded-triangle hull the ball actually bounces off, so the visible face traces the collider.
	_fit_to_collider(visual)
	# Seat the wedge BASE on the surface (element origin, Y = 0) so an off-origin mesh cannot sink
	# below the field. Measured after the scale is set, never hardcoded (KenneyModels.base_seat_y).
	visual.position.y = KenneyModels.base_seat_y(visual, 0.0)
	# Flat scoring-red accent (Palette single colour source) so a standalone sling reads red before
	# the whole-table ScoringReskin pass re-asserts the same accent. Flat albedo only (web-safe).
	_apply_accent(visual)
	# Hide the gray-box prism; the solid wedge replaces it. KickerMesh STAYS present (hidden) as the
	# ScoringReskin marker, which is found by name, not by visibility.
	var gray_box: Node3D = get_node_or_null("KickerMesh") as Node3D
	if gray_box != null:
		gray_box.visible = false
	# The wedge is now the visual and the jab target; capture its AUTHORED rest ONCE (QA BUG-044).
	_visual = visual
	_jab_node = visual
	_visual_rest_pos = visual.position


## Derive the visual's per-axis scale from the collider outline (the anti-magic-number oracle): fit
## the glb's footprint AABB to the frozen rounded-triangle outline the ball bounces off, and
## its height to _height. Positive on every axis (the pre-mirrored glbs need no negative scale), so
## the transform determinant stays > 0 (no reflected/inside-out normals - the mirror gotcha). A
## degenerate model leaves the scale at 1 so a bad asset never divides by ~0.
func _fit_to_collider(visual: Node3D) -> void:
	var box: AABB = KenneyModels.merged_aabb(visual)
	if box.size.x < 0.0001 or box.size.y < 0.0001 or box.size.z < 0.0001:
		return
	var outline: PackedVector2Array = _triangle_outline()
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for p: Vector2 in outline:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var target_w: float = max_x - min_x
	var target_d: float = max_z - min_z
	visual.scale = Vector3(target_w / box.size.x, _height / box.size.y, target_d / box.size.z)


## Paint the imported wedge with the flat scoring-red accent (Palette single colour source, no
## scattered literal) so a standalone sling reads red before ScoringReskin's whole-table pass. Flat
## albedo only (must-feel: no emission - invisible in the web build; no transparency).
func _apply_accent(root: Node3D) -> void:
	var mat: StandardMaterial3D = Palette.flat_material(Palette.SLINGSHOT_ACCENT)
	for mi: MeshInstance3D in KenneyModels.mesh_instances(root):
		mi.material_override = mat


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
	# Restyle (SLICE "Kenney 3D asset integration"): the triangle body is SCORING furniture, so its
	# base material is the shared Palette scoring accent (single colour source, no scattered literal).
	# ScoringReskin re-paints this same red at table build time via material_override; this base keeps
	# the unit-test / pre-reskin look correct and Palette-sourced. Flat albedo (Palette.flat_material)
	# preserves the low-poly faceted read and stays visible in the web export (no emission).
	st.set_material(Palette.flat_material(Palette.SLINGSHOT_ACCENT))
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
# SLICE "Gate 0 polish" (2026-07-19): the SOLID authored wedge (left/right_slingshot.glb) is the
# primary visual (see the header note + _install_art). _ready swaps it in over the gray-box fallback
# and wires the on-hit jab (_play_flex). The collider / kick / score / cooldown are the frozen
# active-kick base - untouched; the wedge and the jab are VISUAL ONLY (the ball is never touched).
# ==================================================================================================


## super._ready() first so the base builds the frozen body / detector / gray-box "KickerMesh". Then
## swap in the solid authored wedge (_install_art) and wire the on-hit jab. The collider / kick /
## score / cooldown are UNTOUCHED (the frozen active-kick base).
func _ready() -> void:
	super._ready()
	# Default the jab target to the gray-box fallback so the on-hit feedback still plays even if the
	# wedge glb fails to import; _install_art overrides these to the wedge on a successful load.
	var gray_box: Node3D = get_node_or_null("KickerMesh") as Node3D
	if gray_box != null:
		_jab_node = gray_box
		_visual_rest_pos = gray_box.position
	_install_art()
	if not kicked.is_connected(_play_flex):
		kicked.connect(_play_flex)


## ON-HIT JAB (restored feedback): lunge the visible wedge briefly ALONG the kick direction (the
## solenoid firing), then ease it back to its AUTHORED rest. PURELY COSMETIC - it moves only the
## visual node, NEVER the ball or the collider, so the decoupling oracle measures a byte-for-byte
## identical outgoing velocity whether this slot is wired or stripped. The tween runs on the PHYSICS
## clock so its progress is deterministic under the headless GUT physics-frame sampler.
##
## QA BUG-044 GUARD: the ease-back target is _visual_rest_pos, captured ONCE at install, NOT the
## node's live position read here - a live read during an in-flight jab would latch a mid-tween
## position as the new "rest" and make the wedge drift out of place over repeated hits.
##
## The `direction` arg matches the kicked(direction: Vector3) signature (a zero-arg slot fails to
## connect; Godot 4 does not drop unconsumed signal args). It is the FIXED kick direction in the
## sling's local X-Z (the sling root carries no rotation), so it is the jab axis directly.
func _play_flex(direction: Vector3) -> void:
	if _jab_node == null:
		return
	var dir: Vector3 = direction
	dir.y = 0.0  ## jab in the surface plane only (no vertical hop)
	if dir.length() < 0.0001:
		return
	dir = dir.normalized()
	# Kill any in-flight jab so overlapping kicks never fight over the node's position; the new jab
	# always ENDS at the authored rest, so no drift accumulates regardless of when it is interrupted.
	if _jab_tween != null and _jab_tween.is_valid():
		_jab_tween.kill()
	var jabbed: Vector3 = _visual_rest_pos + dir * JAB_DISTANCE
	_jab_tween = create_tween()
	_jab_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_jab_tween.tween_property(_jab_node, "position", jabbed, JAB_OUT_S)
	_jab_tween.tween_property(_jab_node, "position", _visual_rest_pos, JAB_BACK_S)
