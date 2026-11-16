class_name LevelDocument
extends RefCounted
## The level being edited: the LevelData itself, where it is saved, whether
## it has unsaved changes, and undo/redo.
##
## Undo works on whole-level snapshots (the JSON dictionary). Levels are a
## few hundred holes at most, so a snapshot is cheap, and it can never get
## out of step with the level the way a list of hand-written inverse
## operations can. Every edit goes:
##
##     document.begin("Move holes")   # snapshot before
##     ...change document.level...
##     document.changed_from(s)       # as often as needed (e.g. while dragging)
##
## and the next begin() (or undo()) closes it.

## The level changed. `from_s` is the smallest distance the change can
## affect (0 for level-wide settings): analysis restarts from there.
signal changed(from_s: float)
## Saved, loaded or renamed: the title bar needs updating.
signal file_state_changed

const MAX_UNDO := 200

var level: LevelData
## Absolute path of the file, or "" if never saved.
var path := ""
var dirty := false

var _undo: Array[Dictionary] = []
var _undo_labels: PackedStringArray = []
var _redo: Array[Dictionary] = []
var _redo_labels: PackedStringArray = []
var _open_label := ""
var _opened_at := 0


func _init(p_level: LevelData = null, p_path: String = "") -> void:
	level = p_level if p_level else new_level()
	path = p_path


## A playable empty level: a minute long, two calm colours, no holes.
static func new_level() -> LevelData:
	var level := LevelData.new()
	level.id = "new_level"
	level.display_name = "New level"
	level.base_speed = 15.0
	level.speed_ramp = 0.2
	level.length = roundf(SpeedProfile.length_for_duration(60.0, level.base_speed, level.speed_ramp))
	level.palette = [
		PaletteStop.new(0.0, Color("8fd3ff"), Color("1b1446"), Color("ffffff")),
		PaletteStop.new(1.0, Color("ffd23f"), Color("2a0d3e"), Color("ff4f79")),
	]
	return level


func display_title() -> String:
	var file := path.get_file() if not path.is_empty() else "unsaved"
	return "%s%s  (%s)" % ["• " if dirty else "", level.display_name, file]


# --- Editing -----------------------------------------------------------------

## Call before changing the level. `label` names the edit for the status bar.
## With `coalesce`, repeats of the same edit within a second and a half
## (dragging a colour picker, clicking a spin box arrow) share one undo step.
func begin(label: String, coalesce: bool = false) -> void:
	var now := Time.get_ticks_msec()
	if coalesce and label == _open_label and now - _opened_at < 1500 and not _undo.is_empty():
		_opened_at = now
		return
	_opened_at = now
	_undo.append(LevelSerializer.to_dict(level))
	_undo_labels.append(label)
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
		_undo_labels.remove_at(0)
	_redo.clear()
	_redo_labels.clear()
	_open_label = label


## Call after (each step of) a change.
func changed_from(from_s: float) -> void:
	level.sort()
	dirty = true
	changed.emit(maxf(from_s, 0.0))
	file_state_changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Returns the label of what was undone, or "".
func undo() -> String:
	if _undo.is_empty():
		return ""
	var label := _undo_labels[_undo_labels.size() - 1]
	_redo.append(LevelSerializer.to_dict(level))
	_redo_labels.append(label)
	_restore(_undo.pop_back())
	_undo_labels.remove_at(_undo_labels.size() - 1)
	_open_label = ""
	return label


func redo() -> String:
	if _redo.is_empty():
		return ""
	var label := _redo_labels[_redo_labels.size() - 1]
	_undo.append(LevelSerializer.to_dict(level))
	_undo_labels.append(label)
	_restore(_redo.pop_back())
	_redo_labels.remove_at(_redo_labels.size() - 1)
	return label


func _restore(snapshot: Dictionary) -> void:
	var result := LevelSerializer.from_dict(snapshot, "undo")
	if result.level == null:
		return
	level = result.level
	dirty = true
	changed.emit(0.0)
	file_state_changed.emit()


# --- Files -------------------------------------------------------------------

## Switches to another level (New, Open): forgets undo history.
func replace(p_level: LevelData, p_path: String) -> void:
	level = p_level
	path = p_path
	dirty = false
	_undo.clear()
	_undo_labels.clear()
	_redo.clear()
	_redo_labels.clear()
	_open_label = ""
	changed.emit(0.0)
	file_state_changed.emit()


static func open(file_path: String) -> LevelSerializer.Result:
	return LevelSerializer.load_file(file_path)


func save(file_path: String = "") -> Error:
	if not file_path.is_empty():
		path = file_path
	if path.is_empty():
		return ERR_FILE_BAD_PATH
	var error := LevelSerializer.save_file(level, path)
	if error == OK:
		dirty = false
		file_state_changed.emit()
	return error


## Adds the level's id to a manifest.json next to the file, so the game
## plays it. Returns a human sentence about what happened.
func add_to_manifest() -> String:
	if path.is_empty():
		return "Save the level first."
	var manifest_path := path.get_base_dir().path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return "No manifest.json next to %s: copy the file into the game's levels/ folder first." % path.get_file()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(manifest) != TYPE_DICTIONARY:
		return "manifest.json is not valid JSON."
	var ids: Array = manifest.get("levels", [])
	if path.get_file().get_basename() != level.id:
		return "The game finds levels by file name: save this level as %s.json first." % level.id
	if level.id in ids:
		return "%s is already in the game's level list." % level.id
	ids.append(level.id)
	manifest["levels"] = ids
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return "Could not write manifest.json."
	file.store_string(JSON.stringify(manifest, "  ", false) + "\n")
	return "Added %s to the game's level list (level %d)." % [level.id, ids.size()]
