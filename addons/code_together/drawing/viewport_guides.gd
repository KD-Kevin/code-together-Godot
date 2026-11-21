@tool
extends RefCounted

const Geometry = preload("geometry.gd")
const Store = preload("guide_store.gd")
const Settings = preload("../settings.gd")
const LOCAL_OWNER := "local"
const TOOL_NAMES := ["Select", "Line", "Pencil", "Spline", "Oval", "Rectangle", "Erase Brush"]

signal changed
signal redraw_requested
signal height_sampled
signal notice(message: String)

var settings: Settings
var store := Store.new()
var tool := Geometry.Tool.SELECT
var expanded := false
var sampling := false
var scene := ""
var selected: Dictionary = {}
var color := Color("#ad80f5")
var radius := 20.0

var _camera: Camera3D
var _right_click_cancel_camera: Camera3D
var _origin: Vector3
var _right: Vector3
var _up: Vector3
var _snap: float
var _follow: bool
var _mask: int
var _smoothing: float
var _min_segment: float
var _anchor_view := Transform3D.IDENTITY
var _projection_mode: int
var _near: float
var _far: float
var _points := PackedVector2Array()
var _preview := PackedVector3Array()
var _erasing := false
var _previous_erase := Vector2.ZERO

func _init(adapter_settings: Settings) -> void:
	settings = adapter_settings

func set_scene(id: String) -> void:
	if scene == id:
		return
	scene = id
	sampling = false
	selected = {}
	cancel()

func set_tool(next: int) -> void:
	tool = next as Geometry.Tool
	sampling = false
	cancel()

func set_tools_open(open: bool) -> void:
	if expanded == open or (open and scene.is_empty()):
		return
	expanded = open
	set_tool(Geometry.Tool.SELECT)

func begin_height_sample() -> void:
	if scene.is_empty():
		return
	cancel()
	sampling = true
	notice.emit("Click a surface in the 3D viewport to sample its height.")

func delete_selected() -> void:
	store.delete(scene, LOCAL_OWNER, selected)
	selected = {}
	changed.emit()

func erase_all() -> void:
	store.erase_all(scene, LOCAL_OWNER)
	selected = {}
	changed.emit()

func cancel() -> void:
	_camera = null
	_points.clear()
	_preview = PackedVector3Array()
	_erasing = false
	changed.emit()

func input(camera: Camera3D, event: InputEvent) -> bool:
	if scene.is_empty():
		return false
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return false
		if event.keycode == KEY_ESCAPE and (sampling or _camera != null):
			sampling = false
			cancel()
			return true
		if tool == Geometry.Tool.SPLINE and camera == _camera and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_finish(false)
			return true
		return false
	if not event is InputEventMouse:
		return false
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_RIGHT:
		var consumes_release := not button.pressed and camera == _right_click_cancel_camera
		_right_click_cancel_camera = null
		if consumes_release:
			return true
		if button.pressed and (sampling or camera == _camera):
			# A cancelled placement owns both halves of the right click.
			_right_click_cancel_camera = camera
			sampling = false
			cancel()
			return true
	if not expanded and not sampling:
		return false
	if event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
		if camera == _camera and button != null and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			cancel()
		return false
	if is_brush_active() and not _erasing:
		redraw_requested.emit()
	if camera != _camera and is_instance_valid(_camera):
		return false
	if button != null:
		return _mouse_button(camera, button)
	if event is InputEventMouseMotion and _camera == camera:
		if _erasing:
			_erase_to(event.position)
		else:
			_update_stroke(event.position, event.shift_pressed)
		return tool != Geometry.Tool.SPLINE
	return false

func _mouse_button(camera: Camera3D, event: InputEventMouseButton) -> bool:
	if tool == Geometry.Tool.ERASE_BRUSH and not sampling and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		radius = clampf(radius + direction * 3.0 * maxf(event.factor, 1.0), 5.0, 160.0)
		redraw_requested.emit()
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not event.pressed:
		if camera != _camera or tool == Geometry.Tool.SPLINE:
			return false
		if _erasing:
			_erase_to(event.position)
			cancel()
		elif _update_stroke(event.position, event.shift_pressed):
			_finish(event.shift_pressed)
		else:
			cancel()
		return true
	if sampling:
		var origin := camera.project_ray_origin(event.position)
		var direction := camera.project_ray_normal(event.position)
		var hit := _raycast(camera, origin, direction, camera.far, int(settings.value("mask")))
		if hit.is_empty():
			notice.emit("No matching surface on the height layers.")
		else:
			sampling = false
			settings.set_value("height", hit.position.y)
			height_sampled.emit()
			notice.emit("Drawing height: %.2f m" % hit.position.y)
		return true
	if tool == Geometry.Tool.SELECT:
		selected = _find_guide(camera, event.position)
		changed.emit()
		return not selected.is_empty()
	if tool == Geometry.Tool.ERASE_BRUSH:
		_camera = camera
		_erasing = true
		_previous_erase = event.position
		_erase_to(event.position)
		return true
	if _points.is_empty():
		_capture_frame(camera)
	var projected: Variant = _plane_point(camera, event.position)
	if projected == null:
		return true
	var point: Vector2 = projected
	_camera = camera
	if tool == Geometry.Tool.SPLINE:
		if event.double_click and _points.size() >= 2:
			_finish(false)
		elif _points.is_empty() or not _points[-1].is_equal_approx(point):
			_points.append(point)
			_show_preview(_points, false)
	else:
		_points.append(point)
	return true

