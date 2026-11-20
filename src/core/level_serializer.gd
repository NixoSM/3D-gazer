class_name LevelSerializer
extends RefCounted
## Converts between LevelData and the JSON level format (docs/LEVEL_FORMAT.md).
##
## Both directions exist on purpose: the game only reads, but a level editor
## will write, and tests check that a level survives a round trip unchanged.
## Angles are stored in degrees in JSON (friendlier to humans and tools) and
## in radians in memory.
##
## Version history: 1 = holes and palette; 2 adds the optional `spin` keys;
## 3 adds the optional hole `twist` (and holes get rounded, blended edges);
## 4 adds the optional `speed` surge keys and on-screen `hints`.
## Older versions are read as if every new field had its default.

const FORMAT_VERSION := 4
const OLDEST_SUPPORTED_VERSION := 1


class Result:
	var level: LevelData
	var errors: PackedStringArray = []

	func ok() -> bool:
		return level != null and errors.is_empty()


static func load_file(path: String) -> Result:
	var result := Result.new()
	if not FileAccess.file_exists(path):
		result.errors.append("Level file not found: %s" % path)
		return result
	var text := FileAccess.get_file_as_string(path)
	return from_json(text, path)


static func from_json(text: String, source_name: String = "<string>") -> Result:
	var result := Result.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		result.errors.append("%s: invalid JSON at line %d: %s" % [source_name, json.get_error_line(), json.get_error_message()])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("%s: top level must be an object" % source_name)
		return result
	return from_dict(json.data, source_name)


static func from_dict(data: Dictionary, source_name: String = "<dict>") -> Result:
	var result := Result.new()
	var version := int(data.get("format_version", 0))
	if version < OLDEST_SUPPORTED_VERSION or version > FORMAT_VERSION:
		result.errors.append("%s: unsupported format_version %d (expected %d..%d)" % [source_name, version, OLDEST_SUPPORTED_VERSION, FORMAT_VERSION])
		return result

	var level := LevelData.new()
	level.id = str(data.get("id", ""))
	level.display_name = str(data.get("name", level.id))
	level.length = float(data.get("length", level.length))
	level.tunnel_radius = float(data.get("tunnel_radius", level.tunnel_radius))
	level.base_speed = float(data.get("base_speed", level.base_speed))
	level.speed_ramp = float(data.get("speed_ramp", level.speed_ramp))

	for entry in data.get("palette", []):
		level.palette.append(PaletteStop.new(
			float(entry.get("at", 0.0)),
			Color.from_string(str(entry.get("wall", "#ffffff")), Color.WHITE),
			Color.from_string(str(entry.get("void", "#000000")), Color.BLACK),
			Color.from_string(str(entry.get("accent", "#ffffff")), Color.WHITE)))

	for entry in data.get("holes", []):
		level.holes.append(HoleData.new(
			float(entry.get("s", 0.0)),
			float(entry.get("length", 1.0)),
			deg_to_rad(float(entry.get("angle", 0.0))),
			deg_to_rad(float(entry.get("width", 45.0))),
			deg_to_rad(float(entry.get("twist", 0.0)))))

	for entry in data.get("spin", []):
		level.spin.append(SpinKey.new(float(entry.get("s", 0.0)), float(entry.get("rate", 0.0))))

	for entry in data.get("speed", []):
		level.speed_keys.append(SpeedKey.new(float(entry.get("s", 0.0)), float(entry.get("factor", 1.0))))

	for entry in data.get("hints", []):
		level.hints.append(LevelHint.new(float(entry.get("s", 0.0)), str(entry.get("text", ""))))

	level.sort()
	result.errors.append_array(validate(level, source_name))
	result.level = level
	return result


