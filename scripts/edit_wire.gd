class_name EditWire
extends Node3D
## A WIRE RAMP the developer draws and sculpts in the editor: a 3D path (points have HEIGHT, not just
## x/z) that the ball travels ON. It rises from the playfield up and over, like a real pinball
## wireform. Two parts, decoupled so the physics is reliable regardless of the look:
##   - VISUAL: chrome tube(s) swept along the path (1, 2, or 4 strands), matching the developer's
##     Blender wire ("Metal - Chromium", 1/8" diameter, 8-sided, 1/10" strand spacing).
##   - COLLISION: a smooth floor ribbon with low side rails that follows the same path - the trough
##     the ball rides in. This carries + contains the ball; the thin wires never have to.
##
## Each path point is a draggable HANDLE: dragged on the x/z plane like a rail point, and raised or
## lowered in HEIGHT with + / - (sculpting the part under the cursor). The mesh + collision rebuild
## live from the handle positions.

## Wire model, converted from the Blender geometry-nodes wire to world units (real_to_world ~= 44.4).
## Diameter 1/8" (0.003175 m), strand spacing 1/10" (0.00254 m), 8-sided tube.
const WIRE_SIDES: int = 8
const SAMPLES_PER_SEG: int = 8        ## path samples between control points (smoothness of the sweep)

var strands: int = 2                  ## 1, 2, or 4 chrome wires (2 = the ball-track default)
var _wire_radius: float = 0.071       ## 1/8" in world units (0.003175 m * real_to_world)
var _gauge: float = 1.2               ## wire spacing, MATCHED to the ball (see configure)

var _seg_root: Node3D = null          ## holds the rebuilt visual + collision (cleared each rebuild)
var _handles: Array[MeshInstance3D] = []
var _handle_mat: StandardMaterial3D = null
var _chrome: StandardMaterial3D = null
var _handles_visible: bool = false


## Set up from a list of 3D points (Vector3, playfield-local; y is the height above the surface).
func configure(points: Array, strand_count: int) -> void:
	strands = strand_count
	_wire_radius = 0.003175 * 0.5 * TableConfig.real_to_world()  ## 1/8" wire, to world units
	# GAUGE matched to the ball: the two rails sit ~one ball-DIAMETER apart, so the ball nestles
	# between them and the inner gap (gauge - 2*wire_radius) stays narrower than the ball - it cradles
	# and rides the rails instead of dropping through or balancing on top.
	_gauge = 2.0 * TableConfig.BALL_RADIUS
	_seg_root = Node3D.new()
	_seg_root.name = "WireRamp"
	add_child(_seg_root)
	_handle_mat = StandardMaterial3D.new()
	_handle_mat.albedo_color = Color(0.1, 0.9, 1.0)  ## cyan grab handles (same as rails)
	_chrome = StandardMaterial3D.new()
	_chrome.albedo_color = Color(0.85, 0.87, 0.9)
	_chrome.metallic = 1.0
	_chrome.roughness = 0.12
	for p: Variant in points:
		_add_handle(_to_v3(p))
	rebuild()


func add_point(local_pos: Vector3) -> void:
	_add_handle(local_pos)
	rebuild()


## Raise/lower the height (local y) of one handle, then rebuild the ramp.
func set_handle_height(handle: Node3D, delta: float) -> void:
	if handle == null or not _handles.has(handle):
		return
	handle.position.y = maxf(handle.position.y + delta, -2.0)
	rebuild()


func points() -> Array[Vector3]:
	var arr: Array[Vector3] = []
	for h: MeshInstance3D in _handles:
		if is_instance_valid(h):
			arr.append(h.position)  ## full 3D - height is meaningful for a ramp
	return arr


func handles() -> Array:
	var arr: Array = []
	for h: MeshInstance3D in _handles:
		if is_instance_valid(h):
			arr.append(h)
	return arr


func set_handles_visible(v: bool) -> void:
	_handles_visible = v
	for h: MeshInstance3D in _handles:
		if is_instance_valid(h):
			h.visible = v


func _add_handle(local_pos: Vector3) -> void:
	var h := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.55
	m.height = 1.1
	h.mesh = m
	h.material_override = _handle_mat
	h.position = local_pos
	h.visible = _handles_visible
	h.set_meta("etype", "wire_handle")
	h.set_meta("wire", self)
	add_child(h)
	_handles.append(h)


