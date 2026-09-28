class_name Monster
extends RigidBody3D

## Emitted by the animal that initiates the pairing, so the arena only hears about each meeting once.
signal wants_to_breed(parent_a, parent_b)
signal clicked(monster)

# --- Boids ---------------------------------------------------------------------------------------
## How far an animal looks for flockmates — and how far it keeps away from other species.
const NEIGHBOR_RADIUS := 5.0
## Inside this, it pushes away from ANY neighbor — flocking should not mean overlapping.
const SEPARATION_RADIUS := 1.6

## The boid weights below are no longer constants shared by every animal — each one is a GENE, carried
## in the Genome and inherited. What remains here are the weights the herd cannot evolve away from:
## hunger and walls.
##
## Hunger overrides sociability — a starving animal leaves the flock to go eat.
const FOOD_WEIGHT := 2.6
const WALL_WEIGHT := 2.2

# --- Locomotion ----------------------------------------------------------------------------------
## How hard gravity pulls a fully un-buoyant animal. Flyers feel none of it.
const GRAVITY := 1.4
const HOP_FORCE := 9.0
const HOP_INTERVAL := Vector2(0.8, 2.2)
const CLING_FORCE := 4.0

## Bouncy walls already exist, but boids left alone will press into a corner and hug it.
const WALL_MARGIN := 1.5
## How fast steering can turn the animal. Physics still owns collisions.
const TURN_RATE := 2.5
## Seconds between re-rolls of the random wander nudge.
const WANDER_INTERVAL := Vector2(1.0, 3.0)

# --- Life ----------------------------------------------------------------------------------------
## How long a parent rests after breeding. The one timing that does not vary by species.
##
## It is also the clock that governs sociability: an animal only mingles with other species while
## fertile, so a long cooldown means long stretches of segregation between brief mating windows.
const BREED_COOLDOWN := 45.0
## Fraction of the way to starving at which the animal begs for food and stops breeding.
const HUNGRY_AT := 0.55

## Size of a newborn relative to the adult it will become. Juveniles start tiny...
const JUVENILE_SIZE := 0.15
## ...and take this much longer than their species' maturity to get there, so growing up is a real wait.
const GROWTH_SLOWDOWN := 2.5
const MARKER_GAP := 0.3
## How see-through the shell is. The core inside stays opaque.
const ALPHA := 0.72

# --- Mate choice ---------------------------------------------------------------------------------
## An animal weighs its own attractor this heavily and everything else the rest.
##
## The split has to be lopsided, not merely tilted. At 60/40 the primary is "weighted highest" but is not
## DECISIVE: two candidates a hair apart on the primary axis, with one sweeping every secondary, let the
## secondaries quietly outvote the attractor — which would make an animal's drive decorative and mute the
## sexual selection this is all for. At 75/25 the attractor decides, and the secondaries break ties.
const PRIMARY_WEIGHT := 0.75
const SECONDARY_WEIGHT := 0.25
## How much a candidate matching this animal's turn-off costs it. Kept below the primary weight so a
## revulsion can spoil a match but never wholly override what the animal is actually looking for.
const TURNOFF_WEIGHT := 0.4
## A partner scoring below this is turned down on contact. Deliberately low: animals should COURT the
## best mate they can see, but still accept an adequate one — a hard bar risks a herd that quietly stops
## breeding altogether, which reads as a bug rather than as choosiness.
const ACCEPTABLE := 0.25

## Every heritable trait: shape, gait, colour, and how this animal flocks. The arena sets it before
## add_child.
var genome := Genome.new()

## The species is DERIVED from the shape genes, never stored — see Species.of. Everything economic still
## hangs off it (name, rarity, value, price); it is simply emergent now rather than assigned.
var species: String:
	get:
		return Species.of(genome)

## Convenience passthrough — the market, the HUD and breeding all talk about an animal's colour.
var color: Color:
	get:
		return genome.color
	set(value):
		genome.color = value

## 0.0 = just fed, 1.0 = dead.
var hunger := 0.0
## Seconds lived. Drives growth and old age, and must stay separate from _breed_timer — that timer is
## reused for the post-breeding cooldown, so sizing off it would shrink an adult back to a baby every
## time it bred.
var age := 0.0
var selected := false: set = _set_selected
## True while the player is carrying it. A held animal is frozen and driven by the mouse — which is also
## how it gets carried into ANOTHER TANK, since a live physics body would simply bounce off the glass.
var held := false

