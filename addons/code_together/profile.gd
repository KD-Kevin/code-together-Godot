@tool
extends RefCounted

const DEFAULT_NAME := ""
const DEFAULT_COLOR := "Light Purple"
const DISPLAY_NAME_FILE := "DisplayName.txt"
const COLOR_FILE := "FavoriteColor.txt"

# Same order, names and sRGB values as the Unity and Unreal adapters.
const PALETTE := {
	"Navy": Color("#1f3369"), "Royal Blue": Color("#4169e1"), "Teal": Color("#008080"), "Sky Blue": Color("#6ab4ff"), "Cyan": Color("#00dcf4"),
	"Maroon": Color("#691831"), "Crimson Red": Color("#aa1840"), "Red": Color("#ee3134"), "Pink": Color("#ff6bb4"), "Rose": Color("#ef7f97"),
	"Forest Green": Color("#228b22"), "Emerald": Color("#19b16c"), "Turquoise": Color("#30c9b1"), "Mint": Color("#8ff0c0"), "Neon Green": Color("#39ff14"),
	"Gold": Color("#c59610"), "Amber": Color("#eea323"), "Lime": Color("#b1d92b"), "Yellow": Color("#ffe635"), "Lemon": Color("#fffc9d"),
	"Royal Purple": Color("#7851a9"), "Violet": Color("#8548ef"), "Magenta": Color("#da30b1"), "Light Purple": Color("#ad80f5"), "Lavender": Color("#d8bdfc"),
	"Brown": Color("#734129"), "Tan": Color("#c49063"), "Coral": Color("#ff7e6c"), "Orange": Color("#ff841a"), "Peach": Color("#ffb383"),
	"Black": Color("#000000"), "Dark Gray": Color("#404040"), "Gray": Color("#808080"), "Light Gray": Color("#c0c0c0"), "White": Color("#ffffff"),
}

var directory: String
var display_name := DEFAULT_NAME
var favorite_color := DEFAULT_COLOR

func _init(profile_directory: String = "") -> void:
	directory = profile_directory if not profile_directory.is_empty() else profile_path()
	refresh()

static func profile_path() -> String:
	var base := OS.get_environment("LOCALAPPDATA") if OS.get_name() == "Windows" else ""
	if base.is_empty():
		base = OS.get_config_dir()
	return base.path_join("BlueTeamGames/CodeTogether/Profile")

static func normalize_name(value: String) -> String:
	var normalized := value.strip_edges()
	# Unity and Unreal count UTF-16 code units on Windows.
	if normalized.to_utf16_buffer().size() > 128 or normalized.contains("\n") or normalized.contains("\r"):
		return ""
	return normalized

func refresh() -> bool:
	var name := normalize_name(_read(DISPLAY_NAME_FILE))
	var color := _read(COLOR_FILE)
	if name.is_empty():
		name = DEFAULT_NAME
	if not PALETTE.has(color):
		color = DEFAULT_COLOR
	var changed := name != display_name or color != favorite_color
	display_name = name
	favorite_color = color
	return changed

func save_name(value: String) -> bool:
	var normalized := normalize_name(value)
	if normalized.is_empty() or not _write(DISPLAY_NAME_FILE, normalized):
		return false
	display_name = normalized
	return true

func save_color(value: String) -> bool:
	if not PALETTE.has(value) or not _write(COLOR_FILE, value):
		return false
	favorite_color = value
	return true

func _read(file_name: String) -> String:
	var file := FileAccess.open(directory.path_join(file_name), FileAccess.READ)
	return file.get_as_text() if file != null else ""

func _write(file_name: String, value: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var target := directory.path_join(file_name)
	var temporary := target + "." + Crypto.new().generate_random_bytes(16).hex_encode() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var written := file.store_string(value)
	file.close()
	# Publish a complete UTF-8 field so another editor never sees a truncated value.
	if written and DirAccess.rename_absolute(temporary, target) == OK:
		return true
	DirAccess.remove_absolute(temporary)
	return false
