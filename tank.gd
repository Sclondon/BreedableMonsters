class_name Tank
extends Node3D

## One tank: its own glass, its own animals, its own food.
##
## Tanks replace the old divided-chamber arena. An animal's flockmates are simply its siblings under
## this tank's Monsters node, so "can't see the next tank over" is structural — there is no filter for a
## future query to forget to apply. Segregating a bloodline means moving it to another tank.

const EXTENTS := Vector3(12.0, 9.0, 8.0)
const WALL_THICKNESS := 1.0
## Gap between neighbouring tanks in world space.
const SPACING := 6.0
const MAX_POPULATION := 30

## Where the pellets come to rest.
const FLOOR_HEIGHT := -EXTENTS.y + 0.4

@onready var monsters: Node3D = $Monsters
@onready var pellets: Node3D = $Pellets


## Tanks sit in a row along X, so tank N is a fixed step from tank 0.
static func tank_position(index: int) -> Vector3:
	return Vector3((EXTENTS.x * 2.0 + SPACING) * index, 0.0, 0.0)


## Which tank a world point falls inside, or -1 for the gap between them. This is what decides where a
## dragged animal is dropped.
static func tank_at(point: Vector3, tank_count: int) -> int:
	for i in tank_count:
		var local := point - tank_position(i)
		if (
			absf(local.x) <= EXTENTS.x
			and absf(local.y) <= EXTENTS.y
			and absf(local.z) <= EXTENTS.z
		):
			return i
	return -1


func _ready() -> void:
	_build_walls()
	_build_outline()


## The living only. Corpses clutter the tank but do not take a breeding slot — cleaning them up is
## rewarded with salvage, not enforced by crowding.
func population() -> int:
	var living := 0
	for node in monsters.get_children():
		var animal := node as Monster
		if animal != null and not animal.dead:
			living += 1
	return living


func is_full() -> bool:
	return population() >= MAX_POPULATION


func random_point() -> Vector3:
	var inner := EXTENTS - Vector3.ONE * 2.0
	return Vector3(
		randf_range(-inner.x, inner.x),
		randf_range(-inner.y, inner.y),
		randf_range(-inner.z, inner.z)
	)


func clamp_point(point: Vector3) -> Vector3:
	var inner := EXTENTS - Vector3.ONE
	return Vector3(
		clampf(point.x, -inner.x, inner.x),
		clampf(point.y, -inner.y, inner.y),
		clampf(point.z, -inner.z, inner.z)
	)


func _build_walls() -> void:
	var bounce := PhysicsMaterial.new()
	bounce.friction = 0.0
	bounce.bounce = 1.0

	var half := WALL_THICKNESS * 0.5
	var span := EXTENTS * 2.0 + Vector3.ONE * WALL_THICKNESS * 2.0

	for axis in 3:
		for sign_ in [-1.0, 1.0]:
			var center := Vector3.ZERO
			center[axis] = sign_ * (EXTENTS[axis] + half)

			var size := span
			size[axis] = WALL_THICKNESS

			var box := BoxShape3D.new()
			box.size = size
			var collision := CollisionShape3D.new()
			collision.shape = box

			var wall := StaticBody3D.new()
			wall.position = center
			wall.physics_material_override = bounce
			# Glass must not swallow clicks meant for the animals behind it.
			wall.input_ray_pickable = false
			wall.add_child(collision)
			add_child(wall)


## Wireframe box, so the invisible glass reads as an actual container.
func _build_outline() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.45, 0.5, 0.65)

	var corners: Array[Vector3] = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				corners.append(EXTENTS * Vector3(x, y, z))

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i in corners.size():
		for j in range(i + 1, corners.size()):
			# Corners that differ on exactly one axis are an edge of the box.
			var difference := corners[i] - corners[j]
			var differing := 0
			for axis in 3:
				if not is_zero_approx(difference[axis]):
					differing += 1
			if differing == 1:
				mesh.surface_add_vertex(corners[i])
				mesh.surface_add_vertex(corners[j])
	mesh.surface_end()

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
