class_name EditRail
extends Node3D
## A RAIL the developer can draw and reshape in the layout editor: a wall or guide defined by a list
## of POINTS. Each point gets a draggable handle (a small sphere); dragging a handle and rebuilding
## redraws the rail through the new points. A "guide" is drawn as a SMOOTH curve through its points
## (rounded, like a real inlane/return guide); a "wall" is drawn as STRAIGHT segments between points.
##
## The rail node sits at the playfield origin, so its handle positions ARE playfield-local grid
## coordinates - the same space the editor's mouse-to-grid raycast returns, so dragging maps 1:1.
##
## The actual wall geometry is built with TableGeometry's shared helpers (_smooth_curve /
## _add_border_segment) so an editor-drawn rail looks and collides exactly like a code-built one.

const HANDLE_RADIUS: float = 0.55

var smooth: bool = true       ## true = guide (curved), false = wall (straight)
var kind: String = "guide"    ## "guide" or "wall" - serialised so a saved layout round-trips

var _seg_root: Node3D = null         ## parent for the rebuilt wall segments (cleared on each rebuild)
var _handles: Array[MeshInstance3D] = []
var _handle_mat: StandardMaterial3D = null
var _handles_visible: bool = false   ## handles only show in edit mode (set via set_handles_visible)


## Set up the rail from a list of playfield-local points. smooth_flag picks curve vs straight.
func configure(points: Array, smooth_flag: bool, kind_str: String) -> void:
	smooth = smooth_flag
	kind = kind_str
	_seg_root = Node3D.new()
	_seg_root.name = "Segments"
	add_child(_seg_root)
	_handle_mat = StandardMaterial3D.new()
	_handle_mat.albedo_color = Color(0.1, 0.9, 1.0)  ## bright cyan grab handles
	for p: Variant in points:
		_add_handle(_to_local3(p))
	rebuild()


## Append one point (and its handle) to the end of the rail, then redraw.
func add_point(local_pos: Vector3) -> void:
	_add_handle(Vector3(local_pos.x, 0.0, local_pos.z))
	rebuild()


## Accept a point as either a Vector2 (x, z) - how default/saved layouts store them - or a Vector3.
func _to_local3(p: Variant) -> Vector3:
	if p is Vector2:
		return Vector3(p.x, 0.0, p.y)
	return Vector3(p.x, 0.0, p.z)


func _add_handle(local_pos: Vector3) -> void:
	var h := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = HANDLE_RADIUS
	m.height = HANDLE_RADIUS * 2.0
	h.mesh = m
	h.material_override = _handle_mat
	h.position = local_pos
	h.visible = _handles_visible
	h.set_meta("etype", "rail_handle")
	h.set_meta("rail", self)
	add_child(h)
	_handles.append(h)


## The current points, read back from the handles (y flattened to the surface).
func points() -> Array[Vector3]:
	var arr: Array[Vector3] = []
	for h: MeshInstance3D in _handles:
		if is_instance_valid(h):
			arr.append(Vector3(h.position.x, 0.0, h.position.z))
	return arr


## Every draggable handle, so the editor can register them as selectable elements.
func handles() -> Array:
	var arr: Array = []
	for h: MeshInstance3D in _handles:
		if is_instance_valid(h):
			arr.append(h)
	return arr


func set_handles_visible(v: bool) -> void:
	_handles_visible = v  ## so handles added later (while drawing) inherit the current visibility
	for h: MeshInstance3D in _handles:
		if is_instance_valid(h):
			h.visible = v


## Redraw the wall segments from the current handle positions. Smooth = curved guide; else straight.
func rebuild() -> void:
	if _seg_root == null:
		return
	for c: Node in _seg_root.get_children():
		c.queue_free()
	var pts: Array[Vector3] = points()
	if pts.size() < 2:
		return
	var path: Array[Vector3] = pts
	if smooth and pts.size() >= 3:
		path = TableGeometry._smooth_curve(pts, 6)
	for i: int in range(path.size() - 1):
		TableGeometry._add_border_segment(_seg_root, path[i], path[i + 1], "Seg%d" % i)
