class_name ScoringReskin
extends RefCounted
## ScoringReskin - applies the RED "aim here" accent to the SCORING furniture (pop bumpers,
## slingshots, standup targets). VISUAL ONLY: it sets material_override on the visible meshes and
## touches no collider, kick vector, cooldown, or score value.
##
## OWNERSHIP: gameplay-programmer (the scoring furniture is theirs). The lead scaffolded a WORKING
## baseline below so the full blue/white/red reskin renders on the artifact; the two DECISION POINTS
## marked TODO are the gameplay-programmer's legibility calls to confirm or tune.
##
## HOW SCORING NODES ARE FOUND (structural, so table.gd needs no group bookkeeping): a scoring
## element is any node that owns one of the marker children a bumper / sling / target builds -
## "BumperVisual", "SlingshotVisual", "KickerMesh" (the gray-box fallback mesh), or "Deflector" (the
## target's solid post). The drain and oob-drain Area3Ds own none of these, so they are never
## recoloured, and the flippers / ball are not scoring nodes, so the flipper two-tone is safe.
##
## Called by TableReskin.apply(). Standalone entry so the future editor can re-accent on its own.

## Child node names that mark a node as scoring furniture (see class doc).
const SCORING_MARKERS: Array[String] = [
	"BumperVisual", "SlingshotVisual", "KickerMesh", "Deflector"
]


## Paint every scoring furniture node with the accent red. Idempotent and null-safe.
static func apply(playfield: Node3D) -> void:
	if playfield == null:
		return
	# One shared flat accent material reused across all scoring furniture.
	var accent := Palette.flat_material(Palette.SCORING_ACCENT)
	for node: Node3D in _scoring_nodes(playfield):
		# DECISION POINT 1 (gameplay-programmer): a solid opaque accent supersedes the pop bumper's
		# old cosmetic hit-flash (that flash used emission + alpha, which the design forbids and which
		# read as invisible in the web build anyway). The HUD score tick remains the hit feedback. If
		# a legible red-based pulse is wanted later, re-wire it here on ALBEDO, not emission. Until
		# then the flat accent is on-brief for must-feel #6 (calm at speed, no shimmer).
		# DECISION POINT 2 (gameplay-programmer): all three scoring types share SCORING_ACCENT today.
		# If the artifact shows targets and bumpers reading as one object, split one to a distinct
		# palette entry (add it to palette.gd, do not hard-code a Color here).
		_paint_subtree(node, accent)


## Collect the scoring furniture nodes under `playfield` by looking for a marker child on each
## descendant. Returns the OWNER node (bumper / sling / target root) so its whole visible subtree
## can be painted in one pass.
static func _scoring_nodes(playfield: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node: Node in _descendants(playfield):
		var owner_3d := node as Node3D
		if owner_3d == null:
			continue
		if _has_marker_child(owner_3d) and not out.has(owner_3d):
			out.append(owner_3d)
	return out


## True when `node` owns a direct child whose name is one of the SCORING_MARKERS.
static func _has_marker_child(node: Node3D) -> bool:
	for c: Node in node.get_children():
		if SCORING_MARKERS.has(c.name):
			return true
	return false


## Set `mat` as material_override on every MeshInstance3D under `root` (inclusive). The override
## layers a colour on top of the built mesh; it never edits the mesh resource or any collider.
static func _paint_subtree(root: Node3D, mat: StandardMaterial3D) -> void:
	for mesh: MeshInstance3D in _mesh_instances(root):
		mesh.material_override = mat


## Every node under `root` (recursive, inclusive) - used to scan for scoring markers.
static func _descendants(root: Node) -> Array:
	var found: Array = [root]
	for c: Node in root.get_children():
		found.append_array(_descendants(c))
	return found


## Every MeshInstance3D under `node` (recursive, inclusive).
static func _mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c: Node in node.get_children():
		found.append_array(_mesh_instances(c))
	return found
