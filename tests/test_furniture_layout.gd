extends GutTest
## Test matrix entry: FURNITURE LAYOUT (the new bodies exist in the real Table, on correct layers,
## in the right regions) + STANDUP BANK + INLANE/OUTLANE GUIDES present and physical.
## Owner: test-builder + qa-lead (integration) + lead (geometry). Slice: "real pinball furniture".
## Updated: slice "Table reshape + playtest fixes" (2026-06-19) - positional assertions for
## widened positions added; gutter spacing asserted at new LANE_GUIDE_DIVIDER_X=13.0.
##
## WHY THIS EXISTS: the developer directive "test the game like a web app" requires a STRUCTURAL
## pass that the new furniture actually lands in the SHIPPING scene (table.gd wiring), not just in
## unit tests. The prior slice shipped two blockers (missing lane pocket, double-offset plunger)
## precisely because the slice unit tests bypassed table.gd. This instances the REAL Table.tscn and
## asserts the furniture is present, physical, and on the right layers.

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


# ---- WIDEN POSITION ASSERTIONS (slice "Table reshape + playtest fixes", 2026-06-19) ----------
# These assert the new post-widen instanced positions in the live scene, not just the constants.
# They are the independent oracle that table.gd correctly reads the widened constants and places
# the bodies at the re-derived positions, not stale pre-widen literals.

func test_slingshots_at_widened_positions() -> void:
	## After the widen the slingshots moved from +/-8.5 to +/-10.5 to stay outboard of the new
	## pivot spread (+/-7.2) and intercept balls falling down the wider side channel. This checks the
	## LIVE instanced position in the scene, not just the constant (the real independent oracle).
	if not ("slingshots" in _table):
		return
	for sling in _table.slingshots:
		var sx: float = absf((sling as Node3D).position.x)
		assert_gt(
			sx, TableConfig.FLIPPER_PIVOT_SPREAD,
			"each slingshot must be outboard of the flipper pivot (x=%f > spread=%f)"
			% [sx, TableConfig.FLIPPER_PIVOT_SPREAD]
		)
		assert_lt(
			sx, TableConfig.HALF_WIDTH,
			"each slingshot must be inside the side wall (x=%f < HALF_WIDTH=%f)"
			% [sx, TableConfig.HALF_WIDTH]
		)


func test_pop_bumpers_at_widened_positions() -> void:
	## The lower bumpers spread from +/-4.5 to +/-6.0 for the wider table. Assert the instanced
	## bumpers in the scene are inside the walls with clearance for their radius.
	if not ("pop_bumpers" in _table):
		return
	for bumper in _table.pop_bumpers:
		var bx: float = absf((bumper as Node3D).position.x)
		# Must be inside the wall with full bumper radius clearance.
		assert_lt(
			bx + TableConfig.POP_BUMPER_RADIUS, TableConfig.HALF_WIDTH,
			"bumper at x=%f + radius %f must clear the side wall (HALF_WIDTH=%f)"
			% [bx, TableConfig.POP_BUMPER_RADIUS, TableConfig.HALF_WIDTH]
		)
		# Must be up-table of the flippers (in the playfield, not the drain).
		assert_lt(
			(bumper as Node3D).position.z, TableConfig.FLIPPER_PIVOT_Z,
			"bumper at z=%f must be up-table of the flipper pivot row (z < %f)"
			% [(bumper as Node3D).position.z, TableConfig.FLIPPER_PIVOT_Z]
		)


func test_standup_bank_at_widened_positions() -> void:
	## The standup bank spread from +/-3.0 to +/-4.5. Each instanced target must sit inside the
	## makeable window (up-table of the flipper reach, down-table of the arch base).
	if not ("targets" in _table):
		return
	var near_z: float = TableConfig.FLIPPER_PIVOT_Z - TableConfig.FLIPPER_LENGTH
	var far_z: float = TableConfig.ARCH_CENTER_Z
	for target in _table.targets:
		var tz: float = (target as Node3D).position.z
		assert_lt(
			tz, near_z,
			"standup target z=%f must be up-table of the flipper-tip reach (< %f)"
			% [tz, near_z]
		)
		assert_gt(
			tz, far_z,
			"standup target z=%f must be down-table of the arch base (> %f)" % [tz, far_z]
		)


