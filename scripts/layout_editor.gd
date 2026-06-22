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
const SELECT_RADIUS: float = 2.5              ## a click within this many table units grabs an element
const ROTATE_STEP_DEG: float = 7.5            ## rotation applied per mouse-wheel tick
const SELECT_LIFT: float = 0.6                ## how far the selected element lifts (visual cue only)

var _table: Node = null
var _camera: Camera3D = null
var _playfield: Node3D = null

var _edit_mode: bool = false
var _selected: Node3D = null
var _selected_base_y: float = 0.0
var _dragging: bool = false

var _hud: CanvasLayer = null
var _status: Label = null
var _palette: Control = null


## Wire the editor to the live table. table.gd calls this once the furniture exists.
func setup(table: Node, camera: Camera3D, playfield: Node3D) -> void:
	_table = table
	_camera = camera
	_playfield = playfield
	_build_hud()
	_load_saved()
	set_process_unhandled_input(true)


# --- Input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_set_edit_mode(not _edit_mode)
			return
		if _edit_mode and _selected != null and (
			event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE
		):
			_delete_selected()
			return
	if not _edit_mode:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging and _selected != null:
		var hit: Variant = _ray_to_field(event.position)
		if hit != null:
			_selected.position.x = hit.x
			_selected.position.z = hit.z


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_select(_pick(event.position))
			_dragging = _selected != null
		else:
			_dragging = false
	elif event.pressed and _selected != null:
		# Wheel up / down rotates the selected element about the vertical (table-normal) axis.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_selected.rotation.y += deg_to_rad(ROTATE_STEP_DEG)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_selected.rotation.y -= deg_to_rad(ROTATE_STEP_DEG)


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
	var best_dist: float = SELECT_RADIUS
	for node: Node3D in _editables():
		var here := Vector2(node.position.x, node.position.z)
		var d: float = click.distance_to(here)
		if d < best_dist:
			best_dist = d
			best = node
	return best


func _select(node: Node3D) -> void:
	if _selected == node:
		return
	if _selected != null:
		_selected.position.y = _selected_base_y   ## drop the previous selection back down
	_selected = node
	if _selected != null:
		_selected_base_y = _selected.position.y
		_selected.position.y = _selected_base_y + SELECT_LIFT
	_refresh_status()


func _delete_selected() -> void:
	if _selected == null:
		return
	var doomed: Node3D = _selected
	_selected = null
	_dragging = false
	if _table.has_method("editor_remove"):
		_table.editor_remove(doomed)
	_refresh_status()


func _editables() -> Array:
	if _table != null and _table.has_method("editor_editables"):
		return _table.editor_editables()
	return []


# --- Palette / adding ----------------------------------------------------------------------------

func _add(etype: String) -> void:
	if _table == null or not _table.has_method("editor_spawn"):
		return
	# Drop the new piece in the upper-middle of the play area where it is easy to see, then the
	# developer drags it into place.
	var node: Node3D = _table.editor_spawn(etype, Vector3(0.0, 0.0, -3.0), 0.0)
	if node != null:
		_select(node)


# --- Persistence (browser only) ------------------------------------------------------------------

## Serialise every editable element to a plain array of {type, x, z, rot_deg} dictionaries.
func _serialize() -> Array:
	var out: Array = []
	for node: Node3D in _editables():
		if not node.has_meta("etype"):
			continue
		out.append({
			"type": node.get_meta("etype"),
			"x": snappedf(node.position.x, 0.01),
			"z": snappedf(node.position.z, 0.01),
			"rot_deg": snappedf(rad_to_deg(node.rotation.y), 0.1),
		})
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
	if not (raw is String) or raw == "":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		return
	_apply_layout(parsed)


## Replace the current furniture with a saved layout: clear every editable, then respawn each entry.
func _apply_layout(entries: Array) -> void:
	if _table == null or not _table.has_method("editor_spawn"):
		return
	for node: Node3D in _editables().duplicate():
		if _table.has_method("editor_remove"):
			_table.editor_remove(node)
	for entry: Variant in entries:
		if not (entry is Dictionary) or not entry.has("type"):
			continue
		var pos := Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
		_table.editor_spawn(String(entry["type"]), pos, deg_to_rad(float(entry.get("rot_deg", 0.0))))


# --- HUD -----------------------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "EditorHUD"
	_hud.layer = 50
	add_child(_hud)

	# Everything sits in ONE dark panel on the LEFT, BELOW the score line, so the editor UI never
	# overlaps the game HUD (SCORE top-left, BALLS top-right, LAUNCH POWER bottom). The panel hugs its
	# contents, so when edit mode is off it is just the small EDIT button.
	var panel := PanelContainer.new()
	panel.position = Vector2(10.0, 96.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	bg.content_margin_left = 8.0
	bg.content_margin_right = 8.0
	bg.content_margin_top = 6.0
	bg.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", bg)
	_hud.add_child(panel)

	var column := VBoxContainer.new()
	panel.add_child(column)

	var toggle := Button.new()
	toggle.text = "EDIT"
	toggle.pressed.connect(func() -> void: _set_edit_mode(not _edit_mode))
	column.add_child(toggle)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(190.0, 0.0)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_status.visible = false
	column.add_child(_status)

	_palette = VBoxContainer.new()
	column.add_child(_palette)
	_add_palette_button("+ Bumper", func() -> void: _add("bumper"))
	_add_palette_button("+ Target", func() -> void: _add("target"))
	_add_palette_button("+ Sling L", func() -> void: _add("sling_left"))
	_add_palette_button("+ Sling R", func() -> void: _add("sling_right"))
	_add_palette_button("Delete sel", _delete_selected)
	_add_palette_button("SAVE", _save)
	_add_palette_button("RESET saved", _reset_saved)
	_palette.visible = false


func _add_palette_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_palette.add_child(b)


func _set_edit_mode(on: bool) -> void:
	_edit_mode = on
	if not on:
		_select(null)
		_dragging = false
	if _palette != null:
		_palette.visible = on
	if _status != null:
		_status.visible = on
	_refresh_status()


func _refresh_status() -> void:
	if _status == null:
		return
	if not _edit_mode:
		_status.text = ""
		return
	var sel: String = "none"
	if _selected != null and _selected.has_meta("etype"):
		sel = String(_selected.get_meta("etype"))
	_status.text = "EDIT MODE\ndrag = move\nwheel = rotate\nDel = remove\nselected: %s" % sel


func _flash(msg: String) -> void:
	if _status != null:
		_status.text = msg
