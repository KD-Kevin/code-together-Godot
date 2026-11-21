@tool
extends EditorPlugin

const Profile = preload("profile.gd")
const Settings = preload("settings.gd")
const InspectorPanel = preload("inspector/panel.gd")
const Guides = preload("drawing/viewport_guides.gd")

var _profile: Profile
var _guides: Guides
var _dock: EditorDock
var _panel: PanelContainer
var _toolbar: HBoxContainer
var _tool_buttons: HBoxContainer
var _expand: Button
var _delete: Button
var _tool_choices: Array[Button] = []
var _scene_root: Node
var _profile_poll := 0.0
var _viewports: Array[SubViewport] = []
var _view_states: Dictionary[int, Array] = {}

func _enter_tree() -> void:
	_profile = Profile.new()
	var settings := Settings.new(_profile.directory.get_base_dir().path_join("GodotSettings.cfg"))
	_guides = Guides.new(settings)
	_guides.color = Profile.PALETTE[_profile.favorite_color]
	_guides.changed.connect(_refresh_toolbar)
	_guides.redraw_requested.connect(update_overlays)
	_dock = EditorDock.new()
	_dock.name = "CodeTogether"
	_dock.title = "Code Together"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_panel = InspectorPanel.new()
	_dock.add_child(_panel)
	_panel.setup(_profile, settings, _guides)
	_panel.drawing_view_requested.connect(func() -> void: EditorInterface.set_main_screen_editor("3D"))
	add_dock(_dock)
	add_tool_menu_item("Code Together", _dock.open)
	_build_toolbar()
	for i in 4:
		_register_viewport(EditorInterface.get_editor_viewport_3d(i))
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	scene_saved.connect(_on_scene_saved)
	_on_scene_changed(EditorInterface.get_edited_scene_root())
	set_process(true)

func _exit_tree() -> void:
	set_process(false)
	scene_changed.disconnect(_on_scene_changed)
	scene_saved.disconnect(_on_scene_saved)
	remove_tool_menu_item("Code Together")
	remove_dock(_dock)
	_dock.free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.free()
	_viewports.clear()
	_view_states.clear()
	_tool_choices.clear()
	_scene_root = null
	_guides = null

func _process(delta: float) -> void:
	_refresh_camera_overlays()
	_profile_poll += delta
	if _profile_poll < 1.0:
		return
	_profile_poll = 0.0
	if _profile.refresh():
		_panel.refresh_profile()
	var favorite: Color = Profile.PALETTE[_profile.favorite_color]
	if favorite != _guides.color:
		_guides.color = favorite
		update_overlays()

func _refresh_camera_overlays() -> void:
	if _guides.scene.is_empty() or not _guides.has_overlay_content():
		if not _view_states.is_empty():
			_view_states.clear()
			update_overlays()
		return
	var dirty := false
	var brush_visible := _guides.is_brush_active()
	for viewport in _viewports:
		if not is_instance_valid(viewport) or viewport.size.x <= 0 or viewport.size.y <= 0:
			continue
		var camera := viewport.get_camera_3d()
		if camera == null:
			continue
		var id := camera.get_instance_id()
		var mouse := viewport.get_mouse_position() if brush_visible else Vector2.ZERO
		var state := [camera.get_camera_transform(), camera.get_camera_projection(), viewport.get_visible_rect().size, mouse, brush_visible]
		if _view_states.get(id) != state:
			_view_states[id] = state
			dirty = true
	if dirty:
		update_overlays()

func _on_scene_changed(root: Node) -> void:
	_scene_root = root
	_update_scene()

func _on_scene_saved(_path: String) -> void:
	_update_scene()

func _update_scene() -> void:
	var id := ""
	if is_instance_valid(_scene_root):
		var path := _scene_root.scene_file_path
		if not path.is_empty():
			var uid := ResourceLoader.get_resource_uid(path)
			id = ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else path
	_guides.set_scene(id)
	_refresh_toolbar()

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	_register_viewport(camera.get_viewport() as SubViewport)
	if _guides.input(camera, event):
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if _guides == null or _guides.scene.is_empty():
		return
	if _viewports.is_empty():
		for i in 4:
			_register_viewport(EditorInterface.get_editor_viewport_3d(i))
	var container: Node = overlay.get_parent()
	while container != null:
		for viewport in _viewports:
			if is_instance_valid(viewport) and container.is_ancestor_of(viewport):
				_guides.draw(overlay, viewport.get_camera_3d())
				return
		container = container.get_parent()

func _register_viewport(viewport: SubViewport) -> void:
	if viewport != null and not _viewports.has(viewport):
		_viewports.append(viewport)

func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 2)
	_expand = _toolbar_button(_toolbar, "Drawing Tools")
	_expand.pressed.connect(_toggle_tools)
	_tool_buttons = HBoxContainer.new()
	_tool_buttons.add_theme_constant_override("separation", 2)
	_toolbar.add_child(_tool_buttons)
	var group := ButtonGroup.new()
	for i in Guides.TOOL_NAMES.size():
		var button := _toolbar_button(_tool_buttons, Guides.TOOL_NAMES[i])
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_guides.set_tool.bind(i))
		_tool_choices.append(button)
	_delete = _toolbar_button(_tool_buttons, "Delete Selected")
	_delete.pressed.connect(_guides.delete_selected)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)

func _toolbar_button(parent: Container, label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", InspectorPanel.box("#252e3d", "#394960", 4, 4))
	button.add_theme_stylebox_override("hover", InspectorPanel.box("#303e53", "#536882", 4, 4))
	button.add_theme_stylebox_override("pressed", InspectorPanel.box("#294f83", "#79affb", 4, 4))
	button.add_theme_stylebox_override("hover_pressed", InspectorPanel.box("#294f83", "#79affb", 4, 4))
	parent.add_child(button)
	return button

func _toggle_tools() -> void:
	_guides.set_tools_open(not _guides.expanded)

func _refresh_toolbar() -> void:
	_expand.disabled = _guides.scene.is_empty()
	_expand.text = "Close" if _guides.expanded and not _expand.disabled else "Drawing Tools"
	_tool_buttons.visible = _guides.expanded and not _expand.disabled
	for i in _tool_choices.size():
		_tool_choices[i].set_pressed_no_signal(i == _guides.tool)
	_delete.disabled = _guides.selected.is_empty() or _guides.selected.get("owner") != Guides.LOCAL_OWNER
	update_overlays()
