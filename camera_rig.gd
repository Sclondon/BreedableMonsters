extends Node3D

## Orbit camera. The rig sits at the pen's center and the camera hangs back along local +Z, so
## orbiting is just rotating this pivot.
##
## Right-drag orbits and the wheel zooms. Left-click is left alone — it belongs to feeding and
## selecting cubes.

const ORBIT_SPEED := 0.006
const ZOOM_STEP := 1.5
const DISTANCE_LIMITS := Vector2(8.0, 35.0)
## Stop just short of the poles, where the view flips over.
const PITCH_LIMIT := deg_to_rad(80.0)

## How fast the pivot slides to whatever it is now watching.
const FOLLOW_RATE := 4.0

var _yaw := 0.0
var _pitch := 0.0
var _distance := 20.0

## What the camera orbits around. A selected polymon becomes the centre of the world — you circle IT,
## and it stays put on screen while its tankmates wheel around behind it. With nothing selected the rig
## falls back to the middle of the tank you are looking at.
var subject: Node3D = null
var home := Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# main.gd pauses the tree on the win/lose screen; keep the camera usable there.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply()


func _process(delta: float) -> void:
	var target := home
	if is_instance_valid(subject):
		target = subject.global_position
	# Slide rather than snap, so picking an animal glides the camera onto it.
	global_position = global_position.lerp(target, minf(FOLLOW_RATE * delta, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		orbit(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(ZOOM_STEP)


func orbit(motion: Vector2) -> void:
	_yaw -= motion.x * ORBIT_SPEED
	_pitch = clampf(_pitch - motion.y * ORBIT_SPEED, -PITCH_LIMIT, PITCH_LIMIT)
	_apply()


func zoom(amount: float) -> void:
	_distance = clampf(_distance + amount, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
	_apply()


func _apply() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
