class_name KenneyModels
extends RefCounted
## KenneyModels - the SINGLE typed source of truth for the Kenney 3D MESH identity (SLICE "Kenney
## 3D asset integration"). This is the mesh twin of palette.gd (which owns the COLOUR identity): it
## maps the frozen 13-entry Kenney Minigolf Kit manifest to res:// paths, records which mesh each
## furniture ROLE uses, and provides the shared scale/seat helpers every visual-swap element calls.
## VISUAL ONLY.
##
## WHY THIS FILE EXISTS: before this slice the .glb path and the "measure the AABB, derive the
## scale, seat the base at the surface" logic were COPY-PASTED into five element scripts
## (pop_bumper.gd, slingshot.gd, wall_element.gd, plunger.gd, flipper.gd - the QA_BACKLOG
## "_merged_aabb 5-file dedup" debt). This module gathers (a) the Kenney model paths in ONE place so
## a mesh swap is a one-line const change, (b) the role-to-element MAPPING the designer locked
## (which mesh each class renders), and (c) the shared, unit-tested scale/seat helpers, so the
## integration gotchas (scale DERIVED from the collider, base seated at Y=0, art mesh NEVER a
## collider) have one correct implementation instead of five drifting copies.
##
## HARD RULE (project north star): NOTHING here reads or writes a collision shape, a physics layer,
## a kick vector, or a layout coordinate. The helpers only MEASURE a visual's mesh AABB and return a
## scale factor / a Y offset. The art mesh is never a collider; the ball always collides with the
## element's existing primitive collider at its existing size and position (physics is FROZEN).
##
## OWNERSHIP: lead-programmer owns this module and its contract. Element owners (physics-programmer
## for the procedural parts, lead for the imported-mesh parts) CALL these helpers, never fork them.
##
## HOUSE STYLE: typed const String paths, UPPER_SNAKE, matching palette.gd / table_config.gd. The
## flat faceted low-poly LOOK comes from the meshes' own normals plus palette.gd flat materials;
## this module carries geometry paths and math only, no colour.

# --- MANIFEST MODEL PATHS ------------------------------------------------------------------------
# The 13 frozen 3d_model entries (docs/assets/KENNEY_BASELINE_MANIFEST.json), copied UNMODIFIED from
# the read-only bundle to assets/kenney/baseline/models/ and imported by a real headless Godot run
# (the .import sidecars are engine-generated, never hand-authored). Grouped by manifest ROLE.

## bumper_body role (round pop-bumper cap candidates). The kit meshes are FALLBACK candidates; the
## chosen in-field bumper mesh is MUSHROOM_BUMPER (see POP_BUMPER_MODEL), the custom-authored asset.
const BUMP: String = "res://assets/kenney/baseline/models/bump.glb"
const BUMP_WALLS: String = "res://assets/kenney/baseline/models/bump-walls.glb"
const HILL_ROUND: String = "res://assets/kenney/baseline/models/hill-round.glb"

## CUSTOM-AUTHORED mushroom-cap pop bumper - the SHIPPED in-field bumper mesh (POP_BUMPER_MODEL
## binds here). It replaces the blocky BUMP kit mesh that failed the eyeball test ("the mushrooms
## are just squares"): a low-poly domed RED cap that clearly OVERHANGS a narrow grey stem, wrapped
## by a light ring band so it reads as a pop bumper from a steep top-down gameplay camera. Modelled
## from scratch in the flat faceted Kenney style - shade_flat on every face, no bevels, 18 segments
## on the round parts, flat baked colours (cap red near 0.86/0.16/0.16, light-grey ring, neutral
## grey post). The pinball-parts set was a PROPORTION reference only, so this mesh is original and
## license-clean. Real proportions: cap diameter about 1.04 units, height about 0.52, with the CAP
## as the widest XZ span so uniform_scale_to_span fits the cap to the collider diameter, and the
## stem base seated at Y=0 on export so base_seat_y keeps it from sinking below the field.
## pop_bumper.gd needs NO code change: it reads KenneyModels.POP_BUMPER_MODEL, wears the
## BumperVisual marker, overhangs the collider, and pulses the albedo hit-flash. BUMP / BUMP_WALLS
## / HILL_ROUND stay as fallback kit candidates only.
const MUSHROOM_BUMPER: String = "res://assets/kenney/baseline/models/mushroom_bumper.glb"

