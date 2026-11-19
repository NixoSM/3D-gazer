#!/usr/bin/env python3
"""Draws Gazer's app icon as an SVG (icon.svg), from code so it stays editable.

The idea: you look straight down the tunnel and the tunnel looks back. The
rings of floor tiles are the iris, a ring-shaped hole is the dark limbal
ring (its cut face and black back line seen on the far side, exactly as
the game draws them), the void at the end of the tunnel is the pupil and
the ball is the catch-light. Flat colours, hard two-tone shading and thick
black outlines, like the game.

    python3 tools/make_icon.py            # writes icon.svg
    godot --headless --script res://tools/rasterize_icon.gd   # icon PNGs

Colours are Dawn's: the first level is the first thing anyone sees.
"""

import math
import os

SIZE = 1024
CX, CY = 512.0, 512.0

NEAR_WALL = (0xff, 0xc9, 0x3c)    # Dawn's wall at the start
FAR_WALL = (0xff, 0x8f, 0x3c)     # further down the tunnel
VOID = (0x3a, 0x1c, 0x80)
PUPIL = (0x1a, 0x0a, 0x44)
INK = (0x0b, 0x08, 0x12)
BALL = (0xff, 0xfb, 0xf4)
SHADOW = (0x2a, 0x10, 0x50)
STRIPE = (0xff, 0x2f, 0x6d)

SHADE_DARK = 0.72       # the half of the tunnel above the ball (tunnel_floor.gdshader)
SEAM_SHADE = 0.78       # tile seams
FACE_SHADE = 0.62       # cut faces (tunnel_wall.gdshader)
TILES_AROUND = 10


def hexc(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def scale(rgb, k):
    return tuple(c * k for c in rgb)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def polar(r, angle):
    # Screen angle: 0 = right, +90° = down.
    return CX + r * math.cos(angle), CY + r * math.sin(angle)


def annulus(r_out, r_in, fill, extra=""):
    def circle(r):
        return "M %.2f %.2f a %.2f %.2f 0 1 0 %.2f 0 a %.2f %.2f 0 1 0 %.2f 0 Z" % (CX - r, CY, r, r, 2 * r, r, r, -2 * r)
    d = circle(r_out) + (" " + circle(r_in) if r_in > 0 else "")
    return '<path d="%s" fill="%s" fill-rule="evenodd"%s/>' % (d, fill, extra)


def sector(r_out, r_in, a0, a1):
    large = 1 if a1 - a0 > math.pi else 0
    x0, y0 = polar(r_out, a0)
    x1, y1 = polar(r_out, a1)
    x2, y2 = polar(r_in, a1)
    x3, y3 = polar(r_in, a0)
    return ("M %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f L %.2f %.2f A %.2f %.2f 0 %d 0 %.2f %.2f Z"
            % (x0, y0, r_out, r_out, large, x1, y1, x2, y2, r_in, r_in, large, x3, y3))


def tiles(r_out, r_in, color, row):
    """One row of rounded tiles between two radii (seams drawn as the gap)."""
    out = [annulus(r_out, r_in, hexc(scale(color, SEAM_SHADE)))]
    seam = r_out * 0.024
    corner = (r_out - r_in) * 0.16
    pad = seam * 0.5 + corner
    step = math.tau / TILES_AROUND
    offset = (row % 2) * step * 0.5 + 0.21
    for i in range(TILES_AROUND):
        a0 = offset + i * step
        a1 = a0 + step
        pa_out = pad / r_out
        pa_in = pad / max(r_in, 1.0)
        path = sector(r_out - pad, r_in + pad, a0 + pa_out, a1 - pa_out) if pa_in < step * 0.4 else ""
        if path:
            out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round"/>'
                       % (path, hexc(color), hexc(color), corner * 2))
    return out


def plus_star(x, y, size, color):
    w = size * 0.32
    return ('<path d="M %.1f %.1f h %.1f v %.1f h %.1f v %.1f h %.1f v %.1f h %.1f v %.1f h %.1f v %.1f h %.1f Z" fill="%s"/>'
            % (x - w / 2, y - size / 2, w, size / 2 - w / 2, size / 2 - w / 2, w, -(size / 2 - w / 2), size / 2 - w / 2,
               -w, -(size / 2 - w / 2), -(size / 2 - w / 2), -w, size / 2 - w / 2, color))