## A corpse: it fades, sinks, and does nothing. It is nobody's flockmate and nobody's mate — a dead
## animal that still courted would be worse than having no corpses at all. It stays in the tank until
## the player drags it to the disposal bin.
var dead := false

# Per-species traits, read from Species.TABLE once the species is known (see _ready).
var _speed := 3.0
var _maturity := 8.0
var _starve_time := 150.0
var _lifespan := 420.0

var _breed_timer := 0.0
var _wander_timer := 0.0
var _hop_timer := 0.0
var _wander_dir := Vector3.ZERO
var _material: StandardMaterial3D
var _core_material: StandardMaterial3D

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _core: MeshInstance3D = $Core
@onready var _collision: CollisionShape3D = $Collision
@onready var _marker: Label3D = $Marker


## The child's color is the average of its parents'. Repeated averaging bleeds saturation, which is
## exactly the pressure the economy is built on — see Species.sale_value.
static func mix_colors(a: Color, b: Color) -> Color:
	return a.lerp(b, 0.5)


func _ready() -> void:
	# Traits only become known once `species` and `genome` are set, which the arena does before add_child.
	# Species sets the baseline pace and genes vary around it — a Dodeca stays sluggish next to a Tetra
	# however its speed gene rolled.
	_speed = Species.trait_of(species, "speed") * genome.speed_mult
	_maturity = Species.trait_of(species, "maturity")
	_starve_time = Species.trait_of(species, "starve")
	_lifespan = Species.trait_of(species, "lifespan")
	# Seed the fertility timer here rather than at its declaration, where the species isn't known yet.
	# An animal is fertile once it is grown, so this tracks the (slowed) growth clock, not the raw
	# species maturity.
	_breed_timer = _maturity * GROWTH_SLOWDOWN

	_mesh.mesh = Species.mesh_for(species)

	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = _material

	# The shell is see-through, so an opaque core reads clearly inside it.
	_core_material = StandardMaterial3D.new()
	_core_material.emission_enabled = true
	_core_material.emission_energy_multiplier = 1.4
	_core.material_override = _core_material

	body_entered.connect(_on_body_entered)
	input_event.connect(_on_input_event)

	# A floating animal ignores gravity; a heavy one falls and has to walk, scoot or hop. Everything in
	# between is a real animal too, which is what makes the gaits interbreed for free.
	gravity_scale = (1.0 - genome.buoyancy) * GRAVITY

	_marker.visible = false
	_wander_dir = _random_direction()
	linear_velocity = _wander_dir * _speed
	angular_velocity = _random_direction() * 1.5
	_refresh_appearance()


func _physics_process(delta: float) -> void:
	if dead:
		# A corpse just sinks. No ageing, no steering, no courting.
		_refresh_appearance()
		return

	_age(delta)
	# A held animal is being carried by the player; boids resume the moment it is let go.
	if not held:
		_steer(delta)
		_locomote(delta)
	_refresh_appearance()


## Death does not remove an animal — it leaves a body. It sinks, fades, and stops taking part in
## anything, and it is the player's job to drag it to the disposal bin.
func die() -> void:
	if dead:
		return
	dead = true
	selected = false
	gravity_scale = 1.0
	angular_damp = 1.0
	linear_velocity *= 0.2
	_marker.visible = false


## The tank this animal lives in. Its flockmates are simply its siblings, so animals in other tanks are
## structurally invisible — there is no filter to forget.
func tank() -> Tank:
	return get_parent().get_parent() as Tank


func grab() -> void:
	held = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func carry_to(point: Vector3) -> void:
	global_position = point


func release() -> void:
	held = false
	freeze = false
	launch()


func _age(delta: float) -> void:
	hunger += delta / _starve_time
	if hunger >= 1.0:
		die()
		return

	age += delta
	if age >= _lifespan:
		die()
		return

	if _breed_timer > 0.0:
		_breed_timer -= delta


# --- Locomotion ----------------------------------------------------------------------------------