func _capture_frame(camera: Camera3D) -> void:
	var plane: int = settings.value("plane")
	var height: float = settings.value("height")
	_anchor_view = camera.get_camera_transform()
	_projection_mode = camera.projection
	_near = camera.near
	_far = camera.far
	_right = Vector3.RIGHT
	_up = Vector3.BACK if plane == Geometry.Placement.GROUND else Vector3.UP
	_origin = Vector3(0, height, 0) if plane == Geometry.Placement.GROUND else Vector3(0, 0, height)
	if plane == Geometry.Placement.CAMERA:
		var forward := -_anchor_view.basis.z
		var pivot_depth := maxf(_near + 0.1, -_anchor_view.origin.dot(forward))
		if pivot_depth <= _near + 0.1:
			pivot_depth = 4.0
		var hit := _raycast(camera, _anchor_view.origin, forward, _far, int(settings.value("mask")))
		if not hit.is_empty():
			pivot_depth = maxf(_near + 0.1, (hit.position - _anchor_view.origin).dot(forward))
		_origin = _anchor_view.origin + forward * pivot_depth
		_right = _anchor_view.basis.x
		_up = _anchor_view.basis.y
	_follow = settings.value("follow")
	_mask = settings.value("mask")
	_snap = 0.0 if tool == Geometry.Tool.PENCIL and not settings.value("pencil_snap") else settings.value("snap")
	_smoothing = settings.value("smoothing")
	_min_segment = settings.value("min_segment")

func _plane_point(camera: Camera3D, pixel: Vector2) -> Variant:
	return Geometry.plane_point(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel), _origin, _right, _up, _snap)

func _update_stroke(pixel: Vector2, constrained: bool) -> bool:
	var projected: Variant = _plane_point(_camera, pixel)
	if projected == null:
		return false
	var point: Vector2 = projected
	if tool == Geometry.Tool.PENCIL:
		if _points[-1].distance_squared_to(point) > _min_segment * _min_segment:
			_points.append(point)
		_show_preview(_points, false)
	else:
		var points := _points.duplicate() if tool == Geometry.Tool.SPLINE else PackedVector2Array([_points[0]])
		points.append(point)
		_show_preview(points, constrained)
		if tool != Geometry.Tool.SPLINE:
			_points = points
	return true

func _show_preview(points: PackedVector2Array, constrained: bool) -> void:
	var path := Geometry.path_for(tool, points, constrained, _smoothing)
	_preview = Geometry.sample_path(path, _follow, _project_sample)
	redraw_requested.emit()

func _project_sample(point: Vector2) -> Vector3:
	var fallback := _origin + _right * point.x + _up * point.y
	if not _follow:
		return fallback
	var forward := -_anchor_view.basis.z
	var offset := fallback - _anchor_view.origin
	var depth := offset.dot(forward)
	if depth <= 0.0:
		return fallback
	var direction := forward if _projection_mode == Camera3D.PROJECTION_ORTHOGONAL else offset.normalized()
	var alignment := direction.dot(forward)
	if alignment < 0.00001:
		return fallback
	var ray_origin := fallback - direction * ((depth - _near) / alignment)
	var hit := _raycast(_camera, ray_origin, direction, (_far - _near) / alignment, _mask)
	return fallback if hit.is_empty() else hit.position

static func _raycast(camera: Camera3D, origin: Vector3, direction: Vector3, distance: float, mask: int) -> Dictionary:
	if mask == 0:
		return {}
	var space := camera.get_world_3d().direct_space_state
	if space == null:
		return {}
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, mask))

func _finish(constrained: bool) -> void:
	_show_preview(_points, constrained)
	if _preview.size() >= 2:
		selected = store.add(scene, LOCAL_OWNER, _preview)
		# Cancel drops the preview reference without modifying the committed path.
	cancel()

