extends Node3D

const START_POPULATION := 4

const START_GOLD := 1500
const START_FOOD := 6
const FOOD_PRICE := 5
const DAY_LENGTH := 90.0
const TARGET_GOLD := 2500
const DEADLINE_DAYS := 20

## Tanks are the gold sink: colour no longer fades, so what you spend on is space, not saturation.
const TANK_PRICE := 800
const TANK_PRICE_GROWTH := 1.8
const MAX_TANKS := 4

## Where dead polymons go. Drag a body here and the lab renders it down for a small salvage fee.
const DISPOSAL_OFFSET := Vector3(-Tank.EXTENTS.x - 9.0, -4.0, 0.0)
const DISPOSAL_EXTENTS := Vector3(3.5, 3.5, 3.5)
## A corpse is worth a fraction of what the animal would have fetched alive.
const SALVAGE_SHARE := 0.2

@export var monster_scene: PackedScene
@export var food_scene: PackedScene
@export var tank_scene: PackedScene

var gold := START_GOLD
var food := START_FOOD
var day := 1

var _market := Market.new()
var _tanks: Array[Tank] = []
var _focused := 0

var _day_timer := 0.0
var _finished := false
var _selected: Monster = null
var _dragging: Monster = null
var _drag_depth := 20.0

@onready var _tank_root: Node3D = $Tanks
@onready var _rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _hud: Control = $HUD/Root
@onready var _status: Label = $HUD/Root/Status
@onready var _buy_food_button: Button = $HUD/Root/Shop/BuyFood
@onready var _buy_tank_button: Button = $HUD/Root/Shop/BuyTank
@onready var _catalogue_button: Button = $HUD/Root/Shop/Catalogue
@onready var _tank_buttons: HBoxContainer = $HUD/Root/Shop/Tanks
@onready var _selection_panel: PanelContainer = $HUD/Root/Selection
@onready var _selection_label: Label = $HUD/Root/Selection/Rows/Info
@onready var _sell_button: Button = $HUD/Root/Selection/Rows/Sell
@onready var _result: Label = $HUD/Root/Result
@onready var _shop: ShopPopup = $HUD/Root/ShopPopup


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_hud.theme = LabTheme.build()

	_buy_food_button.pressed.connect(buy_food)
	_buy_tank_button.pressed.connect(buy_tank)
	_catalogue_button.pressed.connect(open_catalogue)
	_sell_button.pressed.connect(sell_selected)
	_shop.bought.connect(_on_bought)

	_build_disposal()
	_reset()


func _process(delta: float) -> void:
	if not _finished:
		_market.tick(delta)
		_advance_day(delta)
		_keep_monsters_inside()
		_check_outcome()
	_refresh_hud()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_dragging):
		return

	if event is InputEventMouseMotion:
		_dragging.carry_to(_camera.project_position(event.position, _drag_depth))
	elif (
		event is InputEventMouseButton
		and not event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		_drop_dragged()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_reset()
		return

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		# A click on empty water drops food AND clears the selection, which hands the camera back to the
		# tank.
		_select(null)
		drop_food(event.position)


# --- Tanks ---------------------------------------------------------------------------------------


func tank_count() -> int:
	return _tanks.size()


func tank_price() -> int:
	return roundi(TANK_PRICE * pow(TANK_PRICE_GROWTH, tank_count() - 1))


func buy_tank() -> void:
	var price := tank_price()
	if _finished or tank_count() >= MAX_TANKS or gold < price:
		return
	gold -= price
	_add_tank()
	focus_tank(tank_count() - 1)


func _add_tank() -> Tank:
	var tank: Tank = tank_scene.instantiate()
	tank.position = Tank.tank_position(_tanks.size())
	_tank_root.add_child(tank)
	_tanks.append(tank)
	_rebuild_tank_buttons()
	return tank


func focus_tank(index: int) -> void:
	_focused = clampi(index, 0, tank_count() - 1)
	_select(null)
	_rig.home = Tank.tank_position(_focused)


func focused_tank() -> Tank:
	return _tanks[_focused]


func _tank_at(point: Vector3) -> Tank:
	var index := Tank.tank_at(point, tank_count())
	return _tanks[index] if index >= 0 else null


# --- Disposal ------------------------------------------------------------------------------------


## The rendering vat. It is deliberately outside the tanks: a body has to be carried OUT of the water.
func _build_disposal() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.35, 0.3, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.4, 0.3)
	glass.emission_energy_multiplier = 0.25

	var box := BoxMesh.new()
	box.size = DISPOSAL_EXTENTS * 2.0

	var vat := MeshInstance3D.new()
	vat.mesh = box
	vat.material_override = glass
	vat.position = DISPOSAL_OFFSET
	add_child(vat)

	var sign_ := Label3D.new()
	sign_.text = "DISPOSAL"
	sign_.font_size = 64
	sign_.pixel_size = 0.01
	sign_.modulate = Color(1.0, 0.5, 0.4)
	sign_.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_.position = DISPOSAL_OFFSET + Vector3.UP * (DISPOSAL_EXTENTS.y + 1.0)
	add_child(sign_)