## Hops and surface-clinging, the parts of getting around that physics has to do rather than steering.
##
## A heavy animal cannot swim to where it wants to go, so it hops there instead; a clinging one presses
## itself to the nearest surface. Neither is a "type" — they are just what high `hop` and high `cling`
## look like, and an animal can have any amount of both.
func _locomote(delta: float) -> void:
	if genome.cling > 0.05:
		# Press toward the nearest wall or floor, so scooters end up hugging a surface.
		apply_central_force(_nearest_surface() * genome.cling * CLING_FORCE)

	if genome.hop < 0.05:
		return

	_hop_timer -= delta
	if _hop_timer > 0.0:
		return

	# Only push off something solid. A hopper in mid-air is just falling.
	if _on_surface():
		_hop_timer = randf_range(HOP_INTERVAL.x, HOP_INTERVAL.y) / maxf(genome.hop, 0.1)
		var launch_dir := (Vector3.UP + _wander_dir * 0.6).normalized()
		apply_central_impulse(launch_dir * genome.hop * HOP_FORCE * genome.max_size)


## Which way the nearest surface lies, in tank-local space.
func _nearest_surface() -> Vector3:
	var to_floor: float = position.y + Tank.EXTENTS.y
	var closest := Vector3.DOWN
	var shortest := to_floor

	for axis in [0, 2]:
		var to_low: float = position[axis] + Tank.EXTENTS[axis]
		var to_high: float = Tank.EXTENTS[axis] - position[axis]
		if to_low < shortest:
			shortest = to_low
			closest = Vector3.ZERO
			closest[axis] = -1.0
		if to_high < shortest:
			shortest = to_high
			closest = Vector3.ZERO
			closest[axis] = 1.0
	return closest


func _on_surface() -> bool:
	return position.y < -Tank.EXTENTS.y + 1.0 + size()


# --- Steering ------------------------------------------------------------------------------------


## Boids: separation, alignment, cohesion — plus a random nudge so movement stays organic, a pull
## toward food when hungry, and a shove away from the walls.
func _steer(delta: float) -> void:
	var desired := Vector3.ZERO
	desired += _flock()
	desired += _wander(delta) * genome.wander
	desired += _seek_food() * FOOD_WEIGHT
	desired += _avoid_walls() * WALL_WEIGHT

	# Steering picks the direction; the species' speed sets the pace. Collisions bleed off velocity even
	# with a perfectly bouncy material, so the magnitude is re-imposed every frame.
	var heading := linear_velocity
	if desired.length_squared() > 0.0001:
		heading = heading.lerp(desired.normalized() * _speed, minf(TURN_RATE * delta, 1.0))
	if heading.length_squared() < 0.001:
		heading = _random_direction()
	var swim := heading.normalized() * _speed

	# A heavy animal cannot simply will itself upward — gravity owns its vertical motion, and it gets
	# where it is going by hopping and scooting instead. Only a buoyant one steers in full 3D. Without
	# this, a "walker" would serenely swim through the air and the gaits would all look the same.
	linear_velocity.x = swim.x
	linear_velocity.z = swim.z
	linear_velocity.y = lerpf(linear_velocity.y, swim.y, genome.buoyancy)


## How alike two colors are: 1.0 identical, 0.0 opposite.
static func color_affinity(a: Color, b: Color) -> float:
	var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() / sqrt(3.0)
	return clampf(1.0 - distance, 0.0, 1.0)


# --- Mate choice ---------------------------------------------------------------------------------


## Every trait a mate can be judged on, each normalised to 0..1.
func _traits_of(candidate: Monster) -> Dictionary:
	var size_range: Vector2 = Genome.RANGES["max_size"]
	var speed_range: Vector2 = Genome.RANGES["speed_mult"]
	return {
		Genome.Attractor.VIVIDNESS: candidate.color.s,
		Genome.Attractor.SIZE: inverse_lerp(size_range.x, size_range.y, candidate.genome.max_size),
		Genome.Attractor.SPEED: inverse_lerp(speed_range.x, speed_range.y, candidate.genome.speed_mult),
		Genome.Attractor.RARITY: inverse_lerp(
			Species.MIN_FACES, Species.MAX_FACES, Species.faces(candidate.species)
		),
		# How unlike me this candidate is — the axis an outbreeder chases and an inbreeder avoids.
		Genome.Attractor.DIFFERENCE: Genome.distance(genome, candidate.genome),
		Genome.Attractor.BUOYANCY: candidate.genome.buoyancy,
	}


## How well a candidate hits a wanted amount of something. A target of 1.0 or 0.0 means "as much as
## possible" / "as little as possible"; anything between means an animal wants a SPECIFIC amount, and is
## put off by too much just as much as by too little.
static func _match_score(value: float, target: float) -> float:
	return 1.0 - absf(value - target)


