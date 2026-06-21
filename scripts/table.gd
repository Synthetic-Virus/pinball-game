extends Node3D
## Table - the root orchestrator scene for the gray-box pinball table.
##
## OWNERSHIP: lead-programmer (architecture + wiring). This script does NOT implement game rules or
## physics; it BUILDS the scene tree and WIRES the signal contracts between the independently-owned
## systems so the physics-programmer and gameplay-programmer can fill their own files in parallel.
##
## SCENE STRUCTURE (children created in _ready, all under a tilted Playfield node):
##   Table (Node3D, this script)
##     +-- Environment/Camera/Light   (presentation, gray-box only)
##     +-- Playfield (Node3D, rotated TableConfig.TILT_DEG about X) - the tilted table plane
##     |     +-- Surface + Walls + Arch + Lane divider  (static geometry, scripts/table_geometry.gd)
##     |     +-- LeftFlipper / RightFlipper             (scripts/flipper.gd, physics-programmer)
##     |     +-- Targets (scoring obstacles)            (scripts/target.gd, gameplay-programmer)
##     |     +-- Plunger                                (scripts/plunger.gd, gameplay-programmer)
##     |     +-- Drain (Area3D)                         (scripts/drain.gd, gameplay-programmer)
##     |     +-- OobDrain (Area3D)                      failsafe catch-plane (this script)
##     |     +-- Ball                                   (scripts/ball.gd, physics-programmer)
##     +-- GameFlow (Node)   game state machine         (scripts/game_flow.gd, gameplay-programmer)
##     +-- HUD (CanvasLayer)  score/balls/meter/message  (scripts/hud.gd, gameplay-programmer)
##
## SIGNAL WIRING is the integration contract. This script connects (see _wire_signals):
##   Drain.ball_drained          -> GameFlow.on_ball_drained
##   OobDrain.ball_drained       -> GameFlow.on_ball_drained   (failsafe, same handler)
##   Target.scored(points)       -> GameFlow.on_target_scored
##   Plunger.ball_launched       -> GameFlow.on_ball_launched
##   GameFlow.request_new_ball    -> Ball.reset_to_start + Plunger.arm  (_on_request_new_ball)
##   GameFlow.score_changed(int)  -> HUD.set_score
##   GameFlow.balls_changed(int)  -> HUD.set_balls
##   GameFlow.message(String)     -> HUD.set_message
##   GameFlow.game_over(int)      -> HUD.show_game_over
##   Plunger.power_changed(float) -> HUD.set_meter
## RESTART: in GAME_OVER, _physics_process polls the "launch" action and calls GameFlow.restart(),
## which re-runs start_game(); _on_request_new_ball hides the game-over panel so the player is not
## left staring at "GAME OVER" over a live ball (QA BUG-002 / #5 / #6).

# Scene element scripts. preload keeps the contract explicit and fails loudly if a file is missing.
const BallScene := preload("res://scenes/elements/Ball.tscn")
const FlipperScene := preload("res://scenes/elements/Flipper.tscn")
const PlungerScene := preload("res://scenes/elements/Plunger.tscn")
const TargetScene := preload("res://scenes/elements/Target.tscn")
const PopBumperScene := preload("res://scenes/elements/PopBumper.tscn")
const SlingshotScene := preload("res://scenes/elements/Slingshot.tscn")

## The standup target bank positions now come from TableConfig.STANDUP_BANK_POSITIONS (SLICE "real
## pinball furniture"): the 3 physical targets are re-homed into a readable mid-field bank a
## deliberate
## flip can reach (validated by tools/table_viz.py against the flipper-tip sweep). The old scattered
## TARGET_POSITIONS const is removed; table.gd reads the bank from the world-scale contract instead
## so
## the placement lives in one source of truth with the rest of the furniture geometry.

## Camera framing tunables. The camera POSITION is computed at runtime by _frame_camera (it fits
## the table bounds via the engine's real projection); only the viewing FEEL lives here - pitch and
## breathing room. FOV is vertical (Godot default keep_aspect = KEEP_HEIGHT).
const CAMERA_FOV: float = 60.0
const VIEW_PITCH_DEG: float = 42.0
const FRAME_MARGIN: float = 1.08

