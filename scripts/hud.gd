extends CanvasLayer
## HUD - the minimal heads-up display: score, balls remaining, power meter, messages, game over.
##
## OWNERSHIP: gameplay-programmer (with ux-designer input on layout). Pure presentation: it has NO
## game logic. It only renders what GameFlow/Plunger tell it. table.gd connects the signals to the
## setter methods below.
##
## DESIGN scope (minimal): score, balls, an oscillating launch meter, a drain/launch message, and a
## game-over panel with a restart prompt. Nothing more (DESIGN cut list: no menus beyond this).
##
## LAYOUT (built in code, no .tscn required - keeps this script self-contained for tests):
##   Top-left:  "SCORE  0"  label (lbl_score)
##   Top-right: "BALLS  3"  label (lbl_balls)
##   Bottom-left: power meter bar (two stacked ColorRects: bg grey, fill green->red)
##   Centre-bottom: message label (lbl_msg)
##   Centre (hidden by default): game-over panel (pnl_game_over) with a text label
##
## All UI copy uses plain ASCII - no emojis, no em dashes (house style).
##
## STABLE CONTRACT (table.gd connects GameFlow/Plunger signals to these; keep the signatures):
##   func set_score(score: int) -> void
##   func set_balls(balls: int) -> void
##   func set_meter(power: float) -> void       # 0..1, draws the launch power bar.
##   func set_message(text: String) -> void
##   func show_game_over(final_score: int) -> void
##   func hide_game_over() -> void

# --- Node references (assigned in _ready) ---
var _lbl_score: Label
var _lbl_balls: Label
var _lbl_msg: Label
var _meter_fill: ColorRect   # The coloured fill portion of the power meter bar.
var _pnl_game_over: PanelContainer
var _lbl_game_over: Label

## Width of the power meter bar in pixels. Chosen to be readable at 1080p without being obtrusive.
const METER_BAR_WIDTH: float = 200.0
const METER_BAR_HEIGHT: float = 24.0

## Colour gradient for the meter: full green at 0 (relaxed), full red at 1 (max power).
## lerp-ing between these gives the player immediate visual feedback on their power level.
const METER_COLOR_LOW: Color = Color(0.2, 0.85, 0.2)    ## Green - safe, low power.
const METER_COLOR_HIGH: Color = Color(0.9, 0.15, 0.15)  ## Red - high power.

func _ready() -> void:
	_build_ui()

## Build the entire UI tree in code. This keeps the HUD self-contained (no separate .tscn to
## maintain) and makes the node references explicit and easy to follow for a non-expert reader.
func _build_ui() -> void:
	# Root control that fills the viewport so anchored children position correctly.
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD should not eat mouse events.
	add_child(root_ctrl)

	# -- SCORE label (top-left) --
	_lbl_score = Label.new()
	_lbl_score.text = "SCORE  0"
	_lbl_score.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lbl_score.position = Vector2(16.0, 12.0)
	root_ctrl.add_child(_lbl_score)

	# -- BALLS label (top-right) --
	_lbl_balls = Label.new()
	_lbl_balls.text = "BALLS  3"
	_lbl_balls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Offset left from the right edge so the text is not clipped.
	_lbl_balls.position = Vector2(-160.0, 12.0)
	root_ctrl.add_child(_lbl_balls)

	# -- MESSAGE label (bottom-centre) --
	_lbl_msg = Label.new()
	_lbl_msg.text = ""
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lbl_msg.position = Vector2(0.0, -80.0)
	root_ctrl.add_child(_lbl_msg)

	# -- POWER METER (bottom-left) --
	# The meter is two overlapping ColorRects: a grey background bar and a coloured fill on top.
	var meter_bg := ColorRect.new()
	meter_bg.color = Color(0.25, 0.25, 0.25)  # Dark grey background.
	meter_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	meter_bg.position = Vector2(16.0, -48.0)
	meter_bg.size = Vector2(METER_BAR_WIDTH, METER_BAR_HEIGHT)
	root_ctrl.add_child(meter_bg)

	_meter_fill = ColorRect.new()
	_meter_fill.color = METER_COLOR_LOW
	_meter_fill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_meter_fill.position = Vector2(16.0, -48.0)
	_meter_fill.size = Vector2(0.0, METER_BAR_HEIGHT)  # Starts empty (zero power).
	root_ctrl.add_child(_meter_fill)

	# Meter label above the bar so the player knows what it represents.
	var lbl_meter_tag := Label.new()
	lbl_meter_tag.text = "LAUNCH POWER"
	lbl_meter_tag.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lbl_meter_tag.position = Vector2(16.0, -68.0)
	root_ctrl.add_child(lbl_meter_tag)

	# -- GAME OVER PANEL (hidden by default, shown via show_game_over) --
	_pnl_game_over = PanelContainer.new()
	_pnl_game_over.set_anchors_preset(Control.PRESET_CENTER)
	# Give the panel a fixed size large enough for the game-over text.
	_pnl_game_over.size = Vector2(480.0, 140.0)
	# Centre the panel by offsetting half its size from the anchor point.
	_pnl_game_over.position = Vector2(-240.0, -70.0)
	_pnl_game_over.visible = false
	root_ctrl.add_child(_pnl_game_over)

	_lbl_game_over = Label.new()
	_lbl_game_over.text = ""
	_lbl_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_game_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_game_over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pnl_game_over.add_child(_lbl_game_over)

## Update the score display. Receives score_changed(score) from GameFlow. STABLE SIGNATURE.
func set_score(score: int) -> void:
	_lbl_score.text = "SCORE  %d" % score

## Update the ball count display. Receives balls_changed(balls) from GameFlow. STABLE SIGNATURE.
func set_balls(balls: int) -> void:
	_lbl_balls.text = "BALLS  %d" % balls

## Draw the launch power meter. power is 0..1, matching the Plunger's power_changed signal.
## The fill width scales linearly and the colour lerps from green (low) to red (high) so the player
## can read their charge level at a glance without looking at numbers. STABLE SIGNATURE.
func set_meter(power: float) -> void:
	var clamped: float = clampf(power, 0.0, 1.0)
	_meter_fill.size.x = METER_BAR_WIDTH * clamped
	_meter_fill.color = METER_COLOR_LOW.lerp(METER_COLOR_HIGH, clamped)

## Display a status message (e.g. "BALL DRAINED", "HOLD LAUNCH - release to fire", or "").
## Receives message(text) from GameFlow. An empty string clears the line. STABLE SIGNATURE.
func set_message(text: String) -> void:
	_lbl_msg.text = text

## Show the game-over panel with the final score and a clear restart prompt.
## Receives game_over(final_score) from GameFlow. STABLE SIGNATURE.
func show_game_over(final_score: int) -> void:
	_lbl_game_over.text = (
		"GAME OVER\n" +
		"SCORE  %d\n" % final_score +
		"press LAUNCH to restart"
	)
	_pnl_game_over.visible = true

## Hide the game-over panel (called by table.gd / GameFlow when restart() fires). STABLE SIGNATURE.
func hide_game_over() -> void:
	_pnl_game_over.visible = false
