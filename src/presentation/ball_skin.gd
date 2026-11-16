class_name BallSkin
extends Resource
## How a ball looks. Purely cosmetic: skins never change gameplay.
##
## To add a ball, duplicate resources/balls/graphite.tres, change the values
## in the inspector, and pass it to BallView.apply_skin(). A ball shop or
## unlock list only needs to store which skin resource is selected.

@export var display_name := "Graphite"
## Base colour of the surface (dark for the default ball).
@export var base_color := Color("2a2c33")
## Colour of the two hairline seams that make the spin readable.
@export var seam_color := Color("b9bec8")
@export_range(0.0, 0.08) var seam_width := 0.018
## Size of the lamp's highlight: higher = tighter, glossier.
@export_range(4.0, 400.0) var glossiness := 140.0
@export_range(0.0, 2.0) var specular := 1.1
## How much the ball mirrors the tunnel's light (0 = matte, 1 = chrome).
@export_range(0.0, 1.0) var reflectivity := 0.55
## Colour mixed into reflections, e.g. to make a gold ball.
@export var reflection_tint := Color("ffffff")
