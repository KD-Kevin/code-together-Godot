@tool
extends RefCounted

const DEFAULTS := {
	"plane": 2, "height": 0.0, "follow": true, "mask": 0xffffffff,
	"snap": 0.5, "width": 2.0, "min_segment": 0.05, "smoothing": 0.2, "pencil_snap": false,
	"address": "", "port": 8080, "chat_viewport": false, "chat_tabs": false,
}

var _config := ConfigFile.new()
var _path: String

func _init(path: String) -> void:
	_path = path
	_config.load(_path)

func value(key: String) -> Variant:
	var stored: Variant = _config.get_value("adapter", key, DEFAULTS[key])
	return stored if typeof(stored) == typeof(DEFAULTS[key]) else DEFAULTS[key]

func set_value(key: String, new_value: Variant) -> Error:
	var values := {}
	values[key] = new_value
	return _save(values)

static func normalized_address(raw: String) -> String:
	var address := raw.strip_edges()
	if address.begins_with("[") and address.ends_with("]"):
		address = address.substr(1, address.length() - 2)
		return address if address.contains(":") and address.is_valid_ip_address() and not address.contains("%") else ""
	if not address.contains("%") and address.is_valid_ip_address():
		return address
	var hostname := address.trim_suffix(".")
	if hostname.length() > 253:
		return ""
	var labels := hostname.split(".")
	for i in labels.size():
		var label := labels[i]
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return ""
		for j in label.length():
			var code := label.unicode_at(j)
			if not (code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122 or code == 45):
				return ""
	return address

func save_endpoint(raw: String, port_text: String) -> String:
	var address := normalized_address(raw)
	if address.is_empty():
		return "Enter a hostname or IP address. Use the Port field for the port."
	if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
		return "Enter a port from 1 to 65535."
	return "" if _save({"address": address, "port": int(port_text)}) == OK else "Could not save the join address."

func _save(values: Dictionary) -> Error:
	var latest := ConfigFile.new()
	latest.load(_path)
	for key in values:
		latest.set_value("adapter", key, values[key])
	var result := DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if result != OK:
		return result
	var temporary := _path + "." + Crypto.new().generate_random_bytes(16).hex_encode() + ".tmp"
	result = latest.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, _path)
	if result == OK:
		_config = latest
	else:
		DirAccess.remove_absolute(temporary)
	return result