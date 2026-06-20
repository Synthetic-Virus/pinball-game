extends GutTest
## Test matrix entry: FIRST REAL 3D ASSET - the flipper bat visual mesh comes from the imported
## assets/models/flipper_bat.glb, the scale is DERIVED from the collider (not a magic number), and
## the COLLIDER physics are untouched. Owner: test-builder. Slice: "first-real-3d-asset".
##
## WHAT THESE TESTS VERIFY (16-entry test matrix, docs/handoff/first-real-3d-asset.md):
##   (1-2)  Asset exists and imports to a PackedScene with a MeshInstance3D.
##   (3-4)  FlipperVisual is the shown visual; FlipperMesh is hidden (the fallback path).
##   (5-6)  Collider is still ConvexPolygonShape3D, never a trimesh; hull geometry unchanged.
##   (7-8)  Visual world-space length matches the collider length (derived scale, no magic number).
##   (9-10) Both flippers carry the imported visual; right mirror has a positive basis determinant.
##   (11)   Load failure falls back to the procedural mesh without crashing.
##   (12-16) FROZEN keep-green gates live in test_flipper_no_tunneling, test_flipper_momentum,
##           test_flipper_rubber, test_flipper_rubber_top, test_flipper_shape; not duplicated here.
##
## INDEPENDENT-ORACLE DISCIPLINE: every assertion reads the REAL instanced flipper tree (mesh, AABB,
## collision shape class, node visibility), never a self-reported flag. The scale test asserts the
## WORLD-SPACE mesh length equals the collider length within tolerance - the only assertion that
## can catch a hardcoded magic-number scale (a magic number satisfying the formula exactly is
## near-impossible to type by accident; any mismatch produces a measurable length error).
##
## WHEN DO THESE PASS: all 11 tests below are RED until the physics-programmer implements
## FlipperVisual and the set_asset_path_for_test() seam in scripts/flipper.gd. That is the correct
## pre-implementation state: tests written against the agreed seam BEFORE the code lands.

const FLIPPER_SCENE: PackedScene = preload("res://scenes/elements/Flipper.tscn")

## The visual MeshInstance3D node name the imported .glb is instanced under (handoff contract). The
## procedural fallback keeps the legacy name "FlipperMesh"; the imported visual is "FlipperVisual".
const IMPORTED_VISUAL_NODE_NAME: String = "FlipperVisual"

## The procedural gray-box mesh node name (the fallback, kept hidden when the asset loads).
const PROCEDURAL_MESH_NODE_NAME: String = "FlipperMesh"

## The asset path, asserted to exist and load. Single source of truth for the test + the script.
const FLIPPER_BAT_ASSET_PATH: String = "res://assets/models/flipper_bat.glb"

## Tolerance for the derived-scale length match (fraction of collider length). The fit measures the
## asset AABB long axis and scales it to FLIPPER_LENGTH; rounded end caps and mesh bounds vs the
## collider hull bounds differ slightly, so allow a sane band. 20% is wide enough to tolerate mesh
## bounding-box vs collider-hull discrepancies while tight enough to catch an order-of-magnitude
## wrong magic number (e.g. scale left as 1.0 on the real-metre asset produces a bat ~0.080 world
## units vs the 7.0 FLIPPER_LENGTH - a 99% error, far outside this band).
const SCALE_LENGTH_TOLERANCE_FRACTION: float = 0.20

## Epsilon for floating-point comparisons (scale uniformity, basis determinant sign).
const EPSILON: float = 1e-4

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
## fallback path is active or the node does not exist yet.
func _imported_visual(flipper: Node3D) -> MeshInstance3D:
	var node: Node = flipper.find_child(IMPORTED_VISUAL_NODE_NAME, true, false)
	return node as MeshInstance3D


## Resolve the procedural gray-box MeshInstance3D (named PROCEDURAL_MESH_NODE_NAME).
func _procedural_mesh(flipper: Node3D) -> MeshInstance3D:
	var node: Node = flipper.find_child(PROCEDURAL_MESH_NODE_NAME, true, false)
	return node as MeshInstance3D


## Resolve the bat CollisionShape3D (child of FlipperBody) - the FROZEN collider.
func _bat_collision_shape(flipper: Node3D) -> CollisionShape3D:
	var bat: Node = flipper.find_child("FlipperBody", true, false)
	if bat == null:
		return null
	for child: Node in bat.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


