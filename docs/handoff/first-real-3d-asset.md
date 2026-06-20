# Handoff: SLICE "first-real-3d-asset" - the flipper bat as the first imported 3D asset

Owner of this doc: lead-programmer. Branch: slice/first-real-3d-asset (already created; stay on it).
This is foundation phase 2 from docs/specs/asset-data-driven-foundation.md (the asset-pipeline proof
on the most collider-sensitive element). Read DESIGN.md's slice brief and the spec's risks R2/R3/R4
first. This doc is the binding SEAM so the coders fill DIFFERENT files without conflict.

## The one-line shape of this slice
Swap ONLY the flipper's visible mesh from the procedural gray-box ArrayMesh to the imported
assets/models/flipper_bat.glb. The collider, the drive, the spring, the mass, the bounce, and every
flipper contract method stay byte-for-byte. Make CI Git-LFS-aware so the runner pulls the real .glb.

## What the lead already did (do NOT redo)
- Copied the asset to assets/models/flipper_bat.glb and VERIFIED it staged as a 130-byte LFS pointer
  (git lfs ls-files shows it; git cat-file -s on the staged blob = 130, not 33856). git-lfs is
  initialized in the repo (.git/hooks updated).
- Added `lfs: true` to every actions/checkout@v4 (ci.yml lint + test jobs, deploy-demo.yml). NOTE:
  the GUT GUI PNGs are ALSO LFS objects now, so lfs:true was already needed regardless.
- Added CREDITS.md (vbousquet/pinball-parts, CC BY-SA 4.0, modified).
- Scaffolded tests/test_flipper_asset_visual.gd (the asset-specific test stubs, all pending()).
- Did NOT generate the .glb .import file - Godot generates it on first import (the runner/headless
  import pass creates it). The Deliver phase commits the Godot-generated .import.

## NODE CONTRACT (the seam - stable, write code/tests against THIS)
The flipper tree stays as it is today, plus ONE new visual node. Tests find nodes by these names:

    Flipper (Node3D, at the pivot)
      FlipperBody (RigidBody3D)        <- FROZEN. mass 0.40, bounce 0.70, layers, CCD, all unchanged.
        CollisionShape3D               <- FROZEN. ConvexPolygonShape3D tapered hull. NEVER the art.
        FlipperMesh (MeshInstance3D)   <- the PROCEDURAL gray-box mesh. Stays. Becomes the HIDDEN
                                          fallback when the asset loads; SHOWN if the asset fails.
        FlipperVisual (MeshInstance3D) <- NEW. The imported .glb mesh, scaled+oriented to the
                                          collider. SHOWN when the asset loads; absent/hidden on
                                          fallback. This is the only NEW node.
      Pivot (HingeJoint3D)             <- FROZEN.

Why a SEPARATE FlipperVisual node instead of reassigning FlipperMesh.mesh:
- Keeps the procedural fallback fully intact and instantly swappable (visibility toggle), so a load
  failure is a one-line cosmetic downgrade, never a crash (DESIGN must-feel #4).
- Lets the legacy tests (test_flipper_shape.test_bat_has_a_visible_non_box_mesh,
  test_flipper_rubber_top) keep asserting the PROCEDURAL mesh unchanged - they look at FlipperMesh.
  The new imported-mesh assertions live in test_flipper_asset_visual.gd and look at FlipperVisual.
  This is what lets the legacy tests stay green WITHOUT editing them.

## SCALE: derive from the collider, never a literal (the spec's hard rule)
The asset is modelled in REAL METRES (~0.080 glTF units on its long axis). The game world uses a
LARGE world scale (FLIPPER_LENGTH = 7.0 world units, pivot to tip). So the imported mesh must be
enlarged a lot. Compute the factor at load:

    asset_long = (longest axis of the imported mesh's AABB, in the asset's own units)
    collider_long = TableConfig.FLIPPER_LENGTH   # the pivot-to-tip length the collider spans
    scale = collider_long / asset_long           # ONE uniform factor, applied to FlipperVisual

Apply `scale` uniformly to FlipperVisual. Add a comment stating: (1) the real-metres-asset vs
large-world-scale units gap, (2) that this self-corrects if the asset or world scale changes, (3)
that the scale is COSMETIC ONLY - it touches the visual node, never the collider, so a wrong scale
can only look off, never play wrong, and (4) the next asset uses this same derive-from-collider
pattern. Acceptable alternative: bake the SAME measured fit factor into the .glb .import in ONE
documented place. Either way: measured/derived, NEVER a hand-typed literal like 87.5.

Position + orient FlipperVisual so the bat's fat end sits at the pivot (this node's origin) and the
thin tip reaches along the collider's long axis. The collider's long axis runs along the bat's local
+X for the left flipper and -X for the mirrored right (see _apply_handedness / _rebuild_bat_geometry).
Align FlipperVisual to match. If the .glb's long axis or up axis differ from the collider frame, add
a fixed orientation correction (a rotation) with a comment - this is allowed (it is orientation, not
a magic SCALE number).

