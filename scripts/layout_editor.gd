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
const LONG_PRESS_MS: float = 350.0            ## a play touch held this long also fires launch (spacebar)

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

var _drawing: bool = false        ## true while laying down a new rail point-by-point
var _draw_rail: Node3D = null     ## the rail being drawn

var _grabbing: bool = false       ## Blender-style GRAB: selected follows the cursor, no button held
var _grab_origin: Vector3 = Vector3.ZERO  ## where the grabbed element started (restored on cancel)

var _hud: CanvasLayer = null
var _menu: Control = null          ## the main menu (Build / Play), shown at boot
var _play_bar: Control = null      ## the small "Menu" button shown while playing
var _panel: PanelContainer = null  ## the BUILD-mode editor panel
var _header: Label = null
var _hud_dragging: bool = false
var _status: Label = null
var _object_dropdown: OptionButton = null  ## the placeable-object picker (replaces the button list)
var _mirror_check: CheckBox = null         ## when ticked, a placed object gets a linked L/R mirror

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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			# Quick toggle between BUILD and PLAY (skips the menu).
			if _edit_mode:
				_enter_play()
			else:
				_enter_build()
			return
		if _edit_mode and _selected != null and (
			event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE
		):
			_delete_selected()
			return
		# Blender-style GRAB: G picks up the selection so it follows the cursor (no button held); a
		# left-click drops it, Escape (or right-click) cancels back to where it started.
		if _edit_mode and event.keycode == KEY_G and _selected != null and not _drawing:
			_toggle_grab()
			return
		if _grabbing and event.keycode == KEY_ESCAPE:
			_cancel_grab()
			return
	if not _edit_mode:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and (_dragging or _grabbing) and _selected != null:
		var hit: Variant = _ray_to_field(event.position)
		if hit != null:
			_selected.position.x = hit.x
			_selected.position.z = hit.z
			# Moving a rail's point-handle reshapes that rail live.
			if _selected.has_meta("rail"):
				var rail: Node = _selected.get_meta("rail")
				if is_instance_valid(rail):
					rail.rebuild()
			_update_twin(_selected)


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
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# While drawing a rail, each click DROPS A POINT instead of selecting/dragging.
			if _drawing and _draw_rail != null:
				var hit: Variant = _ray_to_field(event.position)
				if hit != null:
					_draw_rail.add_point(Vector3(hit.x, 0.0, hit.z))
				return
			_select(_pick(event.position))
			_dragging = _selected != null
		else:
			_dragging = false
	elif event.pressed and _selected != null:
		# Wheel up / down rotates the selected element about the vertical (table-normal) axis.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_selected.rotation.y += deg_to_rad(ROTATE_STEP_DEG)
			_update_twin(_selected)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_selected.rotation.y -= deg_to_rad(ROTATE_STEP_DEG)
			_update_twin(_selected)


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
	_grabbing = false  ## changing selection ends any in-progress grab
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
		_grab_origin = _selected.position
		_grabbing = true
	_refresh_status()


## Cancel a grab: snap the element back to where it started and stop following the cursor.
func _cancel_grab() -> void:
	if _selected != null:
		_selected.position = _grab_origin
		if _selected.has_meta("rail"):
			var rail: Node = _selected.get_meta("rail")
			if is_instance_valid(rail):
				rail.rebuild()
		_update_twin(_selected)
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


func _editables() -> Array:
	if _table != null and _table.has_method("editor_editables"):
		return _table.editor_editables()
	return []


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
		if String(node.get_meta("etype")) == "rail_handle":
			continue
		out.append({
			"type": node.get_meta("etype"),
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
	build_btn.custom_minimum_size = Vector2(200.0, 48.0)
	build_btn.pressed.connect(_enter_build)
	_apply_font(build_btn, BUTTON_FONT_PATH)
	col.add_child(build_btn)
	var play_btn := Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(200.0, 48.0)
	play_btn.pressed.connect(_enter_play)
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
	_header.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	_header.gui_input.connect(_on_header_input)
	column.add_child(_header)

	# Navigation up top so it is always obvious how to leave BUILD mode (the game HUD is hidden here).
	# NOTE: the button font (Schwarzenberg-Italic) lacks < > / ( ) glyphs, so labels avoid them.
	_add_action(column, "MAIN MENU", _enter_menu)
	_add_action(column, "PLAY", _enter_play)

	# Object picker: a dropdown (so the long list does not crowd the screen) + a Place button.
	_object_dropdown = OptionButton.new()
	_object_dropdown.custom_minimum_size = Vector2(196.0, 0.0)
	for i: int in range(_placeables.size()):
		_object_dropdown.add_item(String(_placeables[i]["label"]), i)
	_apply_font(_object_dropdown, BUTTON_FONT_PATH)
	column.add_child(_object_dropdown)
	_mirror_check = CheckBox.new()
	_mirror_check.text = "Mirror LR linked"
	_apply_font(_mirror_check, BUTTON_FONT_PATH)
	column.add_child(_mirror_check)
	_add_action(column, "PLACE", _place_from_dropdown)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(196.0, 0.0)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	column.add_child(_status)

	_add_action(column, "Draw GUIDE", func() -> void: _begin_draw("guide", true))
	_add_action(column, "Draw WALL", func() -> void: _begin_draw("wall", false))
	_add_action(column, "DONE drawing", _finish_draw)
	_add_action(column, "Grab move  G", _toggle_grab)
	_add_action(column, "Delete selected", _delete_selected)
	_add_action(column, "SAVE", _save)
	_add_action(column, "RESET saved", _reset_saved)


## The small bar shown while PLAYING: a button back to the main menu.
func _build_play_bar() -> void:
	_play_bar = PanelContainer.new()
	_play_bar.position = Vector2(10.0, 96.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	_play_bar.add_theme_stylebox_override("panel", bg)
	_hud.add_child(_play_bar)
	var b := Button.new()
	b.text = "Menu"
	b.pressed.connect(_enter_menu)
	_apply_font(b, BUTTON_FONT_PATH)
	_play_bar.add_child(b)


func _add_action(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
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
	_draw_rail = _table.editor_spawn_rail(kind, smooth, [])
	if _table.has_method("editor_set_rail_handles_visible"):
		_table.editor_set_rail_handles_visible(true)  ## so the points we drop are visible as we draw
	_drawing = true
	_refresh_status()


## Finish the in-progress rail. A rail with fewer than 2 points is discarded.
func _finish_draw() -> void:
	if _draw_rail != null and is_instance_valid(_draw_rail):
		if _draw_rail.points().size() < 2:
			if _table.has_method("editor_rails"):
				_table.editor_rails().erase(_draw_rail)
			_draw_rail.queue_free()
	_draw_rail = null
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
