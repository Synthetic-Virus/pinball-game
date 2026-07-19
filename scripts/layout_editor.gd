class_name LayoutEditor
extends Node
## IN-GAME LAYOUT EDITOR. Lets the developer place / move / rotate / delete table furniture directly
## in the running browser demo, then SAVE the layout. This replaces the "describe it and I rebuild it"
## loop that kept misreading hand-drawn markups: the developer now builds the table themselves and
## sees it live.
##
## CONTROLS (only while edit mode is ON):
##   - click an element            -> select it (it lifts slightly so you can see the selection)
##   - drag                        -> move the selected element on the grid
##   - mouse wheel                 -> rotate the selected element
##   - Delete / Backspace          -> remove the selected element
##   - palette buttons             -> add a new bumper / target / slingshot at the centre
##   - SAVE                        -> store the layout in the browser AND download pinball_layout.json
##   - RESET                       -> wipe the saved layout (next reload shows the built-in default)
##
## Edit mode is OFF by default so the game plays normally; toggle it with the EDIT button or the E key.
## PERSISTENCE is browser-only (localStorage + a file download via JavaScriptBridge); in headless test
## runs there is no browser, so the editor is completely inert and the built-in layout is used.

const LAYOUT_KEY: String = "pinball_layout"   ## browser localStorage key the layout is saved under
## The BAKED default layout (the developer's chosen table). Applied when there is no saved layout in
## localStorage, so it ships in the build and survives a "RESET saved" / cleared browser storage. To
## update it: build the table in the editor, SAVE, then paste the downloaded pinball_layout.json here.
## Headless tests never run the editor (browser-only), so they still use the table_config constants.
const DEFAULT_LAYOUT_JSON: String = """[{"rot_deg":0.0,"type":"bumper","x":-3.43,"z":-6.93},{"rot_deg":0.0,"type":"bumper","x":2.3,"z":-7.15},{"rot_deg":0.0,"type":"bumper","x":-0.17,"z":-1.32},{"rot_deg":0.0,"type":"target","x":-10.33,"z":-11.54},{"rot_deg":0.0,"type":"target","x":9.32,"z":-4.48},{"rot_deg":0.0,"type":"target","x":9.41,"z":-2.83},{"rot_deg":0.0,"type":"target","x":9.21,"z":-0.76},{"rot_deg":0.0,"type":"target","x":-8.93,"z":-12.49},{"rot_deg":45.0,"type":"sling_left","x":-5.07,"z":15.47},{"rot_deg":-45.0,"type":"sling_right","x":4.66,"z":15.27},{"rot_deg":7.5,"type":"sling_left","x":-10.7,"z":4.8},{"rot_deg":0.0,"type":"flipper_left","x":-4.5,"z":20.0},{"rot_deg":0.0,"type":"flipper_right","x":4.5,"z":20.0},{"kind":"guide","points":[[-10.52,11.87],[-9.82,18.57],[-4.97,19.7]],"smooth":true,"type":"rail"},{"kind":"guide","points":[[8.96,12.17],[8.62,18.27],[5.1,19.8]],"smooth":true,"type":"rail"},{"kind":"guide","points":[[10.12,-4.57],[9.77,-6.62],[7.38,-10.53]],"smooth":true,"type":"rail"},{"kind":"wall","points":[[-3.97,-17.36],[-4.0,-14.24]],"smooth":false,"type":"rail"},{"kind":"wall","points":[[-0.69,-17.04],[-0.67,-13.74]],"smooth":false,"type":"rail"},{"kind":"wall","points":[[2.66,-17.46],[2.71,-14.04]],"smooth":false,"type":"rail"},{"kind":"wall","points":[[10.62,-15.57],[7.25,-10.53]],"smooth":false,"type":"rail"},{"kind":"wall","points":[[9.97,-4.57],[10.11,-4.46],[10.12,-0.24],[9.25,1.81],[7.28,3.77],[10.93,8.4]],"smooth":false,"type":"rail"},{"kind":"guide","points":[[-12.46,-5.83],[-11.24,2.13],[-10.9,5.25],[-12.79,7.83]],"smooth":true,"type":"rail"},{"kind":"guide","points":[[-2.8,-24.85],[-6.79,-21.67],[-12.89,-16.92]],"smooth":true,"type":"rail"},{"kind":"wall","points":[[-9.5,0.35],[-12.07,2.54]],"smooth":false,"type":"rail"},{"kind":"guide","points":[[-7.83,-0.64],[-10.77,-6.39],[-11.23,-11.98],[-9.55,-16.55],[-3.71,-20.76]],"smooth":true,"type":"rail"},{"kind":"guide","points":[[-3.65,-20.9],[-6.11,-17.78],[-6.53,-14.69]],"smooth":true,"type":"rail"},{"points":[[-8.54,0.4,0.11],[-11.92,1.6,-7.03],[-11.17,2.0,-15.54],[-5.11,0.0,-21.77]],"strands":2,"type":"wire"}]"""
const SELECT_RADIUS: float = 1.6              ## a click within this many table units grabs an element
const ROTATE_STEP_DEG: float = 7.5            ## rotation applied per mouse-wheel tick
const ANGLE_SNAP_DEG: float = 15.0            ## with SHIFT held, rotation snaps to this increment
const SELECT_LIFT: float = 0.6                ## how far the selected element lifts (visual cue only)
const LONG_PRESS_MS: float = 350.0            ## a play touch held this long also fires launch (spacebar)
const HEIGHT_STEP: float = 0.4                ## how much + / - raise/lower a wire-ramp point per press
const UNDO_DEPTH: int = 40                    ## how many edit snapshots Undo can step back through

## Developer-supplied typefaces: CHLORINP for the title banner, Schwarzenberg-Italic for button text.
const TITLE_FONT_PATH: String = "res://assets/fonts/title.ttf"
const BUTTON_FONT_PATH: String = "res://assets/fonts/button.ttf"

