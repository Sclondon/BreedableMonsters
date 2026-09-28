extends SceneTree

## Headless checks for inheritance:
##   godot --headless --script res://tests/test_genome.gd

const GENERATIONS := 5000
const SAMPLES := 3000

var _failures := 0


func _initialize() -> void:
	_distance()
	_genes_stay_in_range()
	_color_now_mutates()
	_inbreeding_amplifies_mutation()
	_attractors_are_inherited()
	_the_ladder_still_climbs()
	_locomotion_blends()

	if _failures == 0:
		print("PASS: all genome checks")
	else:
		print("FAIL: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Genetic distance is the primitive that mate choice and the inbreeding penalty are both built on, so it
## has to behave: 0 for a clone, symmetric, and never outside 0..1.
func _distance() -> void:
	var a := Genome.random(Color.RED)
	_check("an animal is genetically identical to itself", is_zero_approx(Genome.distance(a, a)))

	var b := Genome.random(Color.CYAN)
	_check("distance is symmetric", is_equal_approx(Genome.distance(a, b), Genome.distance(b, a)))

	for i in 500:
		var x := Genome.random(Color(randf(), randf(), randf()))
		var y := Genome.random(Color(randf(), randf(), randf()))
		var d := Genome.distance(x, y)
		if d < 0.0 or d > 1.0:
			_check("distance stays within 0..1 (got %.3f)" % d, false)
			return
	_check("distance always stays within 0..1", true)

	# Two animals at opposite ends of every range must read as far apart; two near-clones as close.
	var low := Genome.new()
	var high := Genome.new()
	for gene: String in Genome.RANGES:
		low.set(gene, Genome.RANGES[gene].x)
		high.set(gene, Genome.RANGES[gene].y)
	low.color = Color.BLACK
	high.color = Color.WHITE
	low.attractor = Genome.Attractor.VIVIDNESS
	high.attractor = Genome.Attractor.RARITY

	var opposite := Genome.distance(low, high)
	var twins := Genome.distance(low, low)
	_check("opposites are far apart (%.2f)" % opposite, opposite > 0.8)
	_check("clones are not", twins < opposite)


func _genes_stay_in_range() -> void:
	var a := Genome.random(Color.RED)
	var b := Genome.random(Color.BLUE)

	# Breed a lineage forward, always folding the newest child back in. This is the harshest drift test —
	# and, because the parents get more alike each generation, it is also the harshest INBREEDING test:
	# the mutation penalty is compounding the whole way.
	for generation in GENERATIONS:
		var child := Genome.mix(a, b)
		a = b
		b = child

	for gene: String in Genome.RANGES:
		var limits: Vector2 = Genome.RANGES[gene]
		var value: float = b.get(gene)
		_check(
			"'%s' stayed inside its range after %d inbred generations (%.3f in %.2f..%.2f)"
			% [gene, GENERATIONS, value, limits.x, limits.y],
			value >= limits.x - 0.0001 and value <= limits.y + 0.0001
		)

	for channel in [b.color.r, b.color.g, b.color.b]:
		_check("colour stayed inside 0..1 (%.3f)" % channel, channel >= 0.0 and channel <= 1.0)

	_check("kin_color_bias can never reach 1.0", Genome.RANGES["kin_color_bias"].y < 1.0)


## THE INVARIANT THIS PASS DELETES, INVERTED.
##
## Colour used to blend exactly, so herds bled toward grey and the shop existed to sell you saturation.
## Colour now mutates, so a washed-out line can find its way back to vivid on its own — and sexual
## selection will drag it there if the animals like vividness.
func _color_now_mutates() -> void:
	var grey_a := Genome.random(Color(0.5, 0.5, 0.5))
	var grey_b := Genome.random(Color(0.5, 0.5, 0.5))

	var drifted := 0
	var brightest := 0.0
	for i in SAMPLES:
		var child := Genome.mix(grey_a, grey_b)
		if not child.color.is_equal_approx(Color(0.5, 0.5, 0.5)):
			drifted += 1
		brightest = maxf(brightest, child.color.s)

	_check("a child's colour is no longer a fixed midpoint", drifted > SAMPLES / 2)
	_check(
		"two grey parents CAN now produce a saturated child (best %.3f)" % brightest,
		brightest > 0.05
	)

	# It still resembles its parents, though — a bloodline keeps a recognisable palette.
	var red := Genome.random(Color.from_hsv(0.0, 0.9, 1.0))
	var also_red := Genome.random(Color.from_hsv(0.0, 0.9, 1.0))
	var child := Genome.mix(red, also_red)
	_check(
		"a child of two red parents is still recognisably red",
		child.color.r > child.color.g and child.color.r > child.color.b
	)

	_mixing_does_not_drain_color()


## THE REAL SOURCE OF THE GREY DRIFT, AND THE THING THAT FIXES IT.
##
## Mixing two hues in RGB desaturates them: red + blue channel-by-channel is a muddy dark purple, and a
## few generations of that turns any herd to sludge — mutation or no mutation. Blending the HUE around
## the colour wheel instead keeps the child vivid: red + blue becomes a BRIGHT purple.
##
## Without this, a population's saturation sinks no matter what the animals find attractive, and sexual
## selection for vividness is pushing uphill against a leak.
func _mixing_does_not_drain_color() -> void:
	var red := Genome.random(Color.from_hsv(0.0, 1.0, 1.0))
	var blue := Genome.random(Color.from_hsv(0.6, 1.0, 1.0))

	var child := Genome.mix(red, blue)
	_check(
		"mixing two vivid but opposite colours stays vivid (saturation %.2f)" % child.color.s,
		child.color.s > 0.8
	)

	# And a whole lineage of cross-hue mixing must not slide toward grey.
	var line_a := Genome.random(Color.from_hsv(0.0, 0.9, 1.0))
	var line_b := Genome.random(Color.from_hsv(0.5, 0.9, 1.0))
	for generation in 40:
		var next := Genome.mix(line_a, line_b)
		line_a = line_b
		line_b = next

	_check(
		"40 generations of mixing clashing colours does not fade to grey (saturation %.2f)"
		% line_b.color.s,
		line_b.color.s > 0.5
	)


## Low genetic diversity is PENALISED: parents that are too alike throw children with bigger, wilder
## mutations. This is the whole point of the inbreeding rule, so measure it rather than trust it.
func _inbreeding_amplifies_mutation() -> void:
	var clone_a := Genome.random(Color.RED)
	var clone_b := Genome.new()
	for gene: String in Genome.RANGES:
		clone_b.set(gene, clone_a.get(gene))
	clone_b.color = clone_a.color
	clone_b.attractor = clone_a.attractor
	clone_b.attractor_target = clone_a.attractor_target
	clone_b.turnoff = clone_a.turnoff
	clone_b.turnoff_target = clone_a.turnoff_target

	# Two genuinely unrelated animals, for comparison.
	var stranger_a := Genome.random(Color.RED)
	var stranger_b := Genome.new()
	for gene: String in Genome.RANGES:
		var limits: Vector2 = Genome.RANGES[gene]
		stranger_a.set(gene, limits.x)
		stranger_b.set(gene, limits.y)
	stranger_a.color = Color.BLACK
	stranger_b.color = Color.WHITE
	stranger_a.attractor = Genome.Attractor.VIVIDNESS
	stranger_b.attractor = Genome.Attractor.RARITY

	_check("clones read as genetically identical", is_zero_approx(Genome.distance(clone_a, clone_b)))

	var inbred_spread := _mean_deviation(clone_a, clone_b)
	var outbred_spread := _mean_deviation(stranger_a, stranger_b)

	_check(
		"inbreeding produces bigger mutations than outbreeding (%.4f vs %.4f)"
		% [inbred_spread, outbred_spread],
		inbred_spread > outbred_spread
	)
	# And meaningfully bigger, not just noise.
	_check(
		"the inbreeding penalty actually bites (%.2fx)" % (inbred_spread / maxf(outbred_spread, 0.0001)),
		inbred_spread > outbred_spread * 1.5
	)


## Average distance of a child's genes from its parents' midpoint, as a fraction of each gene's range.
func _mean_deviation(a: Genome, b: Genome) -> float:
	var total := 0.0
	var terms := 0
	for i in SAMPLES:
		var child := Genome.mix(a, b)
		for gene: String in Genome.RANGES:
			var limits: Vector2 = Genome.RANGES[gene]
			var span: float = limits.y - limits.x
			var midpoint: float = (a.get(gene) + b.get(gene)) * 0.5
			total += absf(child.get(gene) - midpoint) / span
			terms += 1
	return total / terms


func _attractors_are_inherited() -> void:
	var a := Genome.random(Color.RED)
	var b := Genome.random(Color.BLUE)
	a.attractor = Genome.Attractor.VIVIDNESS
	a.attractor_target = 1.0
	a.turnoff = Genome.Attractor.SIZE
	b.attractor = Genome.Attractor.SIZE
	b.attractor_target = 0.0
	b.turnoff = Genome.Attractor.SPEED

	var from_parent := 0
	for i in SAMPLES:
		var child := Genome.mix(a, b)
		_check("a child's taste is always a real attractor", Genome.ATTRACTORS.has(child.attractor))
		_check("a child's turn-off is always a real attractor", Genome.ATTRACTORS.has(child.turnoff))
		_check(
			"targets stay within 0..1",
			child.attractor_target >= 0.0 and child.attractor_target <= 1.0
			and child.turnoff_target >= 0.0 and child.turnoff_target <= 1.0
		)
		if child.attractor == a.attractor or child.attractor == b.attractor:
			from_parent += 1
		if _failures > 0:
			return

	# Mostly inherited, but not always — taste can mutate, which is what lets a new drive appear at all.
	var inherited := float(from_parent) / SAMPLES
	_check("taste is usually inherited from a parent (%.2f)" % inherited, inherited > 0.7)
	_check("...but not always: it can mutate (%.2f)" % inherited, inherited < 1.0)


## THE ECONOMY'S SPINE.
##
## `sides` blends like any other gene, and a blend lands BETWEEN its parents — so left alone, face count
## regresses to the mean, no lineage ever reaches a Dodeca, and the value system (priced entirely off
## face count) quietly flattens. The additive mutation is what keeps the ladder climbable. If this test
## fails, rarity is dead and the game has no economy.
func _the_ladder_still_climbs() -> void:
	var limits: Vector2 = Genome.RANGES["sides"]

	# Start a lineage at the very bottom of the range and breed it forward. It must be ABLE to climb.
	var best := 0.0
	for run in 40:
		var a := Genome.random(Color.RED)
		var b := Genome.random(Color.BLUE)
		a.sides = limits.x
		b.sides = limits.x

		for generation in 30:
			var child := Genome.mix(a, b)
			a = b
			b = child
			best = maxf(best, child.sides)

	_check(
		"a lineage starting at the fewest sides can still climb to the most (reached %.1f of %.1f)"
		% [best, limits.y],
		best >= limits.y - 0.5
	)

	# And the additive step must actually reach ABOVE the better parent, not merely between the two.
	var climbed := 0
	for i in SAMPLES:
		var a := Genome.new()
		var b := Genome.new()
		a.sides = 5.0
		b.sides = 5.0
		if Genome.mix(a, b).sides > 5.5:
			climbed += 1
	var rate := float(climbed) / SAMPLES
	_check("children sometimes come out with MORE sides than either parent (%.2f)" % rate, rate > 0.15)


## Gaits are corners of a continuous space, not types — so any two parents produce a valid child, and a
## flyer crossed with a hopper lands BETWEEN them rather than snapping to one or the other.
func _locomotion_blends() -> void:
	var flyer := Genome.random(Color.RED)
	flyer.buoyancy = 1.0
	flyer.hop = 0.0
	flyer.cling = 0.0

	var frog := Genome.random(Color.BLUE)
	frog.buoyancy = 0.0
	frog.hop = 1.0
	frog.cling = 0.0

	_check("a pure floater reads as a flyer", flyer.gait() == "flyer")
	_check("a heavy jumper reads as a hopper", frog.gait() == "hopper")

	var between := 0
	for i in SAMPLES:
		var child := Genome.mix(flyer, frog)
		for gene: String in ["buoyancy", "hop", "cling"]:
			var limits: Vector2 = Genome.RANGES[gene]
			var value: float = child.get(gene)
			if value < limits.x - 0.0001 or value > limits.y + 0.0001:
				_check("locomotion gene '%s' escaped its range (%.2f)" % [gene, value], false)
				return
		# The cross should mostly land in the middle ground — a bounding half-floater.
		if child.buoyancy > 0.15 and child.buoyancy < 0.85:
			between += 1

	_check("a flyer crossed with a hopper is usually neither, but something in between", between > SAMPLES / 2)


func _check(what: String, passed: bool) -> void:
	if not passed:
		_failures += 1
		print("  FAILED: %s" % what)