def layer(rows, dark):
    parts = []
    for i, (r_out, r_in, color) in enumerate(rows):
        parts += tiles(r_out, r_in, scale(color, SHADE_DARK) if dark else color, i)
    return parts


def build():
    # Rows of tiles from the camera inwards: radius on screen ~ 1 / distance.
    near = [(800, 600), (600, 486), (486, 410)]
    hole_near, face_out, face_in = 410, 338, 284
    far_edges = [284, 244, 215, 193, 175, 160, 148]
    near_rows = [(a, b, NEAR_WALL) for a, b in near]
    far_rows = []
    for i in range(len(far_edges) - 1):
        fog = i / (len(far_edges) - 1) * 0.8
        far_rows.append((far_edges[i], far_edges[i + 1], mix(FAR_WALL, VOID, fog)))
    pupil_r = far_edges[-1]

    svg = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">' % (SIZE, SIZE, SIZE, SIZE)]
    # The ceiling: the arc of the tunnel above the ball is darker. The ball
    # sits at the bottom; lit where cos(angle from the bottom) > -0.15.
    lit_half = math.acos(-0.15)
    a0 = math.pi / 2 + lit_half
    a1 = math.pi / 2 + math.tau - lit_half
    ceiling = sector(2000, 0.01, a0, a1)
    svg.append('<defs><clipPath id="ceiling"><path d="%s"/></clipPath></defs>' % ceiling)
    svg.append('<rect width="%d" height="%d" fill="%s"/>' % (SIZE, SIZE, hexc(scale(NEAR_WALL, SEAM_SHADE))))

    for dark in (False, True):
        group = layer(near_rows, dark)
        group.append(annulus(hole_near + 26, hole_near, hexc(INK)))            # the floor's outline
        group.append(annulus(hole_near, face_out, hexc(VOID)))                  # through the hole
        face = scale(FAR_WALL, FACE_SHADE)
        group.append(annulus(face_out, face_in, hexc(face)))                    # the far edge's cut face
        step = math.tau / TILES_AROUND
        for i in range(TILES_AROUND):                                           # tile seams down the face
            a = 0.21 + i * step
            x0, y0 = polar(face_out, a)
            x1, y1 = polar(face_in, a)
            group.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="7"/>'
                         % (x0, y0, x1, y1, hexc(scale(FAR_WALL, FACE_SHADE - 0.2))))
        group.append(annulus(face_out + 2, face_out - 11, hexc(INK)))           # back line
        group += layer(far_rows, dark)
        group.append(annulus(face_in, face_in - 13, hexc(INK)))                 # far floor's outline
        group.append(annulus(pupil_r, 0, hexc(PUPIL)))
        if dark:
            svg.append('<g clip-path="url(#ceiling)">%s</g>' % "".join(group))
        else:
            svg += group

    # Void stars, seen through the hole.
    for angle, r, size in [(-2.35, 372, 28), (-0.5, 366, 20), (1.15, 374, 24), (2.5, 368, 17)]:
        x, y = polar(r, angle)
        svg.append(plus_star(x, y, size, "#ffffff"))
    x, y = polar(70, 2.6)
    svg.append(plus_star(x, y, 16, hexc(mix(PUPIL, (255, 255, 255), 0.55))))

    # The ball, as the eye's catch-light, up and to the right of the pupil.
    bx, by, br = 600.0, 424.0, 82.0
    svg.append('<defs><clipPath id="ball"><circle cx="%.1f" cy="%.1f" r="%.1f"/></clipPath></defs>' % (bx, by, br))
    svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (bx, by, br + 17, hexc(INK)))
    svg.append('<g clip-path="url(#ball)">')
    svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (bx, by, br, hexc(BALL)))
    svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" transform="rotate(-24 %.1f %.1f)"/>'
               % (bx - br * 0.22, by - br * 1.2, br * 0.44, br * 2.4, hexc(STRIPE), bx, by))
    # Hard cel shading: a crescent of shadow on the side away from the light.
    svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-opacity="0.16" stroke-width="%.1f"/>'
               % (bx - br * 0.24, by - br * 0.26, br * 1.16, hexc(SHADOW), br * 0.5))
    svg.append('</g>')
    svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#ffffff"/>' % (bx - br * 0.38, by - br * 0.4, br * 0.15))
    svg.append('</svg>')
    return "\n".join(svg) + "\n"


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    with open(os.path.join(root, "icon.svg"), "w") as f:
        f.write(build())
    print("wrote icon.svg")