var _table: Node = null
var _camera: Camera3D = null
var _playfield: Node3D = null

var _edit_mode: bool = false
var _selected: Node3D = null
var _selected_base_y: float = 0.0
var _dragging: bool = false

var _drawing: bool = false        ## true while laying down a new rail/wire point-by-point
var _draw_rail: Node3D = null     ## the rail being drawn
var _draw_wire: Node3D = null     ## the wire ramp being drawn (3D points)
var _hover_handle: Node3D = null  ## wire-ramp handle nearest the cursor (target for + / - height)

var _grabbing: bool = false       ## Blender-style GRAB: selected follows the cursor, no button held
var _grab_origin: Vector3 = Vector3.ZERO  ## where the grabbed element started (restored on cancel)
var _cam_panning: bool = false    ## middle-mouse held: dragging pans the build camera
var _collapsed: bool = false      ## build panel collapsed to just its header bar
var _panel_body: Control = null   ## the part of the build panel hidden when collapsed
var _sel_marker: MeshInstance3D = null  ## bright ring under the selected element (clear selection cue)
var _undo_stack: Array = []             ## snapshots of the layout taken BEFORE each edit (for Undo)
var _drag_undo_pushed: bool = false     ## one Undo snapshot per drag, taken on its first move

var _hud: CanvasLayer = null
var _menu: Control = null          ## the main menu (Build / Play), shown at boot
var _play_bar: Control = null      ## the small "Menu" button shown while playing
var _panel: PanelContainer = null  ## the BUILD-mode editor panel
var _header: Label = null
var _hud_dragging: bool = false
var _status: Label = null
var _object_dropdown: OptionButton = null  ## the placeable-object picker (replaces the button list)
var _mirror_check: CheckBox = null         ## when ticked, a placed object gets a linked L/R mirror
var _snap_to_grid: bool = false            ## when on, dragging snaps element position to the grid step
var _grid_visible: bool = true             ## coord-grid show/hide state, toggled from the panel

## Every object the dropdown can place: furniture + the imported parts. kind "furniture" routes to
## editor_spawn, "asset" routes to editor_spawn_asset. Built in _build_hud from TableConfig.
var _placeables: Array = []

var _playing: bool = false          ## true in PLAY mode (touch flipper controls are live)
var _touches: Dictionary = {}       ## active screen touches: index -> {"action": String, "start": ms}
var _launch_held: bool = false      ## whether a long-press is currently holding the launch action


