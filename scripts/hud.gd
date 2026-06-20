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

## Width of the power meter bar in pixels. Chosen to be readable at 1080p without being obtrusive.
## RESIZE (SLICE "Playtest fixes 2", UX item 7): wider so the WIDTH cue (the colorblind-safe primary
## encoding of power) is easy to read.
const METER_BAR_WIDTH: float = 240.0
const METER_BAR_HEIGHT: float = 28.0

## Colour gradient for the meter: green at 0, red at 1. UX item 7 (SLICE "Playtest fixes 2"):
## COLORBLIND-SAFE. Color is now a SECONDARY cue only - the bar WIDTH (set in set_meter) is the
## PRIMARY encoding of power, so a colorblind player reads the charge from the bar LENGTH alone. We
## keep the color lerp as a redundant cue for sighted players, and add a high-contrast OUTLINE round
## the meter so the filled length is legible against any background regardless of hue.
const METER_COLOR_LOW: Color = Color(0.2, 0.85, 0.2)    ## Green - low power (secondary cue).
const METER_COLOR_HIGH: Color = Color(0.9, 0.15, 0.15)  ## Red - high power (secondary cue).
## High-contrast outline drawn around the meter background so the WIDTH cue reads without color.
const METER_OUTLINE_COLOR: Color = Color(0.95, 0.95, 0.95)
const METER_OUTLINE_WIDTH: float = 2.0

## HUD font size (SLICE "Playtest fixes 2", UX item 8): the default Label font was too small to read
## at a glance on the deployed build. Bump every HUD label to this size. The game-over panel uses a
## slightly larger size (GAME_OVER_FONT_SIZE) so it reads as the headline.
const HUD_FONT_SIZE: int = 28
const GAME_OVER_FONT_SIZE: int = 34

# --- Node references (assigned in _ready) ---
var _lbl_score: Label
var _lbl_balls: Label
var _lbl_msg: Label
var _meter_fill: ColorRect   # The coloured fill portion of the power meter bar.
var _pnl_game_over: PanelContainer
var _lbl_game_over: Label

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
	_apply_font_size(_lbl_score, HUD_FONT_SIZE)
	root_ctrl.add_child(_lbl_score)

	# -- BALLS label (top-right) --
	_lbl_balls = Label.new()
	_lbl_balls.text = "BALLS  3"
	_lbl_balls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Offset left from the right edge so the text is not clipped (wider offset for the bigger font).
	_lbl_balls.position = Vector2(-200.0, 12.0)
	_apply_font_size(_lbl_balls, HUD_FONT_SIZE)
	root_ctrl.add_child(_lbl_balls)

	# -- MESSAGE label (bottom-centre) --
	_lbl_msg = Label.new()
	_lbl_msg.text = ""
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lbl_msg.position = Vector2(0.0, -100.0)
	_apply_font_size(_lbl_msg, HUD_FONT_SIZE)
	root_ctrl.add_child(_lbl_msg)

	# -- POWER METER (bottom-left) --
	# UX item 7 (colorblind-safe): the bar WIDTH is the primary power cue, reinforced by a high-
	# contrast OUTLINE so the filled LENGTH reads against any background without relying on color.
	# Layering (back to front): outline rect, grey background, coloured fill.
	var meter_outline := ColorRect.new()
	meter_outline.color = METER_OUTLINE_COLOR
	meter_outline.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	meter_outline.position = Vector2(16.0 - METER_OUTLINE_WIDTH, -48.0 - METER_OUTLINE_WIDTH)
	meter_outline.size = Vector2(
		METER_BAR_WIDTH + METER_OUTLINE_WIDTH * 2.0,
		METER_BAR_HEIGHT + METER_OUTLINE_WIDTH * 2.0
	)
	root_ctrl.add_child(meter_outline)

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
	lbl_meter_tag.position = Vector2(16.0, -84.0)
	_apply_font_size(lbl_meter_tag, HUD_FONT_SIZE)
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
	_apply_font_size(_lbl_game_over, GAME_OVER_FONT_SIZE)
	_pnl_game_over.add_child(_lbl_game_over)


## Apply a font size override to a Label. WHY a helper: every HUD label needs the same readable size
## (UX item 8), and a font_size theme override is the engine-default-font-safe way to set it without
## shipping a font resource. Centralizing it keeps the size policy in one place.
func _apply_font_size(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)

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
## UX item 6 (SLICE "Playtest fixes 2"): NAME the actual restart key. The restart action is the
## "launch" input action, bound to SPACE (see project.godot input map). "press LAUNCH to restart"
## ambiguous (there is no key labelled LAUNCH); naming SPACE tells the player exactly what to press.
func show_game_over(final_score: int) -> void:
	_lbl_game_over.text = (
		"GAME OVER\n" +
		"SCORE  %d\n" % final_score +
		"press SPACE to restart"
	)
	_pnl_game_over.visible = true

## Hide the game-over panel (called by table.gd / GameFlow when restart() fires). STABLE SIGNATURE.
func hide_game_over() -> void:
	_pnl_game_over.visible = false