## MIRROR (both flippers, one asset)
Both flippers use the one .glb. The right is the mirror of the left. Mirror by a 180-degree ROTATION
about the pivot's vertical axis (the surface normal, this node's local +Y), NOT a negative-scale
reflection. A reflection inverts the normals and buries/inverts the blue rubber. The test
(test_right_flipper_visual_is_not_inside_out) asserts the visual node basis determinant is POSITIVE
(a proper rotation). Visually confirm blue rubber sits on TOP on BOTH sides via table_viz / a render
if available; the determinant test is the deterministic oracle.

## FALLBACK SEAM (so the fallback test does not delete the real asset)
Expose a test-only way to force an asset-load failure WITHOUT removing the file, mirroring the
existing _force_energized test-hook pattern in flipper.gd. Suggested:
- A const for the asset path used by load(), and a test-only setter `set_asset_path_for_test(path)`
  that, if set to "" or a bogus path before _build_flipper / configure, makes the load fail so the
  procedural fallback shows. Document it INERT in production (never called by table.gd). The
  test-builder uses it in test_fallback_to_procedural_when_asset_missing.

## FILE-OWNERSHIP MAP (parallel, no overlapping edits)
- physics-programmer OWNS (the visual swap lives in the physics file because the collider/handedness
  context lives there, but the COLLIDER must NOT change):
    - scripts/flipper.gd  -> add FlipperVisual node, load the .glb, derive+apply the scale, mirror by
      180 deg rotation, hide FlipperMesh when the asset loads, fall back on failure, add the test
      seam. DO NOT touch _shape, the hull, the drive, the spring, BAT_MASS, BAT_BOUNCE, the hinge,
      configure()/is_energized()/tip_speed()/force_energized(), or _apply_handedness's angle/limit/
      seating logic. Keep ALL of _build_bat_outline/_rebuild_bat_geometry/_build_bat_mesh as the
      fallback path.
    - scenes/elements/Flipper.tscn -> only if a node must be authored in-scene; prefer building
      FlipperVisual in code (consistent with how FlipperMesh is built today). If edited, keep it
      minimal.
  physics-programmer does NOT edit ball.gd / plunger.gd / scoring / game_flow for this slice (no
  gameplay change), but is the authority that the no-tunnel + momentum + rubber gates stay green.
- gameplay-programmer: NO gameplay-file changes are in scope for this slice (it is a pure visual +
  pipeline proof; no plunger/scoring/flow change). The gameplay-programmer's contribution is a
  REVIEW of the alignment (does the bat read right in-game, does table_viz still validate) and
  helping wire any render/screenshot validation if used. If table_viz needs a note that the flipper
  visual is now an asset, that is a gameplay/tools-side doc tweak ONLY (no logic change).