# Filled in _ready(). Typed so the rest of the file (and tests) get autocomplete + checks.
var playfield: Node3D
var ball: RigidBody3D
var left_flipper: Node3D
var right_flipper: Node3D
var plunger: Node
var drain: Area3D
var oob_drain: Area3D
var game_flow: Node
var hud: CanvasLayer
var targets: Array[Area3D] = []
## Active-kick furniture (SLICE "real pinball furniture"). Both are Area3D detectors (pop_bumper.gd
## /
## slingshot.gd extend active_kicker.gd) with the same scored/kicked/set_ball contract as targets,
## so
## they wire the same way. Kept as separate typed handles so tests and wiring can address each
## family.
var pop_bumpers: Array[Area3D] = []
var slingshots: Array[Area3D] = []
var _camera: Camera3D


func _ready() -> void:
	_build_presentation()
	_build_playfield()
	_build_static_geometry()
	_build_dynamic_elements()
	_build_flow_and_hud()
	_wire_signals()
	# Kick off the first ball through the flow state machine, not directly.
	if game_flow != null and game_flow.has_method("start_game"):
		game_flow.start_game()


## Build the presentation layer: a camera to view the table, a light to lit the gray-box meshes,
## and an environment for ambient fill + background. WHY THIS EXISTS: the table elements build their
## own MeshInstance3D geometry, but a 3D scene with no Camera3D renders only the clear color (the
## "empty gray table" bug) and unlit meshes are invisible without a light.
##
## The camera POSITION is NOT hardcoded. A hand-tuned position guessed off-engine drifted badly from
## what Godot actually rendered (the table sat jammed at the bottom of the frame). So instead we let
## the ENGINE frame the table: _frame_camera aims at the table center and backs the camera off until
## every table corner is inside the real camera frustum. That uses Godot's own projection and the
## real viewport, so it cannot disagree with the render and it self-corrects for any aspect ratio.
func _build_presentation() -> void:
	const LIGHT_EULER_DEG: Vector3 = Vector3(-50.0, -20.0, 0.0)

	# Environment: dark background plus ambient fill so the neutral gray boxes are legible even on the
	# unlit faces the directional light does not reach.
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.76)
	env.ambient_light_energy = 0.45
	world_env.environment = env
	add_child(world_env)

	# Directional light angled down the table. Shadows are OFF on purpose: shadow mapping is a known
	# web-perf cost and the project's headline gate is smooth FPS; a gray-box does not need shadows.
	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.rotation_degrees = LIGHT_EULER_DEG
	light.light_energy = 1.2
	light.shadow_enabled = false
	add_child(light)

	# Camera: created here, but POSITIONED by _frame_camera. current = true so the viewport uses it.
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = CAMERA_FOV
	add_child(_camera)
	_camera.current = true
	# Frame once after the tree/viewport exist (deferred), and again whenever the viewport resizes -
	# the web canvas only gets its real size after the first frame, so the initial frame may be off.
	get_viewport().size_changed.connect(_frame_camera)
	call_deferred("_frame_camera")


## World-space corners of the (tilted) table bounding box. The table is centered at the origin and
## the Playfield node is rotated TableConfig.TILT_DEG about X, so we apply that same tilt here.
func _table_corners() -> Array:
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(TableConfig.TILT_DEG))
	var hw: float = TableConfig.HALF_WIDTH
	var hl: float = TableConfig.HALF_LENGTH
	var ht: float = TableConfig.WALL_HEIGHT
	var corners: Array = []
	for sx in [-hw, hw]:
		for sy in [0.0, ht]:
			for sz in [-hl, hl]:
				corners.append(tilt * Vector3(sx, sy, sz))
	return corners


## True only when EVERY given world point is inside the current camera frustum (i.e. on screen).
func _all_corners_visible(corners: Array) -> bool:
	for corner in corners:
		if not _camera.is_position_in_frustum(corner):
			return false
	return true


