extends GutTest
## Test matrix entry: PHYSICS LAYERS CONTRACT.
## Owner: test-builder.
##
## Asserts that the four named collision layers are distinct single-bit values and that
## the convenience masks compose exactly the right set of layers. All checks are pure
## arithmetic; no physics frames are needed.
##
## WHY THIS MATTERS: Godot collision layers are raw bitmasks. If two layers share a bit,
## or a mask is missing a layer, collisions silently mis-fire. These tests are the canary
## that catches any edit to physics_layers.gd that breaks the wiring.

## Helper: true if a positive integer is a power of two (i.e. exactly one bit set).
func _is_single_bit(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0

func test_playfield_is_single_bit() -> void:
	assert_true(
		_is_single_bit(PhysicsLayers.PLAYFIELD),
		"PLAYFIELD must be exactly one bit, got %d" % PhysicsLayers.PLAYFIELD
	)

func test_static_obstacles_is_single_bit() -> void:
	assert_true(
		_is_single_bit(PhysicsLayers.STATIC_OBSTACLES),
		"STATIC_OBSTACLES must be exactly one bit, got %d" % PhysicsLayers.STATIC_OBSTACLES
	)

func test_kinematic_obstacles_is_single_bit() -> void:
	assert_true(
		_is_single_bit(PhysicsLayers.KINEMATIC_OBSTACLES),
		"KINEMATIC_OBSTACLES must be exactly one bit, got %d" % PhysicsLayers.KINEMATIC_OBSTACLES
	)

func test_balls_is_single_bit() -> void:
	assert_true(
		_is_single_bit(PhysicsLayers.BALLS),
		"BALLS must be exactly one bit, got %d" % PhysicsLayers.BALLS
	)

func test_four_layers_are_distinct() -> void:
	# No two layers may share a bit. XOR of all four must equal OR of all four (no
	# collision between any pair).
	var layers: Array[int] = [
		PhysicsLayers.PLAYFIELD,
		PhysicsLayers.STATIC_OBSTACLES,
		PhysicsLayers.KINEMATIC_OBSTACLES,
		PhysicsLayers.BALLS,
	]
	var combined_or: int = 0
	var combined_xor: int = 0
	for layer in layers:
		combined_or |= layer
		combined_xor ^= layer
	assert_eq(
		combined_or,
		combined_xor,
		"All four layers must be distinct bits (no overlap). OR=%d XOR=%d" % [combined_or, combined_xor]
	)

func test_four_layers_are_expected_bit_positions() -> void:
	# Architecture doc: Playfield=1, StaticObstacles=2, KinematicObstacles=4, Balls=8.
	assert_eq(PhysicsLayers.PLAYFIELD, 1, "PLAYFIELD should be bit 1 (layer 1)")
	assert_eq(PhysicsLayers.STATIC_OBSTACLES, 2, "STATIC_OBSTACLES should be bit 2 (layer 2)")
	assert_eq(PhysicsLayers.KINEMATIC_OBSTACLES, 4, "KINEMATIC_OBSTACLES should be bit 4 (layer 3)")
	assert_eq(PhysicsLayers.BALLS, 8, "BALLS should be bit 8 (layer 4)")

func test_ball_mask_includes_playfield() -> void:
	assert_true(
		(PhysicsLayers.BALL_COLLISION_MASK & PhysicsLayers.PLAYFIELD) != 0,
		"BALL_COLLISION_MASK must include PLAYFIELD"
	)

func test_ball_mask_includes_static_obstacles() -> void:
	assert_true(
		(PhysicsLayers.BALL_COLLISION_MASK & PhysicsLayers.STATIC_OBSTACLES) != 0,
		"BALL_COLLISION_MASK must include STATIC_OBSTACLES"
	)

func test_ball_mask_includes_kinematic_obstacles() -> void:
	assert_true(
		(PhysicsLayers.BALL_COLLISION_MASK & PhysicsLayers.KINEMATIC_OBSTACLES) != 0,
		"BALL_COLLISION_MASK must include KINEMATIC_OBSTACLES (flippers/plunger)"
	)

func test_ball_mask_includes_balls() -> void:
	# Ball-vs-ball is included now for future multiball; must be present.
	assert_true(
		(PhysicsLayers.BALL_COLLISION_MASK & PhysicsLayers.BALLS) != 0,
		"BALL_COLLISION_MASK must include BALLS (for future multiball)"
	)

func test_kinematic_mask_hits_only_balls() -> void:
	# A flipper/plunger only needs to push the ball; it must not collide with walls
	# or other kinematic bodies. The mask must equal exactly BALLS.
	assert_eq(
		PhysicsLayers.KINEMATIC_COLLISION_MASK,
		PhysicsLayers.BALLS,
		"KINEMATIC_COLLISION_MASK must be exactly BALLS"
	)

func test_kinematic_mask_does_not_include_playfield() -> void:
	assert_true(
		(PhysicsLayers.KINEMATIC_COLLISION_MASK & PhysicsLayers.PLAYFIELD) == 0,
		"KINEMATIC_COLLISION_MASK must NOT include PLAYFIELD"
	)

func test_kinematic_mask_does_not_include_static_obstacles() -> void:
	assert_true(
		(PhysicsLayers.KINEMATIC_COLLISION_MASK & PhysicsLayers.STATIC_OBSTACLES) == 0,
		"KINEMATIC_COLLISION_MASK must NOT include STATIC_OBSTACLES"
	)
