extends GutTest
## Test matrix entry: CAPSULE FLIPPER SHAPE (the bat collider + mesh are a tapered rounded stadium,
## NOT a box). Owner: physics-programmer + test-builder. Slice: "Table reshape + playtest fixes".
##
## WHY THIS EXISTS: developer playtest feedback - the flippers were bare BoxMesh/box colliders and
## read as planks, not flippers. DESIGN must-feel #2: "the flipper is a flipper shape" - a tapered
## rounded form (fatter at the pivot, smaller rounded tip) in BOTH the visible mesh AND the
## collider, with the two AGREEING, so where on the bat the ball hits matters. This STRUCTURAL test
## is the independent oracle for "the shape was actually swapped": it inspects the REAL instanced
## flipper's collision shape and mesh, never a self-reported flag.
##
## SCOPE OF THIS FILE: the SHAPE swap only. The FEEL gates (full swing out-throws a tap; ~50 ms
## snap; rubber rebound >= 35%) live in test_flipper_momentum.gd and test_flipper_rubber.gd, which
## must stay GREEN unchanged after the swap (the drive/material are NOT touched, only the geometry).
## See docs/ARCHITECTURE.md section 11.3.
##
## CONTRACT the physics-programmer fills against (ARCHITECTURE.md 11.3):
##   - The bat's CollisionShape3D.shape is a CapsuleShape3D OR a ConvexPolygonShape3D - NEVER a
##     BoxShape3D. (A capsule is the simplest stadium; a convex hull matching a tapered mesh also
##     satisfies it. The hard assertion is "not a box".)
##   - The bat carries a visible non-box MeshInstance3D (the mesh agrees with the collider).
##   - The bat keeps its rubber PhysicsMaterial (BAT_BOUNCE 0.70) - the rubber feel is unchanged by
##     the shape swap (this overlaps test_flipper_rubber's material check on purpose: shape and
##     surface are both asserted here so a shape swap that drops the material is caught).

const FLIPPER_SCENE: PackedScene = preload("res://scenes/elements/Flipper.tscn")

var _world: Node3D = null
var _flipper: Node3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)

	# A real LEFT flipper, configured exactly like table.gd does, so we inspect the shipping geometry.
	_flipper = FLIPPER_SCENE.instantiate() as Node3D
	_flipper.position = Vector3.ZERO
	_world.add_child(_flipper)
	if _flipper.has_method("configure"):
		_flipper.configure("left_flipper", false)
	await wait_frames(2)  # let _ready / configure build the bat


## Resolve the bat's CollisionShape3D (the child of the FlipperBody RigidBody3D).
func _bat_collision_shape() -> CollisionShape3D:
	var bat: Node = _flipper.find_child("FlipperBody", true, false)
	if bat == null:
		return null
	for child in bat.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


# ---- STRUCTURAL: the collider is a capsule / convex hull, not a box -----------------------------

func test_collider_is_not_a_box() -> void:
	## The headline structural assertion for this fix: the bat collider must NOT be a BoxShape3D. A box
	## is what the developer reported as "a plank"; the swap to a rounded stadium is the whole point.
	var cs: CollisionShape3D = _bat_collision_shape()
	assert_not_null(cs, "the FlipperBody must have a CollisionShape3D")
	if cs != null:
		assert_false(
			cs.shape is BoxShape3D,
			"the flipper collider must NOT be a BoxShape3D (a plank); use a tapered capsule/convex hull"
		)


func test_collider_is_capsule_or_convex() -> void:
	## Positive assertion of the agreed shapes: a CapsuleShape3D (simplest stadium) or a
	## ConvexPolygonShape3D (a hull matching a tapered mesh). Either satisfies "tapered rounded
	## stadium" at gray-box stage; both are NOT a box.
	var cs: CollisionShape3D = _bat_collision_shape()
	assert_not_null(cs, "the FlipperBody must have a CollisionShape3D")
	if cs != null:
		var ok: bool = (cs.shape is CapsuleShape3D) or (cs.shape is ConvexPolygonShape3D)
		assert_true(
			ok,
			"the flipper collider must be a CapsuleShape3D or ConvexPolygonShape3D; got %s"
			% [cs.shape]
		)


# ---- STRUCTURAL: the mesh agrees (visible, non-box) ---------------------------------------------

func test_bat_has_a_visible_non_box_mesh() -> void:
	## The collider and the MESH must AGREE (DESIGN: "mesh AND collider agree"). The bat must carry a
	## MeshInstance3D, and at gray-box stage its mesh must not be a plain BoxMesh (it should be the
	## matching capsule/tapered mesh). We assert presence + not-a-BoxMesh; the exact mesh class is the
	## physics-programmer's choice as long as it reads as the rounded bat.
	var bat: Node = _flipper.find_child("FlipperBody", true, false)
	assert_not_null(bat, "flipper must have a FlipperBody")
	if bat == null:
		return
	var mesh_instance: MeshInstance3D = null
	for child in bat.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	assert_not_null(mesh_instance, "the bat must have a MeshInstance3D so it is visible")
	if mesh_instance != null and mesh_instance.mesh != null:
		assert_false(
			mesh_instance.mesh is BoxMesh,
			"the bat mesh must agree with the rounded collider (not a plain BoxMesh)"
		)


# ---- STRUCTURAL: the rubber surface survives the shape swap -------------------------------------

func test_shape_swap_keeps_rubber_material() -> void:
	## The shape swap must NOT drop the rubber PhysicsMaterial (BAT_BOUNCE). The rubber feel is a
	## SURFACE property independent of the shape; a swap that forgot to re-attach the material would
	## silently regress the rubber-rebound gate. Assert the bat still carries a springy material.
	var bat: Node = _flipper.find_child("FlipperBody", true, false)
	assert_not_null(bat, "flipper must have a FlipperBody")
	if bat != null and bat is RigidBody3D:
		var mat: PhysicsMaterial = (bat as RigidBody3D).physics_material_override
		assert_not_null(mat, "the bat must keep its rubber PhysicsMaterial after the shape swap")
		if mat != null:
			assert_gt(
				mat.bounce, 0.25,
				"the rubber surface must survive the shape swap (bounce > 0.25). bounce=%f" % mat.bounce
			)