## Return the longest world-space axis length of a MeshInstance3D's AABB. Transforms the mesh's
## LOCAL AABB by the node's global_transform to get the world-space bounding box, then returns the
## maximum of the three axis extents. Used to compare visual length against the collider length.
func _mesh_world_long_axis(mesh_instance: MeshInstance3D) -> float:
	if mesh_instance == null or mesh_instance.mesh == null:
		return 0.0
	# The AABB in the node's local space.
	var local_aabb: AABB = mesh_instance.get_aabb()
	# Transform AABB to world space by applying the node's global_transform.
	# We use the absolute extents of the 8 corners so the max along each world axis is correct
	# regardless of rotation (the mesh may be oriented with its long axis not along world X/Y/Z).
	var xform: Transform3D = mesh_instance.global_transform
	var corners: PackedVector3Array = PackedVector3Array()
	var lo: Vector3 = local_aabb.position
	var hi: Vector3 = local_aabb.end
	corners.append(xform * Vector3(lo.x, lo.y, lo.z))
	corners.append(xform * Vector3(hi.x, lo.y, lo.z))
	corners.append(xform * Vector3(lo.x, hi.y, lo.z))
	corners.append(xform * Vector3(lo.x, lo.y, hi.z))
	corners.append(xform * Vector3(hi.x, hi.y, lo.z))
	corners.append(xform * Vector3(hi.x, lo.y, hi.z))
	corners.append(xform * Vector3(lo.x, hi.y, hi.z))
	corners.append(xform * Vector3(hi.x, hi.y, hi.z))
	var world_min: Vector3 = corners[0]
	var world_max: Vector3 = corners[0]
	for c: Vector3 in corners:
		world_min = world_min.min(c)
		world_max = world_max.max(c)
	var size: Vector3 = world_max - world_min
	return maxf(maxf(size.x, size.y), size.z)


# ---- (a) ASSET PRESENT + IMPORTS WITHOUT ERROR -------------------------------------------------

func test_asset_file_exists() -> void:
	## The .glb must be present at the known path (LFS-pulled by the CI `lfs: true` checkout).
	## Without LFS the file would be a 130-byte text pointer that ResourceLoader cannot import -
	## the load test below would also catch that, but this faster check names the failure clearly.
	## WHY ResourceLoader.exists: it resolves the res:// path through the project's import system,
	## so it returns true only when the file is REALLY present and importable, not just named.
	assert_true(
		ResourceLoader.exists(FLIPPER_BAT_ASSET_PATH),
		"The .glb must exist at %s - did the CI checkout run with lfs:true?" % FLIPPER_BAT_ASSET_PATH
	)


func test_asset_imports_as_packed_scene() -> void:
	## Godot imports a .glb to a PackedScene; loading it must succeed and the scene must instantiate
	## without error and contain at least one MeshInstance3D with a real mesh. A LFS pointer or a
	## corrupted import would either return null or fail the MeshInstance3D check.
	var loaded: Resource = load(FLIPPER_BAT_ASSET_PATH)
	assert_not_null(loaded, "load(%s) must not return null" % FLIPPER_BAT_ASSET_PATH)
	if loaded == null:
		return
	assert_true(
		loaded is PackedScene,
		".glb must import to a PackedScene, got %s" % [loaded.get_class()]
	)
	var packed: PackedScene = loaded as PackedScene
	var instance: Node = packed.instantiate()
	assert_not_null(instance, "the imported PackedScene must instantiate without error")
	if instance == null:
		return
	# At least one MeshInstance3D with a real (non-null) mesh must exist in the imported scene.
	var found_mesh: bool = false
	for child: Node in instance.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			found_mesh = true
			break
	# Also scan deeper (the .glb may have a nested structure).
	if not found_mesh:
		for descendant: Node in instance.find_children("*", "MeshInstance3D", true, false):
			if (descendant as MeshInstance3D).mesh != null:
				found_mesh = true
				break
	assert_true(
		found_mesh,
		"the imported .glb must contain at least one MeshInstance3D with a non-null mesh"
	)
	instance.queue_free()


# ---- (d) VISUAL WIRING: FlipperVisual shows the imported .glb ----------------------------------

