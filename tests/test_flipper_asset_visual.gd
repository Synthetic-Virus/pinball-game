extends GutTest
## Test matrix entry: FIRST REAL 3D ASSET - the flipper bat visual mesh comes from the imported
## assets/models/flipper_bat.glb, the scale is DERIVED from the collider (not a magic number), and
## the COLLIDER physics are untouched. Owner: test-builder. Slice: "first-real-3d-asset".
##
## SCAFFOLD STATUS: SKELETON written by the lead-programmer. The physics/gameplay coder fills
## scripts/flipper.gd against the seam documented in docs/handoff/first-real-3d-asset.md; the
## test-builder fills the bodies below against the SAME seam. The signatures the tests rely on are
## STABLE so this file can be written BEFORE the implementation lands.
##
## WHY THIS FILE IS SEPARATE from test_flipper_shape.gd / test_flipper_rubber_top.gd:
##   Those two files assert the PROCEDURAL gray-box mesh (a non-box ArrayMesh carrying the white
##   RUBBER_TOP_COLOR=0.92 cap that faces +Y). The imported .glb is a DIFFERENT mesh with DIFFERENT
##   materials ("Bat - Plastic White" + "Bat - Rubber Blue"). When the asset loads, the procedural
##   FlipperMesh is the HIDDEN fallback and a NEW imported MeshInstance3D ("FlipperVisual") is the
##   shown visual. The two legacy files keep asserting the (still-present, still-correct) fallback;
##   this file asserts the imported visual path. See the handoff doc for the node contract.
##
## INDEPENDENT-ORACLE DISCIPLINE: every assertion reads the REAL instanced flipper tree (mesh, AABB,
## collision shape class), never a self-reported flag. A hardcoded scale literal cannot satisfy the
## derive-from-collider test because it asserts the resulting WORLD-SPACE mesh length equals the
## collider length within tolerance, which only holds if the scale was actually measured/fitted.

const FLIPPER_SCENE: PackedScene = preload("res://scenes/elements/Flipper.tscn")

## The visual MeshInstance3D node name the imported .glb is instanced under (handoff contract). The
## procedural fallback keeps the legacy name "FlipperMesh"; the imported visual is "FlipperVisual".
const IMPORTED_VISUAL_NODE_NAME: String = "FlipperVisual"

## The asset path, asserted to exist and load. Single source of truth for the test + the script.
const FLIPPER_BAT_ASSET_PATH: String = "res://assets/models/flipper_bat.glb"

## Tolerance for the derived-scale length match (fraction of collider length). The fit measures the
## asset AABB long axis and scales it to FLIPPER_LENGTH; rounded end caps and mesh bounds vs the
## collider hull bounds differ slightly, so allow a sane band. TODO(test-builder): tighten once the
## real numbers are known from a headless run; keep it tight enough to catch a wrong magic constant.
const SCALE_LENGTH_TOLERANCE_FRACTION: float = 0.20

var _world: Node3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


## Instance + configure a flipper exactly as table.gd does. mirrored=false is the LEFT bat.
func _make_flipper(action: String, mirrored: bool) -> Node3D:
	var flipper: Node3D = FLIPPER_SCENE.instantiate() as Node3D
	flipper.position = Vector3.ZERO
	_world.add_child(flipper)
	if flipper.has_method("configure"):
		flipper.configure(action, mirrored)
	return flipper


## Resolve the imported visual MeshInstance3D (named IMPORTED_VISUAL_NODE_NAME), or null if the
## fallback path is active. TODO(test-builder): the handoff seam guarantees this node exists when
## the asset loaded; assert on it for the load-success tests.
func _imported_visual(flipper: Node3D) -> MeshInstance3D:
	var node: Node = flipper.find_child(IMPORTED_VISUAL_NODE_NAME, true, false)
	return node as MeshInstance3D


