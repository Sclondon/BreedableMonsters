extends SceneTree

## Headless checks for the two-path species model:
##   godot --headless --script res://tests/test_species.gd

var _failures := 0


func _initialize() -> void:
	_identity()
	_derived_from_genes()
	_shapes_are_distinct()
	_face_counts_are_honest()
	_breeding()
	_pricing()
	_traits()


## THE SPECIES IS NOW DERIVED, NEVER STORED. Any genome at all must round to a species that really
## exists — if a corner of the gene space maps to a name that isn't in the table, breeding an animal
## into that corner crashes the game or, worse, invents a phantom.
func _derived_from_genes() -> void:
	for i in 20000:
		var genome := Genome.random(Color.RED)
		var species := Species.of(genome)
		if not Species.TABLE.has(species):
			_check(
				"a random genome (sides %.2f taper %.2f symmetry %.2f) named a phantom species: '%s'"
				% [genome.sides, genome.taper, genome.symmetry, species],
				false
			)
			return
	_check("every random genome derives a species that actually exists", true)

	# And the extremes of every shape gene, which is where rounding is most likely to fall off the end.
	for sides in [3.0, 3.49, 3.5, 9.99, 10.0]:
		for taper in [0.0, 0.49, 0.5, 1.0]:
			for symmetry in [0.0, 0.49, 0.5, 1.0]:
				var genome := Genome.new()
				genome.sides = sides
				genome.taper = taper
				genome.symmetry = symmetry
				var species := Species.of(genome)
				if not Species.TABLE.has(species):
					_check(
						"shape extreme (%.2f, %.2f, %.2f) named a phantom species: '%s'"
						% [sides, taper, symmetry, species],
						false
					)
					return
	_check("the extremes of every shape gene still derive a real species", true)

	# The genes must actually mean what they claim: taper picks the lineage, sides drives rarity.
	var spike := Genome.new()
	spike.sides = 5.0
	spike.taper = 0.0
	spike.symmetry = 0.0
	var tube := Genome.new()
	tube.sides = 5.0
	tube.taper = 1.0
	tube.symmetry = 0.0
	_check("a low taper grows a spike", Species.path_of(Species.of(spike)) == Species.Path.STAR)
	_check("a high taper grows a tube", Species.path_of(Species.of(tube)) == Species.Path.SQUARE)

	# Symmetry is what makes a bipyramid — and at four sides, that is exactly an octahedron.
	var octahedron := Genome.new()
	octahedron.sides = 4.0
	octahedron.taper = 0.0
	octahedron.symmetry = 1.0
	_check("a symmetrical four-sided spike is an octahedron", Species.of(octahedron) == "Octa Spike")

	# More sides must mean more faces, or rarity would not track shape at all.
	var few := Genome.new()
	few.sides = 4.0
	few.taper = 1.0
	var many := Genome.new()
	many.sides = 10.0
	many.taper = 1.0
	_check(
		"more sides derives a rarer species",
		Species.faces(Species.of(many)) > Species.faces(Species.of(few))
	)

	if _failures == 0:
		print("PASS: all species checks")
	else:
		print("FAIL: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _identity() -> void:
	# The square path has no 4- or 5-face member: the smallest prism with caps is the cube.
	_check("the square path starts at the cube", Species.PATH_MIN_FACES[Species.Path.SQUARE] == 6)
	_check("the star path starts at the tetrahedron", Species.PATH_MIN_FACES[Species.Path.STAR] == 4)

	for species: String in Species.TABLE:
		var path := Species.path_of(species)
		var count := Species.faces(species)
		_check(
			"%s round-trips to its own (path, faces)" % species,
			Species.name_for(path, count) == species
		)
		_check(
			"%s has a legal face count for its path" % species,
			count >= Species.PATH_MIN_FACES[path] and count <= Species.MAX_FACES
		)

	# Value must rise with faces, or rarity would not pay.
	for count in range(Species.MIN_FACES, Species.MAX_FACES):
		_check(
			"a %d-face animal is worth more than a %d-face one" % [count + 1, count],
			Species.value_for(count + 1) > Species.value_for(count)
		)

	# Path is cosmetic: the same face count is worth the same in either lineage.
	_check(
		"a Hexa Tube and a Hexa Spike are worth exactly the same",
		Species.trait_of("Hexa Tube", "value") == Species.trait_of("Hexa Spike", "value")
	)


## THE BUG THAT PROMPTED THIS. Two species must never share a mesh — the old Tetra and Penta were both
## just cones, so the ladder looked samey. Distinct rarity must mean a distinct silhouette.
func _shapes_are_distinct() -> void:
	var seen := {}
	for species: String in Species.TABLE:
		var mesh := Species.mesh_for(species)
		_check("%s has a mesh" % species, mesh != null)

		# Two species share a look only if they were built from identical parameters.
		var fingerprint := _fingerprint(species)
		if seen.has(fingerprint):
			_check(
				"%s and %s must not look identical (%s)" % [species, seen[fingerprint], fingerprint],
				false
			)
		seen[fingerprint] = species

	_check("every species has its own silhouette", seen.size() == Species.TABLE.size())
	_check("meshes are cached", Species.mesh_for("Octa Spike") == Species.mesh_for("Octa Spike"))


## A description of what the solid actually is, so two species that would render identically collide.
func _fingerprint(species: String) -> String:
	var path := Species.path_of(species)
	var count := Species.faces(species)
	var kind := "prism"
	if path == Species.Path.STAR:
		kind = "bipyramid" if count >= 6 and count % 2 == 0 else "pyramid"
	return "%s-%d" % [kind, Species.sides_for(path, count)]


## The solid must really have the number of faces its species claims, or rarity is a lie: a prism of k
## sides has k+2 faces, a pyramid of k has k+1, a bipyramid of k has 2k.
func _face_counts_are_honest() -> void:
	for species: String in Species.TABLE:
		var path := Species.path_of(species)
		var count := Species.faces(species)
		var sides := Species.sides_for(path, count)

		var built: int
		if path == Species.Path.SQUARE:
			built = sides + 2
		elif count >= 6 and count % 2 == 0:
			built = sides * 2
		else:
			built = sides + 1

		_check(
			"%s really has %d faces, not %d" % [species, count, built],
			built == count
		)

	# The shapes the user named, by construction.
	_check("the 4-face star is a tetrahedron (3-sided pyramid)", Species.sides_for(Species.Path.STAR, 4) == 3)
	_check("the 5-face star is a square pyramid (4-sided)", Species.sides_for(Species.Path.STAR, 5) == 4)
	_check("the 8-face star is an octahedron (4-sided bipyramid)", Species.sides_for(Species.Path.STAR, 8) == 4)
	_check("the 6-face square is a cube (4-sided prism)", Species.sides_for(Species.Path.SQUARE, 6) == 4)
	_check("the 7-face square is a pentagonal prism", Species.sides_for(Species.Path.SQUARE, 7) == 5)
	_check("the 8-face square is a hexagonal prism", Species.sides_for(Species.Path.SQUARE, 8) == 6)
	# ...and the square path really does tend toward a tube: more sides the higher it climbs.
	_check(
		"the square path gains sides as it climbs (tube-ward)",
		Species.sides_for(Species.Path.SQUARE, 12) > Species.sides_for(Species.Path.SQUARE, 6)
	)


func _breeding() -> void:
	for species: String in Species.TABLE:
		for i in 50:
			if Species.inherit_shape(species, species) != species:
				_check("%s bred with itself always breeds true" % species, false)
				return
	_check("identical parents always breed true", true)

	# THE CLAMP INVARIANT. A cross-path pairing can roll SQUARE with 4 faces — a species that does not
	# exist. Cross everything with everything, many times, and demand a real animal every time.
	for a: String in Species.TABLE:
		for b: String in Species.TABLE:
			for i in 25:
				var child := Species.inherit_shape(a, b)
				if not Species.TABLE.has(child):
					_check("%s + %s produced a phantom species: '%s'" % [a, b, child], false)
					return
				var count := Species.faces(child)
				var floor_: int = Species.PATH_MIN_FACES[Species.path_of(child)]
				if count < floor_ or count > Species.MAX_FACES:
					_check("%s + %s produced an illegal face count: %s" % [a, b, child], false)
					return
	_check("every possible pairing names a real, legal species", true)

	# The specific case the clamp exists for: a 4-face star crossed with a tube can land on the square
	# path, where 4 faces do not exist, and must be lifted to the cube.
	var lifted := false
	for i in 500:
		var child := Species.inherit_shape("Tetra Spike", "Hexa Tube")
		if Species.path_of(child) == Species.Path.SQUARE:
			lifted = true
			_check(
				"a square-path child of a 4-face parent is lifted to a legal cube or above (%s)" % child,
				Species.faces(child) >= 6
			)
	_check("crossing paths does sometimes produce a square-path child", lifted)

	# Path inheritance: same-path parents keep it, cross-path parents split it.
	for i in 50:
		_check(
			"two tubes make a tube",
			Species.path_of(Species.inherit_shape("Hexa Tube", "Octa Tube")) == Species.Path.SQUARE
		)
		_check(
			"two spikes make a spike",
			Species.path_of(Species.inherit_shape("Tetra Spike", "Octa Spike")) == Species.Path.STAR
		)

	var squares := 0
	var rolls := 4000
	for i in rolls:
		if Species.path_of(Species.inherit_shape("Hexa Tube", "Hexa Spike")) == Species.Path.SQUARE:
			squares += 1
	var share := float(squares) / rolls
	_check("a cross-path child picks its lineage ~50/50 (%.3f)" % share, absf(share - 0.5) < 0.05)

	# Face odds are unchanged: 25% additive, 37.5% each parent.
	var additive := 0
	for i in rolls:
		if Species.faces(Species.inherit_shape("Hexa Spike", "Octa Spike")) == 8:
			pass  # 8 faces could be parent B or the additive step; count the unambiguous case below.
	for i in rolls:
		# Penta(5) + Hexa(6) on one path: additive = 7, parents = 5 or 6, all distinct.
		if Species.faces(Species.inherit_shape("Penta Spike", "Hexa Spike")) == 7:
			additive += 1
	var additive_share := float(additive) / rolls
	_check(
		"the additive step still lands about a quarter of the time (%.3f)" % additive_share,
		absf(additive_share - Species.ADDITIVE_CHANCE) < 0.03
	)


func _pricing() -> void:
	var vivid := Color.from_hsv(0.6, 1.0, 1.0)
	var muddy := Color(0.5, 0.5, 0.5)
	_check("a vivid animal outsells a gray one", Species.sale_value("Dodeca Tube", vivid) > Species.sale_value("Dodeca Tube", muddy))
	_check("rarity beats color", Species.sale_value("Dodeca Tube", muddy) > Species.sale_value("Tetra Spike", vivid))

	# No species may be bought and instantly flipped for profit, or gold prints itself.
	for species: String in Species.TABLE:
		_check(
			"%s cannot be bought and instantly flipped (buy %d > best sale %d)"
			% [species, Species.buy_price(species), Species.max_sale_value(species)],
			Species.buy_price(species) > Species.max_sale_value(species)
		)


func _traits() -> void:
	for species: String in Species.TABLE:
		for name: String in ["lifespan", "starve", "maturity", "speed"]:
			_check("%s has a positive '%s'" % [species, name], Species.trait_of(species, name) > 0.0)

		var lifespan: float = Species.trait_of(species, "lifespan")
		# Juveniles now grow far more slowly, so the real wait to adulthood is the stretched one. If a
		# future tweak to GROWTH_SLOWDOWN ever pushed this past a species' lifespan, that species could
		# never breed at all — it would die a child.
		var grown_up: float = Species.trait_of(species, "maturity") * Monster.GROWTH_SLOWDOWN
		_check(
			"%s lives long enough to grow up AND breed (life %.0f > grown-up %.0f + cooldown %.0f)"
			% [species, lifespan, grown_up, Monster.BREED_COOLDOWN],
			lifespan > grown_up + Monster.BREED_COOLDOWN
		)
		_check(
			"%s can reach adulthood on a single feed (starve %.0f > grown-up %.0f)"
			% [species, Species.trait_of(species, "starve"), grown_up],
			Species.trait_of(species, "starve") > grown_up
		)

	_check("the commons are all real species", Species.commons().all(func(s): return Species.TABLE.has(s)))
	_check("there is a common on each path", Species.commons().size() >= 2)


func _check(what: String, passed: bool) -> void:
	if not passed:
		_failures += 1
		print("  FAILED: %s" % what)
