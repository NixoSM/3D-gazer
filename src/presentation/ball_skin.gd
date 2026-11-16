class_name BallSkin
extends Resource
## How a ball looks. Purely cosmetic: skins never change gameplay.
##
## To add a ball, duplicate resources/balls/classic.tres, change the values
## in the inspector, and pass it to BallView.apply_skin(). A ball shop or
## unlock list only needs to store which skin resource is selected.

@export var display_name := "Classic"
@export var body_color := Color("ffffff")
## The wide band around the ball that shows it rolling.
@export var stripe_color := Color("ff2e63")
## Half-height of the stripe as a fraction of the radius (0 = no stripe).
@export_range(0.0, 0.95) var stripe_width := 0.42
## Outline and stripe-edge colour.
@export var line_color := Color("0b0910")
## Outline thickness as a fraction of the radius.
@export_range(0.0, 0.3) var outline_width := 0.15
## How much darker the shadow side is.
@export_range(0.0, 0.8) var shade_amount := 0.28
@export_range(0.0, 0.5) var shine_size := 0.18
