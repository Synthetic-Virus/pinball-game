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
## (gameplay-programmer). Called ONCE by table.gd after the dynamic elements are instanced.
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
			_paint_subtree(node, rail_mat)  ## editor-drawn inlane/outlane/guide rails
		# else: intentionally untouched (ball, flippers, plunger, drain, grid, scoring furniture).
	# The RED "aim here" accent on the scoring furniture is a separate, gameplay-owned visual file.
	ScoringReskin.apply(playfield)


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
