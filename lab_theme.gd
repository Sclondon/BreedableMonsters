class_name LabTheme
extends RefCounted

## The look: a genetics lab terminal. Near-black panels, thin cyan rules, neon-blue monospace text.
##
## NOTE ON THE FONT. No pixel font ships with this project, and a real bitmap face would have to be a
## licensed .ttf added to the repo. This uses a monospace SystemFont with antialiasing switched off,
## which on Windows lands on Consolas and reads convincingly like a terminal. To swap in a true pixel
## font later, drop the .ttf beside this file and replace _font() with a FontFile load — nothing else
## needs to change.

const NEON := Color(0.31, 0.94, 1.0)
const NEON_DIM := Color(0.18, 0.55, 0.62)
const NEON_HOT := Color(0.55, 1.0, 1.0)
const PANEL := Color(0.03, 0.05, 0.07, 0.92)
const PANEL_EDGE := Color(0.16, 0.55, 0.65, 0.9)
const DANGER := Color(1.0, 0.45, 0.35)

const TEXT_SIZE := 14
const TITLE_SIZE := 18


static func build() -> Theme:
	var theme := Theme.new()
	var font := _font()

	theme.default_font = font
	theme.default_font_size = TEXT_SIZE

	_style_label(theme)
	_style_button(theme, font)
	_style_panel(theme)
	return theme


static func _font() -> Font:
	var font := SystemFont.new()
	# Ordered by preference; Godot falls back to whatever exists on the machine.
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	# Crisp, unsmoothed edges — this is what sells the terminal look.
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font


static func _style_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", NEON)
	theme.set_color("font_outline_color", "Label", Color(0, 0.1, 0.12, 0.8))
	theme.set_constant("outline_size", "Label", 0)
	theme.set_font_size("font_size", "Label", TEXT_SIZE)


static func _style_button(theme: Theme, font: Font) -> void:
	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Button", TEXT_SIZE)
	theme.set_color("font_color", "Button", NEON)
	theme.set_color("font_hover_color", "Button", NEON_HOT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", NEON_DIM)

	theme.set_stylebox("normal", "Button", _box(Color(0.05, 0.09, 0.12, 0.95), PANEL_EDGE))
	theme.set_stylebox("hover", "Button", _box(Color(0.08, 0.18, 0.22, 0.95), NEON))
	theme.set_stylebox("pressed", "Button", _box(Color(0.12, 0.3, 0.35, 0.95), NEON_HOT))
	theme.set_stylebox("disabled", "Button", _box(Color(0.04, 0.06, 0.07, 0.8), Color(0.12, 0.25, 0.3, 0.6)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())


static func _style_panel(theme: Theme) -> void:
	var panel := _box(PANEL, PANEL_EDGE)
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)


static func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## A live 3D preview of the animal a genome would grow into — the shop shows you the creature, not a
## row of numbers.
static func preview_of(genome: Genome, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var pivot := Node3D.new()
	viewport.add_child(pivot)

	var mesh := MeshInstance3D.new()
	mesh.mesh = Species.mesh_for(Species.of(genome))

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(genome.color, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = genome.color
	material.emission_energy_multiplier = 0.5
	mesh.material_override = material
	mesh.scale = Vector3.ONE * genome.max_size
	pivot.add_child(mesh)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	viewport.add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.6, 3.4)
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	viewport.add_child(camera)

	# Slowly turn it, so the silhouette reads from every side.
	var spin := preview_spin(pivot)
	pivot.add_child(spin)
	return viewport


static func preview_spin(pivot: Node3D) -> Node:
	var spinner := PreviewSpinner.new()
	spinner.pivot = pivot
	return spinner


class PreviewSpinner:
	extends Node

	var pivot: Node3D

	func _process(delta: float) -> void:
		if is_instance_valid(pivot):
			pivot.rotate_y(0.7 * delta)
