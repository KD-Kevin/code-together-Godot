extends SceneTree

const Profile = preload("res://addons/code_together/profile.gd")
const Settings = preload("res://addons/code_together/settings.gd")
const Geometry = preload("res://addons/code_together/drawing/geometry.gd")
const Store = preload("res://addons/code_together/drawing/guide_store.gd")
const Guides = preload("res://addons/code_together/drawing/viewport_guides.gd")
const InspectorPanel = preload("res://addons/code_together/inspector/panel.gd")

var _cases := 0
var _failures := 0
var _scratch: String
var _settings: Settings

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_scratch = ProjectSettings.globalize_path("user://adapter-tests-" + Crypto.new().generate_random_bytes(8).hex_encode())
	DirAccess.make_dir_recursive_absolute(_scratch)
	_settings = Settings.new(_scratch.path_join("settings.cfg"))
	_test_profile()
	_test_endpoint()
	_test_geometry()
	_test_eraser()
	await _test_viewport()
	await _test_panel()
	for file in DirAccess.get_files_at(_scratch):
		DirAccess.remove_absolute(_scratch.path_join(file))
	DirAccess.remove_absolute(_scratch)
	print("Code Together: %d checks, %d failures." % [_cases, _failures])
	quit(0 if _failures == 0 else 1)

func _check(result: bool, description: String) -> void:
	_cases += 1
	if not result:
		_failures += 1
		printerr("FAIL: " + description)

func _test_profile() -> void:
	var first := Profile.new(_scratch)
	var second := Profile.new(_scratch)
	_check(first.display_name == "" and first.favorite_color == "Light Purple", "Matches disconnected profile defaults")
	_check(first.save_name("  Godot Developer  "), "Publish normalized display name")
	_check(second.refresh() and second.display_name == "Godot Developer", "Another adapter instance picks up the name")
	_check(second.save_name("Unreal Developer") and first.refresh() and first.display_name == "Unreal Developer", "Replace an existing shared name")
	_check(not first.save_name("   ") and not first.save_name("x".repeat(65)) and not first.save_name("🟦".repeat(33)), "Reject invalid UTF-16 lengths")
	_check(first.save_color("Teal") and second.refresh() and second.favorite_color == "Teal", "Refresh favorite color independently")
	_check(second.save_color("Navy") and first.refresh() and first.favorite_color == "Navy", "Replace an existing shared color")
	_check(not first.save_color("Invalid"), "Reject unknown swatches")
	_check(Profile.PALETTE.size() == 35 and Profile.PALETTE["Light Purple"].to_html(false) == "ad80f5", "Reference palette count and default RGB")

func _test_endpoint() -> void:
	_check(_settings.value("plane") == Geometry.Placement.CAMERA and _settings.value("follow") and _settings.value("mask") == 0xffffffff, "Camera placement and surface projection enabled by default")
	_check(_settings.save_endpoint(" [::1] ", "8080").is_empty(), "Accept bracketed IPv6")
	_check(_settings.save_endpoint("server.local", "65535").is_empty(), "Accept a hostname and maximum port")
	_check(not _settings.save_endpoint("https://server.local", "8080").is_empty(), "Reject URL in address field")
	_check(not _settings.save_endpoint("host:9000", "8080").is_empty(), "Reject combined host and port")
	_check(not _settings.save_endpoint("127.0.0.1", "65536").is_empty(), "Reject out-of-range port")
	var reloaded := Settings.new(_scratch.path_join("settings.cfg"))
	_check(reloaded.value("address") == "server.local" and reloaded.value("port") == 65535, "Reload the last valid address and port")

func _test_geometry() -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(4, 1)])
	var rect := Geometry.path_for(Geometry.Tool.RECTANGLE, points, true, 0.0)
	_check(rect.size() == 5 and rect[2] == Vector2(4, 4) and rect[0] == rect[-1], "Shift constrains a closed square")
	var oval := Geometry.path_for(Geometry.Tool.OVAL, points, true, 0.0)
	_check(oval.size() == 49 and oval[0] == oval[-1] and oval[12].is_equal_approx(Vector2(2, 4)), "Shift constrains a closed 48-segment circle")
	var single_axis := PackedVector2Array([Vector2.ZERO, Vector2(4, 0)])
	_check(Geometry.path_for(Geometry.Tool.OVAL, single_axis, false, 0.0).is_empty(), "Degenerate oval returns an empty path")
	var pencil := PackedVector2Array([Vector2.ZERO, Vector2(2, 2), Vector2(4, 0)])
	_check(Geometry.path_for(Geometry.Tool.PENCIL, pencil, false, 0.5)[1] == Vector2(2, 1), "Pencil smoothing preserves the endpoints")
	var spline := Geometry.path_for(Geometry.Tool.SPLINE, pencil, false, 0.0)
	_check(spline.size() == 25 and spline[12].is_equal_approx(pencil[1]) and spline[-1].is_equal_approx(pencil[-1]), "Spline interpolates through clicked points")
	var world := Geometry.sample_path(points, true, func(point: Vector2) -> Vector3: return Vector3(point.x, 3.0, point.y))
	_check(world.size() > 2 and world[-1] == Vector3(4, 3, 1), "Surface projection samples the whole path")
	var projected: Variant = Geometry.plane_point(Vector3(2.3, 3, 1.8), Vector3.DOWN, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 0.5)
	_check(projected == Vector2(2.5, 2), "Ground placement snaps both local axes")
	_check(Geometry.plane_point(Vector3.UP, Vector3.RIGHT, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 0.0) == null, "Parallel rays have no plane hit")