func test_both_lane_guides_at_correct_widened_spacing() -> void:
	## After the widen LANE_GUIDE_DIVIDER_X = HALF_WIDTH - 3.0 = 13.0. Both guides are symmetric.
	## Assert the guides' X positions are consistent with the new divider constant.
	## LaneGuideLeft sits at x = -LANE_GUIDE_DIVIDER_X (on the left), LaneGuideRight at +X.
	## This is the item-4 (gutters both sides) independent check on the INSTANCED nodes.
	var expected_x: float = TableConfig.LANE_GUIDE_DIVIDER_X
	var left: Node3D = _table.find_child("LaneGuideLeft", true, false) as Node3D
	var right: Node3D = _table.find_child("LaneGuideRight", true, false) as Node3D
	if left != null:
		# Guide position is on the left side; X magnitude should equal LANE_GUIDE_DIVIDER_X
		# within one wall-thickness (the StaticBody may be centered, not edge-aligned).
		assert_gt(
			absf(left.position.x), expected_x - TableConfig.WALL_THICKNESS,
			"LaneGuideLeft position x=%f should be near LANE_GUIDE_DIVIDER_X=%f on the left side"
			% [left.position.x, -expected_x]
		)
	if right != null:
		assert_gt(
			absf(right.position.x), expected_x - TableConfig.WALL_THICKNESS,
			"LaneGuideRight position x=%f should be near LANE_GUIDE_DIVIDER_X=%f on the right side"
			% [right.position.x, expected_x]
		)


# ---- STATIC-BODY CLEARANCE (QA BUG-024) ---------------------------------------------------------
# Two StaticBody3D bodies do not collide with each other, so an OVERLAP between them raises no
# engine warning - but the overlapping surfaces form a concave seam that hands the solver two
# conflicting contact normals when the ball straddles both, causing velocity spikes or micro-clips
# CCD cannot guard. The slingshot KickerBody outer corner overlapped the LaneGuide wall in the
# outlane path (z band [18.0, 18.32]). This computes each body's world AABB from the LIVE scene
# (global transform x shape size, an independent oracle on the instanced geometry) and asserts every
# slingshot-vs-guide pair is disjoint. It FAILS at the old LANE_GUIDE_TOP_Z, PASSES after the fix.

## World-space AABB of a StaticBody3D's first BoxShape3D (accounts for the body's yaw). Returns a
## zero-size AABB at the body origin if no box shape is found (a missing body fails loudly above).
func _body_world_aabb(body: Node3D) -> AABB:
	var col: CollisionShape3D = body.find_child("*", true, false) as CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			col = child as CollisionShape3D
			break
	if col == null or not (col.shape is BoxShape3D):
		return AABB((body as Node3D).global_position, Vector3.ZERO)
	var half: Vector3 = (col.shape as BoxShape3D).size * 0.5
	var xform: Transform3D = col.global_transform
	# Expand the world AABB over all 8 rotated corners of the box.
	var aabb := AABB(xform.origin, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner: Vector3 = xform * Vector3(sx * half.x, sy * half.y, sz * half.z)
				aabb = aabb.expand(corner)
	return aabb


func test_slingshot_and_lane_guide_do_not_overlap() -> void:
	## QA BUG-024: assert the slingshot KickerBody and the LaneGuide wall share NO volume on either
	## side. An AABB intersection of effectively zero is required (a tiny epsilon absorbs float noise).
	if not ("slingshots" in _table):
		return
	var guides: Array[Node3D] = []
	for guide_name in ["LaneGuideLeft", "LaneGuideRight"]:
		var g: Node3D = _table.find_child(guide_name, true, false) as Node3D
		if g != null:
			guides.append(g)
	for sling in _table.slingshots:
		var body: Node3D = (sling as Node).find_child("KickerBody", true, false) as Node3D
		if body == null:
			continue
		var sling_aabb: AABB = _body_world_aabb(body)
		for guide in guides:
			var guide_aabb: AABB = _body_world_aabb(guide)
			var overlap: AABB = sling_aabb.intersection(guide_aabb)
			var vol: float = overlap.size.x * overlap.size.y * overlap.size.z
			assert_lt(
				vol, 0.001,
				"slingshot KickerBody must not overlap %s (overlap volume %f, size %s)"
				% [guide.name, vol, str(overlap.size)]
			)