## Resolve the bat CollisionShape3D (child of FlipperBody) - the FROZEN collider.
func _bat_collision_shape(flipper: Node3D) -> CollisionShape3D:
	var bat: Node = flipper.find_child("FlipperBody", true, false)
	if bat == null:
		return null
	for child in bat.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


# ---- (a) ASSET PRESENT + IMPORTS WITHOUT ERROR -------------------------------------------------

func test_asset_file_exists() -> void:
	## The .glb must be present (LFS-pulled). On CI without lfs:true this would be a 130-byte pointer
	## that ResourceLoader cannot import - the load test below catches that case too.
	# TODO(test-builder): assert ResourceLoader.exists(FLIPPER_BAT_ASSET_PATH) and/or FileAccess on
	# the res:// path. A bare existence check plus the load check is the independent oracle for R2.
	pending("scaffold: assert the .glb exists at FLIPPER_BAT_ASSET_PATH")


func test_asset_imports_as_packed_scene() -> void:
	## Godot imports a .glb to a PackedScene; loading it must succeed and instantiate without error.
	# TODO(test-builder): load(FLIPPER_BAT_ASSET_PATH), assert it is a PackedScene, instantiate it,
	# assert the instance is non-null and contains at least one MeshInstance3D with a non-null mesh.
	pending("scaffold: load the .glb and assert it imports to an instantiable PackedScene")


# ---- (d) VISUAL WIRING: FlipperMesh now sources the imported .glb -------------------------------

func test_flipper_shows_imported_visual() -> void:
	## When the asset loads, the shown bat visual is the imported mesh (node IMPORTED_VISUAL_NODE_NAME
	## carrying a mesh whose surfaces come from the .glb), NOT the procedural builder output.
	# TODO(test-builder): _make_flipper, await wait_frames(2), assert _imported_visual(flipper) is
	# non-null and visible, and that its mesh is the imported asset (e.g. surface material names match
	# "Bat - Plastic White"/"Bat - Rubber Blue", or the mesh resource_name/source differs from the
	# procedural ArrayMesh). The procedural FlipperMesh must exist but be HIDDEN (the fallback).
	pending("scaffold: assert the imported visual node is present, visible, and is the .glb mesh")


func test_procedural_mesh_is_present_but_hidden_fallback() -> void:
	## The gray-box procedural mesh stays in the tree as the crash-proof fallback but is hidden while
	## the asset is shown. (If the asset failed to load, the fallback is shown instead - covered by
	## test_fallback_to_procedural_when_asset_missing.)
	# TODO(test-builder): find_child("FlipperMesh"), assert it exists; assert NOT both visible at once.
	pending("scaffold: assert the procedural FlipperMesh exists and is the hidden fallback")


# ---- SCALE DERIVATION (no magic number) --------------------------------------------------------

func test_visual_scale_is_derived_from_collider_length() -> void:
	## The headline anti-magic-number oracle. The imported visual's WORLD-SPACE long-axis length must
	## match the collider's long-axis length (~FLIPPER_LENGTH) within tolerance. This can only hold if
	## the scale was MEASURED from the asset AABB and fitted to the collider, never a typed literal.
	# TODO(test-builder): _make_flipper(left). Measure the imported visual's AABB long-axis extent in
	# WORLD space (mesh AABB transformed by the node's global_transform, take the longest axis). Get
	# the collider's long-axis length (TableConfig.FLIPPER_LENGTH, or measure the hull AABB). Assert
	# abs(visual_len - collider_len) <= collider_len * SCALE_LENGTH_TOLERANCE_FRACTION. Document the
	# measured numbers in a comment once known from a headless run.
	pending("scaffold: assert derived visual length matches collider length within tolerance")


func test_visual_scale_is_uniform() -> void:
	## The fit is ONE uniform factor (the spec: "apply that single uniform factor"). Assert the
	## imported visual node's scale is uniform (x == y == z within epsilon), so the bat is not
	## stretched on one axis.
	# TODO(test-builder): read _imported_visual(flipper).scale, assert is_equal_approx across axes.
	pending("scaffold: assert the visual node scale is uniform")


