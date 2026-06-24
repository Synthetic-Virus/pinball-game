# Credits and asset attribution

This file lists third-party assets used in the game and the licenses they ship under. Every entry
here must be kept current so a commercial release is on solid legal footing. House rule: no asset
goes into assets/ without a line in this file.

## 3D models

### Flipper bat (assets/models/flipper_bat.glb)
- Derived from: github.com/vbousquet/pinball-parts
- License: Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)
- Modified: yes (re-modelled / adjusted in Blender, then exported to glTF 2.0 .glb)
- Terms honored: commercial use is permitted; attribution is given here; ShareAlike means any
  further-modified derivative of THIS model is itself licensed CC BY-SA 4.0. The two embedded
  materials ("Bat - Plastic White" body, "Bat - Rubber Blue" rubber) ship with the model.

### Pop bumper (assets/models/bumper_body.glb)
- Source: original model created in Blender for this project (PinballBumperModel.blend).
- License: original project work; no third-party attribution required.
- Modified: exported to glTF 2.0 .glb (mushroom body+cap; origin at the base, cap up). Replaced the
  earlier vbousquet/pinball-parts bumper. The collision shape is a native CylinderShape3D built in
  code (scripts/pop_bumper.gd), so no collision mesh ships with this model, and the cap is rendered
  slightly wider than that collider so the ball tucks under the lid.

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

### HUD score/text (assets/fonts/hud.otf) - "OPTIPinBall"
- Source: downloaded. Part of the "OPTI" family (Castcraft Software). License for commercial
  embedding: UNVERIFIED - many "OPTI" fonts are redistributed without clear commercial terms.

### Title banner (assets/fonts/title.ttf) - "Chlorinar / CHLORINP"
- Source: downloaded freeware. Commercial-use + embedding license: UNVERIFIED.

### Button text (assets/fonts/button.ttf) - "Schwarzenberg Italic"
- Source: downloaded. Commercial-use + embedding license: UNVERIFIED.

## Notes
- CC BY-SA 4.0 license text: https://creativecommons.org/licenses/by-sa/4.0/
- ShareAlike applies to the derived MODELS, not to the rest of the game's original code/content.
