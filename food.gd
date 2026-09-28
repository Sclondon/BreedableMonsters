class_name Food
extends Area3D

## A pellet suspended in the tank. It bobs, drifts, and gets shoved aside by passing polymons — food is
## part of the water, not scenery on the floor.
##
## Hungry animals steer toward the nearest one (see Monster._seek_food) and eat it on contact; fed ones
## ignore it. Each pellet carries several bites and visibly shrinks as it is eaten: one bite per pellet
## would make feeding a full herd cost more per minute than a mid-tier animal sells for.

const BITES := 3
const SPIN := 1.2

## Neutrally buoyant: it hangs in the water rather than settling.
const BOB_HEIGHT := 0.25
const BOB_SPEED := 1.1
## A slow, aimless wander so the tank never looks static.
const DRIFT_SPEED := 0.35
const DRIFT_INTERVAL := Vector2(2.0, 5.0)
## How hard a passing animal bats the pellet aside, and from how far.
const WAKE_RADIUS := 2.5
const WAKE_FORCE := 3.0
## Turbulence bleeds away, or a shoved pellet would sail on forever.
const DAMPING := 1.8

var _bites_left := BITES
var _bob_phase := 0.0
var _drift := Vector3.ZERO
var _drift_timer := 0.0
var _wake := Vector3.ZERO
var _anchor := 0.0

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("food")
	body_entered.connect(_on_body_entered)
	_bob_phase = randf() * TAU
	_anchor = position.y
	_drift = _random_drift()
	_resize()


func _process(delta: float) -> void:
	_mesh.rotate_y(SPIN * delta)

	_drift_timer -= delta
	if _drift_timer <= 0.0:
		_drift_timer = randf_range(DRIFT_INTERVAL.x, DRIFT_INTERVAL.y)
		_drift = _random_drift()

	_wake += _turbulence() * delta
	_wake = _wake.move_toward(Vector3.ZERO, DAMPING * delta)

	_anchor += (_drift.y + _wake.y) * delta
	position.x += (_drift.x + _wake.x) * delta
	position.z += (_drift.z + _wake.z) * delta

	# Bobbing rides on top of wherever the pellet has drifted to.
	_bob_phase += BOB_SPEED * delta
	position.y = _anchor + sin(_bob_phase) * BOB_HEIGHT

	_stay_in_tank()


## Every animal nearby pushes the pellet away, harder the closer and the faster it is moving. A polymon
## barrelling past visibly bats its dinner aside before it can catch it.
func _turbulence() -> Vector3:
	var tank := get_parent().get_parent() as Tank
	if tank == null:
		return Vector3.ZERO

	var push := Vector3.ZERO
	for node in tank.monsters.get_children():
		var animal := node as Monster
		if animal == null or animal.dead:
			continue

		var offset := global_position - animal.global_position
		var distance := offset.length()
		if distance < 0.01 or distance > WAKE_RADIUS:
			continue

		var closeness := 1.0 - distance / WAKE_RADIUS
		var wake := 1.0 + animal.linear_velocity.length() * 0.25
		push += offset.normalized() * closeness * closeness * wake * WAKE_FORCE
	return push


func _stay_in_tank() -> void:
	var inner := Tank.EXTENTS - Vector3.ONE
	position = Vector3(
		clampf(position.x, -inner.x, inner.x),
		clampf(position.y, -inner.y, inner.y),
		clampf(position.z, -inner.z, inner.z)
	)
	_anchor = clampf(_anchor, -inner.y, inner.y)


func _random_drift() -> Vector3:
	return Vector3(
		randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)
	).normalized() * DRIFT_SPEED


func _on_body_entered(body: Node) -> void:
	var animal := body as Monster
	if animal == null or animal.dead or not animal.is_hungry():
		return

	animal.feed()
	_bites_left -= 1
	if _bites_left <= 0:
		queue_free()
		return
	_resize()


func _resize() -> void:
	var left := float(_bites_left) / float(BITES)
	_mesh.scale = Vector3.ONE * lerpf(0.45, 1.0, left)