## Wire the editor to the live table. table.gd calls this once the furniture exists.
func setup(table: Node, camera: Camera3D, playfield: Node3D) -> void:
	_table = table
	_camera = camera
	_playfield = playfield
	_build_hud()
	_build_sel_marker()
	_load_saved()
	set_process_unhandled_input(true)
	set_process(true)  ## drives the long-press launch timer during play
	# The editor (and its menu) must keep running while the game is PAUSED so the pause menu responds.
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- Input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# PLAY mode: touch the LEFT half for the left flipper, the RIGHT half for the right; a long press
	# also fires "launch" (the spacebar). Only screen touches drive this, so on-screen buttons (which
	# get the touch first via mouse emulation) stay tappable; the editor never sees these.
	if _playing and event is InputEventScreenTouch:
		_handle_play_touch(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and _handle_edit_key(event):
		return
	if not _edit_mode:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _cam_panning:
		# Middle-drag pans the BUILD view (grab the world and slide it under the cursor).
		if _table != null and _table.has_method("camera_pan"):
			_table.camera_pan(Vector3(-event.relative.x * 0.05, 0.0, -event.relative.y * 0.05))
	elif event is InputEventMouseMotion and (_dragging or _grabbing) and _selected != null:
		var hit: Variant = _ray_to_field(event.position)
		if hit != null:
			if _dragging and not _grabbing and not _drag_undo_pushed:
				_push_undo()  ## one snapshot per drag, on the first move
				_drag_undo_pushed = true
			_apply_move(_selected, hit.x, hit.z)
	elif event is InputEventMouseMotion:
		_update_hover(event.position)  ## track the wire-ramp point under the cursor for + / - height


## Handle an edit-mode keyboard shortcut. Returns true if the key was consumed. Pulled out of
## _unhandled_input to keep that function's branching small.
func _handle_edit_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_E:
		# Quick toggle between BUILD and PLAY (skips the menu).
		if _edit_mode:
			_enter_play()
		else:
			_enter_build()
		return true
	if not _edit_mode:
		return false
	# Edit-mode shortcuts. GRAB (G): pick up the selection so it follows the cursor; Escape cancels.
	if event.keycode == KEY_Z and event.ctrl_pressed:
		_undo()
	elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		_delete_selected()
	elif event.keycode == KEY_G and _selected != null and not _drawing:
		_toggle_grab()
	elif event.keycode == KEY_ESCAPE and _grabbing:
		_cancel_grab()
	elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
		_adjust_height(HEIGHT_STEP)   ## raise the wire-ramp point under the cursor
	elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
		_adjust_height(-HEIGHT_STEP)  ## lower it
	else:
		return false
	return true


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# While GRABBING: a left-click drops the element here, a right-click cancels back to the start.
	if _grabbing and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_grabbing = false
			_refresh_status()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_grab()
			return
	# Middle button held = pan the camera (handled in the motion branch).
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_cam_panning = event.pressed
		return
	# Right-click on empty space (or anywhere) clears the selection.
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not _drawing:
		_select(null)
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# While drawing a rail/wire, each click DROPS A POINT instead of selecting/dragging.
			if _drawing:
				var hit: Variant = _ray_to_field(event.position)
				if hit != null:
					if _draw_wire != null:
						_draw_wire.add_point(Vector3(hit.x, 0.0, hit.z))
					elif _draw_rail != null:
						_draw_rail.add_point(Vector3(hit.x, 0.0, hit.z))
				return
			_select(_pick(event.position))
			_dragging = _selected != null
			_drag_undo_pushed = false  ## the drag's Undo snapshot is taken on its first move
		else:
			_dragging = false
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if _selected != null:
			_push_undo()
			_rotate_selected(1, event.shift_pressed)  ## SHIFT = snap to 15-degree increments
		elif _table != null and _table.has_method("camera_zoom"):
			_table.camera_zoom(1.1)  ## nothing selected: zoom the camera IN (capped in the table)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _selected != null:
			_push_undo()
			_rotate_selected(-1, event.shift_pressed)
		elif _table != null and _table.has_method("camera_zoom"):
			_table.camera_zoom(1.0 / 1.1)  ## zoom OUT


# --- Picking / selection -------------------------------------------------------------------------

## Cast the mouse ray onto the (tilted) playfield plane and return the hit in PLAYFIELD-LOCAL space
## (so x and z read straight off the table grid). Returns null if the ray misses the plane.
func _ray_to_field(screen_pos: Vector2) -> Variant:
	if _camera == null or _playfield == null:
		return null
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	var normal: Vector3 = _playfield.global_transform.basis.y.normalized()
	var plane := Plane(normal, _playfield.global_position.dot(normal))
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return null
	return _playfield.to_local(hit)


## Find the editable element nearest the click (within SELECT_RADIUS) on the grid. Null if none.
func _pick(screen_pos: Vector2) -> Node3D:
	var local: Variant = _ray_to_field(screen_pos)
	if local == null:
		return null
	var click := Vector2(local.x, local.z)
	var best: Node3D = null
	var best_dist: float = INF
	for node: Node3D in _editables():
		var here := Vector2(node.position.x, node.position.z)
		var d: float = click.distance_to(here)
		# Per-element pick radius: most furniture uses SELECT_RADIUS, but a flipper sits at its pivot
		# while the bat reaches a full length away, so it reports a larger radius (editor_pick_radius).
		var r: float = SELECT_RADIUS
		if node.has_method("editor_pick_radius"):
			r = node.editor_pick_radius()
		if d <= r and d < best_dist:
			best_dist = d
			best = node
	return best


func _select(node: Node3D) -> void:
	if _selected == node:
		return
	_grabbing = false  ## changing selection ends any in-progress grab
	if _selected != null:
		_selected.position.y = _selected_base_y   ## drop the previous selection back down
	_selected = node
	if _selected != null:
		_selected_base_y = _selected.position.y
		# Furniture lifts a little as a selection cue; rail/wire HANDLES do not - their y is the path
		# height, so lifting them would distort the curve. The marker ring is their cue instead.
		if not _is_handle(_selected):
			_selected.position.y = _selected_base_y + SELECT_LIFT
	_update_sel_marker()
	_refresh_status()


## A bright ring on the surface, parented to the (tilted) playfield, that marks the selected element.
func _build_sel_marker() -> void:
	if _playfield == null:
		return
	_sel_marker = MeshInstance3D.new()
	_sel_marker.name = "SelectionMarker"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.2
	ring.outer_radius = 1.7
	_sel_marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 2.0
	mat.no_depth_test = true  ## draw on top so the ring is always visible around the element
	_sel_marker.material_override = mat
	_sel_marker.visible = false
	_playfield.add_child(_sel_marker)


## Move the selection ring under the selected element (or hide it when nothing is selected).
func _update_sel_marker() -> void:
	if _sel_marker == null:
		return
	if _selected == null:
		_sel_marker.visible = false
		return
	_sel_marker.visible = true
	_sel_marker.position = Vector3(_selected.position.x, 0.12, _selected.position.z)


## Move a selected node to a new (x, z), handling the cases the editor cares about: flippers need a
## physics teleport (editor_move), rails rebuild from their handle, and a mirror twin follows.
func _apply_move(node: Node3D, x: float, z: float) -> void:
	# Snap-to-grid: round the drop to the visible grid step when the toggle is on.
	if _snap_to_grid and _table != null and _table.has_method("grid_step"):
		var step: float = _table.grid_step()
		if step > 0.0:
			x = snappedf(x, step)
			z = snappedf(z, step)
	if node.has_method("editor_move"):
		node.editor_move(Vector3(x, node.position.y, z))
	else:
		node.position.x = x
		node.position.z = z
	if node.has_meta("rail"):
		var rail: Node = node.get_meta("rail")
		if is_instance_valid(rail):
			rail.rebuild()
	if node.has_meta("wire"):
		var wire: Node = node.get_meta("wire")
		if is_instance_valid(wire):
			wire.rebuild()  ## the wire ramp follows its dragged point
	_update_twin(node)
	_update_sel_marker()


func _delete_selected() -> void:
	if _selected == null:
		return
	_push_undo()
	var doomed: Node3D = _selected
	_selected = null
	_dragging = false
	_update_sel_marker()
	# A mirror pair is removed together.
	if doomed.has_meta("twin"):
		var twin: Node = doomed.get_meta("twin")
		if is_instance_valid(twin) and _table.has_method("editor_remove"):
			_table.editor_remove(twin)
	if _table.has_method("editor_remove"):
		_table.editor_remove(doomed)
	_refresh_status()


## GRAB (Blender's G): toggle the selected element following the cursor. Starting a grab remembers the
## origin so a cancel can restore it; toggling again (or left-click) confirms the new spot.
func _toggle_grab() -> void:
	if _selected == null:
		return
	if _grabbing:
		_grabbing = false
	else:
		_push_undo()  ## snapshot before the grab move so Undo reverts it
		_grab_origin = _selected.position
		_grabbing = true
	_refresh_status()


## Cancel a grab: snap the element back to where it started and stop following the cursor.
func _cancel_grab() -> void:
	if _selected != null:
		_apply_move(_selected, _grab_origin.x, _grab_origin.z)
	_grabbing = false
	_refresh_status()


## Keep a node's mirror twin in sync: mirrored across the table centre (x negated) with the opposite
## yaw, so dragging/rotating one side builds both sides symmetrically.
func _update_twin(node: Node3D) -> void:
	if node == null or not node.has_meta("twin"):
		return
	var twin: Node3D = node.get_meta("twin")
	if not is_instance_valid(twin):
		return
	twin.position = Vector3(-node.position.x, node.position.y, node.position.z)
	twin.rotation.y = -node.rotation.y
	if twin.has_meta("rail"):
		var rail: Node = twin.get_meta("rail")
		if is_instance_valid(rail):
			rail.rebuild()


## Rotate the selection one wheel tick. Normal = ROTATE_STEP_DEG; with SHIFT, snap the result to the
## nearest ANGLE_SNAP_DEG (15-degree) increment for clean alignment. The mirror twin follows.
func _rotate_selected(dir: int, shift: bool) -> void:
	if _selected == null:
		return
	if shift:
		var cur_deg: float = rad_to_deg(_selected.rotation.y)
		_selected.rotation.y = deg_to_rad(snappedf(cur_deg + float(dir) * ANGLE_SNAP_DEG, ANGLE_SNAP_DEG))
	else:
		_selected.rotation.y += float(dir) * deg_to_rad(ROTATE_STEP_DEG)
	_update_twin(_selected)


## Toggle the coord grid on/off (the table owns the grid node).
func _toggle_grid() -> void:
	_grid_visible = not _grid_visible
	if _table != null and _table.has_method("set_grid_visible"):
		_table.set_grid_visible(_grid_visible)
	_flash("Grid %s" % ("ON" if _grid_visible else "OFF"))


## Toggle snap-to-grid for dragging. When on, _apply_move rounds the drop to the visible grid step.
func _toggle_snap() -> void:
	_snap_to_grid = not _snap_to_grid
	_flash("Snap to grid %s" % ("ON" if _snap_to_grid else "OFF"))


func _editables() -> Array:
	if _table != null and _table.has_method("editor_editables"):
		return _table.editor_editables()
	return []


## A rail or wire point-handle (its y is meaningful path height), not a furniture piece.
func _is_handle(node: Node3D) -> bool:
	if node == null or not node.has_meta("etype"):
		return false
	return String(node.get_meta("etype")).ends_with("_handle")


## Track the WIRE-RAMP point nearest the cursor, so + / - raise/lower whatever part is under the mouse.
func _update_hover(screen_pos: Vector2) -> void:
	var local: Variant = _ray_to_field(screen_pos)
	if local == null:
		return
	var click := Vector2(local.x, local.z)
	var best: Node3D = null
	var best_dist: float = 3.0
	for node: Node3D in _editables():
		if not node.has_meta("etype") or String(node.get_meta("etype")) != "wire_handle":
			continue
		var d: float = click.distance_to(Vector2(node.position.x, node.position.z))
		if d < best_dist:
			best_dist = d
			best = node
	_hover_handle = best


## Raise (+) or lower (-) a wire-ramp point's height. Prefers the SELECTED point so the panel BUTTONS
## act on the point you clicked - the cursor is over the button when you press it, not over a ramp
## point, so a cursor-hover target raised the wrong point (developer: it raised the 3rd placed point).
## Falls back to the point under the cursor, which is what the = / - keys use while hovering.
func _adjust_height(delta: float) -> void:
	var handle: Node3D = null
	if _selected != null and is_instance_valid(_selected) and _selected.has_meta("wire"):
		handle = _selected
	elif _hover_handle != null and is_instance_valid(_hover_handle) and _hover_handle.has_meta("wire"):
		handle = _hover_handle
	if handle == null:
		_flash("select a wire-ramp point, then Raise/Lower")
		return
	var wire: Node = handle.get_meta("wire")
	if is_instance_valid(wire):
		_push_undo()
		wire.set_handle_height(handle, delta)


# --- Touch controls (PLAY mode only) -------------------------------------------------------------

## A screen touch in play: LEFT half presses left_flipper, RIGHT half presses right_flipper. The
## per-touch start time feeds the long-press launch in _process. Releasing lifts that flipper.
func _handle_play_touch(event: InputEventScreenTouch) -> void:
	if get_tree().paused:
		return
	if event.pressed:
		var half: float = get_viewport().get_visible_rect().size.x * 0.5
		var action: String = "left_flipper" if event.position.x < half else "right_flipper"
		_touches[event.index] = {"action": action, "start": float(Time.get_ticks_msec())}
		Input.action_press(action)
	elif _touches.has(event.index):
		Input.action_release(_touches[event.index]["action"])
		_touches.erase(event.index)
		_update_launch()


func _process(_delta: float) -> void:
	if _playing and not get_tree().paused:
		_update_launch()


## Hold "launch" (the spacebar) while ANY active touch has been held past LONG_PRESS_MS; release it
## once none are. So a quick tap is just a flipper flick, a long press also charges/fires the plunger.
func _update_launch() -> void:
	var now: float = float(Time.get_ticks_msec())
	var any_long: bool = false
	for idx: int in _touches:
		if now - float(_touches[idx]["start"]) >= LONG_PRESS_MS:
			any_long = true
			break
	if any_long and not _launch_held:
		Input.action_press("launch")
		_launch_held = true
	elif not any_long and _launch_held:
		Input.action_release("launch")
		_launch_held = false


## Lift every held touch action (and launch). Called when leaving PLAY so nothing sticks down.
func _release_all_touches() -> void:
	for idx: int in _touches:
		Input.action_release(_touches[idx]["action"])
	_touches.clear()
	if _launch_held:
		Input.action_release("launch")
		_launch_held = false


# --- Palette / adding ----------------------------------------------------------------------------

## Place the object currently chosen in the dropdown, at the centre of the play area, then select it
## to drag. If the Mirror box is ticked, a linked twin is placed on the other side so dragging one
## builds both. Drop a touch off-centre (x = 2) so the primary and its mirror do not overlap.
func _place_from_dropdown() -> void:
	if _object_dropdown == null or _object_dropdown.selected < 0:
		return
	var idx: int = _object_dropdown.get_item_id(_object_dropdown.selected)
	if idx < 0 or idx >= _placeables.size():
		return
	var spec: Dictionary = _placeables[idx]
	_push_undo()  ## snapshot before placing so Undo removes it
	var mirror: bool = _mirror_check != null and _mirror_check.button_pressed
	var x0: float = 2.0 if mirror else 0.0
	var primary: Node3D = _spawn_placeable(spec, Vector3(x0, 0.0, -3.0))
	if primary == null:
		return
	if mirror:
		var twin: Node3D = _spawn_placeable(spec, Vector3(-x0, 0.0, -3.0))
		if twin != null:
			primary.set_meta("twin", twin)
			twin.set_meta("twin", primary)
	_select(primary)


## Spawn one placeable (furniture or imported part) at a playfield-local position. Returns the node.
func _spawn_placeable(spec: Dictionary, pos: Vector3) -> Node3D:
	if _table == null:
		return null
	if spec.get("kind", "") == "asset":
		if _table.has_method("editor_spawn_asset"):
			return _table.editor_spawn_asset(String(spec["id"]), pos, 0.0)
		return null
	if _table.has_method("editor_spawn"):
		return _table.editor_spawn(String(spec["id"]), pos, 0.0)
	return null


# --- Persistence (browser only) ------------------------------------------------------------------

## Serialise the layout: point furniture + flippers as {type, x, z, rot_deg}, and each rail as
## {type:"rail", kind, smooth, points:[[x,z],...]}. Rail point-handles are skipped (the rail carries
## the points). The result round-trips through _apply_layout.
func _serialize() -> Array:
	var out: Array = []
	for node: Node3D in _editables():
		if not node.has_meta("etype"):
			continue
		var et: String = String(node.get_meta("etype"))
		if et == "rail_handle" or et == "wire_handle":
			continue  ## the rail/wire carries its own points; the handles are not furniture
		out.append({
			"type": et,
			"x": snappedf(node.position.x, 0.01),
			"z": snappedf(node.position.z, 0.01),
			"rot_deg": snappedf(rad_to_deg(node.rotation.y), 0.1),
		})
	if _table != null and _table.has_method("editor_rails"):
		for rail: Node in _table.editor_rails():
			if not is_instance_valid(rail):
				continue
			var pts: Array = []
			for p: Vector3 in rail.points():
				pts.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
			out.append({"type": "rail", "kind": rail.kind, "smooth": rail.smooth, "points": pts})
	if _table != null and _table.has_method("editor_wires"):
		for wire: Node in _table.editor_wires():
			if not is_instance_valid(wire):
				continue
			var wpts: Array = []
			for p: Vector3 in wire.points():
				wpts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
			out.append({"type": "wire", "strands": wire.strands, "points": wpts})
	return out


func _save() -> void:
	if not OS.has_feature("web"):
		_flash("SAVE only works in the browser demo")
		return
	var payload: String = JSON.stringify(_serialize())
	# JSON.stringify(payload) turns the layout JSON into a safe, quoted JS string literal.
	var quoted: String = JSON.stringify(payload)
	JavaScriptBridge.eval("window.localStorage.setItem('%s', %s);" % [LAYOUT_KEY, quoted], true)
	# Also download a copy so the developer can hand the file back to be committed as the new default.
	var dl: String = (
		"(function(){var d=%s;var b=new Blob([d],{type:'application/json'});"
		+ "var u=URL.createObjectURL(b);var a=document.createElement('a');"
		+ "a.href=u;a.download='pinball_layout.json';document.body.appendChild(a);a.click();"
		+ "document.body.removeChild(a);URL.revokeObjectURL(u);})();"
	) % quoted
	JavaScriptBridge.eval(dl, true)
	_flash("Saved (%d elements) + downloaded" % _serialize().size())


func _reset_saved() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.localStorage.removeItem('%s');" % LAYOUT_KEY, true)
	_flash("Saved layout cleared - reload for the built-in default")


func _load_saved() -> void:
	if not OS.has_feature("web"):
		return
	var raw: Variant = JavaScriptBridge.eval(
		"window.localStorage.getItem('%s') || ''" % LAYOUT_KEY, true
	)
	if raw is String and raw != "":
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Array:
			_apply_layout(parsed)
			return
	# No saved layout in this browser: apply the BAKED default so the developer's chosen table ships
	# and reappears after a "RESET saved" / cleared storage.
	var baked: Variant = JSON.parse_string(DEFAULT_LAYOUT_JSON)
	if baked is Array:
		_apply_layout(baked)


## Replace the current furniture/rails with a saved layout: clear the editor-managed elements, then
## respawn each entry. Flippers are repositioned (the table keeps its fixed pair); rails are rebuilt
## from their points; everything else is a point element.
func _apply_layout(entries: Array) -> void:
	if _table == null or not _table.has_method("editor_clear"):
		return
	_table.editor_clear()
	for entry: Variant in entries:
		if not (entry is Dictionary) or not entry.has("type"):
			continue
		var etype: String = String(entry["type"])
		if etype == "rail":
			var pts: Array = []
			for p: Variant in entry.get("points", []):
				pts.append(Vector2(float(p[0]), float(p[1])))
			_table.editor_spawn_rail(String(entry.get("kind", "guide")), bool(entry.get("smooth", true)), pts)
		elif etype == "wire":
			var wpts: Array = []
			for p: Variant in entry.get("points", []):
				wpts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			_table.editor_spawn_wire(wpts, int(entry.get("strands", 1)))
		elif etype.begins_with("asset:"):
			var pos_a := Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
			_table.editor_spawn_asset(
				etype.substr(6), pos_a, deg_to_rad(float(entry.get("rot_deg", 0.0)))
			)
		elif etype == "flipper_left" or etype == "flipper_right":
			_table.editor_set_flipper(
				etype, Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
			)
		else:
			var pos := Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
			_table.editor_spawn(etype, pos, deg_to_rad(float(entry.get("rot_deg", 0.0))))


# --- Undo ----------------------------------------------------------------------------------------

## Snapshot the whole layout BEFORE a mutating edit, so Undo can step back to it. Call this at the
## start of each edit (place, delete, the start of a drag/grab, a draw, a rotate).
func _push_undo() -> void:
	_undo_stack.append(_serialize())
	if _undo_stack.size() > UNDO_DEPTH:
		_undo_stack.pop_front()


## Step back one edit: restore the most recent snapshot and rebuild the table from it.
func _undo() -> void:
	if _undo_stack.is_empty():
		_flash("nothing to undo")
		return
	var snap: Array = _undo_stack.pop_back()
	_select(null)
	_finish_draw()
	_apply_layout(snap)
	_flash("undid (%d left)" % _undo_stack.size())


# --- HUD -----------------------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "EditorHUD"
	_hud.layer = 50
	add_child(_hud)

	# The unified placeable list the dropdown offers: furniture first, then every imported part.
	_placeables = [
		{"id": "bumper", "label": "Bumper", "kind": "furniture"},
		{"id": "target", "label": "Target", "kind": "furniture"},
		{"id": "sling_left", "label": "Slingshot L", "kind": "furniture"},
		{"id": "sling_right", "label": "Slingshot R", "kind": "furniture"},
	]
	for spec: Dictionary in TableConfig.placeable_assets():
		_placeables.append({"id": spec["id"], "label": spec["label"], "kind": "asset"})

	_build_main_menu()
	_build_build_panel()
	_build_play_bar()
	_enter_menu()  ## boot to the main menu


## The MAIN MENU shown at boot: pick BUILD (the editor) or PLAY (straight to the table).
func _build_main_menu() -> void:
	_menu = ColorRect.new()
	_menu.color = Color(0.04, 0.05, 0.08, 0.92)
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_menu)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	var title := Label.new()
	title.text = "PINBALL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	_apply_font(title, TITLE_FONT_PATH)  ## the banner typeface (CHLORINP)
	col.add_child(title)
	var build_btn := Button.new()
	build_btn.text = "BUILD"
	build_btn.custom_minimum_size = Vector2(320.0, 72.0)
	build_btn.add_theme_font_size_override("font_size", 44)
	build_btn.pressed.connect(_on_build_button_pressed)
	_apply_font(build_btn, BUTTON_FONT_PATH)
	col.add_child(build_btn)
	var play_btn := Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(320.0, 72.0)
	play_btn.add_theme_font_size_override("font_size", 44)
	play_btn.pressed.connect(_on_play_button_pressed)
	_apply_font(play_btn, BUTTON_FONT_PATH)
	col.add_child(play_btn)


