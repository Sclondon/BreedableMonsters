class_name Species
extends RefCounted

## A species is a PATH and a FACE COUNT.
##
## Face count is still the only thing that decides rarity, value and traits — a Dodeca is a Dodeca
## whichever lineage it came from. The path decides only what it LOOKS like, and there are two:
##
##   SQUARE — prisms. Cube, pentagonal prism, hexagonal prism … tending toward a tube.
##   STAR   — pyramids and bipyramids. Tetrahedron, square pyramid, octahedron … tending toward a point.
##
## The face count of the built mesh is exactly the face count of the species (a cone of k sides has k+1
## faces, a bipyramid of k has 2k, a prism of k has k+2). If that ever drifts, rarity is a lie — see
## tests/test_species.gd.

enum Path { SQUARE, STAR }

const MIN_FACES := 4
const MAX_FACES := 12

## The square path has no 4- or 5-face member: the smallest prism with caps is the cube (a 4-sided
## prism, 6 faces). Breeding must therefore clamp a child's faces into its path's range — otherwise a
## cross-path pairing could ask for a 4-face prism, which does not exist.
const PATH_MIN_FACES := {Path.SQUARE: 6, Path.STAR: 4}

const GREEK := {
	4: "Tetra",
	5: "Penta",
	6: "Hexa",
	7: "Hepta",
	8: "Octa",
	9: "Ennea",
	10: "Deca",
	11: "Hendeca",
	12: "Dodeca",
}

const PATH_NAMES := {Path.SQUARE: "Tube", Path.STAR: "Spike"}

## The wild stock the shop always carries: the bottom of each lineage.
const COMMONS := [[Path.STAR, 4], [Path.STAR, 5], [Path.SQUARE, 6]]

## A gray animal keeps this fraction of its value; a fully saturated one is worth 1.4x it.
const MUD_FLOOR := 0.4

## Buying must always cost more than the best price the same animal could fetch, or buy-and-flip would
## print gold. 2.5x + 25 clears value * 1.4 with room to spare.
const BUY_MARKUP := 2.5
const BUY_FEE := 25

## Odds a child takes the additive step rather than copying a parent. Parent shapes dominate, so
## climbing the ladder stays a lucky break.
const ADDITIVE_CHANCE := 0.25

static var TABLE := _build_table()
static var _meshes := {}


static func _build_table() -> Dictionary:
	var table := {}
	for path in [Path.SQUARE, Path.STAR]:
		for count in range(PATH_MIN_FACES[path], MAX_FACES + 1):
			table[name_for(path, count)] = {
				"path": path,
				"faces": count,
				"value": value_for(count),
				"buy": roundi(value_for(count) * BUY_MARKUP) + BUY_FEE,
				"lifespan": 420.0 + (count - MIN_FACES) * 60.0,
				"starve": 150.0 - (count - MIN_FACES) * 6.0,
				"maturity": 8.0 + (count - MIN_FACES) * 2.5,
				"speed": 3.2 - (count - MIN_FACES) * 0.12,
			}
	return table


## Superlinear, so climbing the ladder actually pays: 10, 40, 90 … 810.
static func value_for(count: int) -> int:
	return (count - 3) * (count - 3) * 10


static func name_for(path: Path, count: int) -> String:
	return "%s %s" % [GREEK[count], PATH_NAMES[path]]


static func faces(species: String) -> int:
	return TABLE[species]["faces"]


static func path_of(species: String) -> Path:
	return TABLE[species]["path"]


static func trait_of(species: String, name: String) -> Variant:
	return TABLE[species][name]


static func buy_price(species: String) -> int:
	return TABLE[species]["buy"]


static func commons() -> Array:
	return COMMONS.map(func(pair): return name_for(pair[0], pair[1]))


# --- Derivation ----------------------------------------------------------------------------------


## THE SPECIES IS DERIVED FROM THE GENES, NEVER STORED.
##
## An animal's form is three continuous genes — how many sides, how tapered, how symmetrical — and its
## species is simply what those genes round to. That is what lets shape evolve organically while the
## look stays crisply polygonal and the whole economy (rarity, value, market price, name) keeps working
## unchanged: it all still hangs off face count, which is now emergent rather than assigned.
static func of(genome: Genome) -> String:
	var k := clampi(roundi(genome.sides), 3, 10)
	var path: Path = Path.SQUARE if genome.taper >= 0.5 else Path.STAR

	var count: int
	if path == Path.SQUARE:
		count = k + 2  # a prism: k sides plus two caps
	elif genome.symmetry >= 0.5:
		count = k * 2  # a bipyramid: mirrored, so twice the sides. At k=4, an octahedron.
	else:
		count = k + 1  # a pyramid: k sides plus a base

	return _legal(path, count)


# --- Breeding ------------------------------------------------------------------------------------


