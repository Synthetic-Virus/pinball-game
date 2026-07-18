class_name Palette
extends RefCounted
## Palette - the SINGLE typed source of truth for the table's colour identity (SLICE A2 reskin).
##
## WHY THIS FILE EXISTS: before this slice, colours were scattered as raw Color(...) literals inside
## the element scripts (table_geometry.gd, pop_bumper.gd, slingshot.gd, target.gd). That makes a
## palette change a hunt-and-peck edit across many physics-bearing files. This module gathers the
## table-surface colours in ONE place so (a) a reskin is a one-file edit, (b) the future in-game
## table editor has a single object to bind to, and (c) the reskin can be APPLIED from visual-only
## files (table_reskin.gd / scoring_reskin.gd) that never touch a collider, kick vector, or layout.
##
## LOCKED PALETTE DIRECTION (designer, do NOT re-litigate the hues, only tune the exact values for
## legibility on the artifact shot): bright Kenney BLUE playfield (a receded ground so the ball and
## the furniture pop against it), WHITE walls/rails/apron (a calm structural frame), and a RED
## accent on the SCORING furniture (targets, pop bumpers, slingshots) that reads as "aim here".
## Contrast hierarchy that every value must preserve: BALL > FURNITURE > FIELD.
##
## WHAT THIS MODULE DOES NOT COLOUR (frozen on purpose - do not add entries that repaint these):
##   - The BALL: it stays the highest-contrast object on the table (its own material, untouched).
##   - The FLIPPERS: the black-body / white-rubber-top two-tone took several slices to get right on
##     BOTH bats. The reskin must NOT repaint it. table_reskin.gd never walks a flipper node.
##   - The DRAIN mouth / outlanes: they stay dark / open so a drain still reads as LOSS, never
##     painted the same calm white as a safe wall.
##
## HOUSE STYLE: typed const Color, UPPER_SNAKE to match table_config.gd / flipper.gd (BODY_COLOR,
## RUBBER_TOP_COLOR). Flat albedo only - see flat_material(): no emission (invisible in the web
## build), no metal, no gloss, no transparency that would fight the low-poly read or hide the ball.

# --- STRUCTURAL FRAME ----------------------------------------------------------------------------

## The playfield surface. Bright Kenney blue, but deliberately DEEPER than a pure sky blue so the
## white ball and the white frame pop against it (must-feel #1: the ball stays the star). Tune this
## exact value on the PLAY-screen artifact shot; the direction (blue, receded) is locked.
const PLAYFIELD: Color = Color(0.14, 0.44, 0.78)

## Outer walls / borders / lane divider. A calm near-white (not pure 1.0, which blows out and
## flattens the faceted low-poly read). White = boundary; it recedes so the eye finds the accent.
const WALLS: Color = Color(0.93, 0.94, 0.96)

## Inlane / outlane / editor-drawn guide rails. Same white family as the walls but a shade cooler,
## so a rail reads as a distinct-but-related structural line, not a scoring element.
const RAILS: Color = Color(0.87, 0.90, 0.94)

## The apron (the flat lower deck around the flippers / plunger). White family, a touch darker than
## the walls so it reads as a surface plane rather than a wall edge. RESERVED: there is no dedicated
## apron body in the current gray-box geometry; this entry is the contract for when one is added.
const APRON: Color = Color(0.80, 0.84, 0.89)

# --- SCORING ACCENT ------------------------------------------------------------------------------

## The "aim here" red for the SCORING furniture (targets, pop bumpers, slingshots). This is the one
## colour that teaches a new player where a hit is rewarded, so it must be the most saturated hue on
## the table after the ball. Red = aim; white = boundary; blue = ground.
const SCORING_ACCENT: Color = Color(0.86, 0.16, 0.16)

## Slingshots are scoring furniture, so they share the accent red. Kept as a NAMED entry (the
## designer listed slingshots explicitly) so the applier and the future editor can address them
## distinctly if the direction ever splits the sling hue from the target/bumper hue.
const SLINGSHOT_ACCENT: Color = SCORING_ACCENT

# --- OPTIONAL PLAYFIELD ACCENT TEXTURE -----------------------------------------------------------

## pattern_01 from the imported Kenney baseline library. This is the ONE optional accent texture,
## applied to the playfield ONLY IF it demonstrably reads at gameplay zoom on the artifact shot
## (must-feel #6) and does not compete with the ball. The DEFAULT is flat PLAYFIELD blue; the burden
## of proof is on the texture. The other five imported PNGs are the held library, not applied here.
const PLAYFIELD_ACCENT_TEXTURE_PATH: String = "res://assets/kenney/baseline/textures/pattern_01.png"


## Build a FLAT albedo StandardMaterial3D for `color`. This is the ONE place that guarantees the
## reskin stays flat: fully matte (roughness 1.0), non-metallic, no specular pip, NO emission
## (emission reads as invisible in the web build), and fully opaque (transparency would let the
## field bleed through and hurt ball tracking). Every reskin applier builds its materials through
## this helper, so a single edit here re-flattens the whole table. The faceted low-poly LOOK comes
## from the meshes' own normals; this material only removes shine, it does not smooth anything.
static func flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 1.0
	# Kill the default 0.5 specular so flat plastic has no shiny highlight dot under the play light.
	mat.metallic_specular = 0.0
	# Leave emission disabled and transparency off (the StandardMaterial3D defaults) on purpose:
	# albedo is the only channel that renders reliably in the web export.
	return mat
