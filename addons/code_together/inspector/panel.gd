@tool
extends PanelContainer

const Profile = preload("../profile.gd")
const Settings = preload("../settings.gd")
const Guides = preload("../drawing/viewport_guides.gd")
const Geometry = preload("../drawing/geometry.gd")
const TAB_NAMES := ["User", "Connection", "Session", "Chat", "AI", "Misc"]

signal drawing_view_requested

var _profile: Profile
var _settings: Settings
var _guides: Guides
var _pages: Array[ScrollContainer] = []
var _tabs: Array[Button] = []
var _name_field: LineEdit
var _name_dirty := false
var _name_error: Label
var _color_label: Label
var _color_error: Label
var _swatches: Dictionary[String, Button] = {}
var _height: SpinBox
var _sample: Button
var _drawing_notice: Label

func setup(profile: Profile, settings: Settings, guides: Guides) -> void:
	_profile = profile
	_settings = settings
	_guides = guides
	custom_minimum_size.x = 255
	theme = _build_theme()
	add_theme_stylebox_override("panel", box("#171b25", "", 0, 10))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title := _label(root, "Code Together", "#b9d6ff", 20)
	_bold(title)
	var presence := PanelContainer.new()
	presence.add_theme_stylebox_override("panel", box("#202936", "#3c5374", 5, 10))
	presence.custom_minimum_size.y = 42
	root.add_child(presence)
	_label(presence, "No session connected", "#aabbd5")

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 3)
	tabs.add_theme_constant_override("v_separation", 4)
	root.add_child(tabs)
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	var button_group := ButtonGroup.new()
	for i in TAB_NAMES.size():
		var tab := _button(tabs, TAB_NAMES[i])
		tab.toggle_mode = true
		tab.button_group = button_group
		tab.pressed.connect(_select_tab.bind(i))
		_tabs.append(tab)
		var page := ScrollContainer.new()
		page.name = "Page" + TAB_NAMES[i]
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pages.append(page)
	_build_user(_page(0))
	_build_connection(_page(1))
	_build_session(_page(2))
	_build_chat(_page(3))
	_build_ai(_page(4))
	_build_misc(_page(5))
	_select_tab(5)

func refresh_profile() -> void:
	if not _name_field.has_focus() and not _name_dirty and _name_field.text != _profile.display_name:
		_name_field.text = _profile.display_name
		_name_error.hide()
	var favorite := _profile.favorite_color
	_color_label.text = "Favorite Color: " + favorite
	for preset in _swatches:
		_swatches[preset].set_pressed_no_signal(preset == favorite)

