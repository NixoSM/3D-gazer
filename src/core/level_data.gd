class_name LevelData
extends RefCounted
## Everything that defines a level, and nothing about how it is drawn or played.
##
## LevelData is produced by LevelSerializer from a JSON file in res://levels/
## (see docs/LEVEL_FORMAT.md). A future level editor only has to create, edit
## and save these objects: the game never hard-codes level content.

var id: String = ""
var display_name: String = ""
## Tunnel length in metres. The level is complete when the ball reaches it.
var length: float = 600.0
## Inner radius of the tunnel in metres.
var tunnel_radius: float = 4.0
## Forward speed at the start of the level, metres per second.
var base_speed: float = 11.0
## Fractional speed increase reached at the end (0.2 = +20%).
var speed_ramp: float = 0.2
## Colour journey, sorted by `at`.
var palette: Array[PaletteStop] = []
## Holes, sorted by `s_start`.
var holes: Array[HoleData] = []
## Ground spin keys, sorted by `s`. Empty means no spin.
var spin: Array[SpinKey] = []

var _cached_max_hole_length: float = -1.0


func speed_at(s: float) -> float:
	return SpeedProfile.speed_at(s, length, base_speed, speed_ramp)


## Ground spin at distance s, in degrees per second (see SpinKey).
func spin_at(s: float) -> float:
	if spin.is_empty():
		return 0.0
	if s <= spin[0].s:
		return spin[0].rate
	for i in range(1, spin.size()):
		var b := spin[i]
		if s < b.s:
			var a := spin[i - 1]
			var span := b.s - a.s
			return b.rate if span <= 0.0001 else lerpf(a.rate, b.rate, (s - a.s) / span)
	return spin[spin.size() - 1].rate


## Ground spin at distance s as a sideways speed along the wall, m/s.
func spin_speed_at(s: float) -> float:
	return deg_to_rad(spin_at(s)) * tunnel_radius


func duration() -> float:
	return SpeedProfile.duration(length, base_speed, speed_ramp)


func progress_at(s: float) -> float:
	return clampf(s / length, 0.0, 1.0)


## Keeps holes, palette and spin keys sorted. Call after editing either list.
func sort() -> void:
	_cached_max_hole_length = -1.0
	holes.sort_custom(func(a: HoleData, b: HoleData) -> bool: return a.s_start < b.s_start)
	palette.sort_custom(func(a: PaletteStop, b: PaletteStop) -> bool: return a.at < b.at)
	spin.sort_custom(func(a: SpinKey, b: SpinKey) -> bool: return a.s < b.s)


## Index of the first hole that could still overlap distance `s`.
## Holes are sorted by start, so we binary-search on start and walk back over
## any long hole that started earlier. Used for O(log n) hole queries.
func first_hole_index_near(s: float) -> int:
	var lo := 0
	var hi := holes.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if holes[mid].s_start < s:
			lo = mid + 1
		else:
			hi = mid
	# A hole that started before `s` may still cover it: step back while
	# earlier holes could reach s (bounded by the longest hole in the level).
	var index := lo
	var reach := _max_hole_length()
	while index > 0 and holes[index - 1].s_start + reach >= s:
		index -= 1
	return index


## Returns the hole containing the surface point, or null.
func hole_at(s: float, angle: float, margin_s: float = 0.0, margin_arc: float = 0.0) -> HoleData:
	var index := first_hole_index_near(s)
	while index < holes.size() and holes[index].s_start <= s:
		var hole := holes[index]
		if hole.contains(s, angle, tunnel_radius, margin_s, margin_arc):
			return hole
		index += 1
	return null


## Holes overlapping [s0, s1). Used by the renderer's chunk builder.
func holes_between(s0: float, s1: float) -> Array[HoleData]:
	var result: Array[HoleData] = []
	var index := first_hole_index_near(s0)
	while index < holes.size() and holes[index].s_start < s1:
		if holes[index].s_end() > s0:
			result.append(holes[index])
		index += 1
	return result


func _max_hole_length() -> float:
	if _cached_max_hole_length < 0.0:
		_cached_max_hole_length = 0.0
		for hole in holes:
			_cached_max_hole_length = maxf(_cached_max_hole_length, hole.length)
	return _cached_max_hole_length