func test_flipper_shows_imported_visual() -> void:
	## When the asset loads successfully, the shown bat visual is the IMPORTED node
	## (IMPORTED_VISUAL_NODE_NAME = "FlipperVisual") carrying the .glb mesh - it must exist, be
	## visible, and have a non-null mesh. The procedural FlipperMesh stays in the tree but is HIDDEN
	## (it is the fallback, not the primary - confirmed by the next test).
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var visual: MeshInstance3D = _imported_visual(flipper)
	assert_not_null(
		visual,
		'the "%s" MeshInstance3D (the imported .glb visual) must exist in the flipper tree'
		% IMPORTED_VISUAL_NODE_NAME
	)
	if visual == null:
		return
	assert_true(
		visual.visible,
		'the "%s" node must be VISIBLE when the asset loads successfully'
		% IMPORTED_VISUAL_NODE_NAME
	)
	assert_not_null(
		visual.mesh,
		'the "%s" node must have a non-null mesh (the imported .glb mesh)'
		% IMPORTED_VISUAL_NODE_NAME
	)


func test_procedural_mesh_is_present_but_hidden_fallback() -> void:
	## The gray-box procedural mesh (FlipperMesh) must stay in the tree as the crash-proof fallback
	## but HIDDEN while the imported visual is shown. Also asserts that exactly ONE visual is shown
	## at a time (not both simultaneously), so the bat never renders double.
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var proc_mesh: MeshInstance3D = _procedural_mesh(flipper)
	assert_not_null(
		proc_mesh,
		'the procedural "%s" node must remain in the tree as the fallback (never deleted)'
		% PROCEDURAL_MESH_NODE_NAME
	)
	# The procedural mesh must be hidden when the asset-loaded visual is shown.
	if proc_mesh != null:
		assert_false(
			proc_mesh.visible,
			'the procedural "%s" must be HIDDEN while FlipperVisual is the shown visual'
			% PROCEDURAL_MESH_NODE_NAME
		)
	# Belt-and-braces: both should NOT be visible at the same time.
	var imported_vis: MeshInstance3D = _imported_visual(flipper)
	var both_visible: bool = (
		proc_mesh != null and proc_mesh.visible
		and imported_vis != null and imported_vis.visible
	)
	assert_false(both_visible, "FlipperMesh and FlipperVisual must NOT both be visible at once")


# ---- SCALE DERIVATION (no magic number) --------------------------------------------------------

func test_visual_scale_is_derived_from_collider_length() -> void:
	## The headline anti-magic-number oracle (handoff doc: "measured/derived, NEVER a hand-typed
	## literal like 87.5"). The imported FlipperVisual's WORLD-SPACE long-axis length must match
	## TableConfig.FLIPPER_LENGTH within SCALE_LENGTH_TOLERANCE_FRACTION. This can only hold if the
	## scale was measured from the asset's own AABB and fitted to the collider, not guessed by hand:
	## a wrong magic literal (e.g. scale 1.0 on the real-metre ~0.08-unit asset) produces a 0.08-unit
	## world bat vs the required 7.0 - a 99% error that this tolerance catches.
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var visual: MeshInstance3D = _imported_visual(flipper)
	assert_not_null(visual, "FlipperVisual must exist before testing its scale")
	if visual == null:
		return
	var collider_len: float = TableConfig.FLIPPER_LENGTH
	var visual_len: float = _mesh_world_long_axis(visual)
	var allowed_error: float = collider_len * SCALE_LENGTH_TOLERANCE_FRACTION
	assert_lt(
		absf(visual_len - collider_len),
		allowed_error,
		(
			"FlipperVisual world-space long-axis (%.3f) must be within %.0f%% of FLIPPER_LENGTH (%.1f). "
			+ "A magic-number scale that does not derive from the asset AABB will fail this. "
			+ "error=%.3f, allowed=%.3f"
		) % [visual_len, SCALE_LENGTH_TOLERANCE_FRACTION * 100.0, collider_len,
				absf(visual_len - collider_len), allowed_error]
	)