# ---- (b) COLLIDER INTEGRITY: the FROZEN physics shape (risk R3) ---------------------------------

func test_collider_is_still_convex_or_primitive_not_trimesh() -> void:
	## R3: the art mesh must NEVER become the collider. After the visual swap the bat's collision
	## shape must STILL be the ConvexPolygonShape3D (or a primitive), NEVER a ConcavePolygonShape3D /
	## trimesh derived from the imported mesh (those tunnel a fast ball - the project's #1 sin).
	# TODO(test-builder): cs = _bat_collision_shape(flipper); assert_false(cs.shape is
	# ConcavePolygonShape3D); assert_true(cs.shape is ConvexPolygonShape3D or a primitive). This
	# overlaps test_flipper_shape.test_collider_is_capsule_or_convex on purpose: the asset swap must
	# not silently re-home the collider onto the art.
	pending("scaffold: assert collider is still convex/primitive, never a trimesh from the art")


func test_collider_geometry_unchanged_by_visual_swap() -> void:
	## Defense in depth: the collider hull point count / AABB matches the procedural hull (the visual
	## swap touched ONLY the mesh). Proves the swap was cosmetic-only at the shape level.
	# TODO(test-builder): measure the hull's AABB / point count and assert it equals what the
	# procedural build produced (compute from TableConfig FLIPPER_LENGTH/WIDTH/HEIGHT, or snapshot).
	pending("scaffold: assert the collider hull geometry is unchanged by the visual swap")


# ---- (mirror) BLUE RUBBER ON TOP, BOTH SIDES ---------------------------------------------------

func test_both_flippers_use_the_imported_visual() -> void:
	## BOTH flippers source the one asset. The right is the mirror of the left (handoff: rotate 180
	## deg about the pivot vertical axis), so BOTH carry the imported visual node.
	# TODO(test-builder): make a left and a right flipper; assert _imported_visual is non-null and
	# visible for BOTH.
	pending("scaffold: assert both left and right flippers carry the imported visual")


func test_right_flipper_visual_is_not_inside_out() -> void:
	## The mirror must not invert the normals (an inside-out bat reads wrong-lit / blue rubber buried).
	## Mirroring by a 180 deg rotation about the pivot vertical axis (NOT a negative-scale reflection)
	## keeps the winding/normals correct. Independent oracle: the right visual node's basis determinant
	## is POSITIVE (a rotation, not a reflection); a negative determinant means a reflected, inverted
	## mesh.
	# TODO(test-builder): get the right flipper's _imported_visual global_transform.basis; assert
	# basis.determinant() > 0.0 (a proper rotation, no reflection). Optionally cross-check the rubber
	# sub-mesh's average world normal Y is positive (blue rubber faces up) on BOTH sides, mirroring
	# the technique in test_flipper_rubber_top.gd.
	pending("scaffold: assert the right visual is a clean rotation mirror (no reflection/inversion)")


# ---- (#4) NEVER CRASHES: graceful fallback -----------------------------------------------------

func test_fallback_to_procedural_when_asset_missing() -> void:
	## A missing/failed asset is a cosmetic downgrade, never a crash. If the .glb cannot load, the
	## flipper shows the procedural gray-box mesh and play continues.
	# TODO(test-builder): this needs the script to expose a seam to force the asset-load failure
	# WITHOUT deleting the file (e.g. a test-only setter for the asset path, mirroring the
	# _force_energized test-hook pattern in flipper.gd, OR build a flipper with a bogus path). Assert
	# the procedural FlipperMesh is shown and the flipper still configures/energizes without error.
	# The lead documents this seam in the handoff doc; do not delete the real asset in a test.
	pending("scaffold: assert graceful fallback to the procedural mesh when the asset fails to load")
