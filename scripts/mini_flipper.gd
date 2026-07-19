extends "res://scripts/flipper.gd"
## MiniFlipper - a SMALLER upper-field flipper that bats the ball up toward the bumper cluster.
##
## OWNERSHIP: physics-programmer (it inherits the flipper drive). This file adds NO new physics: it
## is
## a thin subclass of flipper.gd that overrides ONLY the geometry getters and the visible asset path
## (the overridable seams flipper.gd exposes), so the mini reuses the SAME kinematic
## AnimatableBody3D +
## sync_to_physics + scripted input-duration angle drive, the same rubber rebound, and the same
## no-tunnel guarantee (ball CCD + the post-contact clamp) as the main flippers - just at ~60% size.
## DESIGN: "a mini flipper bats the ball up top", a REAL flipper at its own scale, not a scripted
## shortcut. The drive rebuild (SLICE "Flipper physics rebuild") required ZERO change here: the mini
## inherits the new drive automatically because it only overrides geometry, never the drive.
##
## INPUT: it reuses the EXISTING "left_flipper" action via inherited configure(action, mirrored),
## so it flips together with the lower-left flipper (the classic upper-flipper convention). NO new
## input action and NO new input system were added (the designer's preferred small option).
##
## STABLE CONTRACT: inherits configure(action_name, mirrored) / is_energized() / tip_speed() /
## force_energized() from flipper.gd byte-for-byte. table.gd instances this, positions it at
## TableConfig.MINI_FLIPPER_PIVOT, and calls configure("left_flipper", false).

## The mini's visible art is our custom mini_flipper.glb (Flipper_Bat_Mini + Flipper_Rubber_Mini,
## the matched low-poly blue family). The inherited _build_visual instances the WHOLE subtree (both
## meshes) and scales it from the merged AABB to the mini collider length, so the rubber is never
## dropped (the same fix as the main flipper). On a load failure the inherited gray-box bat
## stays visible (the flipper never vanishes).
const MINI_FLIPPER_ASSET_PATH: String = "res://assets/models/mini_flipper.glb"


## Override the geometry seams so this flipper is the MINI size. Everything else (the kinematic
## drive,
## the swing integration, the return spring, the rubber material, the handedness) is inherited
## unchanged.
func _flipper_length() -> float:
	return TableConfig.MINI_FLIPPER_LENGTH


func _flipper_width() -> float:
	return TableConfig.MINI_FLIPPER_WIDTH


func _flipper_height() -> float:
	return TableConfig.MINI_FLIPPER_HEIGHT


func _flipper_rest_angle() -> float:
	return TableConfig.MINI_FLIPPER_REST_ANGLE


func _flipper_up_angle() -> float:
	return TableConfig.MINI_FLIPPER_UP_ANGLE


## The mini's visible asset (instanced whole-subtree by the inherited _build_visual, so both the bat
## and the rubber sleeve render). The collider/drive are unaffected - cosmetic mesh only.
func _flipper_asset_path() -> String:
	return MINI_FLIPPER_ASSET_PATH