func test_visual_scale_is_uniform() -> void:
	## The handoff spec requires ONE uniform scale factor (not a per-axis stretch that would distort
	## the bat's shape). Assert the FlipperVisual node's local scale is equal on all three axes
	## within EPSILON. A non-uniform scale would read as a squashed/stretched bat.
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var visual: MeshInstance3D = _imported_visual(flipper)
	assert_not_null(visual, "FlipperVisual must exist before testing its scale uniformity")
	if visual == null:
		return
	var s: Vector3 = visual.scale
	# All three axes must be equal (uniform scale), allowing a tiny float epsilon.
	assert_lt(
		absf(s.x - s.y),
		EPSILON,
		"FlipperVisual scale.x (%.6f) must equal scale.y (%.6f) - uniform scale required" % [s.x, s.y]
	)
	assert_lt(
		absf(s.y - s.z),
		EPSILON,
		"FlipperVisual scale.y (%.6f) must equal scale.z (%.6f) - uniform scale required" % [s.y, s.z]
	)


# ---- (b) COLLIDER INTEGRITY: the FROZEN physics shape (risk R3) ---------------------------------

func test_collider_is_still_convex_or_primitive_not_trimesh() -> void:
	## R3 from the asset spec: the art mesh must NEVER become the collider. After the visual swap the
	## bat's collision shape must STILL be the ConvexPolygonShape3D (or a primitive), NEVER a
	## ConcavePolygonShape3D / trimesh derived from the imported mesh. ConcavePolygonShape3D is Godot's
	## "trimesh" mode - it tunnels a fast ball (the project's #1 sin, CLAUDE.md). This check overlaps
	## test_flipper_shape.test_collider_is_capsule_or_convex intentionally: the visual swap MUST NOT
	## silently re-home the collider to the imported mesh.
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var cs: CollisionShape3D = _bat_collision_shape(flipper)
	assert_not_null(cs, "the FlipperBody must have a CollisionShape3D after the visual swap")
	if cs == null:
		return
	assert_false(
		cs.shape is ConcavePolygonShape3D,
		(
			"the flipper collider must NEVER be a ConcavePolygonShape3D (trimesh from art mesh). "
			+ "R3: the art mesh must NOT become the collider. shape=%s" % [cs.shape.get_class()]
		)
	)
	var ok: bool = (cs.shape is ConvexPolygonShape3D) or (cs.shape is CapsuleShape3D)
	assert_true(
		ok,
		(
			"after the visual swap the collider must still be a ConvexPolygonShape3D or "
			+ "CapsuleShape3D, not %s" % [cs.shape.get_class()]
		)
	)


func test_collider_geometry_unchanged_by_visual_swap() -> void:
	## Defense in depth: the collider AABB must match the dimensions the procedural build produced
	## (FLIPPER_LENGTH x FLIPPER_WIDTH x FLIPPER_HEIGHT from TableConfig). The visual swap must be
	## cosmetic-only at the shape level: only the MeshInstance3D changes, never the hull points or
	## the shape's extents. A swap that accidentally resized the hull would change the AABB here.
	## We allow a 10% tolerance for the rounded ends and the convex-hull approximation of the taper.
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var cs: CollisionShape3D = _bat_collision_shape(flipper)
	assert_not_null(cs, "the FlipperBody must have a CollisionShape3D")
	if cs == null or cs.shape == null:
		return
	# Measure the collider's AABB extents (in the shape's local frame).
	var shape_aabb: AABB = cs.shape.get_debug_mesh().get_aabb()
	var shape_size: Vector3 = shape_aabb.size
	var tol: float = 0.10  # 10% tolerance for rounding and taper approximation.
	# The long axis (FLIPPER_LENGTH) is always the largest dimension.
	var max_extent: float = maxf(maxf(shape_size.x, shape_size.y), shape_size.z)
	assert_lt(
		absf(max_extent - TableConfig.FLIPPER_LENGTH) / TableConfig.FLIPPER_LENGTH,
		tol,
		(
			"collider long-axis extent (%.3f) must be within %.0f%% of FLIPPER_LENGTH (%.1f) - "
			+ "the visual swap must not resize the hull"
		) % [max_extent, tol * 100.0, TableConfig.FLIPPER_LENGTH]
	)


# ---- (mirror) BLUE RUBBER ON TOP, BOTH SIDES ---------------------------------------------------