func _erase_to(pixel: Vector2) -> void:
	var steps := maxi(1, ceili(_previous_erase.distance_to(pixel) / (radius * 0.5)))
	var view := _camera.get_camera_transform()
	var project := _project.bind(_camera, view)
	var clip := _near_span.bind(view, _camera.near)
	var erased := false
	for i in range(1, steps + 1):
		if store.erase_brush(scene, LOCAL_OWNER, _previous_erase.lerp(pixel, float(i) / steps), radius, project, clip):
			erased = true
	_previous_erase = pixel
	if erased:
		selected = {}
		changed.emit()
	else:
		redraw_requested.emit()

static func _depth(point: Vector3, view: Transform3D) -> float:
	return (view.origin - point).dot(view.basis.z)

static func _near_span(a: Vector3, b: Vector3, view: Transform3D, near: float) -> Vector2:
	var depth_a := _depth(a, view)
	var depth_b := _depth(b, view)
	if depth_a >= near and depth_b >= near:
		return Vector2(0, 1)
	if depth_a < near and depth_b < near:
		return Vector2.ZERO
	# Leave a small margin so the projected boundary survives float rounding.
	var margin := minf(0.0001, (maxf(depth_a, depth_b) - near) * 0.5)
	var cut := (near + margin - depth_a) / (depth_b - depth_a)
	return Vector2(cut, 1) if depth_a < near else Vector2(0, cut)

static func _project(point: Vector3, camera: Camera3D, view: Transform3D) -> Vector3:
	var depth := _depth(point, view)
	if depth < camera.near:
		return Vector3.ZERO
	var pixel := camera.unproject_position(point)
	return Vector3(pixel.x, pixel.y, 1.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else depth)

func _find_guide(camera: Camera3D, pixel: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var best := 9.0
	var view := camera.get_camera_transform()
	for guide in store.guides:
		if guide.scene != scene:
			continue
		var path: PackedVector3Array = guide.path
		for i in range(1, path.size()):
			var span := _near_span(path[i - 1], path[i], view, camera.near)
			if span.x < span.y:
				var a := camera.unproject_position(path[i - 1].lerp(path[i], span.x))
				var b := camera.unproject_position(path[i - 1].lerp(path[i], span.y))
				var point := Geometry2D.get_closest_point_to_segment(pixel, a, b)
				var distance := pixel.distance_to(point)
				if distance < best:
					best = distance
					nearest = guide
	return nearest

func is_brush_active() -> bool:
	return expanded and tool == Geometry.Tool.ERASE_BRUSH and not sampling and not (
		Input.is_key_pressed(KEY_ALT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE))

func has_overlay_content() -> bool:
	return not store.guides.is_empty() or not _preview.is_empty() or is_brush_active()

func draw(overlay: Control, camera: Camera3D) -> void:
	if scene.is_empty() or not is_instance_valid(camera):
		return
	var view_size := camera.get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	var scale := overlay.size / view_size
	var width: float = settings.value("width")
	var view := camera.get_camera_transform()
	for guide in store.guides:
		if guide.scene == scene:
			_draw_path(overlay, camera, view, guide.path, scale, width + 1.0 if is_same(selected, guide) else width)
	if camera == _camera and _preview.size() >= 2:
		_draw_path(overlay, camera, view, _preview, scale, width)
	if is_brush_active():
		var mouse := overlay.get_local_mouse_position()
		if Rect2(Vector2.ZERO, overlay.size).has_point(mouse):
			var ring := PackedVector2Array()
			for i in 49:
				ring.append(mouse + Vector2.from_angle(TAU * i / 48.0) * radius * scale)
			overlay.draw_polyline(ring, Color.BLACK, 3.0, true)
			overlay.draw_polyline(ring, Color.WHITE, 1.5, true)

func _draw_path(overlay: Control, camera: Camera3D, view: Transform3D, path: PackedVector3Array, scale: Vector2, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(1, path.size()):
		var start := path[i - 1]
		var end := path[i]
		var visible := _near_span(start, end, view, camera.near)
		if visible.x < visible.y:
			if points.is_empty():
				points.append(camera.unproject_position(start.lerp(end, visible.x)) * scale)
			points.append(camera.unproject_position(start.lerp(end, visible.y)) * scale)
		if visible.y < 1.0:
			if points.size() >= 2:
				overlay.draw_polyline(points, color, width, true)
			points.clear()
	if points.size() >= 2:
		overlay.draw_polyline(points, color, width, true)
