class_name LevelPalette
extends RefCounted
## Turns a level's PaletteStops into gradients for shaders and colour lookups
## for scripts, so GPU and CPU always agree on "the colour at progress p".

const TEXTURE_WIDTH := 2048

var wall := Gradient.new()
var void_color := Gradient.new()
var accent := Gradient.new()
var wall_texture := GradientTexture1D.new()
var accent_texture := GradientTexture1D.new()


func _init(stops: Array[PaletteStop]) -> void:
	for gradient in [wall, void_color, accent]:
		# Gradients start with two default points; replace them.
		while gradient.get_point_count() > 1:
			gradient.remove_point(gradient.get_point_count() - 1)
	for i in stops.size():
		var stop := stops[i]
		if i == 0:
			wall.set_offset(0, stop.at)
			wall.set_color(0, stop.wall)
			void_color.set_offset(0, stop.at)
			void_color.set_color(0, stop.void_color)
			accent.set_offset(0, stop.at)
			accent.set_color(0, stop.accent)
		else:
			wall.add_point(stop.at, stop.wall)
			void_color.add_point(stop.at, stop.void_color)
			accent.add_point(stop.at, stop.accent)
	for gradient in [wall, void_color, accent]:
		gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB
	# Fine enough for colour bands a few metres long on a 2 km level.
	wall_texture.gradient = wall
	wall_texture.width = TEXTURE_WIDTH
	accent_texture.gradient = accent
	accent_texture.width = TEXTURE_WIDTH


func wall_at(progress: float) -> Color:
	return wall.sample(clampf(progress, 0.0, 1.0))


func void_at(progress: float) -> Color:
	return void_color.sample(clampf(progress, 0.0, 1.0))


func accent_at(progress: float) -> Color:
	return accent.sample(clampf(progress, 0.0, 1.0))
