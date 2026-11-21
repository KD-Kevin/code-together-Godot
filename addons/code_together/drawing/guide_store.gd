@tool
extends RefCounted

var guides: Array[Dictionary] = []

func add(scene: String, owner: String, path: PackedVector3Array) -> Dictionary:
	var guide := {"scene": scene, "owner": owner, "path": path}
	guides.append(guide)
	return guide

func delete(scene: String, owner: String, guide: Dictionary) -> bool:
	if guide.get("scene") != scene or guide.get("owner") != owner:
		return false
	for i in guides.size():
		if is_same(guides[i], guide):
			guides.remove_at(i)
			return true
	return false

func erase_all(scene: String, owner: String) -> void:
	for i in range(guides.size() - 1, -1, -1):
		if guides[i].scene == scene and guides[i].owner == owner:
			guides.remove_at(i)

func erase_brush(scene: String, owner: String, center: Vector2, radius: float, project: Callable, visible_span: Callable = Callable()) -> bool:
	var changed := false
	for i in range(guides.size() - 1, -1, -1):
		var guide := guides[i]
		if guide.scene != scene or guide.owner != owner:
			continue
		var pieces: Variant = clip(guide.path, center, radius, project, visible_span)
		if pieces == null:
			continue
		changed = true
		guides.remove_at(i)
		for j in pieces.size():
			guides.insert(i + j, {"scene": scene, "owner": owner, "path": pieces[j]})
	return changed

# The projection returns screen pixels and positive camera depth. Orthographic callers use depth 1.
static func clip(path: PackedVector3Array, center: Vector2, radius: float, project: Callable, visible_span: Callable = Callable()) -> Variant:
	if path.size() < 2:
		return null
	var pieces: Array[PackedVector3Array] = []
	var piece := PackedVector3Array()
	var changed := false
	var screen_a: Vector3 = project.call(path[0])
	for i in range(1, path.size()):
		var screen_b: Vector3 = project.call(path[i])
		var a := path[i - 1]
		var b := path[i]
		var visible := Vector2(0, 1)
		var projected_a := screen_a
		var projected_b := screen_b
		if visible_span.is_valid() and (screen_a.z <= 0.0 or screen_b.z <= 0.0):
			visible = visible_span.call(a, b)
			if visible.x < visible.y:
				if visible.x > 0.0:
					projected_a = project.call(a.lerp(b, visible.x))
				if visible.y < 1.0:
					projected_b = project.call(a.lerp(b, visible.y))
		var span := _brush_span(projected_a, projected_b, center, radius)
		if span.x < span.y:
			if not changed:
				piece = path.slice(0, i)
				changed = true
			if span.x > 0.0 or visible.x > 0.0:
				if piece.is_empty():
					piece.append(a)
				piece.append(a.lerp(b, _cut_fraction(visible, projected_a.z, projected_b.z, span.x)))
			if piece.size() >= 2:
				pieces.append(piece)
			piece = PackedVector3Array()
			if span.y < 1.0 or visible.y < 1.0:
				piece.append(a.lerp(b, _cut_fraction(visible, projected_a.z, projected_b.z, span.y)))
				piece.append(b)
		elif changed:
			if piece.is_empty():
				piece.append(path[i - 1])
			piece.append(path[i])
		screen_a = screen_b
	if not changed:
		return null
	if piece.size() >= 2:
		pieces.append(piece)
	return pieces

static func _brush_span(a: Vector3, b: Vector3, center: Vector2, radius: float) -> Vector2:
	if a.z <= 0.0 or b.z <= 0.0:
		return Vector2.ZERO
	var offset := Vector2(a.x, a.y) - center
	var direction := Vector2(b.x - a.x, b.y - a.y)
	var length_squared := direction.length_squared()
	if length_squared < 0.00001:
		return Vector2(0, 1) if offset.length_squared() < radius * radius else Vector2.ZERO
	var closest := -offset.dot(direction) / length_squared
	var remaining := radius * radius - (offset + closest * direction).length_squared()
	if remaining <= 0.0:
		return Vector2.ZERO
	var half := sqrt(remaining / length_squared)
	return Vector2(clampf(closest - half, 0.0, 1.0), clampf(closest + half, 0.0, 1.0))

static func _cut_fraction(visible: Vector2, depth_a: float, depth_b: float, fraction: float) -> float:
	var local := fraction * depth_a / lerpf(depth_b, depth_a, fraction)
	return lerpf(visible.x, visible.y, local)