## Rebuild the swept chrome tube(s) + the carrying trough collision from the current handle positions.
func rebuild() -> void:
	if _seg_root == null:
		return
	for c: Node in _seg_root.get_children():
		c.queue_free()
	var ctrl: Array[Vector3] = points()
	if ctrl.size() < 2:
		return
	var path: Array[Vector3] = TableGeometry._smooth_curve(ctrl, SAMPLES_PER_SEG)
	if path.size() < 2:
		return
	var frames: Array = _path_frames(path)  ## [tangent, normal, binormal] per sample
	_build_wires(path, frames)
	_build_collision(path, frames)


## A stable frame (tangent, normal, binormal) at each path sample, using world-up as the reference so
## the trough's "up" stays sane on a gentle ramp.
func _path_frames(path: Array[Vector3]) -> Array:
	var frames: Array = []
	var up := Vector3.UP
	for i: int in range(path.size()):
		var tan: Vector3
		if i < path.size() - 1:
			tan = path[i + 1] - path[i]
		else:
			tan = path[i] - path[i - 1]
		if tan.length() < 0.0001:
			tan = Vector3.FORWARD
		tan = tan.normalized()
		var bin: Vector3 = tan.cross(up)
		if bin.length() < 0.001:
			bin = tan.cross(Vector3.RIGHT)
		bin = bin.normalized()
		var nrm: Vector3 = bin.cross(tan).normalized()
		frames.append([tan, nrm, bin])
	return frames


## The sideways offsets of each strand from the path centerline, set by the ball-matched gauge so the
## two rails sit a ball-diameter apart (the ball rides between them).
func _strand_offsets() -> Array[float]:
	if strands == 2:
		return [-_gauge * 0.5, _gauge * 0.5]
	if strands == 4:
		return [-_gauge * 0.75, -_gauge * 0.25, _gauge * 0.25, _gauge * 0.75]
	return [0.0]


## Sweep the chrome tube(s) along the path - one MeshInstance per strand.
func _build_wires(path: Array[Vector3], frames: Array) -> void:
	for off: float in _strand_offsets():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_tube(st, path, frames, off)
		st.generate_normals()
		var mesh := ArrayMesh.new()
		st.commit(mesh)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _chrome
		_seg_root.add_child(mi)


## COLLISION = the rails themselves. The ball rides ON the wires (gauge matched to the ball), so the
## collider is the SAME swept tubes, as one static trimesh body. With the ball's continuous_cd this is
## tunnel-safe; the gauge keeps the inner gap narrower than the ball so it cannot drop through.
func _build_collision(path: Array[Vector3], frames: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for off: float in _strand_offsets():
		_add_tube(st, path, frames, off)
	st.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.STATIC_OBSTACLES
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	_seg_root.add_child(body)


## Append one tube (a ring of WIRE_SIDES verts per sample, offset sideways by `lateral`) to a surface.
func _add_tube(st: SurfaceTool, path: Array[Vector3], frames: Array, lateral: float) -> void:
	for i: int in range(path.size() - 1):
		var c0: Vector3 = path[i] + frames[i][2] * lateral
		var c1: Vector3 = path[i + 1] + frames[i + 1][2] * lateral
		for k: int in range(WIRE_SIDES):
			var a0: float = TAU * float(k) / float(WIRE_SIDES)
			var a1: float = TAU * float(k + 1) / float(WIRE_SIDES)
			var v00: Vector3 = c0 + _ring_pt(frames[i], a0)
			var v01: Vector3 = c0 + _ring_pt(frames[i], a1)
			var v10: Vector3 = c1 + _ring_pt(frames[i + 1], a0)
			var v11: Vector3 = c1 + _ring_pt(frames[i + 1], a1)
			st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v01)
			st.add_vertex(v01); st.add_vertex(v10); st.add_vertex(v11)


## A point on the tube ring at angle a, in the sample's frame [tan, normal, binormal].
func _ring_pt(frame: Array, a: float) -> Vector3:
	return (frame[1] * cos(a) + frame[2] * sin(a)) * _wire_radius


func _to_v3(p: Variant) -> Vector3:
	if p is Vector3:
		return p
	if p is Vector2:
		return Vector3(p.x, 0.0, p.y)
	return Vector3(p.x, 0.0, p.z)
