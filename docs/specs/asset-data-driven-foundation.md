# Design: Asset-based, data-driven table (foundation for the editor)

Status: PROPOSED - awaiting Andrew's approval. Design only; no code yet.

## Why
This is a 3D game with a planned UI table EDITOR. Today the table geometry is procedural: walls/arch/
lane are built from numbers in `scripts/config/table_config.gd`, and each element builds its own
mesh in code. That is the wrong foundation for "import 3D assets and place/morph them in an editor."
We pivot to: each element is a PREFAB (imported visual mesh + a cheap collision shape + its behavior
script), and the table LAYOUT is DATA the runtime and the editor both read/write.

## Key insight (why this is cheap, not a rewrite)
The code is already two-thirds there: `table.gd` already instances each element from a `.tscn` prefab,
sets its transform, and calls `configure(...)`. Behavior scripts already never decide their own
position. So the pivot is only: (a) swap each element's VISUAL mesh source (code mesh -> imported
`.glb`, with gray-box as the fallback), and (b) swap the PLACEMENT source (hardcoded TableConfig loops
-> a data file). The proven physics (force-driven flipper, ball `continuous_cd`, plunger launch,
active kicks, scoring) and every collider do NOT change.

## Architecture
1. ELEMENT PREFAB = imported visual mesh (cosmetic child) + a CHEAP collision shape (primitive or
   convex hull, sized to the mesh) + the existing behavior script. HARD RULE: the art mesh is NEVER a
   collider for a fast-ball table (concave/trimesh colliders tunnel and are slow). Colliders stay the
   tuned primitives/hulls we already build.
2. LAYOUT DATA = a typed Godot Resource `TableDefinition` (`.tres`, plain-text in git, no JSON):
   - `TableDefinition { table_name, tilt_deg, elements: Array[ElementInstance] }`
   - `ElementInstance { element_type, prefab, position, rotation_deg, scale, visual_mode
     (GRAY_BOX|MESH_ASSET|PARAMETRIC), visual_asset, params }`
   - Chosen over JSON because Godot's Inspector edits Resources for free (the future editor binds to
     these fields with zero parser code), fields are typed, and `PackedScene`/`uid://` refs survive
     file moves. A JSON export can be added later if table sharing is ever wanted.
3. `table.gd` BUILDS FROM DATA: read the `TableDefinition`, instance each prefab at its transform,
   apply params via the existing `configure(...)`, wire the ball in a second pass. World-scale/tilt
   stays in `TableConfig` (global contract); per-table placement moves to the data.
4. FIXED vs PARAMETRIC elements: flipper/ball/bumper/target/plunger are FIXED meshes (editor moves/
   rotates/scales them). Walls/arch/ramps are PARAMETRIC (a length the user drags) - their prefab
   builds mesh+collider from params (this is what `table_geometry.gd` already does; it becomes the
   parametric wall/arch prefab). Classifying each element up front decides editor gizmo behavior.

## Migration (every step keeps the full GUT suite green + the demo playable)
- Phase 0: add `TableDefinition`/`ElementInstance`/`ElementCatalog` + a `default_table.tres` that
  reproduces today's layout 1:1. Nothing uses it yet. (Gray-box, no behavior change.)
- Phase 1: flip `table.gd` to build from `default_table.tres`. Same positions => integration/layout/
  no-tunnel tests stay green. Node names preserved (tests find nodes by name). STILL gray-box.
- Phase 2: convert ONE element's visual to a real `.glb` (recommended: the TARGET - smallest surface,
  primitive collider, no handedness). Collider + scoring unchanged; only the mesh swaps. This is the
  end-to-end proof of the asset pipeline + Git LFS.
- Phase 3: swap remaining visuals to `.glb` incrementally; flipper + ball LAST (collider-sensitive).
- Phase 4 (later, when editor work starts): walls/arch -> parametric prefabs (empties table_geometry).
- Phase 5 (separate slice): the editor UI (an inspector for `TableDefinition` + a 3D gizmo).

## Assets (use CC0 now; custom later)
- Foundation phases 0-1 need NO art (gray-box). Art comes in phase 2+.
- Ramps/rails: Kenney coaster-kit (already downloaded, CC0).
- Furniture when wanted: Poly Pizza, Quaternius, Sketchfab (CC0 filter), Meshy.ai (AI, CC0) - all
  commercial-safe. Most elements are simple enough that gray-box-with-materials is fine for a while.
- The architecture makes swapping in Andrew's own future models a one-line data change.

## Risks (flag to producer)
- R1 Node-name compatibility: ~15 tests find nodes by exact name; the data build loop MUST name nodes
  deterministically. Add a test asserting the built tree's names match the legacy set.
- R2 CI must be Git-LFS-aware BEFORE phase 2 merges, or the web build gets pointer files and breaks.
  Owner: gamedev-devops-engineer (confirm git-lfs in the runner image + LFS pull in CI).
- R3 Art-as-collider ban: add a CI test asserting no element uses a concave/trimesh collider.
- R4 `.glb` footprint must match the tuned collider (esp. the tapered flipper) or feel/look diverge;
  flipper/ball convert last with explicit alignment review.
- R5 No editor scope-creep: phases 0-3 ship a fully data-driven GAME with no editor; the editor is a
  later, deliberate slice. The data format needs no rework to support it.

## Recommended first slice (for approval)
SLICE A - data foundation (phases 0-1), gray-box only, ZERO art, ZERO physics change. Acceptance:
full GUT suite green, demo build visually identical to today, table now built from `default_table.tres`.
This is the safe bedrock; Slice B (the Target `.glb` + LFS) proves the asset pipeline next.