## How appealing this animal finds a candidate, 0..1 — judged from ITS OWN point of view.
##
## Its attractor decides which trait dominates and how much of it it wants; its turn-off decides what
## repels it. So one polymon can chase middling-sized, vivid mates while being repelled by fast ones, and
## its tankmate can want the exact opposite. The remaining traits count only as a tiebreak.
func fitness_of(candidate: Monster) -> float:
	if candidate.dead:
		return 0.0

	var traits := _traits_of(candidate)

	var primary := _match_score(traits[genome.attractor], genome.attractor_target)

	var secondary := 0.0
	for key: int in traits:
		if key != genome.attractor:
			secondary += traits[key]
	secondary /= maxf(1.0, traits.size() - 1.0)

	# The turn-off subtracts: the closer a candidate sits to what repels this animal, the worse it does.
	var repulsion := _match_score(traits[genome.turnoff], genome.turnoff_target) * TURNOFF_WEIGHT

	var score := PRIMARY_WEIGHT * primary + SECONDARY_WEIGHT * secondary - repulsion
	return clampf(score, 0.0, 1.0)


## Boids, with a social rule: flock with your own kind (preferring your own color), shun everyone else
## — unless you're fertile, in which case any other fertile animal is worth crossing the pen for.
##
## Every weight here comes from this animal's genome, so two animals in the same pen can disagree about
## how gregarious, how choosy, or how amorous to be — and their children inherit the argument.
func _flock() -> Vector3:
	var separation := Vector3.ZERO
	var alignment := Vector3.ZERO
	var cohesion := Vector3.ZERO
	var kinship := 0.0
	var avoidance := Vector3.ZERO
	var courtship := Vector3.ZERO

	var fertile := is_fertile()
	var suitor: Monster = null
	var suitor_score := -1.0

	# Siblings only — animals in another tank are not in this list at all.
	for node in get_parent().get_children():
		if node == self or not node is Monster:
			continue
		var other: Monster = node
		# The dead are nobody's flockmate and nobody's mate.
		if other.dead:
			continue

		var offset: Vector3 = global_position - other.global_position
		var distance := offset.length()
		if distance < 0.01 or distance > NEIGHBOR_RADIUS:
			continue

		# Nobody wants to be sat on, whatever their species.
		if distance < SEPARATION_RADIUS:
			separation += offset / (distance * distance)

		if other.species == species:
			# Own kind: flock, weighted by how close their color is to ours — how much that matters is
			# itself a gene (kin_color_bias).
			var weight := genome.kin_weight(color, other.color)
			alignment += other.linear_velocity * weight
			cohesion += other.global_position * weight
			kinship += weight
		elif not (fertile and other.is_fertile()):
			# Not a prospect: keep away from the other species.
			avoidance += offset.normalized()

		# Both in heat? Then this is a candidate — and an animal chases the BEST mate it can see, not
		# merely the nearest one. This is where sexual selection actually bites.
		if fertile and other.is_fertile():
			var score := fitness_of(other)
			if score > suitor_score:
				suitor_score = score
				suitor = other

	if suitor != null:
		courtship = (suitor.global_position - global_position).normalized()

	var steer := separation.normalized() * genome.separation
	steer += avoidance.normalized() * genome.xeno_avoidance
	steer += courtship * genome.courtship

	if kinship > 0.0:
		steer += (alignment / kinship).normalized() * genome.alignment
		var center := cohesion / kinship
		steer += (center - global_position).normalized() * genome.cohesion
	return steer


func _wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(WANDER_INTERVAL.x, WANDER_INTERVAL.y)
		_wander_dir = _random_direction()
	return _wander_dir


## A hungry animal beelines for the nearest pellet. This is what turns dropped food into eaten food.
func _seek_food() -> Vector3:
	if not is_hungry():
		return Vector3.ZERO

	var home := tank()
	if home == null:
		return Vector3.ZERO

	var nearest: Node3D = null
	var best := INF
	# Only this tank's pellets: food in another tank is behind glass, and swimming at it would starve.
	for pellet in home.pellets.get_children():
		var distance: float = global_position.distance_squared_to(pellet.global_position)
		if distance < best:
			best = distance
			nearest = pellet

	if nearest == null:
		return Vector3.ZERO
	return (nearest.global_position - global_position).normalized()


## Steer inward near the glass. Bouncy walls already exist, but boids left alone press into a corner and
## hug it. Position is tank-local, since the animal hangs under its tank.
func _avoid_walls() -> Vector3:
	var push := Vector3.ZERO
	for axis in 3:
		var limit: float = Tank.EXTENTS[axis] - WALL_MARGIN
		if position[axis] > limit:
			push[axis] = -1.0
		elif position[axis] < -limit:
			push[axis] = 1.0
	return push