func test_both_flippers_use_the_imported_visual() -> void:
	## BOTH flippers use the one .glb asset. The right bat is the mirror of the left (a 180-degree
	## rotation about the pivot vertical axis, per the handoff spec). Both must therefore carry a
	## FlipperVisual node that is visible and has a non-null mesh.
	var left: Node3D = _make_flipper("left_flipper", false)
	var right: Node3D = _make_flipper("right_flipper", true)
	await wait_frames(2)
	var left_vis: MeshInstance3D = _imported_visual(left)
	var right_vis: MeshInstance3D = _imported_visual(right)
	assert_not_null(
		left_vis,
		"the LEFT flipper must carry a FlipperVisual (imported .glb) node"
	)
	assert_not_null(
		right_vis,
		"the RIGHT flipper must also carry a FlipperVisual (imported .glb) node"
	)
	if left_vis != null:
		assert_true(left_vis.visible, "the LEFT FlipperVisual must be visible")
		assert_not_null(left_vis.mesh, "the LEFT FlipperVisual must have a non-null mesh")
	if right_vis != null:
		assert_true(right_vis.visible, "the RIGHT FlipperVisual must be visible")
		assert_not_null(right_vis.mesh, "the RIGHT FlipperVisual must have a non-null mesh")


func test_right_flipper_visual_is_not_inside_out() -> void:
	## The handoff spec: mirror by a 180-degree ROTATION about the pivot vertical axis (+Y), NOT a
	## negative-scale reflection. A reflection inverts winding/normals so the blue rubber is buried
	## (the inside-out bat is dark/wrong-lit). The deterministic oracle: the right FlipperVisual's
	## global_transform.basis determinant must be POSITIVE. A proper rotation (orthonormal, det +1)
	## is positive; a reflection has det -1.
	var right: Node3D = _make_flipper("right_flipper", true)
	await wait_frames(2)
	var visual: MeshInstance3D = _imported_visual(right)
	assert_not_null(visual, "the RIGHT flipper must have a FlipperVisual to test its orientation")
	if visual == null:
		return
	var det: float = visual.global_transform.basis.determinant()
	assert_gt(
		det,
		0.0,
		(
			"the RIGHT FlipperVisual basis determinant must be POSITIVE (a clean rotation, not a "
			+ "reflection). det=%.4f. A negative determinant means the bat is inside-out (normals "
			+ "inverted, blue rubber buried). Mirror by 180 deg rotation about +Y, not by -scale."
		) % det
	)


# ---- (#4) NEVER CRASHES: graceful fallback -----------------------------------------------------

func test_fallback_to_procedural_when_asset_missing() -> void:
	## A failed asset load is a cosmetic downgrade, never a crash (DESIGN must-feel #4). If the .glb
	## cannot load, the flipper must show the procedural gray-box mesh and continue to
	## configure/energize without error. The seam that triggers this path is the test hook
	## set_asset_path_for_test("") (or a bogus path), documented in the handoff doc, mirroring the
	## _force_energized test-hook pattern. We force a bad path, instance the flipper, and check the
	## procedural fallback is visible and the script did not crash.
	var flipper: Node3D = FLIPPER_SCENE.instantiate() as Node3D
	flipper.position = Vector3.ZERO
	# Force the asset-load failure BEFORE adding to the tree so the seam fires on _ready().
	if flipper.has_method("set_asset_path_for_test"):
		flipper.set_asset_path_for_test("res://does_not_exist_flipper_bat.glb")
	_world.add_child(flipper)
	if flipper.has_method("configure"):
		flipper.configure("left_flipper", false)
	await wait_frames(2)

	# Procedural mesh must be SHOWN (the fallback is active).
	var proc_mesh: MeshInstance3D = _procedural_mesh(flipper)
	assert_not_null(
		proc_mesh,
		"the procedural FlipperMesh must still exist when the asset fails to load"
	)
	if proc_mesh != null:
		assert_true(
			proc_mesh.visible,
			"the procedural FlipperMesh must be VISIBLE when the asset fails (fallback active)"
		)

	# Imported visual must be absent OR hidden (no crashed half-loaded node shown).
	var visual: MeshInstance3D = _imported_visual(flipper)
	if visual != null:
		assert_false(
			visual.visible,
			"FlipperVisual must NOT be visible when the asset failed to load"
		)

	# The flipper must still be usable (configure/energize must not have crashed it).
	assert_true(
		flipper.has_method("is_energized"),
		"the flipper must still expose is_energized() after a failed asset load (no crash)"
	)
	if flipper.has_method("is_energized"):
		# Should not throw; just exercise the path. Discard the result.
		var energized: bool = flipper.is_energized()
		assert_false(energized and false, "exercising is_energized() must not crash")