## obstacle_post role (standup-target bank candidates). OBSTACLE_BLOCK is the chosen bank mesh (see
## STANDUP_TARGET_MODEL); diamond and triangle are held for future variety.
const OBSTACLE_BLOCK: String = "res://assets/kenney/baseline/models/obstacle-block.glb"
const OBSTACLE_DIAMOND: String = "res://assets/kenney/baseline/models/obstacle-diamond.glb"
const OBSTACLE_TRIANGLE: String = "res://assets/kenney/baseline/models/obstacle-triangle.glb"

## wall_border role. BLOCK_BORDERS skins the perimeter rails / rail brackets; NARROW_BLOCK skins the
## narrow lane dividers / guides.
const BLOCK_BORDERS: String = "res://assets/kenney/baseline/models/block-borders.glb"
const NARROW_BLOCK: String = "res://assets/kenney/baseline/models/narrow-block.glb"

## ramp role - HELD in the library only. There is NO ramp element in v1 (the designer cut placing a
## ramp: it is theme dressing, a separate slice). Copied + LFS-tracked as breadth, not placed.
const RAMP_HIGH: String = "res://assets/kenney/baseline/models/ramp-high.glb"
const RAMP_LARGE_SIDE: String = "res://assets/kenney/baseline/models/ramp-large-side.glb"
const HILL_SQUARE: String = "res://assets/kenney/baseline/models/hill-square.glb"

## deco_prop role - HELD in the library only. No theme dressing (crest / castle) is planted on the
## playfield in v1 (the designer cut it). Copied + LFS-tracked as breadth, not placed.
const CREST: String = "res://assets/kenney/baseline/models/crest.glb"
const CASTLE: String = "res://assets/kenney/baseline/models/castle.glb"

# --- ROLE -> ELEMENT MAPPING (the designer's locked decision, made concrete) ---------------------
# DESIGN.md "Role-to-element mapping": ONE consistent mesh per furniture class so the table reads as
# one designed object (a matched set), not random clutter. Element scripts reference THESE, never a
# raw path literal, so a mesh choice is changed in exactly one place.

## POP BUMPERS (all THREE share one mesh): the custom MUSHROOM_BUMPER, which reads as a domed
## mushroom pop bumper instantly at play zoom (the read the earlier BUMP kit mesh failed on: "the
## mushrooms are just squares"). The cap overhangs the contact post so the ball tucks under the lip
## (cap_overhang test). BUMP / BUMP_WALLS / HILL_ROUND stay in the library as fallback candidates.
const POP_BUMPER_MODEL: String = MUSHROOM_BUMPER

## STANDUP TARGET BANK (all THREE share one mesh). OBSTACLE_BLOCK reads as a clean standup post, and
## a bank of identical blocks reads as a set. The target keeps its "Deflector" scoring marker.
const STANDUP_TARGET_MODEL: String = OBSTACLE_BLOCK

## PERIMETER WALLS / BORDER RAILS / RAIL BRACKETS. BLOCK_BORDERS is the bordered wall block.
const WALL_BORDER_MODEL: String = BLOCK_BORDERS

## NARROW LANE DIVIDERS / GUIDES. NARROW_BLOCK is the thin wall segment for tight lane separation.
const NARROW_GUIDE_MODEL: String = NARROW_BLOCK

# --- MODEL SETS (for the structural / pipeline tests) --------------------------------------------

## All 13 manifest models. The structural test asserts each is LFS-tracked, imports to a PackedScene
## with real mesh geometry, and its .import carries no collider directive.
const ALL_MODELS: Array[String] = [
	BUMP, BUMP_WALLS, HILL_ROUND,
	OBSTACLE_BLOCK, OBSTACLE_DIAMOND, OBSTACLE_TRIANGLE,
	RAMP_HIGH, RAMP_LARGE_SIDE, HILL_SQUARE,
	BLOCK_BORDERS, NARROW_BLOCK,
	CREST, CASTLE,
]

