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
##     |     +-- Ball                                   (scripts/ball.gd, physics-programmer)
##     +-- GameFlow (Node)   game state machine         (scripts/game_flow.gd, gameplay-programmer)
##     +-- HUD (CanvasLayer)  score/balls/meter/message  (scripts/hud.gd, gameplay-programmer)
##
## SIGNAL WIRING is the integration contract. This script connects:
##   Drain.ball_drained          -> GameFlow.on_ball_drained
##   Target.scored(points)       -> GameFlow.on_target_scored
##   Plunger.ball_launched       -> GameFlow.on_ball_launched
##   GameFlow.request_new_ball    -> Ball.reset_to_start + Plunger.arm
##   GameFlow.score_changed(int)  -> HUD.set_score
##   GameFlow.balls_changed(int)  -> HUD.set_balls
##   GameFlow.message(String)     -> HUD.set_message
##   GameFlow.game_over(int)      -> HUD.show_game_over
##   Plunger.power_changed(float) -> HUD.set_meter
## See _wire_signals() for the single place these are connected.

# Scene element scripts. preload keeps the contract explicit and fails loudly if a file is missing.
const BallScene := preload("res://scenes/elements/Ball.tscn")
const FlipperScene := preload("res://scenes/elements/Flipper.tscn")
const PlungerScene := preload("res://scenes/elements/Plunger.tscn")
const TargetScene := preload("res://scenes/elements/Target.tscn")

# Filled in _ready(). Typed so the rest of the file (and tests) get autocomplete + checks.
var playfield: Node3D
var ball: RigidBody3D
var left_flipper: Node3D
var right_flipper: Node3D
var plunger: Node
var drain: Area3D
var game_flow: Node
var hud: CanvasLayer

func _ready() -> void:
	# TODO(lead): build presentation (environment, camera, light) - gray-box, low priority.
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

## TODO(lead): instance the static geometry (surface, perimeter walls, arch, lane divider) from
## scripts/table_geometry.gd. Lead-owned; does not block physics/gameplay coders.
func _build_static_geometry() -> void:
	pass

## TODO(lead): instance Ball, two Flippers, Plunger, Targets, Drain under the playfield and assign
## the typed handles above. Each element's BEHAVIOR is owned by its file; this only places them.
func _build_dynamic_elements() -> void:
	pass

## TODO(lead): instance GameFlow (Node) and HUD (CanvasLayer) and assign handles.
func _build_flow_and_hud() -> void:
	pass

## The ONE place cross-system signals are connected. Keeping wiring here means a coder can change a
## system's internals freely as long as the documented signal signatures hold.
## TODO(lead): connect the signals listed in the header once the element handles exist. Guard each
## connection with has_signal/has_method so a not-yet-implemented stub does not crash the scene.
func _wire_signals() -> void:
	pass