# --- State ---------------------------------------------------------------------------------------


func launch() -> void:
	linear_velocity = _random_direction() * _speed
	angular_velocity = _random_direction() * 1.5


## How big this animal is right now. It grows from a tiny juvenile toward the adult size its genes call
## for — which varies far more than it used to, so a herd can hold giants and runts side by side.
func size() -> float:
	var grown := clampf(age / (_maturity * GROWTH_SLOWDOWN), 0.0, 1.0)
	return genome.max_size * lerpf(JUVENILE_SIZE, 1.0, grown)


## How far through its natural life this one is, 0..1.
func agedness() -> float:
	return clampf(age / _lifespan, 0.0, 1.0)


func is_hungry() -> bool:
	return hunger >= HUNGRY_AT


## Fertile animals glow. A hungry one will not breed — feeding the herd is what keeps it growing. Nor,
## obviously, does a dead one.
func is_fertile() -> bool:
	return not dead and _breed_timer <= 0.0 and not is_hungry()


func feed() -> void:
	hunger = 0.0


func on_bred() -> void:
	_breed_timer = BREED_COOLDOWN


func sale_value() -> int:
	return Species.sale_value(species, color)


func _refresh_appearance() -> void:
	if dead:
		# A corpse is drained of colour and light — unmistakably an object, not an animal.
		var corpse := Color(0.35, 0.36, 0.4, 0.55)
		_material.albedo_color = corpse
		_material.emission = Color.BLACK
		_material.emission_energy_multiplier = 0.0
		_core_material.albedo_color = corpse
		_core_material.emission = Color.BLACK
		_marker.visible = false
		return

	# A hungry animal visibly fades, so neglect is legible at a glance.
	var tint := color.darkened(hunger * 0.6)
	tint.a = ALPHA
	_material.albedo_color = tint
	_material.emission = color
	_material.emission_energy_multiplier = 0.6 if is_fertile() else 0.0

	_core_material.albedo_color = color.lightened(0.5)
	_core_material.emission = color.lightened(0.35)

	# Grow the hitbox with the mesh, or a juvenile would keep an adult-sized invisible hitbox and
	# collide (and breed) at a visible distance.
	var scale_factor := Vector3.ONE * size()
	_mesh.scale = scale_factor
	_core.scale = scale_factor
	_collision.scale = scale_factor

	# The marker is top_level, so it ignores the animal's tumbling rotation instead of swinging around
	# it like a moon. That means placing it by hand.
	_marker.visible = is_hungry()
	_marker.global_position = global_position + Vector3.UP * (0.5 * size() + MARKER_GAP)


func _set_selected(value: bool) -> void:
	selected = value
	if not is_node_ready():
		return
	# An inverted-hull outline: a slightly grown, front-face-culled copy drawn behind the shell.
	if selected:
		var outline := StandardMaterial3D.new()
		outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline.albedo_color = Color.WHITE
		outline.cull_mode = BaseMaterial3D.CULL_FRONT
		outline.grow = true
		outline.grow_amount = 0.05
		_material.next_pass = outline
	else:
		_material.next_pass = null


func _random_direction() -> Vector3:
	return Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	).normalized()


func _on_input_event(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int
) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		# Consume it, or the same click falls through to the arena and ALSO drops a food pellet.
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if not body is Monster:
		return
	if not is_fertile() or not body.is_fertile():
		return

	# Both must find the other at least tolerable...
	var mine := fitness_of(body)
	var theirs: float = body.fitness_of(self)
	if mine < ACCEPTABLE or theirs < ACCEPTABLE:
		return

	# ...and then each says yes with a probability equal to how much it likes the other.
	#
	# Steering alone does NOT make preference real: in a crowded tank an animal collides with whoever
	# happens to drift into it, so the pairings that actually happen are close to random however
	# pointedly it was swimming at its favourite. This is the gate that turns a preference into
	# offspring — an appealing partner is roughly twice as likely to be accepted as a dull one, so who
	# gets to breed finally reflects who was wanted.
	if randf() > mine or randf() > theirs:
		return

	# Both animals get this signal for the same collision. Let the lower id be the initiator so the
	# pair only produces one child.
	if get_instance_id() < body.get_instance_id():
		wants_to_breed.emit(self, body)
