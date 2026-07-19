# Credits and asset attribution

This file lists third-party assets used in the game and the licenses they ship under. Every entry
here must be kept current so a commercial release is on solid legal footing. House rule: no asset
goes into assets/ without a line in this file.

## 3D models

### Custom low-poly element family (assets/models/)
Files: `flipper_bat.glb`, `mini_flipper.glb`, `pop_bumper.glb`, `launcher.glb`, `wall.glb`,
`left_slingshot.glb`.
- Source: original low-poly models created in Blender for this project (the matched stylized
  flat-shaded blue-cap family). They REPLACE the earlier borrowed art (the vbousquet/pinball-parts
  flipper bat and the older bumper_body.glb, both removed from the repo).
- License: original project work; no third-party attribution required.
- Modified: exported to glTF 2.0 .glb. The art carries NO collision geometry: every element's collider
  is a primitive shape built in code (the flipper / mini-flipper convex hull, the pop bumper
  CylinderShape3D, the wall BoxShape3D, the slingshot ConvexPolygonShape3D) or, for the launcher, the
  AnimatableBody3D strike face. Object names: flipper_bat (Flipper_Bat, Flipper_Rubber); mini_flipper
  (Flipper_Bat_Mini, Flipper_Rubber_Mini); pop_bumper (Bumper_Base, Bumper_Body, Bumper_Cap); launcher
  (Box_* housing + Plunger_Anim{Rod,Tip,Clip} + Plunger_Spring); wall (Wall_Body, Wall_Cap).

### Kenney asset packs (assets/kenney/baseline/)
Files: every model, texture, UI image, font, and audio clip under `assets/kenney/baseline/`
(3D Kit `models/*.glb` and `models/Textures/colormap.png`, `textures/*.png`, `ui/*.png`,
`fonts/kenney_future*.ttf`, `audio/*.ogg`), copied unmodified from the Kenney.nl asset packs into
this repo per the frozen baseline manifest (docs/assets/KENNEY_BASELINE_MANIFEST.json, kept local
per this repo's docs/ policy).
- Source: Kenney (kenney.nl) - Minigolf Kit, UI Pack (Sci-fi), Kenney Fonts, and the Kenney audio
  packs (UI Audio / Impact Sounds / Music Jingles).
- License: CC0 1.0 Universal (public domain dedication) - https://kenney.nl/assets - no attribution
  legally required, credited here anyway as house policy and good practice.
- Modified: none (used as shipped by Kenney); imported into Godot's own resource format by the
  headless importer (the `.import` sidecars alongside each file, engine-generated).

### Custom-authored mushroom-cap pop bumper (assets/kenney/baseline/models/mushroom_bumper.glb)
- Source: original model, built from scratch in Blender for this project (a low-poly domed cap
  overhanging a post, in the flat faceted Kenney style) to replace the Minigolf Kit's `bump.glb`,
  which read as a plain square rather than a pop bumper at gameplay zoom. The Kenney pinball-parts
  reference set (see below) was used as a PROPORTION reference only; no geometry was copied from it.
- License: original project work; no third-party attribution required.
- Modified: exported to glTF 2.0 .glb, no collision geometry (the bumper's collider is the existing
  primitive shape built in code, per the project's art-mesh-is-never-a-collider rule).

### Imported parts (wire guides, flat rails, bottom lane guides, drop/react targets)
Files: `wire_guide_1in_thin.glb`, `wire_guide_1in_thick.glb`, `wire_guide_2in_thin.glb`,
`flat_rail_brackets.glb`, `flat_rail_bezier.glb`, `bottom_lane_guide_left.glb`,
`bottom_lane_guide_right.glb`, `drop_target.glb`, `react_target_thin.glb` (all under assets/models/).
- Derived from: github.com/vbousquet/pinball-parts. The mesh node names inside the files
  ("Gottlieb", "DE Sega Stern", "Williams/Bally") identify them as parts from that library.
- License: Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)
- Modified: exported to glTF 2.0 .glb with collision geometry.
- ACTION: confirm none of these were modelled from scratch (if any are original, move them out of this
  entry). ShareAlike means any further-modified derivative of these models is itself CC BY-SA 4.0.

## Fonts

WARNING - a COMMERCIAL release EMBEDS these fonts in the shipped build, so each must be licensed for
BOTH commercial use AND embedding/redistribution. The entries below are UNVERIFIED. Confirm each
license (or swap in an open-licensed alternative such as an SIL OFL font) BEFORE selling the game.

### HUD score/text (assets/fonts/hud.otf) - "OPTIPinBall" - NO LONGER USED
- Source: downloaded. Part of the "OPTI" family (Castcraft Software). License for commercial
  embedding: UNVERIFIED - many "OPTI" fonts are redistributed without clear commercial terms.
- STATUS: hud.gd no longer loads this font (replaced by the CC0 Kenney Future / Kenney Future Narrow
  faces below, see the Kenney asset packs entry above). The .otf file is left on disk in case another
  surface still needs it; if nothing references it after a full grep, delete the file and this entry
  removes the licensing risk entirely.

### Title banner (assets/fonts/title.ttf) - "Chlorinar / CHLORINP"
- Source: downloaded freeware. Commercial-use + embedding license: UNVERIFIED.

### Button text (assets/fonts/button.ttf) - "Schwarzenberg Italic"
- Source: downloaded. Commercial-use + embedding license: UNVERIFIED. Still used by
  layout_editor.gd's BUILD-mode developer tool panel (the player-facing menu/play-bar buttons now
  use the CC0 Kenney Future Narrow face instead, see the Kenney asset packs entry above).

## Notes
- CC BY-SA 4.0 license text: https://creativecommons.org/licenses/by-sa/4.0/
- ShareAlike applies to the derived MODELS, not to the rest of the game's original code/content.