func _in_disposal(point: Vector3) -> bool:
	var local := point - DISPOSAL_OFFSET
	return (
		absf(local.x) <= DISPOSAL_EXTENTS.x
		and absf(local.y) <= DISPOSAL_EXTENTS.y
		and absf(local.z) <= DISPOSAL_EXTENTS.z
	)


func salvage_value(monster: Monster) -> int:
	return maxi(1, roundi(_market.sell_price(monster.species, monster.color) * SALVAGE_SHARE))


## Let go of a carried animal: into the vat if it is dead and you dropped it there, into a tank
## otherwise. Reparenting is what actually moves an animal between tanks, since flockmates are siblings.
func _drop_dragged() -> void:
	var monster := _dragging
	_dragging = null
	if not is_instance_valid(monster):
		return

	if monster.dead and _in_disposal(monster.global_position):
		gold += salvage_value(monster)
		if _selected == monster:
			_select(null)
		monster.queue_free()
		return

	var destination := _tank_at(monster.global_position)
	if destination == null or (destination.is_full() and destination != monster.tank()):
		destination = monster.tank()

	if destination != monster.tank():
		var world := monster.global_position
		monster.get_parent().remove_child(monster)
		destination.monsters.add_child(monster)
		monster.global_position = world

	monster.position = monster.tank().clamp_point(monster.position)
	monster.release()


# --- Food ----------------------------------------------------------------------------------------


func drop_food(screen_position: Vector2) -> void:
	if _finished or food <= 0:
		return

	var tank := focused_tank()
	var depth := _camera.global_position.distance_to(tank.global_position)
	var world := _camera.project_position(screen_position, depth)

	food -= 1
	var pellet: Food = food_scene.instantiate()
	pellet.position = tank.clamp_point(world - tank.global_position)
	tank.pellets.add_child(pellet)


# --- Economy -------------------------------------------------------------------------------------


func buy_food() -> void:
	if _finished or gold < FOOD_PRICE:
		return
	gold -= FOOD_PRICE
	food += 1


func open_catalogue() -> void:
	if _finished:
		return
	_shop.open(_market)


## The catalogue sells GENETICS: a specimen grown to order, unrelated to anything in your tanks. That is
## the outcross you reach for when a line has bred itself into a corner.
func _on_bought(genome: Genome, price: int) -> void:
	var tank := focused_tank()
	if _finished or gold < price or tank.is_full():
		return
	gold -= price
	_spawn_monster(genome, tank, tank.random_point())
	_shop.reroll()


func sell_selected() -> void:
	if _finished or not is_instance_valid(_selected):
		return
	var sold := _selected
	gold += salvage_value(sold) if sold.dead else _market.sell_price(sold.species, sold.color)
	_select(null)
	sold.queue_free()


func _advance_day(delta: float) -> void:
	_day_timer += delta
	if _day_timer >= DAY_LENGTH:
		_day_timer -= DAY_LENGTH
		day += 1


func _check_outcome() -> void:
	if gold >= TARGET_GOLD:
		_finish("THE LAB THRIVES\nyou reached %d gold on day %d" % [gold, day])
	elif day > DEADLINE_DAYS:
		_finish("FUNDING WITHDRAWN\nyou raised %d of the %d gold needed" % [gold, TARGET_GOLD])


func _finish(message: String) -> void:
	_finished = true
	_result.text = "%s\n\n[R] TO START OVER" % message
	_result.visible = true
	get_tree().paused = true


# --- Animals -------------------------------------------------------------------------------------


func _reset() -> void:
	get_tree().paused = false
	_finished = false
	gold = START_GOLD
	food = START_FOOD
	day = 1
	_day_timer = 0.0
	_market = Market.new()
	_select(null)
	_dragging = null
	_shop.hide()

	for tank in _tanks:
		tank.free()
	_tanks.clear()
	_add_tank()
	focus_tank(0)

	var tank := focused_tank()
	for i in START_POPULATION:
		_spawn_monster(
			Genome.random(Color.from_hsv(randf(), 0.95, 1.0)), tank, tank.random_point()
		)


