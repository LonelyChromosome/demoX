class_name GameplayTheme
extends RefCounted


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	for type in ["Label", "Button", "CheckButton", "OptionButton", "RichTextLabel"]:
		theme.set_color("font_color", type, Color("f1e6c9"))
	theme.set_color("default_color", "RichTextLabel", Color("f1e6c9"))
	theme.set_stylebox("panel", "PanelContainer", panel(Color("354335"), Color("827955")))
	theme.set_stylebox("panel", "Panel", panel(Color("354335"), Color("827955")))
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, panel(Color("405245"), Color("8c8762")))
		theme.set_stylebox("hover", type, panel(Color("536654"), Color("d5bd81")))
		theme.set_stylebox("pressed", type, panel(Color("34596d"), Color("d5bd81")))
		theme.set_stylebox("disabled", type, panel(Color("394238"), Color("606950")))
		theme.set_stylebox("focus", type, panel(Color(0, 0, 0, 0), Color("e0c88f")))
	return theme


static func panel(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
