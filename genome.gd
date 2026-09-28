class_name Genome
extends RefCounted

## Every heritable trait: what an animal looks like, how it moves, how it flocks, and what it wants in a
## mate. Nothing about a polymon is a fixed category any more — its SHAPE and its way of MOVING are just
## numbers that blend and mutate like everything else.
##
## Mutation is not constant: the more alike two parents are, the bigger and likelier their child's
## mutations. Inbreeding buys instability.

## What an animal weighs most heavily when sizing up a mate — and, separately, what repels it.
enum Attractor { VIVIDNESS, SIZE, SPEED, RARITY, DIFFERENCE, BUOYANCY }

const ATTRACTORS := [
	Attractor.VIVIDNESS,
	Attractor.SIZE,
	Attractor.SPEED,
	Attractor.RARITY,
	Attractor.DIFFERENCE,
	Attractor.BUOYANCY,
]

const ATTRACTOR_NAMES := {
	Attractor.VIVIDNESS: "vividness",
	Attractor.SIZE: "size",
	Attractor.SPEED: "speed",
	Attractor.RARITY: "rarity",
	Attractor.DIFFERENCE: "difference",
	Attractor.BUOYANCY: "buoyancy",
}

## Range each numeric gene is rolled within and clamped to.
const RANGES := {
	# --- Shape. The species is DERIVED from these (Species.of), never stored, so a polymon's form
	# --- evolves as organically as anything else about it.
	"sides": Vector2(3.0, 10.0),
	## 0 = spike (a cone/pyramid), 1 = tube (a prism). The old STAR and SQUARE paths are now the two
	## ends of one continuous axis, which is what lets a lineage slide from one to the other.
	"taper": Vector2(0.0, 1.0),
	## Past the halfway mark the solid is mirrored top-to-bottom into a bipyramid — how an octahedron
	## comes to exist at all.
	"symmetry": Vector2(0.0, 1.0),
	# --- Locomotion. Flyers, frogs and scooters are not types; they are CORNERS of this space, so every
	# --- cross between them is automatically a real animal.
	## 0 = falls under gravity, 1 = floats freely.
	"buoyancy": Vector2(0.0, 1.0),
	## 0 = never jumps, 1 = launches hard off any surface it touches.
	"hop": Vector2(0.0, 1.0),
	## 0 = ignores surfaces, 1 = hugs the floor and walls.
	"cling": Vector2(0.0, 1.0),
	# --- Body and temperament.
	"speed_mult": Vector2(0.6, 1.5),
	"max_size": Vector2(0.5, 2.2),
	"cohesion": Vector2(0.0, 1.6),
	"alignment": Vector2(0.0, 1.6),
	"separation": Vector2(0.6, 2.6),
	"kin_color_bias": Vector2(0.0, 0.75),
	"xeno_avoidance": Vector2(0.0, 2.0),
	"courtship": Vector2(0.4, 3.0),
	"wander": Vector2(0.0, 1.5),
}

## Baseline drift from the parents' average, as a fraction of each gene's range.
const MUTATION := 0.07
## How much identical parents amplify that drift.
const INBREED_PENALTY := 2.5
## Odds of a rare, large mutation — scaled by how alike the parents are.
const BIG_JUMP_CHANCE := 0.18
const BIG_JUMP_SIZE := 0.35

## THE LADDER'S LIFELINE.
##
## `sides` blends like any other gene, and a blend always lands BETWEEN its parents — so face count would
## regress to the mean, no lineage would ever reach a Dodeca, and the value economy (priced entirely off
## face count) would quietly flatten. This is the old additive step, surviving as a mutation: sometimes a
## child comes out with one more side than its better parent. Drift makes shape organic; this keeps the
## ladder climbable.
const ADDITIVE_CHANCE := 0.25

const COLOR_MUTATION := 0.06
## Odds a child re-rolls what it finds attractive (or repellent), or shifts what it is looking for.
const ATTRACTOR_MUTATION := 0.08
const TARGET_MUTATION := 0.12

var sides := 5.0
var taper := 0.5
var symmetry := 0.0

var buoyancy := 1.0
var hop := 0.0
var cling := 0.0

var speed_mult := 1.0
var max_size := 1.0
var cohesion := 0.6
var alignment := 0.7
var separation := 1.8
var kin_color_bias := 0.4
var xeno_avoidance := 1.1
var courtship := 2.2
var wander := 0.7
var color := Color.WHITE

## What this animal is looking for, and HOW MUCH of it. A target of 1.0 or 0.0 reproduces the old
## "wants the most" / "wants the least"; anything between lets an animal want a specific amount — a
## middling size, a moderate speed — which a high/low switch could never express.
var attractor: Attractor = Attractor.VIVIDNESS
var attractor_target := 1.0

## And what puts it off. The turn-off subtracts from a candidate's score the closer that candidate sits
## to this target, so an animal can chase vividness while being repelled by giants.
var turnoff: Attractor = Attractor.SIZE
var turnoff_target := 1.0


static func random(with_color: Color) -> Genome:
	var genome := Genome.new()
	for gene: String in RANGES:
		var limits: Vector2 = RANGES[gene]
		genome.set(gene, randf_range(limits.x, limits.y))
	genome.color = with_color

	genome.attractor = ATTRACTORS.pick_random()
	genome.attractor_target = _random_target()
	genome.turnoff = ATTRACTORS.pick_random()
	genome.turnoff_target = _random_target()
	return genome


