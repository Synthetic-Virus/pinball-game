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

## Collision trough proportions (world units): wide enough to cradle the ball (radius 0.6), with low
## side rails so it cannot roll off on a curve.
const TROUGH_HALF_WIDTH: float = 0.7
const RAIL_HEIGHT: float = 0.55

var strands: int = 1                  ## 1, 2, or 4 chrome wires
var _wire_radius: float = 0.071       ## 1/8" in world units (0.003175 m * real_to_world)
var _spacing: float = 0.113           ## 1/10" in world units (strand offset, used for 2/4 wires)

var _seg_root: Node3D = null          ## holds the rebuilt visual + collision (cleared each rebuild)
var _handles: Array[MeshInstance3D] = []
var _handle_mat: StandardMaterial3D = null
var _chrome: StandardMaterial3D = null
var _handles_visible: bool = false


## Set up from a list of 3D points (Vector3, playfield-local; y is the height above the surface).
func configure(points: Array, strand_count: int) -> void:
	strands = strand_count
	_wire_radius = 0.003175 * 0.5 * TableConfig.real_to_world()
	_spacing = 0.00254 * TableConfig.real_to_world()
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


## Sweep the chrome tube(s) along the path. Multiple strands are offset sideways along the binormal.
func _build_wires(path: Array[Vector3], frames: Array) -> void:
	var offsets: Array[float] = [0.0]
	if strands == 2:
		offsets = [-_spacing * 0.5, _spacing * 0.5]
	elif strands == 4:
		offsets = [-_spacing * 1.5, -_spacing * 0.5, _spacing * 0.5, _spacing * 1.5]
	for off: float in offsets:
		var mesh := _sweep_tube(path, frames, off)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _chrome
		_seg_root.add_child(mi)


## Build one tube mesh: a ring of WIRE_SIDES verts at each sample (offset sideways by `lateral`),
## connected sample-to-sample into a tube.
func _sweep_tube(path: Array[Vector3], frames: Array, lateral: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = path.size()
	for i: int in range(n - 1):
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
	st.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


## A point on the tube ring at angle a, in the sample's frame [tan, normal, binormal].
func _ring_pt(frame: Array, a: float) -> Vector3:
	return (frame[1] * cos(a) + frame[2] * sin(a)) * _wire_radius


## Carrying COLLISION: a floor ribbon at the path height plus two low side rails, following the path,
## as one static body the ball rides in. Decoupled from the thin visual wires so the ball is held
## reliably. The ball's continuous_cd plus this static trough keep it from tunnelling at speed.
func _build_collision(path: Array[Vector3], frames: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = path.size()
	for i: int in range(n - 1):
		_trough_quads(st, path[i], frames[i], path[i + 1], frames[i + 1])
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


## One segment of the trough: a floor quad (cradle bottom) and two side-rail quads.
func _trough_quads(st: SurfaceTool, p0: Vector3, f0: Array, p1: Vector3, f1: Array) -> void:
	var b0: Vector3 = f0[2]
	var b1: Vector3 = f1[2]
	var up0: Vector3 = f0[1]
	var up1: Vector3 = f1[1]
	# Floor edges (left/right of the path).
	var fl0: Vector3 = p0 - b0 * TROUGH_HALF_WIDTH
	var fr0: Vector3 = p0 + b0 * TROUGH_HALF_WIDTH
	var fl1: Vector3 = p1 - b1 * TROUGH_HALF_WIDTH
	var fr1: Vector3 = p1 + b1 * TROUGH_HALF_WIDTH
	_quad(st, fl0, fr0, fl1, fr1)
	# Left + right side rails rising from the floor edges.
	var tl0: Vector3 = fl0 + up0 * RAIL_HEIGHT
	var tl1: Vector3 = fl1 + up1 * RAIL_HEIGHT
	var tr0: Vector3 = fr0 + up0 * RAIL_HEIGHT
	var tr1: Vector3 = fr1 + up1 * RAIL_HEIGHT
	_quad(st, tl0, fl0, tl1, fl1)
	_quad(st, fr0, tr0, fr1, tr1)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.add_vertex(b); st.add_vertex(c); st.add_vertex(d)


func _to_v3(p: Variant) -> Vector3:
	if p is Vector3:
		return p
	if p is Vector2:
		return Vector3(p.x, 0.0, p.y)
	return Vector3(p.x, 0.0, p.z)
