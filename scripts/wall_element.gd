extends StaticBody3D
## WallElement - a basic placeable WALL the ball bounces off, built from our custom wall.glb.
##
## OWNERSHIP: physics-programmer owns the collider + bounce; lead scaffolds the asset install. The
## full draw-along-curve / closed-solid / tunnel-tool wall EDITOR is OUT OF SCOPE for this slice
## (future). This element just gets the wall ASSET instanced and bouncing in the game now.
##
## PHYSICS-FIRST (non-negotiable): the ART MESH is NEVER a collider. The collider is a PRIMITIVE
## BoxShape3D sized from TableConfig (LENGTH x THICKNESS x HEIGHT), on STATIC_OBSTACLES,
## with HIGH restitution (WALL_ELEMENT_BOUNCE) so the ball rebounds with life. The box stands taller
## than the ball diameter so the ball cannot ride over it, and the ball's continuous_cd plus the
## static box mean no tunneling even at >= 2x LAUNCH_SPEED_MAX (proven by the stress test).
##
## VISUAL: the imported wall.glb (dark Wall_Body + blue translucent Wall_Cap) is instanced as the
## visible art, scaled by a factor DERIVED from the collider length (never hardcoded), parented to
## this body so it follows the box. If the .glb fails to import, the gray-box mesh stays so the wall
## never vanishes.
##
## STABLE CONTRACT (table.gd / tests depend on these):
##   func configure() -> void   # pull dimensions/material from TableConfig (called by table.gd).

## The imported wall art (custom low-poly, matched blue-cap family).
const WALL_ASSET_PATH: String = "res://assets/models/wall.glb"

## The node name the imported .glb visual is instanced under (tests resolve it by this name).
const WALL_VISUAL_NODE_NAME: String = "WallVisual"

## TEST SEAM: force the imported-asset load to use a different path so a test can drive the fallback
## branch. "" means "use WALL_ASSET_PATH" (the production path).
var _asset_path_override: String = ""

## The instanced .glb visual root (null on fallback / before _ready).
var _visual: Node3D = null

## Resolved dimensions (set in configure(), default to TableConfig so a bare instance is valid).
var _length: float = TableConfig.WALL_ELEMENT_LENGTH
var _thickness: float = TableConfig.WALL_ELEMENT_THICKNESS
var _height: float = TableConfig.WALL_ELEMENT_HEIGHT


## Pull dimensions from TableConfig. table.gd calls this after instancing, before adding to the tree
## so _ready/_build see the resolved values. STABLE SIGNATURE.
func configure() -> void:
	_length = TableConfig.WALL_ELEMENT_LENGTH
	_thickness = TableConfig.WALL_ELEMENT_THICKNESS
	_height = TableConfig.WALL_ELEMENT_HEIGHT


func _ready() -> void:
	_build_collider_and_graybox()
	_install_art()


## Build the PRIMITIVE collider (BoxShape3D, never the art mesh) + a gray-box fallback. The body
## is on STATIC_OBSTACLES (mask 0: only collided with, like the walls), so the ball already
## hits it via BALL_COLLISION_MASK - NO layer/mask change. A LOCAL PhysicsMaterial gives the
## high-restitution bounce; the static box + the ball's continuous_cd guarantee no tunneling.
func _build_collider_and_graybox() -> void:
	collision_layer = PhysicsLayers.STATIC_OBSTACLES
	collision_mask = 0

	var material := PhysicsMaterial.new()
	material.bounce = TableConfig.WALL_ELEMENT_BOUNCE
	material.friction = TableConfig.WALL_ELEMENT_FRICTION
	physics_material_override = material

	var col := CollisionShape3D.new()
	col.name = "WallCollider"
	var box := BoxShape3D.new()
	box.size = Vector3(_length, _height, _thickness)
	col.shape = box
	add_child(col)

	# Gray-box mesh matching the collider so the wall is visible if the .glb import fails. Hidden on a
	# successful import (the imported art replaces it). The wall never vanishes on a bad asset.
	var gray := MeshInstance3D.new()
	gray.name = "WallGrayBox"
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	gray.mesh = box_mesh
	add_child(gray)


## Instance the imported wall.glb as the visible art and hide the gray box. COPIES the proven
## pop_bumper.gd / slingshot.gd install: load the path (or test override), bail to the gray box on
## any failure, instance the WHOLE subtree under a named child, scale it from the merged AABB to the
## collider length (DERIVED, not a literal), hide the gray box on success. The art is pure mesh - it
## is never a collider.
func _install_art() -> void:
	var path: String = WALL_ASSET_PATH if _asset_path_override == "" else _asset_path_override
	if path == "" or not ResourceLoader.exists(path):
		return  ## fallback: the gray box stays visible
	var scene: Resource = load(path)
	if scene == null or not (scene is PackedScene):
		return  ## fallback (bad/absent asset)
	_visual = (scene as PackedScene).instantiate()
	_visual.name = WALL_VISUAL_NODE_NAME
	add_child(_visual)
	var factor: float = _derive_scale(_visual)
	_visual.scale = Vector3(factor, factor, factor)
	var gray: Node = get_node_or_null("WallGrayBox")
	if gray != null:
		gray.visible = false


## Uniform scale so the imported model's LONG axis matches the collider length. Measured from the
## merged mesh AABB (independent oracle on the scale), never hardcoded: re-exporting the model at a
## different size self-corrects. The structural test asserts the scale TRACKS the collider length.
func _derive_scale(root: Node3D) -> float:
	var box: AABB = _merged_aabb(root)
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest < 0.0001:
		return 1.0
	return _length / longest


## Merge every descendant MeshInstance3D's AABB into root-local space (copy of the proven helper).
func _merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _mesh_instances(root):
		var local: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var a: AABB = local * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## Every MeshInstance3D under `node` (recursive).
func _mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for c: Node in node.get_children():
		found.append_array(_mesh_instances(c))
	return found