## Targets cluster at the extremes — most animals want the most or the least of something — but a
## meaningful minority want a particular middling amount.
static func _random_target() -> float:
	var roll := randf()
	if roll < 0.4:
		return 1.0
	if roll < 0.8:
		return 0.0
	return randf()


## How unlike two genomes are, 0.0 (identical) to 1.0. The primitive that mate choice and the inbreeding
## penalty are both built on.
static func distance(a: Genome, b: Genome) -> float:
	var total := 0.0
	var terms := 0

	for gene: String in RANGES:
		var limits: Vector2 = RANGES[gene]
		var span: float = limits.y - limits.x
		total += absf(a.get(gene) - b.get(gene)) / span
		terms += 1

	total += Vector3(a.color.r - b.color.r, a.color.g - b.color.g, a.color.b - b.color.b).length() / sqrt(3.0)
	terms += 1

	total += 0.0 if a.attractor == b.attractor else 1.0
	terms += 1
	total += absf(a.attractor_target - b.attractor_target)
	terms += 1

	return clampf(total / terms, 0.0, 1.0)


## A child of two parents. The closer they are, the harsher the mutation.
static func mix(a: Genome, b: Genome) -> Genome:
	var genome := Genome.new()

	var similarity := 1.0 - distance(a, b)
	var drift := MUTATION * (1.0 + INBREED_PENALTY * similarity)
	var jump_odds := BIG_JUMP_CHANCE * similarity

	for gene: String in RANGES:
		var limits: Vector2 = RANGES[gene]
		var span: float = limits.y - limits.x
		var blended: float = (a.get(gene) + b.get(gene)) * 0.5

		var mutation := randf_range(-drift, drift) * span
		if randf() < jump_odds:
			mutation += randf_range(-BIG_JUMP_SIZE, BIG_JUMP_SIZE) * span

		genome.set(gene, clampf(blended + mutation, limits.x, limits.y))

	# The additive step: without it, blending would cap every lineage at its founders' rarity.
	if randf() < ADDITIVE_CHANCE:
		genome.sides = clampf(maxf(a.sides, b.sides) + 1.0, RANGES["sides"].x, RANGES["sides"].y)

	genome.color = _mix_color(a.color, b.color, drift)
	genome._inherit_taste(a, b)
	return genome


## Taste is part categorical (which trait) and part continuous (how much of it), so it is inherited in
## two pieces: the trait comes from one parent outright, the target is blended.
func _inherit_taste(a: Genome, b: Genome) -> void:
	var parent: Genome = a if randf() < 0.5 else b
	attractor = parent.attractor
	turnoff = parent.turnoff

	attractor_target = clampf((a.attractor_target + b.attractor_target) * 0.5, 0.0, 1.0)
	turnoff_target = clampf((a.turnoff_target + b.turnoff_target) * 0.5, 0.0, 1.0)

	if randf() < ATTRACTOR_MUTATION:
		attractor = ATTRACTORS.pick_random()
	if randf() < ATTRACTOR_MUTATION:
		turnoff = ATTRACTORS.pick_random()
	if randf() < TARGET_MUTATION:
		attractor_target = clampf(attractor_target + randf_range(-0.3, 0.3), 0.0, 1.0)
	if randf() < TARGET_MUTATION:
		turnoff_target = clampf(turnoff_target + randf_range(-0.3, 0.3), 0.0, 1.0)


## Colour blends in HSV, NOT in RGB — and that is why herds no longer fade to grey. Averaging two hues
## channel-by-channel makes mud (red + blue = a dark muddy purple), and repeating that across generations
## bleeds every line toward sludge. Interpolating the HUE around the wheel keeps red + blue a VIVID purple.
static func _mix_color(a: Color, b: Color, drift: float) -> Color:
	var hue := _mix_hue(a.h, b.h)
	var saturation := (a.s + b.s) * 0.5
	var value := (a.v + b.v) * 0.5

	var wobble := COLOR_MUTATION * (1.0 + drift)
	hue = fposmod(hue + randf_range(-wobble, wobble), 1.0)
	saturation = clampf(saturation + randf_range(-wobble, wobble), 0.0, 1.0)
	value = clampf(value + randf_range(-wobble, wobble), 0.35, 1.0)

	return Color.from_hsv(hue, saturation, value)


## Hue lives on a circle, so the midpoint of 0.95 and 0.05 is red, not cyan.
static func _mix_hue(a: float, b: float) -> float:
	var difference := fposmod(b - a, 1.0)
	if difference > 0.5:
		difference -= 1.0
	return fposmod(a + difference * 0.5, 1.0)


func kin_weight(mine: Color, theirs: Color) -> float:
	return (1.0 - kin_color_bias) + kin_color_bias * Monster.color_affinity(mine, theirs)


func taste() -> String:
	return (
		"likes %s @%d%%\nrepelled by %s @%d%%"
		% [
			ATTRACTOR_NAMES[attractor], roundi(attractor_target * 100.0),
			ATTRACTOR_NAMES[turnoff], roundi(turnoff_target * 100.0),
		]
	)


## How this animal gets around, in words — the emergent creature that its locomotion genes add up to.
func gait() -> String:
	if buoyancy > 0.66:
		return "flyer" if hop < 0.5 else "flitter"
	if cling > 0.6:
		return "scooter"
	if hop > 0.5:
		return "hopper"
	return "walker" if buoyancy < 0.33 else "drifter"


func describe() -> String:
	return (
		"speed x%.2f  size x%.2f\ngait: %s  (float %.2f hop %.2f cling %.2f)\n%s"
		% [speed_mult, max_size, gait(), buoyancy, hop, cling, taste()]
	)