## The four meshes actually PLACED on the table (the rest are the held library). The DoD "no legacy
## model visible" oracle checks the field renders only these plus the procedural parts.
const USED_MODELS: Array[String] = [
	POP_BUMPER_MODEL, STANDUP_TARGET_MODEL, WALL_BORDER_MODEL, NARROW_GUIDE_MODEL,
]

## Ramps + deco - copied to the library and HELD, never placed on the v1 field (theme dressing is a
## separate slice). Named so a test can assert they are present-but-unplaced.
const HELD_MODELS: Array[String] = [
	RAMP_HIGH, RAMP_LARGE_SIDE, HILL_SQUARE, CREST, CASTLE,
]

## Sentinel for uniform_scale_to_span's `axis` argument: measure the model's LONGEST local axis (X,
## Y or Z), the right choice for a length-fit like a wall. Pass 0/1/2 instead to pin one axis.
const AXIS_LONGEST: int = -1


# --- SHARED VISUAL HELPERS (measure-only; never touch a collider) --------------------------------
# These replace the five copy-pasted _merged_aabb / _derive_scale / _mesh_instances blocks. Each is
# a pure function of the visual's mesh geometry (an independent oracle on scale/seat): change the
# model and the derived numbers self-correct, so no magic scale literal is ever hand-typed.


## Every MeshInstance3D under `node` (recursive, inclusive). An imported .glb usually has several
## named sub-meshes; a merged measurement needs them all.
static func mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for c: Node in node.get_children():
		found.append_array(mesh_instances(c))
	return found


## Merge every descendant MeshInstance3D's AABB into `root`'s LOCAL space. Uses
## TableConfig.relative_xform so it is valid even before `root` is inside the SceneTree (elements
## measure the imported subtree while wiring it). Returns a zero AABB if `root` has no meshes.
static func merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for mi: MeshInstance3D in mesh_instances(root):
		var local: Transform3D = TableConfig.relative_xform(root, mi)
		var a: AABB = local * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## The uniform scale factor that fits a visual's measured footprint to `target_span` (a collider
## dimension the ELEMENT supplies - its post radius, wall length, kicking-face span, etc.). The
## anti-magic-number oracle: the factor is target_span / (the model's own measured span), so a
## re-exported model at a different size self-corrects and no scale literal is ever typed.
##
## `axis`: AXIS_LONGEST (default) fits the largest of X/Y/Z (a length-fit); 0/1/2 pins X/Y/Z (a
## cross-section fit). Returns 1.0 (a safe no-op) on a degenerate model, so a bad asset never
## divides by ~0.
static func uniform_scale_to_span(
	visual: Node3D, target_span: float, axis: int = AXIS_LONGEST
) -> float:
	var box: AABB = merged_aabb(visual)
	var span: float
	if axis == AXIS_LONGEST:
		span = maxf(box.size.x, maxf(box.size.y, box.size.z))
	else:
		span = box.size[axis]
	if span < 0.0001:
		return 1.0
	return target_span / span


## The local Y position to give an already-scaled `visual` so its mesh BASE sits at `base_y` in the
## parent (element) frame. This fixes the burned "off-origin geometry sinks below the playfield"
## gotcha: a Kenney mesh whose authored geometry sits below its own origin would sink under the
## field unless lifted. We read the visual's merged mesh AABB min-Y (in the visual's own frame),
## scale it by the visual's current scale.y for the parent-frame min-Y, and return the offset that
## lands that minimum on `base_y`. Call AFTER setting `visual.scale`. Pure measurement - no collider
## is read or moved (the collider's own Y is set by the element's frozen physics build, untouched).
static func base_seat_y(visual: Node3D, base_y: float = 0.0) -> float:
	var box: AABB = merged_aabb(visual)
	var scaled_min_y: float = box.position.y * visual.scale.y
	return base_y - scaled_min_y
