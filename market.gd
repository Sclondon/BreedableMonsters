class_name Market
extends RefCounted

## Per-species prices that drift slowly and randomly.
##
## Each species carries a multiplier applied to BOTH its buy and its sell price. Because the same
## multiplier scales both, it cancels out of a buy-then-immediately-sell round trip — that trade always
## loses money on the shop's margin alone, no matter what the market is doing (tests/test_species.gd
## pins the invariant). What the market DOES offer is timing: buy a species while it's cheap, hold it,
## and sell once it recovers. That costs food and risks the animal dying of old age in the meantime.

## Seconds between new price targets. Prices ease toward the target, so they drift rather than snap.
const TICK := 2.5
## Biggest jump a single tick can ask for.
const STEP := 0.09
## Pull back toward 1.0. Without this the walk is unbounded and a species eventually drifts to a
## corner of its clamp and stays there.
const PULL := 0.15
## How fast the live price chases its target.
const EASE := 0.8

const LIMITS := Vector2(0.6, 1.6)

var _rates := {}
var _targets := {}
var _elapsed := 0.0


func _init() -> void:
	for species: String in Species.TABLE:
		_rates[species] = 1.0
		_targets[species] = 1.0


func tick(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= TICK:
		_elapsed -= TICK
		for species: String in _targets:
			_targets[species] = _new_target(_targets[species])

	for species: String in _rates:
		_rates[species] = lerpf(_rates[species], _targets[species], minf(EASE * delta, 1.0))


func _new_target(current: float) -> float:
	var drift := randf_range(-STEP, STEP)
	var reversion := (current - 1.0) * PULL
	return clampf(current + drift - reversion, LIMITS.x, LIMITS.y)


func rate(species: String) -> float:
	return _rates[species]


func buy_price(species: String) -> int:
	return maxi(1, roundi(Species.buy_price(species) * rate(species)))


func sell_price(species: String, color: Color) -> int:
	return maxi(1, roundi(Species.sale_value(species, color) * rate(species)))


## Arrow for the HUD: is this species trading above or below its baseline?
func trend(species: String) -> String:
	var r := rate(species)
	if r > 1.06:
		return "^"
	if r < 0.94:
		return "v"
	return "-"
