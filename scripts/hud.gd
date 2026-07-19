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
##   Bottom-left: power meter bar (Kenney trough art + a ColorRect fill, green->red, width primary)
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
## keep the color lerp as a redundant cue for sighted players; the Kenney meter-frame art (see
## METER_FRAME_*_PATH below) supplies the high-contrast trough edge that used to be a hand-drawn
## outline, so the WIDTH cue still reads clearly against any background regardless of hue.
const METER_COLOR_LOW: Color = Color(0.2, 0.85, 0.2)    ## Green - low power (secondary cue).
const METER_COLOR_HIGH: Color = Color(0.9, 0.15, 0.15)  ## Red - high power (secondary cue).

## HUD font size (SLICE "Playtest fixes 2", UX item 8): the default Label font was too small to read
## at a glance on the deployed build. Bump every HUD label to this size. The game-over panel uses a
## slightly larger size (GAME_OVER_FONT_SIZE) so it reads as the headline.
const HUD_FONT_SIZE: int = 28
const TITLE_FONT_PATH: String = "res://assets/fonts/title.ttf"  ## CHLORINP, the backbox banner
const GAME_OVER_FONT_SIZE: int = 34

# --- Kenney UI kit (SLICE "Kenney baseline COMPLETION", UX front) -------------------------------
## The HUD reskin swaps the old placeholder OPTIPinBall font and hand-drawn ColorRect meter chrome
## for the frozen Kenney baseline (docs/assets/KENNEY_BASELINE_MANIFEST.json). Two typefaces, one
## role each, per the design brief: Kenney Future (regular width) for the SCORE readout - the one
## number a player reads mid-flip, so it gets the more legible face for digits - and Kenney Future
## Narrow for every other label (BALLS, HIGH, LAUNCH POWER, messages, game over), which is compact
## enough to fit the backbox column without wrapping. Both are CC0 (kenney.nl), which also retires
## the previously UNVERIFIED-license OPTIPinBall font from this HUD (see CREDITS.md).
const KENNEY_FUTURE_FONT_PATH: String = "res://assets/kenney/baseline/fonts/kenney_future.ttf"
const KENNEY_FUTURE_NARROW_FONT_PATH: String = (
	"res://assets/kenney/baseline/fonts/kenney_future_narrow.ttf"
)

## The backbox readout panel's background art (Kenney UI Pack - Sci-fi "metalPanel"), applied as a
## StyleBoxTexture 9-slice so it stretches to fit the column without smearing the rounded corners /
## rivets. SCORE_PANEL_MARGIN is the pixel inset (native 100x100 art) that the corner/rivet detail
## occupies - measured from the source texture so the 9-slice never stretches that detail.
const SCORE_PANEL_TEXTURE_PATH: String = "res://assets/kenney/baseline/ui/score_panel.png"
const SCORE_PANEL_MARGIN: float = 20.0
## The Kenney panel art ships as a light silver metal plate. self_modulate (which, unlike modulate,
## does NOT tint child labels) darkens it toward the HUD's existing dark-navy family so the
## established light-blue/white text stays high contrast, while the multiply keeps the rivets/
## corner bevel visible as a subtle darker fleck - a "riveted backbox plate" read, not a flat swap.
const SCORE_PANEL_TINT: Color = Color(0.16, 0.17, 0.26, 1.0)

