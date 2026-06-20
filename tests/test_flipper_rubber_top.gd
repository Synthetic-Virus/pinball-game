extends GutTest
## Test matrix entry: BOTH FLIPPERS RENDER THE WHITE RUBBER TOP (right-bat mirror fix).
## Owner: physics-programmer + test-builder. Slice: "Playtest fixes 2", fix 2.
##
## WHY THIS EXISTS: developer playtest feedback - the LEFT flipper shows the white rubber top but
## the RIGHT (mirrored) flipper renders all black. ROOT CAUSE (flipper.gd): _rebuild_bat_geometry
## mirrors the outline by negating X, which REVERSES the winding; _build_bat_mesh wound the top cap
## (surface 1, the white RUBBER_TOP_COLOR) for the +X order, so on the right bat the top cap faces
## DOWN (-Y) and is backface-culled - no white top. The fix flips the winding for the mirrored side
## (_emit_tri(..., flip)). This STRUCTURAL test is the independent oracle: it inspects the REAL
## instanced LEFT and RIGHT bats and asserts BOTH carry a white-rubber-top surface whose top cap
## faces +Y, never a self-reported flag.
##
## DESIGN must-feel #2: both flippers look identical (black body + white rubber top). A side-by-side
## look shows two matching bats, not one black and one two-tone.

const FLIPPER_SCENE: PackedScene = preload("res://scenes/elements/Flipper.tscn")

## The white rubber-top color the mesh builder assigns to surface 1 (must match flipper.gd).
const RUBBER_TOP_COLOR: Color = Color(0.92, 0.92, 0.92)

var _world: Node3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


## Instance and configure a flipper of the given handedness exactly as table.gd does.
func _make_flipper(action: String, mirrored: bool) -> Node3D:
	var flipper: Node3D = FLIPPER_SCENE.instantiate() as Node3D
	flipper.position = Vector3.ZERO
	_world.add_child(flipper)
	if flipper.has_method("configure"):
		flipper.configure(action, mirrored)
	return flipper


## Resolve the bat MeshInstance3D (child of FlipperBody).
func _bat_mesh(flipper: Node3D) -> MeshInstance3D:
	var bat: Node = flipper.find_child("FlipperBody", true, false)
	if bat == null:
		return null
	for child in bat.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


## True if the mesh has at least one surface whose material albedo is the white rubber-top color.
func _has_rubber_top_surface(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return false
	for s in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			var albedo: Color = (mat as StandardMaterial3D).albedo_color
			if albedo.is_equal_approx(RUBBER_TOP_COLOR):
				return true
	return false


## The average Y component of the geometric normals of the rubber-top surface, in the bat's LOCAL
## frame. A correctly-wound up-facing cap has a POSITIVE average (faces +Y); a wrong-wound cap
## faces -Y (negative). This is the independent oracle for "the right bat's top is not flipped".
## Returns 0.0 if the surface is absent (the absence is caught by _has_rubber_top_surface).
func _rubber_top_avg_normal_y(mesh_instance: MeshInstance3D) -> float:
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return 0.0
	for s in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(s)
		if not (mat is StandardMaterial3D):
			continue
		if not (mat as StandardMaterial3D).albedo_color.is_equal_approx(RUBBER_TOP_COLOR):
			continue
		var arrays: Array = mesh.surface_get_arrays(s)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if normals.is_empty():
			return 0.0
		var sum_y: float = 0.0
		for nrm: Vector3 in normals:
			sum_y += nrm.y
		return sum_y / float(normals.size())
	return 0.0


# ---- STRUCTURAL: both bats carry the white rubber top ------------------------------------------

func test_left_flipper_has_white_rubber_top() -> void:
	var flipper: Node3D = _make_flipper("left_flipper", false)
	await wait_frames(2)
	var mesh_instance: MeshInstance3D = _bat_mesh(flipper)
	assert_not_null(mesh_instance, "the left flipper must have a bat MeshInstance3D")
	assert_true(
		_has_rubber_top_surface(mesh_instance),
		"the LEFT flipper must carry a white rubber-top surface"
	)


func test_right_flipper_has_white_rubber_top() -> void:
	## The headline assertion for this fix: the RIGHT (mirrored) bat must ALSO carry the white rubber
	## top - the mirror must not drop the surface.
	var flipper: Node3D = _make_flipper("right_flipper", true)
	await wait_frames(2)
	var mesh_instance: MeshInstance3D = _bat_mesh(flipper)
	assert_not_null(mesh_instance, "the right flipper must have a bat MeshInstance3D")
	assert_true(
		_has_rubber_top_surface(mesh_instance),
		"the RIGHT (mirrored) flipper must ALSO carry the white rubber-top surface (fix 2)"
	)


func test_right_flipper_top_cap_faces_up() -> void:
	## The deeper oracle: the right bat's rubber top must FACE +Y (up), not be culled facing down. A
	## mirror that reversed the winding without correcting it leaves the cap facing -Y - present in the
	## surface list but invisible. Assert the average normal Y is positive (faces up), like the left.
	var left: Node3D = _make_flipper("left_flipper", false)
	var right: Node3D = _make_flipper("right_flipper", true)
	await wait_frames(2)
	var left_y: float = _rubber_top_avg_normal_y(_bat_mesh(left))
	var right_y: float = _rubber_top_avg_normal_y(_bat_mesh(right))
	assert_gt(left_y, 0.0, "the LEFT bat's rubber top must face +Y (sanity). avg_ny=%f" % left_y)
	assert_gt(
		right_y, 0.0,
		"the RIGHT bat's rubber top must face +Y (not be culled facing down). avg_ny=%f" % right_y
	)