static func to_dict(level: LevelData) -> Dictionary:
	var palette := []
	for stop in level.palette:
		palette.append({
			"at": snappedf(stop.at, 0.0001),
			"wall": "#" + stop.wall.to_html(false),
			"void": "#" + stop.void_color.to_html(false),
			"accent": "#" + stop.accent.to_html(false),
		})
	var holes := []
	for hole in level.holes:
		var entry := {
			"s": snappedf(hole.s_start, 0.01),
			"length": snappedf(hole.length, 0.01),
			"angle": snappedf(rad_to_deg(hole.angle_center), 0.1),
			"width": snappedf(rad_to_deg(hole.angle_width), 0.1),
		}
		if hole.twist != 0.0:
			entry["twist"] = snappedf(rad_to_deg(hole.twist), 0.01)
		holes.append(entry)
	var spin := []
	for key in level.spin:
		spin.append({"s": snappedf(key.s, 0.01), "rate": snappedf(key.rate, 0.1)})
	var result := {
		"format_version": FORMAT_VERSION,
		"id": level.id,
		"name": level.display_name,
		"length": level.length,
		"tunnel_radius": level.tunnel_radius,
		"base_speed": level.base_speed,
		"speed_ramp": level.speed_ramp,
		"palette": palette,
		"spin": spin,
	}
	# Optional sections are only written when used, so plain levels stay plain.
	if not level.speed_keys.is_empty():
		var speed := []
		for key in level.speed_keys:
			speed.append({"s": snappedf(key.s, 0.01), "factor": snappedf(key.factor, 0.001)})
		result["speed"] = speed
	if not level.hints.is_empty():
		var hints := []
		for hint in level.hints:
			hints.append({"s": snappedf(hint.s, 0.01), "text": hint.text})
		result["hints"] = hints
	result["holes"] = holes
	return result


static func to_json(level: LevelData) -> String:
	return JSON.stringify(to_dict(level), "  ", false)


static func save_file(level: LevelData, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json(level) + "\n")
	return OK


## Structural checks. Playability checks live in LevelValidator.
static func validate(level: LevelData, source_name: String = "<level>") -> PackedStringArray:
	var errors := PackedStringArray()
	if level.id.is_empty():
		errors.append("%s: missing id" % source_name)
	if level.length <= 0.0:
		errors.append("%s: length must be > 0" % source_name)
	if level.tunnel_radius <= 0.5:
		errors.append("%s: tunnel_radius must be > 0.5" % source_name)
	if level.base_speed <= 0.0:
		errors.append("%s: base_speed must be > 0" % source_name)
	if level.speed_ramp < 0.0:
		errors.append("%s: speed_ramp must be >= 0" % source_name)
	if level.palette.size() < 2:
		errors.append("%s: palette needs at least 2 stops" % source_name)
	for i in level.holes.size():
		var hole := level.holes[i]
		if hole.length <= 0.0:
			errors.append("%s: hole %d has non-positive length" % [source_name, i])
		if hole.angle_width <= 0.0 or hole.angle_width > TAU:
			errors.append("%s: hole %d width must be in (0, 360] degrees" % [source_name, i])
		if hole.s_start < 0.0 or hole.s_end() > level.length:
			errors.append("%s: hole %d lies outside the tunnel" % [source_name, i])
		if absf(rad_to_deg(hole.twist)) > 30.0:
			errors.append("%s: hole %d twist must be within ±30 °/m" % [source_name, i])
	for i in level.spin.size():
		var key := level.spin[i]
		if key.s < 0.0 or key.s > level.length:
			errors.append("%s: spin key %d lies outside the tunnel" % [source_name, i])
		if absf(key.rate) > 180.0:
			errors.append("%s: spin key %d rate must be within ±180 °/s" % [source_name, i])
	for i in level.speed_keys.size():
		var key := level.speed_keys[i]
		if key.s < 0.0 or key.s > level.length:
			errors.append("%s: speed key %d lies outside the tunnel" % [source_name, i])
		if key.factor < 0.25 or key.factor > 4.0:
			errors.append("%s: speed key %d factor must be within 0.25..4" % [source_name, i])
	for i in level.hints.size():
		if level.hints[i].text.strip_edges().is_empty():
			errors.append("%s: hint %d has no text" % [source_name, i])
	return errors