func _select_tab(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
		_tabs[i].set_pressed_no_signal(i == index)
	if index == 0:
		_profile.refresh()
		refresh_profile()

func _page(index: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_pages[index].add_child(column)
	return column

func _build_user(page: VBoxContainer) -> void:
	var card := _card(page, "Profile")
	_name_field = _line(card, "Display Name", _profile.display_name)
	_name_field.tooltip_text = "Press Enter or leave the field to save locally."
	_name_field.text_changed.connect(func(_text: String) -> void: _name_dirty = true)
	_name_field.text_submitted.connect(func(_text: String) -> void: _commit_name())
	_name_field.focus_exited.connect(_commit_name)
	_name_error = _note(card, "")
	_name_error.hide()
	_color_label = _label(card, "")
	_bold(_color_label)
	_color_error = _note(card, "Could not save the shared favorite color.")
	_color_error.hide()
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.add_child(grid)
	var group := ButtonGroup.new()
	for preset in Profile.PALETTE:
		var swatch := _button(grid, "")
		swatch.tooltip_text = preset
		swatch.custom_minimum_size = Vector2(29, 29)
		swatch.toggle_mode = true
		swatch.button_group = group
		var base: Color = Profile.PALETTE[preset]
		swatch.add_theme_stylebox_override("normal", box(base, "#5a6d88", 4))
		swatch.add_theme_stylebox_override("hover", box(base, "#a3c7fd", 4))
		swatch.add_theme_stylebox_override("pressed", box(base, "#d7e8ff", 4, 0, 2))
		swatch.add_theme_stylebox_override("hover_pressed", box(base, "#d7e8ff", 4, 0, 2))
		swatch.pressed.connect(_save_color.bind(preset))
		_swatches[preset] = swatch
	_note(card, "Your favorite color is requested when you join.")
	_action(card, "Choose Session Color")
	refresh_profile()

func _commit_name() -> void:
	if not _name_dirty:
		_profile.refresh()
		refresh_profile()
		return
	_name_dirty = false
	var normalized := Profile.normalize_name(_name_field.text)
	if normalized.is_empty():
		_name_error.text = "Enter a display name between 1 and 64 characters."
		_name_error.show()
		return
	if not _profile.save_name(normalized):
		_name_error.text = "Could not save the shared display name."
		_name_error.show()
		return
	_name_error.hide()
	_name_field.text = normalized
	_name_field.caret_column = normalized.length()

func _save_color(preset: String) -> void:
	_color_error.visible = not _profile.save_color(preset)
	refresh_profile()
	_guides.color = Profile.PALETTE[_profile.favorite_color]
	_guides.changed.emit()

func _build_connection(page: VBoxContainer) -> void:
	var join := _card(page, "Join by Address")
	var address := _line(join, "Address", _settings.value("address"))
	address.tooltip_text = "Server hostname or IP address"
	var port := _line(join, "Port", str(_settings.value("port")))
	port.tooltip_text = "Server port"
	var error := _note(join, "")
	error.hide()
	var save := func() -> void:
		error.text = _settings.save_endpoint(address.text, port.text)
		error.visible = not error.text.is_empty()
		if not error.visible:
			address.text = _settings.value("address")
			port.text = str(_settings.value("port"))
	address.text_submitted.connect(func(_text: String) -> void: save.call())
	port.text_submitted.connect(func(_text: String) -> void: save.call())
	address.focus_exited.connect(func() -> void:
		if address.text != _settings.value("address"):
			save.call())
	port.focus_exited.connect(func() -> void:
		if port.text != str(_settings.value("port")):
			save.call())
	_line(join, "Password", "", true)
	_action(join, "Join Session", true)
	var host := _card(page, "Host a Session")
	_line(host, "Session Name")
	_number(host, "Port", 0, 0, 65535, 1)
	var password := _line(host, "Password", "", true)
	password.tooltip_text = "Optional. Leave blank to host without a password."
	_action(host, "Host Session")
	_note(_card(page, "Favorites"), "No favorites saved.")
	_note(_card(page, "Recent Connections"), "No recent connections.")

func _build_session(page: VBoxContainer) -> void:
	_note(_card(page, "Session"), "Join a session to see participants and their current apps.")

func _build_chat(page: VBoxContainer) -> void:
	var card := _card(page, "Chat")
	_note(card, "Join a session to chat across connected IDEs and engines.")
	_compose(card, "Message", false)
	_action(card, "Send", true)
	_switch(card, "Show Chat in 3D Viewport", _settings.value("chat_viewport")).toggled.connect(_save_setting.bind("chat_viewport"))
	_switch(card, "Show Chat at Bottom of Tabs", _settings.value("chat_tabs")).toggled.connect(_save_setting.bind("chat_tabs"))

func _build_ai(page: VBoxContainer) -> void:
	var agent := _card(page, "AI Agent")
	_note(agent, "No AI agent connected.")
	_choice(agent, "Provider", ["ChatGPT", "Claude", "Gemini", "Grok"], 0)
	_action(agent, "Connect AI", true)
	_line(agent, "Nickname")
	_choice(agent, "Mode", ["Off", "On Request", "Selective", "Active"], 0)
	var context := _card(page, "Scene Context")
	_note(context, "No guide attached.")
	_compose(context, "AI request", true)
	_action(context, "Send", true)
	var objects := _card(page, "Preferred Objects")
	_note(objects, "No preferred objects added.")
	_action(objects, "Add Objects")

func _build_misc(page: VBoxContainer) -> void:
	var card := _card(page, "Drawing")
	var toggle := _button(card, "Open Drawing Tools")
	var tool := _choice(card, "Tool", Guides.TOOL_NAMES, _guides.tool)
	var delete := _button(card, "Delete Selected")
	var scene_hint := _note(card, "Open and save a 3D scene to use the drawing tools.")
	toggle.pressed.connect(func() -> void:
		_guides.set_tools_open(not _guides.expanded)
		if _guides.expanded:
			drawing_view_requested.emit())
	tool.item_selected.connect(_guides.set_tool)
	delete.pressed.connect(_guides.delete_selected)
	var refresh_tools := func() -> void:
		var has_scene := not _guides.scene.is_empty()
		toggle.disabled = not has_scene
		toggle.text = "Close Drawing Tools" if has_scene and _guides.expanded else "Open Drawing Tools"
		tool.disabled = not has_scene or not _guides.expanded
		tool.select(_guides.tool)
		delete.disabled = tool.disabled or _guides.selected.get("owner") != Guides.LOCAL_OWNER
		scene_hint.visible = not has_scene
	_guides.changed.connect(refresh_tools)
	refresh_tools.call()
	var initial_plane := clampi(_settings.value("plane"), 0, 2)
	var plane := _choice(card, "Plane", ["Ground (XZ)", "Scene (XY)", "Camera"], initial_plane)
	_height = _number(card, "Fixed Height", _settings.value("height"), -1000000, 1000000, 0.01)
	_height.value_changed.connect(_save_setting.bind("height"))
	_switch(card, "Follow Surfaces", _settings.value("follow")).toggled.connect(_save_setting.bind("follow"))
	_build_layer_mask(card)
	_number(card, "Snap", _settings.value("snap"), 0, 1000000, 0.01).value_changed.connect(_save_setting.bind("snap"))
	_slider(card, "Line Width", _settings.value("width"), 1, 8, 0.1).value_changed.connect(_save_setting.bind("width"))
	_sample = _button(card, "Sample Height")
	_sample.pressed.connect(_guides.begin_height_sample)
	_guides.height_sampled.connect(func() -> void: _height.set_value_no_signal(_settings.value("height")))
	_guides.changed.connect(func() -> void: _sample.disabled = int(_settings.value("plane")) != Geometry.Placement.GROUND or _guides.scene.is_empty())
	plane.item_selected.connect(func(index: int) -> void:
		_save_setting(index, "plane")
		_update_plane(index))
	_update_plane(initial_plane)
	_bold(_label(card, "Pencil"))
	_number(card, "Minimum Segment Length", _settings.value("min_segment"), 0.001, 1000000, 0.001).value_changed.connect(_save_setting.bind("min_segment"))
	_slider(card, "Smoothing", _settings.value("smoothing"), 0, 1, 0.01).value_changed.connect(_save_setting.bind("smoothing"))
	_switch(card, "Snap to Grid", _settings.value("pencil_snap")).toggled.connect(_save_setting.bind("pencil_snap"))
	_drawing_notice = _note(card, "")
	_drawing_notice.hide()
	_guides.notice.connect(_show_drawing_notice)
	var erase := _button(card, "Erase All My Guides")
	var confirm := ConfirmationDialog.new()
	confirm.title = "Erase Guides"
	confirm.dialog_text = "Erase your guides in the active scene?"
	confirm.ok_button_text = "Erase"
	add_child(confirm)
	var pending_scene := [""]
	erase.pressed.connect(func() -> void:
		pending_scene[0] = _guides.scene
		confirm.popup_centered())
	confirm.confirmed.connect(func() -> void:
		if _guides.scene == pending_scene[0]:
			_guides.erase_all())
	_guides.changed.connect(func() -> void: erase.disabled = _guides.scene.is_empty())
	erase.disabled = _guides.scene.is_empty()
	var ping := _card(page, "Context Ping")
	_number(ping, "Duration (s)", 5, 0, 60, 0.1).editable = false
	_number(ping, "Size", 1, 0, 100, 0.1).editable = false
	_switch(ping, "Reduced Motion", false).disabled = true
	var audio := _card(page, "Audio")
	_slider(audio, "Ping Sound", 0.7, 0, 1, 0.01).editable = false
	_slider(audio, "Presence Sound", 0.7, 0, 1, 0.01).editable = false

func _update_plane(index: int) -> void:
	_height.editable = index != Geometry.Placement.CAMERA
	_sample.disabled = index != Geometry.Placement.GROUND or _guides.scene.is_empty()

func _show_drawing_notice(message: String) -> void:
	_drawing_notice.text = message
	_drawing_notice.show()

func _save_setting(new_value: Variant, key: String) -> void:
	var result := _settings.set_value(key, new_value)
	if result != OK and _drawing_notice != null:
		_show_drawing_notice("Could not save adapter settings.")
	_guides.changed.emit()

func _build_layer_mask(parent: Container) -> void:
	var menu := MenuButton.new()
	_field(parent, "Height Layer Mask", menu)
	var popup := menu.get_popup()
	popup.hide_on_checkable_item_selection = false
	popup.add_item("All", 32)
	popup.add_item("None", 33)
	popup.add_separator()
	for i in 32:
		var layer: String = ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % (i + 1), "")
		var label := "%d: %s" % [i + 1, layer] if not layer.is_empty() else "Layer %d" % (i + 1)
		popup.add_check_item(label, i)
	var update := func() -> void:
		var mask: int = _settings.value("mask")
		var count := 0
		for i in 32:
			var checked := (mask & (1 << i)) != 0
			popup.set_item_checked(popup.get_item_index(i), checked)
			count += int(checked)
		menu.text = "All" if count == 32 else ("None" if count == 0 else "%d layers" % count)
	popup.id_pressed.connect(func(id: int) -> void:
		var mask: int = _settings.value("mask")
		if id == 32:
			mask = 0xffffffff
		elif id == 33:
			mask = 0
		else:
			mask ^= 1 << id
		_save_setting(mask, "mask")
		update.call())
	update.call()

func _card(parent: Container, text: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", box("#212937", "#3d4f66", 5, 11))
	parent.add_child(frame)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	frame.add_child(card)
	_bold(_label(card, text))
	return card

func _bold(label: Label) -> void:
	var font := get_theme_font("bold", "EditorFonts")
	if font != null:
		label.add_theme_font_override("font", font)

func _label(parent: Container, text: String, color: String = "#edf2fb", font_size: int = 13) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(color))
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _note(parent: Container, text: String) -> Label:
	var label := _label(parent, text, "#adbed5")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _field(parent: Container, title: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := _label(row, title, "#e1eaf6")
	label.custom_minimum_size.x = 99
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)

func _line(parent: Container, title: String, value: String = "", secret: bool = false) -> LineEdit:
	var line := LineEdit.new()
	line.text = value
	line.secret = secret
	line.custom_minimum_size = Vector2(76, 26)
	_field(parent, title, line)
	return line

func _number(parent: Container, title: String, value: float, low: float, high: float, step: float) -> SpinBox:
	var number := SpinBox.new()
	number.min_value = low
	number.max_value = high
	number.step = step
	number.value = value
	number.get_line_edit().custom_minimum_size.x = 66
	_field(parent, title, number)
	return number

func _slider(parent: Container, title: String, value: float, low: float, high: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_field(parent, title, slider)
	return slider

func _choice(parent: Container, title: String, items: Array, index: int) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.selected = index
	option.fit_to_longest_item = false
	_field(parent, title, option)
	return option

func _switch(parent: Container, title: String, state: bool) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.button_pressed = state
	_field(parent, title, toggle)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	return toggle

func _compose(parent: Container, hint: String, editable: bool) -> void:
	var input := TextEdit.new()
	input.placeholder_text = hint
	input.custom_minimum_size.y = 56
	input.editable = editable
	parent.add_child(input)

func _button(parent: Container, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 26
	parent.add_child(button)
	return button

func _action(parent: Container, text: String, primary: bool = false) -> void:
	var button := _button(parent, text)
	button.disabled = true
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.add_theme_stylebox_override("disabled", box("#2b548a", "#71a1e1", 4, 5) if primary else box("#27354b", "#4b678c", 4, 5))

static func box(fill: Variant, border: String = "", radius: int = 4, padding: int = 0, thickness: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill) if fill is String else fill
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	if not border.is_empty():
		style.border_color = Color(border)
		style.set_border_width_all(thickness)
	return style

static func _build_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 13
	for type in ["Button", "OptionButton", "MenuButton"]:
		result.set_stylebox("normal", type, box("#252e3d", "#394960", 4, 4))
		result.set_stylebox("hover", type, box("#303e53", "#536882", 4, 4))
		result.set_stylebox("pressed", type, box("#294f83", "#79affb", 4, 4))
		result.set_stylebox("hover_pressed", type, box("#294f83", "#79affb", 4, 4))
		result.set_stylebox("focus", type, box("#00000000", "#a3c7fd", 4))
		result.set_color("font_color", type, Color("#dce7f5"))
	for type in ["LineEdit", "TextEdit", "OptionButton"]:
		result.set_stylebox("normal", type, box("#343f51", "#536882", 4, 4))
		result.set_stylebox("focus", type, box("#00000000", "#86b4f4", 4))
		result.set_color("font_color", type, Color("#f3f7ff"))
	return result
