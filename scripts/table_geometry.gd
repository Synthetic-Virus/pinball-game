class_name TableGeometry
extends RefCounted
## TableGeometry - builds the STATIC gray-box geometry of the table (surface, walls, arch, lane).
##
## OWNERSHIP: lead-programmer. This is the fixed shell the ball lives in. It is intentionally NOT a
## behaviour script: it is a builder called by table.gd so the geometry math lives in one place and
## reads every dimension from TableConfig (the world-scale contract). No game rules here.
##
## All bodies created are StaticBody3D on the STATIC_OBSTACLES layer (the flat surface is on the
## PLAYFIELD layer). Everything is added under the tilted Playfield node passed in by table.gd.
##
## DESIGN LAYOUT honored (DESIGN.md): upright frame, launch lane up the RIGHT side, a rounded top
## ARCH that turns the launched ball into the playfield, perimeter walls, open bottom for the drain.

## Entry point. table.gd calls TableGeometry.build(playfield_node).
static func build(_playfield: Node3D) -> void:
	# TODO(lead): _build_surface(), _build_perimeter_walls(), _build_lane_divider(), _build_arch().
	# Each helper reads dimensions from TableConfig, sets collision_layer = PhysicsLayers.* and a
	# gray-box material, and adds the body under _playfield. Build solid: the arch must actually
	# redirect a full-speed launched ball (no gap a fast ball squeezes through), and walls must be
	# tall enough (TableConfig.WALL_HEIGHT) that the ball cannot hop them at max launch speed.
	pass

# --- Builder helpers (lead fills these) ---------------------------------------------------------
# static func _build_surface(parent: Node3D) -> void:        # PLAYFIELD layer flat box.
# static func _build_perimeter_walls(parent: Node3D) -> void: # STATIC_OBSTACLES side/top walls.
# static func _build_lane_divider(parent: Node3D) -> void:    # inner wall making the right lane.
# static func _build_arch(parent: Node3D) -> void:            # polyline arch from TableConfig.ARCH_*.
