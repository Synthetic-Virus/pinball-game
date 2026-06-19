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

## Local (playfield-space) positions of the scoring targets in the upper-middle of the table. A
## small handful so a flip has something worth aiming at (DESIGN: at least one rewarding target). Z
## values are up-table (negative) so they sit above the flippers; X spreads them across the field.
const TARGET_POSITIONS: Array[Vector3] = [
	Vector3(-5.0, 0.0, -6.0),
	Vector3(5.0, 0.0, -6.0),
	Vector3(0.0, 0.0, -12.0),
]

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


func _ready() -> void:
	_build_playfield()
	_build_static_geometry()
	_build_dynamic_elements()
	_build_flow_and_hud()
	_wire_signals()
	# Kick off the first ball through the flow state machine, not directly.
	if game_flow != null and game_flow.has_method("start_game"):
		game_flow.start_game()


## Create the tilted Playfield node that every table element is parented under.
func _build_playfield() -> void:
	playfield = Node3D.new()
	playfield.name = "Playfield"
	playfield.rotation_degrees = Vector3(TableConfig.TILT_DEG, 0.0, 0.0)
	add_child(playfield)


## Instance the static geometry (surface, perimeter walls, arch, lane divider) via TableGeometry.
func _build_static_geometry() -> void:
	TableGeometry.build(playfield)


## Instance Ball, two Flippers, Plunger, Targets, Drain (+ failsafe OobDrain) under the playfield and
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

	# --- Targets ----------------------------------------------------------------------------------
	targets.clear()
	for pos: Vector3 in TARGET_POSITIONS:
		var target: Area3D = TargetScene.instantiate()
		target.position = pos
		playfield.add_child(target)
		target.set_ball(ball)
		targets.append(target)

	# --- Plunger ----------------------------------------------------------------------------------
	plunger = PlungerScene.instantiate()
	plunger.name = "Plunger"
	plunger.position = TableConfig.BALL_START
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

	# Plunger -> launch + HUD meter.
	if plunger != null:
		if plunger.has_signal("ball_launched") and game_flow.has_method("on_ball_launched"):
			plunger.ball_launched.connect(game_flow.on_ball_launched)
		if plunger.has_signal("power_changed") and hud.has_method("set_meter"):
			plunger.power_changed.connect(hud.set_meter)

	# GameFlow -> ball/plunger reset, and HUD displays.
	if game_flow.has_signal("request_new_ball"):
		game_flow.request_new_ball.connect(_on_request_new_ball)
	if game_flow.has_signal("score_changed") and hud.has_method("set_score"):
		game_flow.score_changed.connect(hud.set_score)
	if game_flow.has_signal("balls_changed") and hud.has_method("set_balls"):
		game_flow.balls_changed.connect(hud.set_balls)
	if game_flow.has_signal("message") and hud.has_method("set_message"):
		game_flow.message.connect(hud.set_message)
	if game_flow.has_signal("game_over") and hud.has_method("show_game_over"):
		game_flow.game_over.connect(hud.show_game_over)


## GameFlow asked for a fresh ball (start, or after a non-final drain). Reset the ball to the launch
## lane, arm the plunger, and HIDE the game-over panel. Hiding here covers BOTH a normal new ball and
## a restart (restart() -> start_game() -> request_new_ball), so the panel is never left over a live
## ball (QA BUG-002 / #5). hide_game_over is harmless when the panel is already hidden.
func _on_request_new_ball() -> void:
	if ball != null and ball.has_method("reset_to_start"):
		ball.reset_to_start()
	if plunger != null and plunger.has_method("arm"):
		plunger.arm()
	if hud != null and hud.has_method("hide_game_over"):
		hud.hide_game_over()


## Failsafe drain hit: route any BALLS-layer body that has fallen out of bounds to the same GameFlow
## drain handler the center drain uses. GameFlow's own state guard prevents a double-spend if both
## drains fire for the same lost ball (the second arrives in READY_TO_LAUNCH and is ignored).
##
## We match by LAYER MEMBERSHIP, not by identity against the single tracked `ball` (QA BUG-015). The
## OOB plane is a last-resort anti-soft-lock failsafe: its job is to drain ANYTHING that has escaped
## the playfield so the game can never hang in BALL_IN_PLAY with no ball reachable. An identity check
## would silently ignore any body that is not the one tracked reference (e.g. a future extra ball),
## defeating the failsafe's whole purpose. A layer check keeps it correct for the current single ball
## and robust against escape regardless of which body fell. The center drain keeps its identity check
## (it is scoring-relevant, not a failsafe), so this widening lives only on the failsafe path.
func _on_oob_body_entered(body: Node) -> void:
	var body_layer: int = 0
	if body is CollisionObject3D:
		body_layer = (body as CollisionObject3D).collision_layer
	if body_layer & PhysicsLayers.BALLS == 0:
		return
	if game_flow != null and game_flow.has_method("on_ball_drained"):
		game_flow.on_ball_drained()


## Poll for the restart input. Only meaningful in GAME_OVER; GameFlow.restart() ignores it otherwise.
## We poll here (not in GameFlow) because input belongs to the orchestrator, and we use the JUST-
## PRESSED edge so holding "launch" through game over does not instantly restart and re-fire (it must
## be a deliberate fresh press). The new ball's plunger then also requires its own release (BUG-008).
func _physics_process(_delta: float) -> void:
	if game_flow == null or not game_flow.has_method("current_state"):
		return
	if game_flow.current_state() != game_flow.State.GAME_OVER:
		return
	if Input.is_action_just_pressed("launch") and game_flow.has_method("restart"):
		game_flow.restart()