## Position the camera so the whole table is framed, using the ENGINE's real projection. Aim at the
## table center (centered by construction) from a fixed downward pitch, then back the camera off
## along that direction until every table corner is inside the frustum, plus a margin.
## Re-runnable: called deferred at startup and on every viewport resize.
func _frame_camera() -> void:
	if _camera == null:
		return
	var corners := _table_corners()
	var center := Vector3.ZERO  # table is centered at the world origin
	var pitch := deg_to_rad(VIEW_PITCH_DEG)
	# Direction from the table center out to the camera: elevated (+Y) and behind the drain end (+Z).
	var out_dir := Vector3(0.0, sin(pitch), cos(pitch)).normalized()
	var dist := 18.0
	_place_camera(center, out_dir, dist)
	# Grow the distance until the whole table fits (guard bounds the loop defensively).
	var guard := 0
	while guard < 400 and not _all_corners_visible(corners):
		dist += 1.5
		_place_camera(center, out_dir, dist)
		guard += 1
	# A little breathing room so the table is not edge-to-edge.
	_place_camera(center, out_dir, dist * FRAME_MARGIN)


func _place_camera(center: Vector3, out_dir: Vector3, dist: float) -> void:
	_camera.global_position = center + out_dir * dist
	_camera.look_at(center, Vector3.UP)


## Create the tilted Playfield node that every table element is parented under.
func _build_playfield() -> void:
	playfield = Node3D.new()
	playfield.name = "Playfield"
	playfield.rotation_degrees = Vector3(TableConfig.TILT_DEG, 0.0, 0.0)
	add_child(playfield)


## Instance the static geometry (surface, perimeter walls, arch, lane divider) via TableGeometry.
func _build_static_geometry() -> void:
	TableGeometry.build(playfield)


## Instance Ball, two Flippers, Plunger, Targets, Drain (+ failsafe OobDrain) under the playfield
## and
## assign the typed handles. Each element's BEHAVIOR is owned by its file; this only places them and
## hands each the ball it must track (set_ball), which is required for drain/scoring to fire at all.
func _build_dynamic_elements() -> void:
	# --- Ball -------------------------------------------------------------------------------------
	ball = BallScene.instantiate()
	ball.name = "Ball"
	playfield.add_child(ball)

	# --- Flippers (inverted V near the drain end) -------------------------------------------------
	# Pivots at +/-FLIPPER_PIVOT_SPREAD on X, FLIPPER_PIVOT_Z up from the drain. The left flipper is
	# non-mirrored; the right is mirrored so it is a true mirror image (geometry fix lives in
	# flipper.gd configure/_apply_handedness).
	var pivot_z: float = TableConfig.FLIPPER_PIVOT_Z
	var spread: float = TableConfig.FLIPPER_PIVOT_SPREAD

	left_flipper = FlipperScene.instantiate()
	left_flipper.name = "LeftFlipper"
	left_flipper.position = Vector3(-spread, 0.0, pivot_z)
	playfield.add_child(left_flipper)
	left_flipper.configure("left_flipper", false)

	right_flipper = FlipperScene.instantiate()
	right_flipper.name = "RightFlipper"
	right_flipper.position = Vector3(spread, 0.0, pivot_z)
	playfield.add_child(right_flipper)
	right_flipper.configure("right_flipper", true)

	# --- Furniture: rebuilding from the developer's markup, ONE verified piece at a time ----------
	# After the 2026-06-21 reset (flat play area + borders) we add furniture back per the hand-drawn
	# plan (docs/REFERENCE_LAYOUT.md), checking each piece plays before the next.

	# --- Slingshots (markup piece 3): one angled 3-post kicker outboard of each flipper ------------
	slingshots.clear()
	var left_sling: Area3D = SlingshotScene.instantiate()
	left_sling.name = "LeftSlingshot"
	left_sling.position = TableConfig.SLINGSHOT_LEFT_POS
	if left_sling.has_method("configure"):
		left_sling.configure(false)
	playfield.add_child(left_sling)
	left_sling.set_ball(ball)
	slingshots.append(left_sling)

	var right_sling: Area3D = SlingshotScene.instantiate()
	right_sling.name = "RightSlingshot"
	right_sling.position = TableConfig.SLINGSHOT_RIGHT_POS
	if right_sling.has_method("configure"):
		right_sling.configure(true)
	playfield.add_child(right_sling)
	right_sling.set_ball(ball)
	slingshots.append(right_sling)

	# --- Targets (markup piece 2): purple posts from STANDUP_BANK_POSITIONS ------------------------
	targets.clear()
	for pos: Vector3 in TableConfig.STANDUP_BANK_POSITIONS:
		var target: Area3D = TargetScene.instantiate()
		target.position = pos
		playfield.add_child(target)
		target.set_ball(ball)
		targets.append(target)

	# --- Pop bumpers (markup piece 1): 3-bumper triangle, positions from POP_BUMPER_POSITIONS -----
	pop_bumpers.clear()
	for pos: Vector3 in TableConfig.POP_BUMPER_POSITIONS:
		var bumper: Area3D = PopBumperScene.instantiate()
		bumper.position = pos
		if bumper.has_method("configure"):
			bumper.configure()
		playfield.add_child(bumper)
		bumper.set_ball(ball)
		pop_bumpers.append(bumper)

	# --- Plunger ----------------------------------------------------------------------------------
	# CONTRACT (QA BUG-013): the Plunger node MUST sit at the playfield origin (Vector3.ZERO). Its
	# child face (plunger.gd._build_face) seats itself at the playfield-LOCAL
	# TableConfig.PLUNGER_REST_POS
	# and, like every other element here, treats its own local space as playfield space. Parenting the
	# Plunger anywhere else (the old code set it to BALL_START) double-offsets the face: it would land
	# at
	# BALL_START + PLUNGER_REST_POS, off the table, and the strike would never contact the ball.
	# tests/test_plunger_launch.gd sets the plunger to ZERO for exactly this reason; honor that here.
	plunger = PlungerScene.instantiate()
	plunger.name = "Plunger"
	plunger.position = Vector3.ZERO
	playfield.add_child(plunger)
	plunger.set_ball(ball)

	# --- Drain (open center/bottom) ---------------------------------------------------------------
	drain = preload("res://scripts/drain.gd").new()
	drain.name = "Drain"
	playfield.add_child(drain)
	drain.set_ball(ball)

	# --- Out-of-bounds failsafe drain (defense in depth, QA BUG-006) ------------------------------
	# A large low Area3D below the surface that catches ANY ball which escapes the playfield (e.g.
	# popped over a wall or squeezed through a seam) so the game can never soft-lock in BALL_IN_PLAY.
	# This is a PLAIN Area3D (not drain.gd) so it does not inherit drain.gd's _ready geometry, which
	# is sized/placed for the center drain. Its body_entered is wired in _wire_signals.
	oob_drain = Area3D.new()
	oob_drain.name = "OobDrain"
	oob_drain.collision_mask = PhysicsLayers.BALLS
	var oob_col := CollisionShape3D.new()
	var oob_box := BoxShape3D.new()
	# Spans far beyond the table in X/Z and is thin in Y, sitting well below the surface.
	oob_box.size = Vector3(TableConfig.HALF_WIDTH * 6.0, 4.0, TableConfig.HALF_LENGTH * 6.0)
	oob_col.shape = oob_box
	oob_drain.add_child(oob_col)
	oob_drain.position = Vector3(0.0, TableConfig.OOB_DRAIN_Y, 0.0)
	playfield.add_child(oob_drain)


