extends SceneTree

## Headless checks for the drifting market:
##   godot --headless --script res://tests/test_market.gd

const STEPS := 20000
const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	var market := Market.new()

	for species: String in Species.TABLE:
		_check("%s starts at its baseline price" % species, is_equal_approx(market.rate(species), 1.0))

	# Drive a long game and watch the walk. The mean-reversion term is what keeps a species from
	# wandering off to a corner of the clamp and staying there, so check both the hard bounds and that
	# prices still spend their time near the baseline.
	var lows := {}
	var highs := {}
	var totals := {}
	for species: String in Species.TABLE:
		lows[species] = INF
		highs[species] = -INF
		totals[species] = 0.0

	for step in STEPS:
		market.tick(DT)
		for species: String in Species.TABLE:
			var r := market.rate(species)
			lows[species] = minf(lows[species], r)
			highs[species] = maxf(highs[species], r)
			totals[species] += r

	for species: String in Species.TABLE:
		_check(
			"%s stays inside its clamp (saw %.2f..%.2f)" % [species, lows[species], highs[species]],
			lows[species] >= Market.LIMITS.x - 0.001 and highs[species] <= Market.LIMITS.y + 0.001
		)
		var mean: float = totals[species] / STEPS
		_check(
			"%s reverts toward its baseline rather than drifting away (mean %.2f)" % [species, mean],
			absf(mean - 1.0) < 0.25
		)
		_check("%s actually moved" % species, highs[species] - lows[species] > 0.05)

	_prices(market)

	if _failures == 0:
		print("PASS: all market checks")
	else:
		print("FAIL: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _prices(market: Market) -> void:
	var vivid := Color.from_hsv(0.3, 1.0, 1.0)

	for species: String in Species.TABLE:
		var rate := market.rate(species)
		_check(
			"%s buy price tracks the market (rate %.2f)" % [species, rate],
			market.buy_price(species) == maxi(1, roundi(Species.buy_price(species) * rate))
		)
		# The round trip must lose money at whatever the market currently says — this is the same
		# invariant test_species.gd pins on the table, re-checked through the live market, since the
		# multiplier applies to both sides and cancels.
		_check(
			"%s still cannot be flipped for profit at rate %.2f (buy %d > sell %d)"
			% [species, rate, market.buy_price(species), market.sell_price(species, vivid)],
			market.buy_price(species) > market.sell_price(species, vivid)
		)
		_check("%s prices never hit zero" % species, market.sell_price(species, Color(0.5, 0.5, 0.5)) > 0)


func _check(what: String, passed: bool) -> void:
	if not passed:
		_failures += 1
		print("  FAILED: %s" % what)
