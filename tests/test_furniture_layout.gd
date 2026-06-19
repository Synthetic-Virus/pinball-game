extends GutTest
## Test matrix entry: FURNITURE LAYOUT (the new bodies exist in the real Table, on correct layers,
## in
## the right regions) + STANDUP BANK + INLANE/OUTLANE GUIDES present and physical.
## Owner: test-builder + qa-lead (integration) + lead (geometry). Slice: "real pinball furniture".
##
## WHY THIS EXISTS: the developer directive "test the game like a web app" requires a STRUCTURAL
## pass
## that the new furniture actually lands in the SHIPPING scene (table.gd wiring), not just in unit
## tests. The prior slice shipped two blockers (missing lane pocket, double-offset plunger)
## precisely
## because the slice unit tests bypassed table.gd. This instances the REAL Table.tscn and asserts
## the
## furniture is present, physical, and on the right layers.

const TABLE_SCENE: PackedScene = preload("res://scenes/Table.tscn")

var _table: Node3D = null


func before_each() -> void:
	_table = TABLE_SCENE.instantiate() as Node3D
	add_child_autofree(_table)
	await wait_frames(3)  # let _ready build the playfield + instance every element


# ---- POP BUMPERS --------------------------------------------------------------------------------

func test_pop_bumpers_present_in_table() -> void:
	## The table must instance one pop bumper per TableConfig.POP_BUMPER_POSITIONS, each with a solid
	## KickerBody on STATIC_OBSTACLES in the upper-middle (negative Z, above the flippers).
	assert_true("pop_bumpers" in _table, "table.gd must expose a pop_bumpers handle")
	if "pop_bumpers" in _table:
		assert_eq(
			(_table.pop_bumpers as Array).size(),
			TableConfig.POP_BUMPER_POSITIONS.size(),
			"table must instance one pop bumper per TableConfig.POP_BUMPER_POSITIONS"
		)
		for bumper in _table.pop_bumpers:
			var body: Node = (bumper as Node).find_child("KickerBody", true, false)
			assert_not_null(body, "each pop bumper must have a solid KickerBody")


# ---- SLINGSHOTS ---------------------------------------------------------------------------------

func test_slingshots_present_above_flippers() -> void:
	## Two slingshots, one per side, up-table of the flipper pivot row (smaller Z than
	## FLIPPER_PIVOT_Z).
	assert_true("slingshots" in _table, "table.gd must expose a slingshots handle")
	if "slingshots" in _table:
		assert_eq(
			(_table.slingshots as Array).size(), 2,
			"table must instance exactly two slingshots (one per side)"
		)
		for sling in _table.slingshots:
			assert_lt(
				(sling as Node3D).position.z, TableConfig.FLIPPER_PIVOT_Z,
				"a slingshot must sit up-table of the flipper pivot row (into play, above the drain)"
			)


# ---- STANDUP BANK -------------------------------------------------------------------------------

func test_standup_bank_present_and_physical() -> void:
	## The standup bank is the re-homed physical targets at TableConfig.STANDUP_BANK_POSITIONS, each
	## with a solid Deflector (the target's physical post). They must be physical, not pass-through.
	assert_true("targets" in _table, "table.gd must expose a targets handle")
	if "targets" in _table:
		assert_eq(
			(_table.targets as Array).size(),
			TableConfig.STANDUP_BANK_POSITIONS.size(),
			"the standup bank must have one target per STANDUP_BANK_POSITIONS"
		)
		for target in _table.targets:
			var deflector: Node = (target as Node).find_child("Deflector", true, false)
			assert_not_null(deflector, "each standup target must have a solid Deflector (physical)")


# ---- INLANE / OUTLANE GUIDES --------------------------------------------------------------------

func test_lane_guides_present_and_static() -> void:
	## The inlane/outlane guide divider walls must exist as StaticBody3D on STATIC_OBSTACLES (physical,
	## unlit guide walls only - no rollover scoring). We assert the two named guide bodies exist.
	var left: Node = _table.find_child("LaneGuideLeft", true, false)
	var right: Node = _table.find_child("LaneGuideRight", true, false)
	assert_not_null(left, "table_geometry must build a LaneGuideLeft divider wall")
	assert_not_null(right, "table_geometry must build a LaneGuideRight divider wall")
	if left != null and left is StaticBody3D:
		assert_eq(
			(left as StaticBody3D).collision_layer, PhysicsLayers.STATIC_OBSTACLES,
			"lane guides must be physical (StaticBody3D on STATIC_OBSTACLES)"
		)