## Instance GameFlow (Node) and HUD (CanvasLayer) and assign handles.
func _build_flow_and_hud() -> void:
	game_flow = preload("res://scripts/game_flow.gd").new()
	game_flow.name = "GameFlow"
	add_child(game_flow)

	hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)


## The ONE place cross-system signals are connected. Keeping wiring here means a coder can change a
## system's internals freely as long as the documented signal signatures hold. Each connection is
## guarded with has_signal/has_method so a not-yet-implemented stub never crashes the scene.
func _wire_signals() -> void:
	# Drain -> spend a ball.
	if drain != null and drain.has_signal("ball_drained") and game_flow.has_method("on_ball_drained"):
		drain.ball_drained.connect(game_flow.on_ball_drained)
	# Failsafe OOB drain: plain Area3D, so route its body_entered through a local handler that filters
	# for the ball and calls the same GameFlow path. Same effect as the center drain.
	if oob_drain != null:
		oob_drain.body_entered.connect(_on_oob_body_entered)

	# Targets -> score.
	for target: Area3D in targets:
		if target.has_signal("scored") and game_flow.has_method("on_target_scored"):
			target.scored.connect(game_flow.on_target_scored)

	# Active-kick furniture -> score (same scored(points) contract as targets; reuse the handler).
	# Pop bumpers and slingshots score on their kick; GameFlow.on_target_scored adds the flat points,
	# so no new GameFlow method is needed (the active kick is invisible to the flow behind the signal).
	for kicker: Area3D in (pop_bumpers + slingshots):
		if kicker.has_signal("scored") and game_flow.has_method("on_target_scored"):
			kicker.scored.connect(game_flow.on_target_scored)

	# Plunger -> launch + HUD meter.
	if plunger != null:
		if plunger.has_signal("ball_launched") and game_flow.has_method("on_ball_launched"):
			plunger.ball_launched.connect(game_flow.on_ball_launched)
		if plunger.has_signal("power_changed") and hud.has_method("set_meter"):
			plunger.power_changed.connect(hud.set_meter)

	# GameFlow -> ball/plunger reset, and HUD displays.
	if game_flow.has_signal("request_new_ball"):
		game_flow.request_new_ball.connect(_on_request_new_ball)
	# SOFT-LOCK FIX: GameFlow asks to RE-LAUNCH the SAME ball (a failed launch that never reached
	# play). Same re-seat-and-arm path as a new ball, but reached via a distinct signal so the intent
	# is explicit and a test can tell a recovery from a fresh ball (no balls_changed accompanies it).
	if game_flow.has_signal("request_relaunch"):
		game_flow.request_relaunch.connect(_on_request_new_ball)
	if game_flow.has_signal("score_changed") and hud.has_method("set_score"):
		game_flow.score_changed.connect(hud.set_score)
	if game_flow.has_signal("balls_changed") and hud.has_method("set_balls"):
		game_flow.balls_changed.connect(hud.set_balls)
	if game_flow.has_signal("message") and hud.has_method("set_message"):
		game_flow.message.connect(hud.set_message)
	if game_flow.has_signal("game_over") and hud.has_method("show_game_over"):
		game_flow.game_over.connect(hud.show_game_over)


