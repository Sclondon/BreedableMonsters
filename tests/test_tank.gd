extends SceneTree

## Headless checks for the tank layout:
##   godot --headless --script res://tests/test_tank.gd

var _failures := 0


func _initialize() -> void:
	_layout()
	_hit_testing()

	if _failures == 0:
		print("PASS: all tank checks")
	else:
		print("FAIL: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Tanks sit in a row and must never overlap — if they did, an animal could be judged to be in two tanks
## at once, and dragging would deliver it to the wrong one.
func _layout() -> void:
	_check("the first tank sits at the origin", Tank.tank_position(0).is_equal_approx(Vector3.ZERO))

	for i in 6:
		var a := Tank.tank_position(i)
		var b := Tank.tank_position(i + 1)
		var gap: float = b.x - a.x - Tank.EXTENTS.x * 2.0
		_check(
			"tanks %d and %d do not overlap (gap %.1f)" % [i, i + 1, gap],
			gap > 0.0
		)
		_check("tanks are evenly spaced", is_equal_approx(gap, Tank.SPACING))


func _hit_testing() -> void:
	var count := 4

	# The centre of each tank must resolve back to that tank — the round trip drag relies on.
	for i in count:
		_check(
			"the centre of tank %d resolves to tank %d" % [i, i],
			Tank.tank_at(Tank.tank_position(i), count) == i
		)

	# So must a point just inside each far wall.
	for i in count:
		var edge := Tank.tank_position(i) + Vector3(Tank.EXTENTS.x - 0.1, 0, 0)
		_check("a point inside tank %d's wall is still tank %d" % [i, i], Tank.tank_at(edge, count) == i)

	# The gap between two tanks belongs to NEITHER. An animal dropped there must be put back rather than
	# silently teleported into a tank it was never over.
	var between := (Tank.tank_position(0) + Tank.tank_position(1)) * 0.5
	_check("the gap between tanks belongs to no tank", Tank.tank_at(between, count) == -1)

	# And a point way out in space belongs to no tank either.
	_check(
		"open space belongs to no tank",
		Tank.tank_at(Vector3(0, 500, 0), count) == -1
	)

	# A tank that has not been bought yet must never be hit.
	var fifth := Tank.tank_position(4)
	_check("a tank beyond the ones you own is never hit", Tank.tank_at(fifth, count) == -1)


func _check(what: String, passed: bool) -> void:
	if not passed:
		_failures += 1
		print("  FAILED: %s" % what)