## The launch-power meter's trough art (Kenney UI Pack - Sci-fi horizontal bar), assembled from a
## fixed left/right end cap plus a stretchable middle segment so it scales to METER_BAR_WIDTH
## cleanly. Native art is 26px tall; METER_FRAME_HEIGHT/CAP_WIDTH scale it up (~1.23x) to match the
## HUD's font scale while keeping the caps' original proportions.
const METER_FRAME_LEFT_PATH: String = "res://assets/kenney/baseline/ui/meter_bar_left.png"
const METER_FRAME_MID_PATH: String = "res://assets/kenney/baseline/ui/meter_bar_mid.png"
const METER_FRAME_RIGHT_PATH: String = "res://assets/kenney/baseline/ui/meter_bar_right.png"
const METER_FRAME_HEIGHT: float = 32.0
const METER_FRAME_CAP_WIDTH: float = 8.0
## The fill sits INSET inside the trough (clear of the end caps and the top/bottom bevel) so it
## reads as "liquid inside the gauge", not a bar drawn on top of the frame. The fill's own max
## width is therefore narrower than METER_BAR_WIDTH - this is still the WIDTH-as-primary-signal cue
## (UX item 7, colorblind-safe rule): empty at power 0, fully spans the inset trough at power 1,
## monotonic and unambiguous with no dependency on color.
const METER_FILL_INSET_Y: float = 4.0
const METER_FILL_MAX_WIDTH: float = METER_BAR_WIDTH - METER_FRAME_CAP_WIDTH * 2.0

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
	# top-right CORNER (both horizontal anchors at 1.0) with a FIXED min width, growing LEFT and DOWN
	# to fit its content. WHY a fixed width instead of a percentage span: the labels do not wrap and
	# have no min size, so a percentage-width panel could clip a long SCORE / the banner on a narrow
	# window; a fixed 340px panel is always wide enough and never clips (it grows left further if
	# content exceeds).
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
	_style_readout_panel(box)
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
	_apply_score_font(_lbl_score, 38)
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
	# tag plus a fixed-width bar (Kenney trough art + a coloured fill) centred in the column.
	var lbl_meter_tag := Label.new()
	lbl_meter_tag.text = "LAUNCH POWER"
	lbl_meter_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font_size(lbl_meter_tag, 18)
	col.add_child(lbl_meter_tag)

	var meter_holder := Control.new()
	meter_holder.custom_minimum_size = Vector2(METER_BAR_WIDTH, METER_FRAME_HEIGHT)
	meter_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(meter_holder)

	# Trough art: a fixed left cap, a middle segment stretched to fill the remaining width, a fixed
	# right cap - the standard way to scale a small 9-slice-style bar asset to an arbitrary width
	# without distorting its end caps. An HBoxContainer does the width bookkeeping for us.
	var meter_frame := HBoxContainer.new()
	meter_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	meter_frame.add_theme_constant_override("separation", 0)
	meter_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter_holder.add_child(meter_frame)
	_add_meter_cap(meter_frame, METER_FRAME_LEFT_PATH, METER_FRAME_CAP_WIDTH, false)
	_add_meter_cap(meter_frame, METER_FRAME_MID_PATH, 0.0, true)
	_add_meter_cap(meter_frame, METER_FRAME_RIGHT_PATH, METER_FRAME_CAP_WIDTH, false)

	# The fill sits ON TOP of the trough art, inset clear of the end caps (see METER_FILL_MAX_WIDTH).
	_meter_fill = ColorRect.new()
	_meter_fill.color = METER_COLOR_LOW
	_meter_fill.position = Vector2(METER_FRAME_CAP_WIDTH, METER_FILL_INSET_Y)
	_meter_fill.size = Vector2(0.0, METER_FRAME_HEIGHT - METER_FILL_INSET_Y * 2.0)  # empty at power 0
	meter_holder.add_child(_meter_fill)

	# -- GAME OVER PANEL (hidden by default, shown via show_game_over) --
	_pnl_game_over = PanelContainer.new()
	_pnl_game_over.set_anchors_preset(Control.PRESET_CENTER)
	# Give the panel a fixed size large enough for the game-over text.
	_pnl_game_over.size = Vector2(480.0, 140.0)
	# Centre the panel by offsetting half its size from the anchor point.
	_pnl_game_over.position = Vector2(-240.0, -70.0)
	_pnl_game_over.visible = false
	_style_readout_panel(_pnl_game_over)  ## same Kenney backbox-plate look as the scoreboard
	root_ctrl.add_child(_pnl_game_over)

	_lbl_game_over = Label.new()
	_lbl_game_over.text = ""
	_lbl_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_game_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_game_over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font_size(_lbl_game_over, GAME_OVER_FONT_SIZE)
	_pnl_game_over.add_child(_lbl_game_over)