## The additive step: one face above the parents' average, the deterministic climb.
static func breed(a: String, b: String) -> String:
	if a == b:
		return a
	var count := roundi((faces(a) + faces(b)) / 2.0) + 1
	return _legal(_inherit_path(a, b), count)


## The child's lineage. Same-path parents pass theirs down; a cross-path pairing is a coin flip.
static func _inherit_path(a: String, b: String) -> Path:
	var path_a := path_of(a)
	var path_b := path_of(b)
	if path_a == path_b:
		return path_a
	return path_a if randf() < 0.5 else path_b


## Pin a (path, faces) pair onto a species that actually exists.
##
## This is the guard the two-path model needs: the square path bottoms out at the cube, so a child that
## rolls SQUARE with 4 faces has to be lifted to 6. Without it, breeding could name an animal that is
## not in the table at all.
static func _legal(path: Path, count: int) -> String:
	var floor_: int = PATH_MIN_FACES[path]
	return name_for(path, clampi(count, floor_, MAX_FACES))


## Shape is inherited, not decreed: a child takes one parent's face count, the other's, or the additive
## step above them both — and picks a lineage.
##
## Identical parents breed TRUE. Without that carve-out, the additive roll (their average + 1) would let
## a single-species herd climb the whole ladder on its own, and cross-species courtship — what the
## flocking rules are built around — would be pointless.
static func inherit_shape(a: String, b: String) -> String:
	if a == b:
		return a

	var path := _inherit_path(a, b)
	var roll := randf()
	var count: int
	if roll < ADDITIVE_CHANCE:
		count = roundi((faces(a) + faces(b)) / 2.0) + 1
	elif roll < ADDITIVE_CHANCE + (1.0 - ADDITIVE_CHANCE) * 0.5:
		count = faces(a)
	else:
		count = faces(b)
	return _legal(path, count)


# --- Value ---------------------------------------------------------------------------------------


## Species worth scaled by color vividness. Averaging colors bleeds saturation, so an inbred, muddy herd
## is a losing proposition — saturation is money.
static func sale_value(species: String, color: Color) -> int:
	return int(TABLE[species]["value"] * (MUD_FLOOR + color.s))


## The most a specimen could ever fetch. The shop's buy price must stay above this.
static func max_sale_value(species: String) -> int:
	return int(TABLE[species]["value"] * (MUD_FLOOR + 1.0))


# --- Meshes --------------------------------------------------------------------------------------


## How many sides the generated solid needs so that its face count really equals `count`.
static func sides_for(path: Path, count: int) -> int:
	if path == Path.SQUARE:
		return count - 2  # prism: k sides + 2 caps
	if _is_bipyramid(count):
		return int(count / 2.0)  # bipyramid: 2k faces
	return count - 1  # pyramid: k sides + 1 base


## Even-faced stars are bipyramids — which makes the 8-face star exactly an octahedron. Odd ones (and
## the 4- and 5-face runts) are single pyramids: the tetrahedron and the square pyramid.
static func _is_bipyramid(count: int) -> bool:
	return count >= 6 and count % 2 == 0


static func mesh_for(species: String) -> Mesh:
	var key := species
	if not _meshes.has(key):
		_meshes[key] = _build_mesh(path_of(species), faces(species))
	return _meshes[key]


static func _build_mesh(path: Path, count: int) -> Mesh:
	var sides := sides_for(path, count)

	if path == Path.SQUARE:
		# More sides as it climbs, so the lineage slides from cube toward tube.
		var prism := CylinderMesh.new()
		prism.top_radius = 0.5
		prism.bottom_radius = 0.5
		prism.height = 1.0
		prism.radial_segments = sides
		prism.rings = 0
		return prism

	if _is_bipyramid(count):
		return _bipyramid(sides)

	# A cylinder with no top is a cone — 3 sides is a tetrahedron, 4 a square pyramid.
	var pyramid := CylinderMesh.new()
	pyramid.top_radius = 0.0
	pyramid.bottom_radius = 0.62
	pyramid.height = 1.2
	pyramid.radial_segments = sides
	pyramid.rings = 0
	return pyramid


## Godot has no bipyramid primitive, so build one: a ring of `sides` vertices with an apex above and
## below, giving 2 * sides triangular faces. At 4 sides that is the octahedron.
static func _bipyramid(sides: int) -> ArrayMesh:
	var radius := 0.55
	var apex := 0.75

	var vertices := PackedVector3Array()
	var top := Vector3(0.0, apex, 0.0)
	var bottom := Vector3(0.0, -apex, 0.0)

	for i in sides:
		var a := TAU * i / sides
		var b := TAU * (i + 1) / sides
		var p := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		var q := Vector3(cos(b) * radius, 0.0, sin(b) * radius)

		# Wind each face outward: up-facing then down-facing.
		vertices.append_array([top, q, p])
		vertices.append_array([bottom, p, q])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Flat shading needs per-face normals; regenerating them keeps the facets crisp.
	var tool := SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.generate_normals()
	return tool.commit()