func _spawn_monster(genome: Genome, tank: Tank, spawn_point: Vector3) -> Monster:
	var monster: Monster = monster_scene.instantiate()
	monster.genome = genome
	monster.position = spawn_point
	monster.wants_to_breed.connect(_on_wants_to_breed)
	monster.clicked.connect(_on_monster_clicked)
	tank.monsters.add_child(monster)
	return monster


func _on_wants_to_breed(parent_a: Monster, parent_b: Monster) -> void:
	var tank := parent_a.tank()
	if _finished or tank == null or tank.is_full():
		return

	# Everything is genetic now — shape included. The child's whole body plan is blended and mutated, and
	# its species is simply whatever those genes round to.
	var child := Genome.mix(parent_a.genome, parent_b.genome)
	var birthplace := (parent_a.position + parent_b.position) * 0.5
	_spawn_monster(child, tank, tank.clamp_point(birthplace))

	parent_a.on_bred()
	parent_b.on_bred()


## Clicking an animal selects it, picks it up, AND makes it the centre of the camera's orbit.
func _on_monster_clicked(monster: Monster) -> void:
	if _finished:
		return
	_select(monster)

	_dragging = monster
	_drag_depth = _camera.global_position.distance_to(monster.global_position)
	monster.grab()


func _select(monster: Monster) -> void:
	if is_instance_valid(_selected):
		_selected.selected = false
	_selected = monster
	if is_instance_valid(_selected):
		_selected.selected = true
	# The camera orbits whatever you have selected; with nothing selected it falls back to the tank.
	_rig.subject = _selected


func _keep_monsters_inside() -> void:
	var escape := Tank.EXTENTS + Vector3.ONE * 2.0
	for tank in _tanks:
		for monster: Monster in tank.monsters.get_children():
			if monster.held:
				continue
			var p := monster.position
			if absf(p.x) > escape.x or absf(p.y) > escape.y or absf(p.z) > escape.z:
				monster.position = tank.random_point()
				monster.launch()


# --- HUD -----------------------------------------------------------------------------------------


func _rebuild_tank_buttons() -> void:
	for button in _tank_buttons.get_children():
		button.queue_free()
	for i in tank_count():
		var button := Button.new()
		button.text = str(i + 1)
		button.pressed.connect(focus_tank.bind(i))
		_tank_buttons.add_child(button)


func _refresh_hud() -> void:
	var tank := focused_tank()
	var living := 0
	var corpses := 0
	var hungry := 0
	for monster: Monster in tank.monsters.get_children():
		if monster.dead:
			corpses += 1
			continue
		living += 1
		if monster.is_hungry():
			hungry += 1

	_status.text = (
		"CREDITS %d/%d   DAY %d/%d   FEED %d   TANK %d/%d   SPECIMENS %d/%d   HUNGRY %d   DECEASED %d\n"
		% [
			gold, TARGET_GOLD, day, DEADLINE_DAYS, food,
			_focused + 1, tank_count(), living, Tank.MAX_POPULATION, hungry, corpses,
		]
		+ "CLICK WATER: DROP FEED   CLICK SPECIMEN: SELECT + ORBIT   DRAG: RELOCATE   DEAD -> DISPOSAL VAT"
	)

	_buy_food_button.text = "FEED  %dg" % FOOD_PRICE
	_buy_food_button.disabled = _finished or gold < FOOD_PRICE

	var maxed := tank_count() >= MAX_TANKS
	_buy_tank_button.text = "TANKS MAXED" if maxed else "NEW TANK  %dg" % tank_price()
	_buy_tank_button.disabled = _finished or maxed or gold < tank_price()

	_catalogue_button.disabled = _finished

	_selection_panel.visible = is_instance_valid(_selected)
	if is_instance_valid(_selected):
		var species: String = _selected.species
		if _selected.dead:
			_selection_label.text = (
				"%s\n\n:: DECEASED ::\ndrag to the disposal vat\n\nsalvage %dg"
				% [species.to_upper(), salvage_value(_selected)]
			)
			_sell_button.text = "SALVAGE  %dg" % salvage_value(_selected)
		else:
			var price := _market.sell_price(species, _selected.color)
			_selection_label.text = (
				"%s   %d faces\nvivid %d%%   age %d%%%s\n\n%s"
				% [
					species.to_upper(),
					Species.faces(species),
					roundi(_selected.color.s * 100.0),
					roundi(_selected.agedness() * 100.0),
					"\n:: HUNGRY ::" if _selected.is_hungry() else "",
					_selected.genome.describe(),
				]
			)
			_sell_button.text = "SELL  %dg" % price
