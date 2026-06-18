extends Node
## PhysicsLayers - the named collision layers for the table (autoload singleton).
##
## WHY THIS EXISTS: Godot collision layers are raw bitmasks (1, 2, 4, 8...). Scattering raw bit
## numbers across the codebase is unreadable and bug-prone. Every body in the table sets its layer
## and mask from THESE constants instead, so "what collides with what" is stated in one place.
##
## OWNERSHIP: lead-programmer owns this file. It is a CONTRACT. Do not change bit values without a
## team note, because changing them silently re-wires every collision in the game.
##
## The four layers mirror the pinhead reference (docs/pinhead-tech-notes.md) and the [layer_names]
## section of project.godot. Keep all three in sync (this file, project.godot, and any scene that
## sets layers in the inspector).

## Bit values. Godot layer N is the bit (1 << (N - 1)).
const PLAYFIELD: int = 1 << 0           ## Layer 1: the flat table surface the ball rolls on.
const STATIC_OBSTACLES: int = 1 << 1    ## Layer 2: walls, arch, drain guides, bumpers/targets (fixed).
const KINEMATIC_OBSTACLES: int = 1 << 2 ## Layer 3: flippers and the plunger (driven physics bodies).
const BALLS: int = 1 << 3               ## Layer 4: the pinball(s).

## Convenience mask: everything the BALL should physically collide with.
## The ball rolls on the playfield, bounces off static obstacles, and is struck by flippers/plunger.
## Ball-vs-ball is included for future multiball; harmless with a single ball this slice.
const BALL_COLLISION_MASK: int = PLAYFIELD | STATIC_OBSTACLES | KINEMATIC_OBSTACLES | BALLS

## Convenience mask: what a flipper/plunger (kinematic obstacle) should collide with.
## They only need to push the ball; they do not need to collide with walls or each other.
const KINEMATIC_COLLISION_MASK: int = BALLS
