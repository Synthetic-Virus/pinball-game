extends GutTest
## Test matrix entry: INPUT ACTION MAP.
## Owner: test-builder.
##
## Asserts that the four required actions exist in the InputMap with at least one bound
## event each. Reads InputMap directly as an independent oracle from the scripts that
## poll the actions, so a typo in either the script or project.godot fails immediately
## rather than silently producing an action-not-found runtime error.
##
## WHY FOUR ACTIONS: DESIGN.md mandates action-based input so remap is cheap. The
## flippers poll "left_flipper"/"right_flipper", the plunger polls "launch", and the
## nudge polls "nudge". Every agent that polls an action relies on it existing here.

const REQUIRED_ACTIONS: Array[String] = ["left_flipper", "right_flipper", "launch", "nudge"]

func test_required_actions_exist() -> void:
	# Each action must be registered in InputMap (set in project.godot [input]).
	for action_name in REQUIRED_ACTIONS:
		assert_true(
			InputMap.has_action(action_name),
			"InputMap must have action '%s' (check project.godot [input] section)" % action_name
		)

func test_actions_have_at_least_one_event() -> void:
	# An action with zero bound events is useless: polls will never fire. Verify each
	# action has at least one InputEvent bound.
	for action_name in REQUIRED_ACTIONS:
		if not InputMap.has_action(action_name):
			# Already failed in test_required_actions_exist; skip to avoid a null-access.
			continue
		var events: Array = InputMap.action_get_events(action_name)
		assert_true(
			events.size() > 0,
			"Action '%s' must have at least one bound event" % action_name
		)

func test_left_flipper_is_not_same_events_as_right() -> void:
	# A basic sanity check: the two flipper actions must not share identical event
	# objects (A and D / Left and Right must be distinct keys).
	if not InputMap.has_action("left_flipper") or not InputMap.has_action("right_flipper"):
		pass  # Skip gracefully if actions missing; other test will flag it.
		return
	var left_events: Array = InputMap.action_get_events("left_flipper")
	var right_events: Array = InputMap.action_get_events("right_flipper")
	# Convert to a comparable representation (physical keycode strings).
	var left_codes: Array = []
	for ev in left_events:
		if ev is InputEventKey:
			left_codes.append(ev.physical_keycode)
	var right_codes: Array = []
	for ev in right_events:
		if ev is InputEventKey:
			right_codes.append(ev.physical_keycode)
	# The two sets must not be identical.
	assert_ne(
		left_codes,
		right_codes,
		"left_flipper and right_flipper must not share identical key events"
	)

func test_launch_action_includes_space_key() -> void:
	# DESIGN: the launch action defaults to Space. Verify the physical keycode 32
	# (Space) is bound. Physical keycode 32 is KEY_SPACE in Godot 4.
	if not InputMap.has_action("launch"):
		return
	var found_space: bool = false
	for ev in InputMap.action_get_events("launch"):
		if ev is InputEventKey and ev.physical_keycode == KEY_SPACE:
			found_space = true
			break
	assert_true(found_space, "The 'launch' action must bind the Space key (KEY_SPACE)")
