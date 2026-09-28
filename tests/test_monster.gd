extends SceneTree

## Headless checks for flocking weights and mate choice:
##   godot --headless --script res://tests/test_monster.gd

var _failures := 0


func _initialize() -> void:
	_color_affinity()
	_shape_outranks_color()
	_mate_choice()

	if _failures == 0:
		print("PASS: all monster checks")
	else:
		print("FAIL: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _color_affinity() -> void:
	var red := Color(1, 0, 0)
	var cyan := Color(0, 1, 1)
	var pink := Color(1, 0.3, 0.3)

	_check("identical colors are perfectly alike", is_equal_approx(Monster.color_affinity(red, red), 1.0))
	_check("opposite colors are maximally unalike", Monster.color_affinity(red, cyan) < 0.05)
	_check("a near color sits in between", Monster.color_affinity(red, pink) > Monster.color_affinity(red, cyan))
	_check("affinity is symmetric", is_equal_approx(Monster.color_affinity(red, pink), Monster.color_affinity(pink, red)))


## Animals flock by SHAPE first and colour second. The trade-off is a gene, so this must hold for every
## value it can take — otherwise some lineage could evolve into flocking purely by colour.
func _shape_outranks_color() -> void:
	var limits: Vector2 = Genome.RANGES["kin_color_bias"]

	for step in 21:
		var bias: float = lerpf(limits.x, limits.y, step / 20.0)
		var genome := Genome.new()
		genome.kin_color_bias = bias

		var worst := genome.kin_weight(Color.RED, Color.CYAN)
		var best := genome.kin_weight(Color.RED, Color.RED)

		_check("at colour-bias %.2f, a clashing flockmate still attracts (%.3f)" % [bias, worst], worst > 0.0)
		_check("at colour-bias %.2f, a colour match attracts at least as much" % bias, best >= worst)
		_check("at colour-bias %.2f, kin weight never exceeds 1" % bias, best <= 1.0001)


# --- Mate choice ---------------------------------------------------------------------------------


## An animal with given normalised traits. Species is derived from the shape genes now, so `sides` is
## what decides how rare it reads as.
func _animal(sides: float, vividness: float, size: float, speed: float) -> Monster:
	var monster := Monster.new()
	var genome := Genome.new()
	genome.sides = sides
	genome.taper = 1.0  # a tube, so faces = sides + 2
	genome.color = Color.from_hsv(0.5, vividness, 1.0)
	genome.max_size = lerpf(Genome.RANGES["max_size"].x, Genome.RANGES["max_size"].y, size)
	genome.speed_mult = lerpf(Genome.RANGES["speed_mult"].x, Genome.RANGES["speed_mult"].y, speed)
	# A turn-off nobody in these tests matches, so it never muddies the comparison.
	genome.turnoff = Genome.Attractor.BUOYANCY
	genome.turnoff_target = 1.0
	genome.buoyancy = 0.0
	monster.genome = genome
	return monster


func _mate_choice() -> void:
	# Two candidates: one vivid but tiny and slow, one drab but huge and fast.
	var vivid := _animal(4.0, 1.0, 0.0, 0.0)
	var drab := _animal(4.0, 0.0, 1.0, 1.0)

	# An animal that goes for vividness prefers the vivid one, EVEN THOUGH the drab one wins every other
	# trait. That is what makes the attractor primary rather than just another vote.
	var suitor := _animal(4.0, 0.5, 0.5, 0.5)
	suitor.genome.attractor = Genome.Attractor.VIVIDNESS
	suitor.genome.attractor_target = 1.0
	_check(
		"the primary attractor outweighs every secondary put together",
		suitor.fitness_of(vivid) > suitor.fitness_of(drab)
	)

	# Target 0.0 inverts it: this animal now wants the DRABBEST mate it can find.
	suitor.genome.attractor_target = 0.0
	_check(
		"a target of zero reverses who is attractive",
		suitor.fitness_of(drab) > suitor.fitness_of(vivid)
	)

	# THE POINT OF TARGETS. An animal can want a SPECIFIC amount of something — here, a middling
	# vividness — and be put off by too much just as much as by too little. A high/low switch could
	# never express this.
	var middling := _animal(4.0, 0.5, 0.5, 0.5)
	suitor.genome.attractor_target = 0.5
	_check(
		"an animal wanting HALF vividness prefers a middling mate to a vivid one",
		suitor.fitness_of(middling) > suitor.fitness_of(vivid)
	)
	_check(
		"...and to a drab one, too — it is put off by too little as well as too much",
		suitor.fitness_of(middling) > suitor.fitness_of(drab)
	)

	# Rarity works off derived face count, so more sides should out-score fewer for a rarity-chaser.
	var common := _animal(4.0, 0.5, 0.5, 0.5)
	var rare := _animal(10.0, 0.5, 0.5, 0.5)
	_check("more sides really does mean a rarer species", Species.faces(rare.species) > Species.faces(common.species))

	suitor.genome.attractor = Genome.Attractor.RARITY
	suitor.genome.attractor_target = 1.0
	_check("a rarity-chaser prefers the higher face count", suitor.fitness_of(rare) > suitor.fitness_of(common))
	suitor.genome.attractor_target = 0.0
	_check("...and one that likes common animals prefers the plain one", suitor.fitness_of(common) > suitor.fitness_of(rare))

	# Genetic difference: an outbreeder prefers a stranger to its own twin; an inbreeder the reverse.
	var outbreeder := _animal(4.0, 0.5, 0.5, 0.5)
	outbreeder.genome.attractor = Genome.Attractor.DIFFERENCE
	outbreeder.genome.attractor_target = 1.0

	var stranger := _animal(9.0, 0.9, 0.9, 0.9)
	stranger.genome.attractor = Genome.Attractor.SPEED

	var outbred_twin := _clone_of(outbreeder)
	_check(
		"an outbreeder prefers a stranger to its own twin",
		outbreeder.fitness_of(stranger) > outbreeder.fitness_of(outbred_twin)
	)
	outbred_twin.free()

	outbreeder.genome.attractor_target = 0.0
	var twin := _clone_of(outbreeder)
	_check(
		"an inbreeder prefers its twin to a stranger who wins every secondary",
		outbreeder.fitness_of(twin) > outbreeder.fitness_of(stranger)
	)

	_turn_offs()

	# Scores must stay in range, or the acceptance gate means nothing.
	for candidate in [vivid, drab, common, rare, twin, stranger, middling]:
		var score := suitor.fitness_of(candidate)
		_check("fitness stays within 0..1 (%.3f)" % score, score >= 0.0 and score <= 1.0)

	# The acceptance bar has to be low enough that ordinary animals still breed — a herd that refuses
	# everything quietly stops reproducing, and a frozen population reads as a bug, not as good taste.
	suitor.genome.attractor = Genome.Attractor.VIVIDNESS
	suitor.genome.attractor_target = 0.5
	_check("an average animal clears the acceptance bar", suitor.fitness_of(middling) > Monster.ACCEPTABLE)

	# A corpse is nobody's prospect.
	middling.dead = true
	_check("a dead animal has no appeal at all", is_zero_approx(suitor.fitness_of(middling)))

	for animal in [vivid, drab, common, rare, twin, stranger, suitor, outbreeder, middling]:
		animal.free()


## A turn-off subtracts. An animal can chase one thing while being repelled by another, so a candidate
## that nails what it wants can still be spoiled by carrying what it hates.
func _turn_offs() -> void:
	var plain := _animal(4.0, 1.0, 0.0, 0.5)
	var giant := _animal(4.0, 1.0, 1.0, 0.5)

	var suitor := _animal(4.0, 0.5, 0.5, 0.5)
	suitor.genome.attractor = Genome.Attractor.VIVIDNESS
	suitor.genome.attractor_target = 1.0
	suitor.genome.turnoff = Genome.Attractor.BUOYANCY
	suitor.genome.turnoff_target = 1.0  # neither candidate is buoyant, so nothing is repellent yet

	var before := suitor.fitness_of(giant)

	# Now make it hate giants. Both candidates are equally vivid, but one is huge.
	suitor.genome.turnoff = Genome.Attractor.SIZE
	suitor.genome.turnoff_target = 1.0

	var after := suitor.fitness_of(giant)
	_check("a turn-off lowers a candidate's score (%.3f -> %.3f)" % [before, after], after < before)
	_check(
		"a repellent candidate loses to an equally attractive one that lacks the flaw",
		suitor.fitness_of(plain) > suitor.fitness_of(giant)
	)
	_check("...but a turn-off can never push fitness below zero", after >= 0.0)

	for animal in [plain, giant, suitor]:
		animal.free()


## An exact genetic copy, taste included.
func _clone_of(original: Monster) -> Monster:
	var copy := Monster.new()
	var genome := Genome.new()
	for gene: String in Genome.RANGES:
		genome.set(gene, original.genome.get(gene))
	genome.color = original.genome.color
	genome.attractor = original.genome.attractor
	genome.attractor_target = original.genome.attractor_target
	genome.turnoff = original.genome.turnoff
	genome.turnoff_target = original.genome.turnoff_target
	copy.genome = genome

	_check("a clone is at zero genetic distance", is_zero_approx(Genome.distance(genome, original.genome)))
	return copy


func _check(what: String, passed: bool) -> void:
	if not passed:
		_failures += 1
		print("  FAILED: %s" % what)