## GameFlow asked for a fresh ball (start, or after a non-final drain). Reset the ball to the launch
## lane, arm the plunger, and HIDE the game-over panel. Hiding here covers BOTH a normal new ball
## and
## a restart (restart() -> start_game() -> request_new_ball), so the panel is never left over a live
## ball (QA BUG-002 / #5). hide_game_over is harmless when the panel is already hidden.
func _on_request_new_ball() -> void:
	if ball != null and ball.has_method("reset_to_start"):
		ball.reset_to_start()
	if plunger != null and plunger.has_method("arm"):
		plunger.arm()
	if hud != null and hud.has_method("hide_game_over"):
		hud.hide_game_over()


## Failsafe drain hit: only the live ball counts (ignore any other body), then route to the same
## GameFlow drain handler the center drain uses. GameFlow's own state guard prevents a double-spend
## if both drains somehow fire for the same lost ball (the second arrives in READY_TO_LAUNCH and is
## ignored).
func _on_oob_body_entered(body: Node) -> void:
	if body != ball:
		return
	if game_flow != null and game_flow.has_method("on_ball_drained"):
		game_flow.on_ball_drained()


## Poll for the restart input. Only meaningful in GAME_OVER; GameFlow.restart() ignores it
## otherwise.
## We poll here (not in GameFlow) because input belongs to the orchestrator, and we use the JUST-
## PRESSED edge so holding "launch" through game over does not instantly restart and re-fire (it
## must
## be a deliberate fresh press). The new ball's plunger then also requires its own release
## (BUG-008).
func _physics_process(delta: float) -> void:
	if game_flow == null or not game_flow.has_method("current_state"):
		return

	# SOFT-LOCK FIX: feed the ball's MEASURED playfield-local Z to GameFlow's launch watchdog every
	# physics frame. GameFlow only acts on it while LAUNCHING (a no-op otherwise), so this is cheap and
	# safe to call unconditionally. The ball is parented under the tilted Playfield, so ball.position
	# is already the playfield-local coordinate the TableConfig Z thresholds are written in - an
	# independent oracle (the real body's position, not a self-reported flag). This is what breaks the
	# soft-lock: a launch that never crosses LAUNCH_REACHED_PLAY_Z is recovered after the settle gap.
	if ball != null and game_flow.has_method("tick_launch_watch"):
		game_flow.tick_launch_watch(ball.position.z, delta)

	# RESTART poll (GAME_OVER only).
	if game_flow.current_state() != game_flow.State.GAME_OVER:
		return
	if Input.is_action_just_pressed("launch") and game_flow.has_method("restart"):
		game_flow.restart()
