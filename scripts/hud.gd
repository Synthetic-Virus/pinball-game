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
const HUD_FONT_PATH: String = "res://assets/fonts/hud.otf"  ## OPTIPinBall, developer-supplied
const TITLE_FONT_PATH: String = "res://assets/fonts/title.ttf"  ## CHLORINP, the backbox banner
const GAME_OVER_FONT_SIZE: int = 34

# --- Node references (assigned in _ready) ---
var _root: Control          ## the full-rect root control; visibility + fade are applied here
var _lbl_score: Label
var _lbl_balls: Label
var _lbl_high: Label         ## backbox high-score line (best score this session)
var _high_score: int = 0     ## tracked across balls so the backbox can show a running best
var _lbl_msg: Label
var _meter_fill: ColorRect   # The coloured fill portion of the power meter bar.
var _pnl_game_over: PanelContainer
var _lbl_game_over: Label

func _ready() -> void:
	_build_ui()

## Build the entire UI tree in code. This keeps the HUD self-contained (no separate .tscn to
## maintain) and makes the node references explicit and easy to follow for a non-expert reader.
func _build_ui() -> void:
	# Root control that fills the viewport so anchored children position correctly. Stored so the HUD
	# can be shown/hidden per game mode and faded in when play starts.
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD should not eat mouse events.
	add_child(root_ctrl)
	_root = root_ctrl

	# -- BACKBOX scoreboard (the "head"): a framed dark panel on the RIGHT with the banner, score, ball
	# count, a message line, and the session high score. The table is panned LEFT in play mode (see
	# table.set_play_view) so this panel does not cover the playfield.
	var box := PanelContainer.new()
	# TOP-RIGHT aligned (developer: "scoreboard should be right aligned at the top"). Pinned to the
	# top-right CORNER (both horizontal anchors at 1.0) with a FIXED min width, growing LEFT and DOWN to
	# fit its content. WHY a fixed width instead of a percentage span: the labels do not wrap and have no
	# min size, so a percentage-width panel could clip a long SCORE / the banner on a narrow window; a
	# fixed 340px panel is always wide enough and never clips (it grows left further if content exceeds).
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN  ## expand LEFT from the right edge
	box.grow_vertical = Control.GROW_DIRECTION_END      ## expand DOWN from the top
	box.custom_minimum_size = Vector2(340.0, 0.0)       ## wide enough for a long SCORE at 38px
	box.offset_left = 0.0
	box.offset_right = -10.0  ## small margin off the right edge
	box.offset_top = 8.0
	box.offset_bottom = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.07, 0.96)
	sb.border_color = Color(0.45, 0.45, 0.62)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	box.add_theme_stylebox_override("panel", sb)
	root_ctrl.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)

	# Banner (the table name) in the title typeface.
	var banner := Label.new()
	banner.text = "PINBALL"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 44)
	var title_font: Resource = load(TITLE_FONT_PATH)
	if title_font is Font:
		banner.add_theme_font_override("font", title_font)
	col.add_child(banner)

	# SCORE (large, accent colour) - the headline number.
	_lbl_score = Label.new()
	_lbl_score.text = "SCORE  0"
	_lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_size(_lbl_score, 38)
	_lbl_score.add_theme_color_override("font_color", Color(0.55, 0.72, 1.0))
	col.add_child(_lbl_score)

	# BALL count.
	_lbl_balls = Label.new()
	_lbl_balls.text = "BALLS  3"
	_lbl_balls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_size(_lbl_balls, HUD_FONT_SIZE)
	col.add_child(_lbl_balls)

	# MESSAGE line (launch prompt, drain messages...).
	_lbl_msg = Label.new()
	_lbl_msg.text = ""
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font_size(_lbl_msg, 22)
	_lbl_msg.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0))
	col.add_child(_lbl_msg)

	# HIGH score (best this session).
	_lbl_high = Label.new()
	_lbl_high.text = "HIGH  0"
	_lbl_high.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_size(_lbl_high, 22)
	col.add_child(_lbl_high)

	# -- LAUNCH POWER meter, INSIDE the backbox (was bottom-left, "way far down" from the table). A
	# tag plus a fixed-width bar (outline + grey background + coloured fill) centred in the column.
	var lbl_meter_tag := Label.new()
	lbl_meter_tag.text = "LAUNCH POWER"
	lbl_meter_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_size(lbl_meter_tag, 18)
	col.add_child(lbl_meter_tag)

	var meter_holder := Control.new()
	meter_holder.custom_minimum_size = Vector2(
		METER_BAR_WIDTH + METER_OUTLINE_WIDTH * 2.0, METER_BAR_HEIGHT + METER_OUTLINE_WIDTH * 2.0
	)
	meter_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(meter_holder)

	var meter_outline := ColorRect.new()
	meter_outline.color = METER_OUTLINE_COLOR
	meter_outline.position = Vector2.ZERO
	meter_outline.size = Vector2(
		METER_BAR_WIDTH + METER_OUTLINE_WIDTH * 2.0, METER_BAR_HEIGHT + METER_OUTLINE_WIDTH * 2.0
	)
	meter_holder.add_child(meter_outline)

	var meter_bg := ColorRect.new()
	meter_bg.color = Color(0.25, 0.25, 0.25)
	meter_bg.position = Vector2(METER_OUTLINE_WIDTH, METER_OUTLINE_WIDTH)
	meter_bg.size = Vector2(METER_BAR_WIDTH, METER_BAR_HEIGHT)
	meter_holder.add_child(meter_bg)

	_meter_fill = ColorRect.new()
	_meter_fill.color = METER_COLOR_LOW
	_meter_fill.position = Vector2(METER_OUTLINE_WIDTH, METER_OUTLINE_WIDTH)
	_meter_fill.size = Vector2(0.0, METER_BAR_HEIGHT)  # Starts empty (zero power).
	meter_holder.add_child(_meter_fill)

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
	# The developer-supplied pinball typeface (OPTIPinBall). load() so a missing font degrades to the
	# engine default instead of failing the scene.
	var font: Resource = load(HUD_FONT_PATH)
	if font is Font:
		label.add_theme_font_override("font", font)


## Show or instantly hide the whole HUD. Hidden in the main menu and BUILD mode so only the editor UI
## is visible there; shown for PLAY. Modulate is reset to fully opaque when shown without a fade.
func set_shown(shown: bool) -> void:
	if _root == null:
		return
	_root.visible = shown
	if shown:
		_root.modulate.a = 1.0


## Fade the HUD in from transparent - used when play starts so the display eases in with the table.
func fade_in(duration: float = 0.6) -> void:
	if _root == null:
		return
	_root.visible = true
	_root.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, duration)


## Update the score display. Receives score_changed(score) from GameFlow. STABLE SIGNATURE.
func set_score(score: int) -> void:
	_lbl_score.text = "SCORE  %d" % score
	if score > _high_score:
		_high_score = score
		if _lbl_high != null:
			_lbl_high.text = "HIGH  %d" % _high_score

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
