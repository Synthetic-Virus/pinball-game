class_name ScoringReskin
extends RefCounted
## ScoringReskin - applies the RED "aim here" accent to the SCORING furniture (pop bumpers,
## slingshots, standup targets). VISUAL ONLY: it sets material_override on the visible meshes and
## touches no collider, kick vector, cooldown, or score value.
##
## OWNERSHIP: gameplay-programmer (the scoring furniture is theirs). The lead scaffolded a WORKING
## baseline below so the full blue/white/red reskin renders on the artifact; the two decision points
## the gameplay-programmer had to confirm or tune are RESOLVED below (see the two comments inside
## apply()). Both were legibility/behaviour calls within this one file - no other file was touched,
## keeping the slice's visual-only diff proof intact.
##
## HOW SCORING NODES ARE FOUND (structural, so table.gd needs no group bookkeeping): a scoring
## element is any node that owns one of the marker children a bumper / sling / target builds -
## "BumperVisual" (the pop bumper cap), "KickerMesh" (the slingshot's procedural triangle AND the
## pop bumper's gray-box fallback mesh), or "Deflector" (the target's solid post). The drain and
## oob-drain Area3Ds own none of these, so they are never recoloured, and the flippers / ball are
## not scoring nodes, so the flipper two-tone is safe. NOTE: the slingshot's visible mesh is named
## "KickerMesh" by ActiveKicker (the legacy .glb "SlingshotVisual" art was retired in the Kenney 3D
## swap), so slings carry no separate "SlingshotVisual" node - they are accented via "KickerMesh".
##
## Called by TableReskin.apply(). Standalone entry so the future editor can re-accent on its own.

## Child node names that mark a node as scoring furniture (see class doc). "SlingshotVisual" is
## deliberately absent: no node is ever named that (the slingshot renders as "KickerMesh"), so a
## literal for it would just be dead marker weight that matches nothing.
const SCORING_MARKERS: Array[String] = [
	"BumperVisual", "KickerMesh", "Deflector"
]


## Paint every scoring furniture node with the accent red. Idempotent and null-safe.
static func apply(playfield: Node3D) -> void:
	if playfield == null:
		return
	# One shared flat accent material reused across all scoring furniture.
	var accent := Palette.flat_material(Palette.SCORING_ACCENT)
	for node: Node3D in _scoring_nodes(playfield):
		# DECISION 1 (gameplay-programmer, RESOLVED; behaviour updated by commit 760742a): the flat
		# opaque accent DOES supersede the pop bumper's own idle cap colour - verified by construction,
		# not by guess. table.gd's _build_dynamic_elements() add_child()s every pop bumper/slingshot/
		# target under Playfield BEFORE table.gd calls TableReskin.apply(playfield) (that call is a
		# final whole-table pass in table.gd _ready(), after both build phases, so it lands after every
		# furniture add_child). Godot runs _ready() synchronously on add_child, so pop_bumper.gd's
		# _install_art() has already set its own flat, opaque material_override on "BumperVisual" by
		# the time this loop runs; _paint_subtree below sets material_override again on the same
		# meshes, so the flat red accent is last-write and is what actually renders at rest. pop_
		# bumper.gd is NO LONGER FROZEN (commit 760742a rewired its hit-flash): _flash_on_hit() now
		# isolates a PRIVATE copy of the mesh's LIVE material_override (whatever ScoringReskin most
		# recently painted there, read at flash time via meshes[0].material_override, not a stale
		# handle captured at _ready) and pulses that copy's albedo from FLASH_PEAK_ALBEDO back to
		# FLASH_REST_ALBEDO (Palette.SCORING_ACCENT) on the physics clock, then re-installs it as the
		# mesh's material_override. So the flash renders correctly on top of whatever ScoringReskin
		# painted, with zero coupling back into this file (pop_bumper.gd never touches ScoringReskin's
		# shared accent object, only its own private duplicate) - DESIGN must-feel #4 (a hit flash must
		# never stop flashing) is satisfied; no BACKLOG.md follow-up remains for this defect.
		#
		# DECISION 2 (gameplay-programmer, RESOLVED for this slice): all three scoring types keep the
		# single shared SCORING_ACCENT. The locked design direction names one hue for "the scoring
		# furniture" as a category (DESIGN.md: "red accent on the scoring furniture... teaches a new
		# player where to aim"), not a distinct hue per type, and splitting it is a legibility judgment
		# that needs the actual PLAY-screen artifact shot (must-feel #2/#3) to justify - a call this
		# file cannot make without a rendered build. Keeping one entry is also the reversible choice:
		# adding a second entry later is cheap, unwinding one now would not be. If QA's fresh
		# Playwright shot on the PR artifact shows targets and bumpers reading as one indistinct
		# object, add ONE new named entry to palette.gd (e.g. Palette.TARGET_ACCENT) and point
		# _paint_subtree at it for the target case only; never hard-code a Color here.
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
