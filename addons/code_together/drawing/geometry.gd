@tool
extends RefCounted

enum Tool { SELECT, LINE, PENCIL, SPLINE, OVAL, RECTANGLE, ERASE_BRUSH }
enum Placement { GROUND, SCENE, CAMERA }

static func plane_point(ray_origin: Vector3, direction: Vector3, origin: Vector3, right: Vector3, up: Vector3, snap: float) -> Variant:
	var normal := right.cross(up)
	var alignment := normal.dot(direction)
	if absf(alignment) < 0.00001:
		return null
	var distance := (origin - ray_origin).dot(normal) / alignment
	if distance < 0.0:
		return null
	var offset := ray_origin + direction * distance - origin
	var point := Vector2(offset.dot(right), offset.dot(up))
	return point.snapped(Vector2(snap, snap)) if snap > 0.0 else point

static func path_for(tool: Tool, points: PackedVector2Array, constrain: bool, smoothing: float) -> PackedVector2Array:
	var path := PackedVector2Array()
	if points.size() < 2:
		return path
	var first := points[0]
	var last := points[-1]
	match tool:
		Tool.LINE:
			path = PackedVector2Array([first, last])
		Tool.PENCIL:
			path.append(first)
			for i in range(1, points.size() - 1):
				path.append(points[i].lerp((points[i - 1] + points[i + 1]) * 0.5, smoothing))
			path.append(last)
		Tool.SPLINE:
			path.append(first)
			for i in points.size() - 1:
				var a := points[maxi(0, i - 1)]
				var b := points[i]
				var c := points[i + 1]
				var d := points[mini(i + 2, points.size() - 1)]
				for j in range(1, 13):
					var t := j / 12.0
					path.append(0.5 * (2.0 * b + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t))
		Tool.OVAL, Tool.RECTANGLE:
			var delta := last - first
			if constrain:
				var side := maxf(absf(delta.x), absf(delta.y))
				delta = Vector2(-side if delta.x < 0.0 else side, -side if delta.y < 0.0 else side)
				last = first + delta
			if is_zero_approx(delta.x) or is_zero_approx(delta.y):
				return path
			if tool == Tool.RECTANGLE:
				path = PackedVector2Array([first, Vector2(last.x, first.y), last, Vector2(first.x, last.y)])
			else:
				var center := (first + last) * 0.5
				var radii := delta * 0.5
				for i in 48:
					path.append(center + Vector2.from_angle(TAU * i / 48.0) * radii)
			path.append(path[0])
	return path

static func sample_path(path: PackedVector2Array, follow: bool, project: Callable) -> PackedVector3Array:
	var world := PackedVector3Array()
	if path.is_empty():
		return world
	world.append(project.call(path[0]))
	for i in range(1, path.size()):
		var steps := clampi(ceili(path[i - 1].distance_to(path[i]) / 0.25), 1, 128) if follow else 1
		for j in range(1, steps + 1):
			var point: Vector3 = project.call(path[i - 1].lerp(path[i], float(j) / steps))
			if not point.is_equal_approx(world[-1]):
				world.append(point)
	return world
