class_name TableReskin
extends RefCounted
## TableReskin - applies the STRUCTURAL palette (playfield, walls, rails) to the built table, then
## delegates the scoring-furniture accent to ScoringReskin. VISUAL ONLY.
##
## WHY A SEPARATE APPLIER (the SLICE A2 architecture decision): this slice is visual-only with
## FROZEN physics. Rather than edit the colour literals inside the physics-bearing builders
## (table_geometry builds colliders; pop_bumper / slingshot / target apply kicks), the reskin walks
## the ALREADY-BUILT scene and sets `material_override` on the VISIBLE MeshInstance3D nodes only.
## Nothing here reads or writes a collision shape, a layer, a position, or a kick vector. That is
## what lets `git diff --stat` prove the reskin touched no physics/collision/layout/kick script:
## those files show ZERO diff; the only new code is this file, palette.gd, scoring_reskin.gd, plus
## one call line in table.gd.
##
## OWNERSHIP: lead-programmer (structural frame). The scoring accent is scoring_reskin.gd
## (gameplay-programmer). Called by table.gd as a final WHOLE-TABLE pass from _ready(), after BOTH
## build phases (static geometry, dynamic furniture, AND the layout editor's rails). Running it that
## late is what lets the EditRail branch below actually reach the rails - they are spawned by the
## layout editor, so an earlier call left that branch dead (QA BUG-049). reskin_spawned() below
## keeps a piece the developer places IN the editor after load on-palette too.
##
## ALLOWLIST, NOT DENYLIST: this only recolours nodes it explicitly names (Surface, Border*,
## LaneDivider, WallDemo, EditRail). Everything else - the ball, BOTH flippers (their two-tone is
## sacred), the plunger hardware, the drain mouth, the coord grid - is left untouched by
## construction, so the reskin can never accidentally repaint the ball or a flipper.


## Apply the whole reskin to a built playfield. Idempotent: material_override simply replaces the
## previous override, so calling twice is harmless. Safe on a null / empty playfield (no-op).
static func apply(playfield: Node3D) -> void:
	if playfield == null:
		return
	# Build one shared flat material per structural colour and reuse it across every matching body,
	# so the whole frame shares one material resource (cheaper than one material per mesh).
	var field_mat := Palette.flat_material(Palette.PLAYFIELD)
	var wall_mat := Palette.flat_material(Palette.WALLS)
	var rail_mat := Palette.flat_material(Palette.RAILS)
	for child: Node in playfield.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var n: String = node.name
		if n == "Surface":
			_paint_subtree(node, field_mat)  ## the blue ground the ball rolls on
		elif n.begins_with("Border") or n == "LaneDivider" or n == "WallDemo":
			_paint_subtree(node, wall_mat)  ## the calm white boundary frame
		elif node is EditRail:
			_paint_rail(node, rail_mat)  ## editor-drawn inlane/outlane/guide rails
		# else: intentionally untouched (ball, flippers, plunger, drain, grid, scoring furniture).
	# The RED "aim here" accent on the scoring furniture is a separate, gameplay-owned visual file.
	ScoringReskin.apply(playfield)


## Reskin ONE node the in-game layout editor just spawned, so a rail / wall / scoring piece the
## developer adds AFTER load stays on-palette without re-walking the whole table. VISUAL ONLY and
## null-safe; mirrors apply()'s allowlist decision for a single node (QA BUG-049).
static func reskin_spawned(node: Node3D) -> void:
	if node == null:
		return
	var n: String = node.name
	if n.begins_with("Border") or n == "LaneDivider" or n == "WallDemo":
		_paint_subtree(node, Palette.flat_material(Palette.WALLS))
	elif node is EditRail:
		_paint_rail(node, Palette.flat_material(Palette.RAILS))
	else:
		# Scoring furniture (bumper / sling / target) is found by its marker child; the gameplay-owned
		# accent file paints it red. A non-scoring node with no marker is simply left untouched.
		ScoringReskin.apply(node)


## Paint an editor rail into the white frame, but only its WALL SEGMENTS, never its drag-handles. An
## EditRail builds its wall segments under a "Segments" child (edit_rail.gd); its point-handles are
## separate MeshInstance3D children with a bright cyan grab material (an EDIT-MODE affordance, not
## table geometry). Painting the whole subtree would clobber that cyan, so we paint only "Segments".
static func _paint_rail(rail: Node3D, mat: StandardMaterial3D) -> void:
	var segments := rail.get_node_or_null("Segments") as Node3D
	if segments != null:
		_paint_subtree(segments, mat)


## Set `mat` as the material_override on EVERY MeshInstance3D under `root` (inclusive). Using
## material_override (not mesh.material) means the reskin never edits the built mesh resource, it
## only layers a colour on top, so the underlying geometry/collider is provably untouched. It also
## covers the skinned wall.glb meshes (a Border body hides its gray-box box mesh and shows the wall
## model), so a border reads white whether it renders as the box or the imported wall.
static func _paint_subtree(root: Node3D, mat: StandardMaterial3D) -> void:
	for mesh: MeshInstance3D in _mesh_instances(root):
		mesh.material_override = mat


## Every MeshInstance3D under `node` (recursive), so a body plus any skinned .glb child are caught.
static func _mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c: Node in node.get_children():
		found.append_array(_mesh_instances(c))
	return found
