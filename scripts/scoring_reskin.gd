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
		# DECISION 1 (gameplay-programmer, RESOLVED; behaviour updated by commit 760742a; CARVED OUT
		# for the pop bumper cap by the Kenney texture-restoration slice - see _paint_owner): the flat
		# opaque accent supersedes a scoring mesh's own idle colour for every scoring node EXCEPT the
		# pop bumper's "BumperVisual" cap when that cap already carries its own baked material (a
		# custom asset arriving this same slice, cap already red by design). table.gd's
		# _build_dynamic_elements() add_child()s every pop bumper/slingshot/target under Playfield
		# BEFORE table.gd calls TableReskin.apply(playfield) (a final whole-table pass in table.gd
		# _ready(), after both build phases), so this loop always runs after every furniture
		# add_child, and _paint_owner below decides per-mesh whether to overwrite it. pop_bumper.gd is
		# NO LONGER FROZEN (commit 760742a rewired its hit-flash): _flash_on_hit() isolates a PRIVATE
		# copy of the mesh's LIVE material_override (whatever is ACTUALLY rendered - either this
		# reskin's shared accent, or the cap's own baked material when _paint_owner left it alone -
		# read at flash time via meshes[0].material_override, not a stale handle captured at _ready)
		# and pulses that copy's albedo from FLASH_PEAK_ALBEDO back to FLASH_REST_ALBEDO
		# (Palette.SCORING_ACCENT) on the physics clock, then re-installs it as the mesh's
		# material_override. So the flash renders correctly on top of whatever is actually visible,
		# with zero coupling back into this file - DESIGN must-feel #4 (a hit flash must never stop
		# flashing) is satisfied; no BACKLOG.md follow-up remains for this defect.
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
		# _paint_owner at it for the target case only; never hard-code a Color here.
		_paint_owner(node, accent)


## Paint one scoring-furniture owner's meshes with the accent, EXCEPT the pop bumper's own
## "BumperVisual" cap when it already carries a material of its own. The cap is a CUSTOM asset with
## a BAKED red material (SLICE "Kenney baseline COMPLETION" front 1, the mushroom-cap bumper
## authored this same slice - "its cap is already red" by construction), so its own
## imported material already IS the "aim here" red; stomping it with the shared flat accent would
## throw away the baked look for zero legibility gain. Every OTHER scoring mesh - the slingshot/
## target "KickerMesh"/"Deflector" visuals, and the pop bumper's own gray-box "KickerMesh" fallback
## (only visible if the cap failed to load, in which case no "BumperVisual" node exists at all) - is
## unaffected and still gets the shared flat accent exactly as before, so "aim here" red stays
## consistent everywhere except the one mesh that already reads red on its own.
static func _paint_owner(owner: Node3D, mat: StandardMaterial3D) -> void:
	var baked_cap := owner.get_node_or_null("BumperVisual") as Node3D
	for mesh: MeshInstance3D in _mesh_instances(owner):
		var under_baked_cap: bool = (
			baked_cap != null and (mesh == baked_cap or baked_cap.is_ancestor_of(mesh))
		)
		if under_baked_cap and _has_own_material(mesh):
			continue  # keep the cap's own baked material - it already reads red, don't stomp it
		mesh.material_override = mat


## True when every surface of `mesh`'s own MESH RESOURCE already carries a material, independent of
## any material_override a reskin pass may have set (checked via surface_get_material, never
## material_override, so this reads the BAKED material, not a previous coat of paint). An imported
## .glb with baked colours (the mushroom-cap bumper) satisfies this; a mesh with no material of its
## own does not. Used only as the safety net in _paint_owner: if the baked-material cap ever ships
## with a surface missing its material, that surface still gets the flat accent so the bumper never
## reads unpainted grey/white instead of "aim here" red.
static func _has_own_material(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
		return false
	for i in mesh.mesh.get_surface_count():
		if mesh.mesh.surface_get_material(i) == null:
			return false
	return true


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