- test-builder OWNS:
    - tests/test_flipper_asset_visual.gd -> fill every pending() body against the node contract +
      scale rule + mirror rule + fallback seam above. Independent oracle only (real instanced tree,
      measured AABB/length, shape class), never a self-reported flag.
    - Keep these GREEN unchanged (they assert the FROZEN collider/drive/material/fallback mesh):
      test_flipper_no_tunneling.gd, test_flipper_momentum.gd, test_flipper_rubber.gd,
      test_flipper_rubber_top.gd. Update test_flipper_shape.gd ONLY if a body asserted the OLD
      procedural VISUAL as the shown mesh; its COLLIDER assertions (not-a-box, capsule/convex,
      keeps-rubber-material) MUST still hold. Because the procedural FlipperMesh stays present as the
      fallback, test_flipper_shape.test_bat_has_a_visible_non_box_mesh should still pass against
      FlipperMesh - confirm, do not pre-emptively edit.
- devops (lead already did the mechanical part): the runner must have git-lfs installed. Confirm
  `git lfs version` on the homelab godot runner (docs/INFRA.md). The .import for the .glb is
  generated by Godot's headless import pass; the Deliver phase commits it.

## TEST MATRIX (the bar for this slice)
| # | Class | Assertion | File | Owner |
|---|-------|-----------|------|-------|
| 1 | Structural | asset exists at res://assets/models/flipper_bat.glb | test_flipper_asset_visual | test-builder |
| 2 | Structural | .glb imports to an instantiable PackedScene with a MeshInstance3D | test_flipper_asset_visual | test-builder |
| 3 | Structural | FlipperVisual present + visible; sources the .glb (material names / mesh identity) | test_flipper_asset_visual | test-builder |
| 4 | Structural | procedural FlipperMesh present but HIDDEN fallback (not both shown) | test_flipper_asset_visual | test-builder |
| 5 | Structural (R3) | collider STILL ConvexPolygonShape3D/primitive, NEVER ConcavePolygonShape3D | test_flipper_asset_visual | test-builder |
| 6 | Structural | collider hull geometry unchanged by the visual swap | test_flipper_asset_visual | test-builder |
| 7 | Derived-scale | FlipperVisual world-space long-axis length == collider length within tol (no literal) | test_flipper_asset_visual | test-builder |
| 8 | Derived-scale | FlipperVisual scale is uniform (x==y==z) | test_flipper_asset_visual | test-builder |
| 9 | Mirror | both flippers carry the imported visual | test_flipper_asset_visual | test-builder |
| 10 | Mirror | right visual basis determinant > 0 (rotation, not reflection; rubber not inside-out) | test_flipper_asset_visual | test-builder |
| 11 | Robustness | asset-load failure falls back to procedural mesh, no crash | test_flipper_asset_visual | test-builder |
| 12 | FROZEN (keep green) | no tunneling at >= ~2x launch speed (resting + mid-swing) | test_flipper_no_tunneling | test-builder |
| 13 | FROZEN (keep green) | full swing out-throws a tap; ~50 ms snap | test_flipper_momentum | test-builder |
| 14 | FROZEN (keep green) | rubber rebound >= 35%; momentum preserved; rubber material present | test_flipper_rubber | test-builder |
| 15 | FROZEN (keep green) | both procedural fallback caps face +Y (legacy mesh path) | test_flipper_rubber_top | test-builder |
| 16 | FROZEN (keep green) | collider not-a-box / capsule-or-convex / keeps rubber material | test_flipper_shape | test-builder |

## DELIVERY (recap from the brief)
Stay on slice/first-real-3d-asset. Build/QA COMMIT locally, do NOT push. The Deliver phase fetches
headless Godot 4.x, runs the FULL GUT suite GREEN locally, AND re-verifies the .glb is a proper LFS
object (git lfs ls-files; staged pointer ~130 bytes) BEFORE pushing ONE PR. Producer requires green
CI (with the lfs:true pull) on the pushed sha. Do NOT touch main.
