# Tech Notes: learnings from the pinhead reference (for the core rebuild)
Source: GandalfDG/pinhead (https://github.com/GandalfDG/pinhead). License: MIT (notice: "Copyright (c)
2022 MarcPhi" - retain it if any code is lifted verbatim). Godot 4.2, 3D, GDScript. Studied 2026-06-17;
cloned to /tmp/pinhead (ephemeral - re-clone with `git clone https://github.com/GandalfDG/pinhead`).

These are MECHANICS and PATTERNS (not copyrightable); the rebuild writes ORIGINAL code on Godot 4.6 +
built-in Jolt, using these as the blueprint.

## Already adopted (in project.godot, commit f57262b)
- Built-in Jolt 3D physics engine (native since Godot 4.4): physics/3d/physics_engine="Jolt Physics"
- 240 Hz physics tick + max 32 steps/frame
- Jolt tuning: continuous_cd/max_penetration=0.0, sleep/velocity_threshold=0.002, solver/bounce_velocity_threshold=10.0

## Patterns to adopt in the rebuild
1. FORCE-DRIVEN FLIPPERS, not kinematic rotation. pinhead drives flippers as physics bodies pushed by a
   "solenoid" force with a return spring (elements/flipper/FlipperBody.gd, FlipperPair.gd, flipper.gd;
   utilities/physics_components/Solenoid.gd, SolenoidSpring.gd, AxisSpring.gd, SpringReset.gd). This is the
   biggest feel upgrade over the current kinematic boxes. Use a hinge joint + driven torque/force + return spring.
2. ACTION-BASED INPUT. Define input actions left_flipper / right_flipper / launch / up_nudge / left_nudge /
   right_nudge instead of hardcoded keys. (pinhead default: left=Z, right=/.)
3. COMPONENT ELEMENT ARCHITECTURE. Each table element is a small reusable scene sharing ScoringElement and
   TriggerableElement behavior (elements/: drop_target, rollover, spinner, pop_bumper/Kicker). This is the
   structure that keeps a growing table maintainable and makes multi-board feasible later.
4. PHYSICS LAYERS: Playfield, Static Obstacles, Kinematic Obstacles, Balls. Organize collisions, do not
   leave everything colliding with everything.
5. NUDGE mechanic (up/left/right) is a first-class action in pinhead - plan for it.
6. Optional: CSG-generated walls/playfield (utilities/wall_generator, playfield_cutout) and LocalAxisLock
   to constrain elements to the table plane.

## Other confirmed resources
- dbisdorf/professor-pinball (MIT, Godot 3, complete 2D game): reference for the FULL component set and a
  working DMD + scoring + challenge structure. Port patterns to 4.6; do not fork the Godot 3 code.
- Kenney audio packs (CC0, no attribution): commercial-safe SFX (Impact/Interface/UI/Casino/Digital/Jingles).