func _test_eraser() -> void:
	var path := PackedVector3Array([Vector3(-10, 0, 1), Vector3(10, 0, 1)])
	var identity := func(point: Vector3) -> Vector3: return point
	var pieces: Variant = Store.clip(path, Vector2.ZERO, 2.0, identity)
	_check(pieces != null and pieces.size() == 2 and pieces[0][-1].is_equal_approx(Vector3(-2, 0, 1)) and pieces[1][0].is_equal_approx(Vector3(2, 0, 1)), "Brush clips just the middle of a segment")
	_check(Store.clip(path, Vector2(0, 2), 2.0, identity) == null, "A tangent does not split a guide")
	pieces = Store.clip(path, Vector2.ZERO, 11.0, identity)
	_check(pieces != null and pieces.is_empty(), "A fully covered stroke is removed")
	var depth_path := PackedVector3Array([Vector3(-10, 0, 1), Vector3(20, 0, 2)])
	var perspective := func(point: Vector3) -> Vector3: return Vector3(point.x / point.z, point.y / point.z, point.z)
	pieces = Store.clip(depth_path, Vector2.ZERO, 2.0, perspective)
	var left: Vector3 = pieces[0][-1]
	var right: Vector3 = pieces[1][0]
	_check(is_equal_approx(left.x / left.z, -2.0) and is_equal_approx(right.x / right.z, 2.0), "World cuts reproject to the brush edge at varying depth")
	var store := Store.new()
	store.add("other_scene", "local", path)
	store.add("current_scene", "teammate", path)
	store.add("current_scene", "local", path)
	_check(store.erase_brush("current_scene", "local", Vector2.ZERO, 2.0, identity) and store.guides.size() == 4, "Brush only clips the current scene and owner")
	store.erase_all("current_scene", "local")
	_check(store.guides.size() == 2, "Erase all preserves teammates and other scenes")