## The BUILD-mode editor panel (dropdown picker + mirror + place + draw tools + actions).
func _build_build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(10.0, 96.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.78)
	bg.content_margin_left = 8.0
	bg.content_margin_right = 8.0
	bg.content_margin_top = 6.0
	bg.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", bg)
	_hud.add_child(_panel)

	var column := VBoxContainer.new()
	_panel.add_child(column)

	# Drag handle: grab this strip to move the whole editor panel off the playfield.
	_header = Label.new()
	_header.text = "= = =  drag to move  = = ="
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.add_theme_font_size_override("font_size", 18)
	_header.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	_header.gui_input.connect(_on_header_input)
	column.add_child(_header)

	# Collapse toggle (stays visible) so the panel can shrink to just the header + this button.
	var collapse_btn := Button.new()
	collapse_btn.text = "collapse"
	collapse_btn.custom_minimum_size = Vector2(0.0, 40.0)
	collapse_btn.add_theme_font_size_override("font_size", 22)
	_apply_font(collapse_btn, BUTTON_FONT_PATH)
	collapse_btn.pressed.connect(_toggle_collapse)
	column.add_child(collapse_btn)

	# Everything below lives in the BODY, which is what collapsing hides.
	_panel_body = VBoxContainer.new()
	column.add_child(_panel_body)
	var body: VBoxContainer = _panel_body

	# WIDE layout, not a long vertical strip down the playfield (developer: "make it wide not long, it
	# blocks too much of the play field"). A short header, the picker, then every tool button in a
	# 2-column grid: roughly half the height, twice the width.
	var cam_hint := Label.new()
	cam_hint.text = "view: middle-drag pan, wheel zoom"
	cam_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cam_hint.custom_minimum_size = Vector2(230.0, 0.0)
	cam_hint.add_theme_font_size_override("font_size", 18)
	cam_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	body.add_child(cam_hint)

	# Object picker: dropdown (full width) with the mirror toggle + PLACE sharing the row below it.
	_object_dropdown = OptionButton.new()
	_object_dropdown.custom_minimum_size = Vector2(460.0, 48.0)
	_object_dropdown.add_theme_font_size_override("font_size", 28)
	for i: int in range(_placeables.size()):
		_object_dropdown.add_item(String(_placeables[i]["label"]), i)
	_apply_font(_object_dropdown, BUTTON_FONT_PATH)
	body.add_child(_object_dropdown)
	var pick_row := HBoxContainer.new()
	body.add_child(pick_row)
	_mirror_check = CheckBox.new()
	_mirror_check.text = "Mirror LR linked"
	_mirror_check.add_theme_font_size_override("font_size", 28)
	_apply_font(_mirror_check, BUTTON_FONT_PATH)
	pick_row.add_child(_mirror_check)
	_add_grid_action(pick_row, "PLACE", _place_from_dropdown)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(460.0, 0.0)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	body.add_child(_status)

	# Every navigation + tool button in a 2-column grid.
	# NOTE: the button font (Schwarzenberg-Italic) lacks < > / ( ) + - glyphs, so labels avoid them
	# (they render as tofu boxes - developer report). The = / - keys still raise/lower wire points.
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)
	_add_grid_action(grid, "MAIN MENU", _enter_menu)
	_add_grid_action(grid, "PLAY", _enter_play)
	_add_grid_action(grid, "Reset view", _reset_view)
	_add_grid_action(grid, "Grid show hide", _toggle_grid)
	_add_grid_action(grid, "Snap to grid", _toggle_snap)
	_add_grid_action(grid, "Draw GUIDE", func() -> void: _begin_draw("guide", true))
	_add_grid_action(grid, "Draw WALL", func() -> void: _begin_draw("wall", false))
	_add_grid_action(grid, "Draw WIRE ramp", func() -> void: _begin_draw_wire(2))
	_add_grid_action(grid, "DONE drawing", _finish_draw)
	_add_grid_action(grid, "Raise point", func() -> void: _adjust_height(HEIGHT_STEP))
	_add_grid_action(grid, "Lower point", func() -> void: _adjust_height(-HEIGHT_STEP))
	_add_grid_action(grid, "Grab move  G", _toggle_grab)
	_add_grid_action(grid, "Undo  Ctrl Z", _undo)
	_add_grid_action(grid, "Delete selected", _delete_selected)
	_add_action(body, "SAVE", _save)
	_add_action(body, "RESET saved", _reset_saved)


