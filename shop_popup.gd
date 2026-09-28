class_name ShopPopup
extends PanelContainer

## SPECIMEN CATALOGUE. Three polymons, grown at random, each shown as the creature it would actually be
## rather than as a line of text: a live 3D preview of the very mesh its genes produce, beside a readout
## of what it is and what it wants.
##
## This replaces the old list of species buttons. There is no "stock" any more — the shop is a supply of
## fresh GENETICS, and no two offers are ever quite the same animal.

signal bought(genome: Genome, price: int)

const OFFERS := 3
const PREVIEW_SIZE := Vector2i(150, 150)
## What the lab charges over the animal's market value for growing you a bespoke specimen.
const MARKUP := 1.15

var _market: Market
var _offers: Array[Genome] = []

@onready var _row: HBoxContainer = $Rows/Offers
@onready var _reroll_button: Button = $Rows/Buttons/Reroll
@onready var _close_button: Button = $Rows/Buttons/Close


func _ready() -> void:
	hide()
	_reroll_button.pressed.connect(reroll)
	_close_button.pressed.connect(hide)


func open(market: Market) -> void:
	_market = market
	reroll()
	show()


## Grow three new specimens. Rerolling is free — the cost of the catalogue is that you cannot keep a
## specimen you passed over.
func reroll() -> void:
	_offers.clear()
	for i in OFFERS:
		_offers.append(Genome.random(Color.from_hsv(randf(), randf_range(0.6, 1.0), 1.0)))
	_rebuild()


func price_of(genome: Genome) -> int:
	return roundi(_market.buy_price(Species.of(genome)) * MARKUP)


func _rebuild() -> void:
	for child in _row.get_children():
		child.queue_free()

	for genome in _offers:
		_row.add_child(_build_offer(genome))


func _build_offer(genome: Genome) -> Control:
	var card := PanelContainer.new()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	card.add_child(rows)

	var species := Species.of(genome)

	var title := Label.new()
	title.text = species.to_upper()
	title.add_theme_font_size_override("font_size", LabTheme.TITLE_SIZE)
	title.add_theme_color_override("font_color", LabTheme.NEON_HOT)
	rows.add_child(title)

	# The live preview: the actual solid these genes grow, turning slowly.
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = PREVIEW_SIZE
	frame.stretch = true
	frame.add_child(LabTheme.preview_of(genome, PREVIEW_SIZE))
	rows.add_child(frame)

	var readout := Label.new()
	readout.text = (
		"%d faces   vivid %d%%\n%s\nspeed x%.2f  size x%.2f\n%s"
		% [
			Species.faces(species),
			roundi(genome.color.s * 100.0),
			genome.gait(),
			genome.speed_mult,
			genome.max_size,
			genome.taste(),
		]
	)
	readout.add_theme_color_override("font_color", LabTheme.NEON_DIM)
	rows.add_child(readout)

	var buy := Button.new()
	var price := price_of(genome)
	buy.text = "ACQUIRE  %dg" % price
	buy.pressed.connect(func(): bought.emit(genome, price))
	rows.add_child(buy)

	return card