func _test_viewport() -> void:
	var guides := Guides.new(_settings)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 400)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 10)
	camera.current = true
	var surface := StaticBody3D.new()
	surface.position = Vector3(0, 0, 3)
	surface.collision_layer = 4
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 6, 0.2)
	collision.shape = shape
	surface.add_child(collision)
	viewport.add_child(surface)
	await physics_frame
	await process_frame
	guides.set_scene("preview")
	guides.expanded = true
	guides.set_tool(Geometry.Tool.OVAL)
	_check(guides.input(camera, _mouse(Vector2(260, 180), MOUSE_BUTTON_LEFT, true)), "Viewport captures an oval drag")
	guides.input(camera, _motion(Vector2(340, 240)))
	_check(guides.input(camera, _mouse(Vector2(340, 240), MOUSE_BUTTON_RIGHT, true)), "Right-click consumes and cancels the drag")
	_check(guides.input(camera, _mouse(Vector2(340, 240), MOUSE_BUTTON_RIGHT, false)), "Right-click cancellation consumes release as well")
	_check(not guides.input(camera, _mouse(Vector2(340, 240), MOUSE_BUTTON_RIGHT, true)), "Right-click without a placement stays available to the editor")
	guides.input(camera, _mouse(Vector2(340, 240), MOUSE_BUTTON_LEFT, false))
	_check(guides.store.guides.is_empty(), "Cancelled oval never commits")
	guides.set_tool(Geometry.Tool.SPLINE)
	guides.input(camera, _mouse(Vector2(260, 180), MOUSE_BUTTON_LEFT, true))
	guides.input(camera, _mouse(Vector2(340, 240), MOUSE_BUTTON_LEFT, true))
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_check(guides.input(camera, enter) and guides.store.guides.size() == 1, "Enter commits the spline")
	var path: PackedVector3Array = guides.store.guides[0].path if not guides.store.guides.is_empty() else PackedVector3Array()
	_check(path.size() >= 2 and is_equal_approx(path[0].z, 3.1) and is_equal_approx(path[-1].z, 3.1), "Drawn spline projects in world space onto a physics layer")
	guides.set_tool(Geometry.Tool.ERASE_BRUSH)
	_check(guides.input(camera, _mouse(Vector2(300, 200), MOUSE_BUTTON_WHEEL_UP, true)) and guides.radius == 23.0, "Wheel increases brush radius and consumes zoom")
	var projected := camera.unproject_position(Vector3(0, 0, 3.1))
	var teammate := guides.store.add("preview", "teammate", path)
	var navigating := _mouse(projected, MOUSE_BUTTON_WHEEL_UP, true)
	navigating.button_mask = MOUSE_BUTTON_MASK_RIGHT
	_check(not guides.input(camera, navigating) and guides.radius == 23.0, "Wheel stays available to the editor during right-button navigation")
	guides.input(camera, _mouse(projected, MOUSE_BUTTON_LEFT, true))
	guides.input(camera, _mouse(projected, MOUSE_BUTTON_LEFT, false))
	_check(guides.store.guides.size() == 3, "Drawing input splits only the local guide")
	_check(is_same(guides.store.guides[-1], teammate) and teammate.path == path, "Brush input preserves an overlapping teammate guide")
	guides.set_scene("rotated")
	camera.rotation_degrees = Vector3(-17, 32, 38)
	var view := camera.get_camera_transform()
	var a := view * Vector3(-4, 0, -6)
	var b := view * Vector3(4, 0, -6)
	guides.store.add("rotated", "local", PackedVector3Array([a, b]))
	projected = camera.unproject_position(a.lerp(b, 0.5))
	guides.input(camera, _mouse(projected, MOUSE_BUTTON_LEFT, true))
	guides.input(camera, _mouse(projected, MOUSE_BUTTON_LEFT, false))
	var left_piece: PackedVector3Array = guides.store.guides[-2].path
	var right_piece: PackedVector3Array = guides.store.guides[-1].path
	_check(left_piece[0].is_equal_approx(a) and right_piece[-1].is_equal_approx(b), "Orbit and roll preserve the original world-space endpoints")
	_check(is_equal_approx(camera.unproject_position(left_piece[-1]).distance_to(projected), guides.radius) and is_equal_approx(camera.unproject_position(right_piece[0]).distance_to(projected), guides.radius), "Rotated camera cuts at the visible brush edge")
	var behind := view * Vector3(-0.005, 0, 1)
	var in_front := view * Vector3(0.005, 0, -5)
	var visible := Guides._near_span(behind, in_front, view, camera.near)
	_check(visible.x > 0.0 and visible.x < 1.0 and visible.y == 1.0, "A guide crossing the camera near plane keeps its visible segment")
	var near_pieces: Variant = Store.clip(PackedVector3Array([behind, in_front]), camera.unproject_position(in_front), 20.0, Guides._project.bind(camera, view), Guides._near_span.bind(view, camera.near))
	_check(near_pieces != null and near_pieces.size() >= 1 and near_pieces[0][0].is_equal_approx(behind), "Erasing a near-plane crossing preserves the hidden end")
	guides.set_tool(Geometry.Tool.SELECT)
	_check(not guides.input(camera, _mouse(Vector2(10, 10), MOUSE_BUTTON_LEFT, true)), "Select passes clicks that miss all guides")
	viewport.free()

func _test_panel() -> void:
	var profile := Profile.new(_scratch)
	var external := Profile.new(_scratch)
	var panel := InspectorPanel.new()
	root.add_child(panel)
	var guides := Guides.new(_settings)
	panel.setup(profile, _settings, guides)
	_check(panel._pages.size() == 6 and panel._pages[5].visible, "Six reference tabs with Misc selected by default")
	var drawing_button: Button
	for child in panel.find_children("*", "Button", true, false):
		if child.text == "Open Drawing Tools":
			drawing_button = child
			break
	_check(drawing_button != null and drawing_button.disabled, "Inspector shows an unavailable drawing shortcut without a saved scene")
	if drawing_button != null:
		guides.set_scene("preview")
		_check(not drawing_button.disabled, "Inspector enables the drawing shortcut for a saved scene")
		drawing_button.pressed.emit()
		_check(guides.expanded and drawing_button.text == "Close Drawing Tools", "Inspector opens the same drawing tools as the viewport")
		guides.set_tools_open(false)
		_check(drawing_button.text == "Open Drawing Tools", "Inspector updates when the viewport closes the tools")
	panel._select_tab(0)
	await process_frame
	panel._name_field.grab_focus()
	panel._name_field.text = "Draft"
	panel._name_field.text_changed.emit("Draft")
	external.save_name("From Unity")
	external.save_color("Red")
	profile.refresh()
	panel.refresh_profile()
	_check(panel._name_field.text == "Draft" and panel._swatches["Red"].button_pressed and not panel._swatches["Navy"].button_pressed, "Active edit survives external name updates while the swatch refreshes")
	panel._name_field.text_submitted.emit("Draft")
	_check(external.refresh() and external.display_name == "Draft", "Committing an edit publishes it to the shared profile")
	panel._name_field.release_focus()
	external.save_name("From Unreal")
	profile.refresh()
	panel.refresh_profile()
	_check(panel._name_field.text == "From Unreal", "InspectorPanel resumes external name refresh after the field loses focus")
	panel.free()

static func _mouse(position: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	return event

static func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event