## The small bar shown while PLAYING: a button back to the main menu.
func _build_play_bar() -> void:
	_play_bar = PanelContainer.new()
	_play_bar.position = Vector2(10.0, 96.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	_play_bar.add_theme_stylebox_override("panel", bg)
	_hud.add_child(_play_bar)
	# A row: MENU (back to main menu) + RESET (re-seat a stuck ball, no ball spent - "just in case").
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_play_bar.add_child(row)
	var menu_btn := Button.new()
	menu_btn.text = "MENU"
	menu_btn.custom_minimum_size = Vector2(120.0, 48.0)
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(_on_play_bar_menu_pressed)
	_apply_font(menu_btn, BUTTON_FONT_PATH)
	row.add_child(menu_btn)
	var reset_btn := Button.new()
	reset_btn.text = "RESET BALL"
	reset_btn.custom_minimum_size = Vector2(160.0, 48.0)
	reset_btn.add_theme_font_size_override("font_size", 26)
	reset_btn.pressed.connect(_on_reset_ball_button_pressed)
	_apply_font(reset_btn, BUTTON_FONT_PATH)
	row.add_child(reset_btn)


## Play-bar RESET BALL: re-seat the live ball in the launch lane (no ball spent) in case it got stuck.
func _reset_stuck_ball() -> void:
	if _table != null and _table.has_method("manual_reset_ball"):
		_table.manual_reset_ball()


# --- UI CLICK SOUND WIRING (SLICE "Kenney baseline COMPLETION", FRONT 3) --------------------------
# table.gd owns and null-guards the AudioDirector forward (play_ui_click); this editor never touches
# AudioDirector directly, it only calls the stable table.gd forwarder like every other _table.* call
# in this file. Per the DESIGN event-to-sound map, MENU/PLAY/BUILD share the PRIMARY click voice
# (click_001) and RESET BALL gets the SECONDARY voice (click_002) so the two button families sound
# distinct. Only the four buttons a player actually presses in normal play (main-menu BUILD/PLAY,
# the play-bar MENU/RESET BALL) are wired; the keyboard quick-toggle (Tab) and the boot-to-menu call
# are NOT button presses so they stay silent, and the BUILD-panel's internal "MAIN MENU"/"PLAY"
# shortcuts are a developer-only tool, out of this slice's player-facing scope (FRONT 3 split).


## Main-menu BUILD button: click, then enter the editor.
func _on_build_button_pressed() -> void:
	_play_click(false)
	_enter_build()


## Main-menu PLAY button: click, then start the game. This is normally the FIRST user gesture in the
## browser, so it also doubles as the web-audio unlock point (see table.gd play_ui_click docs).
func _on_play_button_pressed() -> void:
	_play_click(false)
	_enter_play()


## Play-bar MENU button: click, then return to the main menu.
func _on_play_bar_menu_pressed() -> void:
	_play_click(false)
	_enter_menu()


## Play-bar RESET BALL button: click (the secondary voice), then re-seat the stuck ball.
func _on_reset_ball_button_pressed() -> void:
	_play_click(true)
	_reset_stuck_ball()


## Voice a UI button click through table.gd's null-safe AudioDirector forwarder. `secondary` selects
## the RESET BALL voice; every other wired button uses the primary MENU/PLAY/BUILD voice. Safe to
## call before the table is wired (e.g. in a future test) since it mirrors the has_method guard used
## everywhere else in this editor.
func _play_click(secondary: bool = false) -> void:
	if _table != null and _table.has_method("play_ui_click"):
		_table.play_ui_click(secondary)


func _add_action(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300.0, 48.0)  ## wider panel + taller hit target (developer request)
	b.add_theme_font_size_override("font_size", 30)  ## larger, readable; min width widens the whole panel
	b.pressed.connect(cb)
	_apply_font(b, BUTTON_FONT_PATH)
	parent.add_child(b)


## A narrower action button for the 2-column tool grid, so the panel reads WIDE rather than long.
## Two of these per row (~225 each) keep the panel about 460 wide and roughly half as tall.
func _add_grid_action(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(225.0, 46.0)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	_apply_font(b, BUTTON_FONT_PATH)
	parent.add_child(b)


## Apply a developer-supplied font to a control. load() (not preload) so a missing font degrades to
## the engine default instead of failing the scene.
func _apply_font(ctrl: Control, path: String) -> void:
	var font: Resource = load(path)
	if font is Font:
		ctrl.add_theme_font_override("font", font)


# --- Modes ---------------------------------------------------------------------------------------

func _enter_menu() -> void:
	# Opening the menu FROM play is a PAUSE: freeze the game and use a TRANSLUCENT background so the
	# table shows through (it stands out as an overlay). Opening it at boot / from build uses an OPAQUE
	# background so the game board is NOT visible behind the main menu.
	var pausing: bool = _playing
	_playing = false
	_release_all_touches()
	if _play_bar != null:
		_play_bar.visible = false
	if _menu != null:
		_menu.visible = true
		_menu.color = Color(0.04, 0.05, 0.08, 0.55 if pausing else 1.0)
	if pausing:
		get_tree().paused = true  ## keep the HUD/board behind the translucent overlay, frozen
	else:
		_set_edit_mode(false)
		_show_hud(false)
		get_tree().paused = false


func _enter_build() -> void:
	get_tree().paused = false  ## leaving a pause menu into build resumes the tree
	_playing = false
	_release_all_touches()
	if _menu != null:
		_menu.visible = false
	if _play_bar != null:
		_play_bar.visible = false
	_set_edit_mode(true)
	_show_hud(false)  ## no game HUD while editing - only the editor UI


func _enter_play() -> void:
	var resuming: bool = get_tree().paused
	get_tree().paused = false
	if _menu != null:
		_menu.visible = false
	_set_edit_mode(false)
	if _play_bar != null:
		_play_bar.visible = true
	_playing = true
	if not resuming:
		# A fresh start (from the boot menu / build): fade the HUD in and serve the first ball. When
		# RESUMING a paused game the HUD and framing are already up, so just unpause above.
		_show_hud(true)
		if _table != null and _table.has_method("start_play"):
			_table.start_play()


## Collapse the build panel down to just its header + the collapse button (and back).
func _toggle_collapse() -> void:
	_collapsed = not _collapsed
	if _panel_body != null:
		_panel_body.visible = not _collapsed
	# Shrink the panel's shadow box to fit the now-hidden body (otherwise the dark box stays full size).
	if _panel != null:
		_panel.reset_size()


## Reset the build camera (pan + zoom) to the default gameplay framing.
func _reset_view() -> void:
	if _table != null and _table.has_method("reset_camera"):
		_table.reset_camera()


## Show (fade in) or hide the game HUD via the table.
func _show_hud(shown: bool) -> void:
	if _table != null and _table.has_method("set_hud_shown"):
		_table.set_hud_shown(shown, shown)
	# PLAY view pans the table left to make room for the backbox; BUILD/menu re-centre it.
	if _table != null and _table.has_method("set_play_view"):
		_table.set_play_view(shown)


func _set_edit_mode(on: bool) -> void:
	_edit_mode = on
	if not on:
		_select(null)
		_dragging = false
		_finish_draw()
	if _table != null and _table.has_method("editor_set_rail_handles_visible"):
		_table.editor_set_rail_handles_visible(on)
	if _table != null and _table.has_method("set_grid_visible"):
		_table.set_grid_visible(on)  ## the coordinate grid shows ONLY in build mode
	if _table != null and not on and _table.has_method("reset_camera"):
		_table.reset_camera()  ## leaving build resets any pan/zoom to the gameplay framing
	if _panel != null:
		_panel.visible = on
	_refresh_status()


## Drag the whole editor panel by its header strip, so it can be moved off the playfield.
func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hud_dragging = event.pressed
	elif event is InputEventMouseMotion and _hud_dragging and _panel != null:
		_panel.position += event.relative


# --- Drawing rails (walls / guides) --------------------------------------------------------------

## Start laying down a new rail. Each grid click adds a point; "DONE" finishes it. kind "guide" draws
## a smooth curve, "wall" draws straight segments.
func _begin_draw(kind: String, smooth: bool) -> void:
	if _table == null or not _table.has_method("editor_spawn_rail"):
		return
	_finish_draw()
	_select(null)
	_push_undo()  ## snapshot before drawing so Undo removes the new rail
	_draw_rail = _table.editor_spawn_rail(kind, smooth, [])
	if _table.has_method("editor_set_rail_handles_visible"):
		_table.editor_set_rail_handles_visible(true)  ## so the points we drop are visible as we draw
	_drawing = true
	_refresh_status()


## Start laying down a WIRE RAMP (3D points). strands = 1/2/4; raise/lower points with + / - after.
func _begin_draw_wire(strands: int) -> void:
	if _table == null or not _table.has_method("editor_spawn_wire"):
		return
	_finish_draw()
	_select(null)
	_push_undo()
	_draw_wire = _table.editor_spawn_wire([], strands)
	if _table.has_method("editor_set_rail_handles_visible"):
		_table.editor_set_rail_handles_visible(true)
	_drawing = true
	_refresh_status()


## Finish the in-progress rail/wire. One with fewer than 2 points is discarded.
func _finish_draw() -> void:
	if _draw_rail != null and is_instance_valid(_draw_rail):
		if _draw_rail.points().size() < 2:
			if _table.has_method("editor_rails"):
				_table.editor_rails().erase(_draw_rail)
			_draw_rail.queue_free()
	if _draw_wire != null and is_instance_valid(_draw_wire):
		if _draw_wire.points().size() < 2:
			if _table.has_method("editor_wires"):
				_table.editor_wires().erase(_draw_wire)
			_draw_wire.queue_free()
	_draw_rail = null
	_draw_wire = null
	_drawing = false
	_refresh_status()


func _refresh_status() -> void:
	if _status == null:
		return
	if not _edit_mode:
		_status.text = ""
		return
	if _drawing:
		_status.text = "DRAWING\nclick = add point\nDONE = finish"
		return
	if _grabbing:
		_status.text = "GRAB\nmove mouse\nclick = drop\nEsc = cancel"
		return
	var sel: String = "none"
	if _selected != null and _selected.has_meta("etype"):
		sel = String(_selected.get_meta("etype"))
	_status.text = (
		"EDIT MODE\nG = grab/move\ndrag = move\nwheel = rotate\nDel = remove\nselected: %s" % sel
	)


func _flash(msg: String) -> void:
	if _status != null:
		_status.text = msg