## Apply a font size + the Kenney LABEL typeface (Future Narrow) to a Label. WHY a helper: every HUD
## label needs the same readable size (UX item 8) and the same face; centralizing it keeps the size/
## font policy in one place. load() (not preload) so a missing font degrades to the engine default
## instead of failing the scene.
func _apply_font_size(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	var font: Resource = load(KENNEY_FUTURE_NARROW_FONT_PATH)
	if font is Font:
		label.add_theme_font_override("font", font)


## Apply a font size + the Kenney NUMERAL typeface (Future, regular width) to a Label. Used only for
## the SCORE readout (see _build_ui): the score is the one number a player reads at a glance
## mid-flip, and the regular-width face is more legible for digits than the narrower label face.
func _apply_score_font(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	var font: Resource = load(KENNEY_FUTURE_FONT_PATH)
	if font is Font:
		label.add_theme_font_override("font", font)


## Style a PanelContainer (the backbox scoreboard, the game-over panel) with the Kenney metal-panel
## art via a StyleBoxTexture 9-slice, tinted dark (see SCORE_PANEL_TINT) to match the HUD's existing
## palette. Falls back to the previous hand-drawn flat panel if the texture is missing, so a broken
## asset path degrades gracefully instead of leaving the HUD panel invisible.
func _style_readout_panel(panel: PanelContainer) -> void:
	var tex: Resource = load(SCORE_PANEL_TEXTURE_PATH)
	if tex is Texture2D:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = SCORE_PANEL_MARGIN
		sb.texture_margin_right = SCORE_PANEL_MARGIN
		sb.texture_margin_top = SCORE_PANEL_MARGIN
		sb.texture_margin_bottom = SCORE_PANEL_MARGIN
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		panel.add_theme_stylebox_override("panel", sb)
		panel.self_modulate = SCORE_PANEL_TINT  ## self_modulate only tints THIS node, not its labels
	else:
		var fallback := StyleBoxFlat.new()
		fallback.bg_color = Color(0.02, 0.02, 0.07, 0.96)
		fallback.border_color = Color(0.45, 0.45, 0.62)
		fallback.set_border_width_all(3)
		fallback.set_corner_radius_all(8)
		fallback.content_margin_left = 12.0
		fallback.content_margin_right = 12.0
		fallback.content_margin_top = 10.0
		fallback.content_margin_bottom = 10.0
		panel.add_theme_stylebox_override("panel", fallback)


## Add one piece of the meter-trough art to the frame row. `fixed_width` > 0 gives the piece that
## exact width (the end caps); `expand` true lets it grow to fill the remaining row width (the
## middle segment). Texture load() degrades to an invisible (untextured) TextureRect if the asset
## is missing rather than failing the scene - the fill on top still reads the power either way.
func _add_meter_cap(row: HBoxContainer, path: String, fixed_width: float, expand: bool) -> void:
	var piece := TextureRect.new()
	var tex: Resource = load(path)
	if tex is Texture2D:
		piece.texture = tex
	piece.stretch_mode = TextureRect.STRETCH_SCALE
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		piece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		piece.custom_minimum_size = Vector2(0.0, METER_FRAME_HEIGHT)
	else:
		piece.custom_minimum_size = Vector2(fixed_width, METER_FRAME_HEIGHT)
	row.add_child(piece)


## Show or instantly hide the whole HUD. Hidden in the main menu and BUILD mode so only the editor
## UI is visible there; shown for PLAY. Modulate is reset to fully opaque when shown without a fade.
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
## The fill WIDTH is the PRIMARY, colorblind-safe cue (UX item 7): it scales linearly from empty at
## power 0 to fully spanning the inset trough (METER_FILL_MAX_WIDTH) at power 1, monotonic and
## legible with no dependency on color. The green->red lerp is a secondary cue for sighted players.
## STABLE SIGNATURE.
func set_meter(power: float) -> void:
	var clamped: float = clampf(power, 0.0, 1.0)
	_meter_fill.size.x = METER_FILL_MAX_WIDTH * clamped
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
