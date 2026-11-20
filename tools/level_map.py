#!/usr/bin/env python3
"""Draws a level as an unrolled map, one column per stretch of time.

    python3 tools/level_map.py <level.json> <out.png> [trace.csv ...]

Each column is SECONDS seconds of the level, read bottom to top; across a
column is the whole way round the tunnel, 0 deg (where the ball starts) in
the middle, the player's right to the right. Floor is the wall colour of
the level at that point, void is its void colour, edges are black. Bot runs
(tools/trace_path.gd) are drawn on top: rolling solid, airborne dotted,
jumps as triangles, echoes as diamonds, a fall as a cross. Hints and speed
and spin changes are written beside the column.
"""
import csv
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from visual_oracle import Level  # noqa: E402

SECONDS = 10.0
PX_PER_S = 110
COL_W = 300          # pixels for 360 degrees
GUTTER = 120
TRACE_COLOURS = [(255, 255, 255), (0, 0, 0), (255, 60, 60), (40, 200, 255)]


def hexcolour(text):
    text = text.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def lerp_palette(stops, p, key):
    stops = sorted(stops, key=lambda e: e["at"])
    if p <= stops[0]["at"]:
        return hexcolour(stops[0][key])
    for a, b in zip(stops, stops[1:]):
        if p <= b["at"]:
            f = (p - a["at"]) / max(b["at"] - a["at"], 1e-6)
            ca, cb = hexcolour(a[key]), hexcolour(b[key])
            return tuple(int(ca[i] + (cb[i] - ca[i]) * f) for i in range(3))
    return hexcolour(stops[-1][key])


class Clock:
    """Time <-> distance for a level, speed surges included."""

    def __init__(self, data):
        self.length = float(data["length"])
        self.base = float(data["base_speed"])
        self.ramp = float(data.get("speed_ramp", 0.2))
        self.keys = sorted(data.get("speed", []), key=lambda k: k["s"])
        step = 0.25
        self.s = np.arange(0.0, self.length + 200.0, step)
        v = self.speed(self.s + step * 0.5)
        self.t = np.concatenate([[0.0], np.cumsum(step / v)[:-1]])

    def factor(self, s):
        if not self.keys:
            return np.ones_like(s)
        xs = [k["s"] for k in self.keys]
        fs = [k["factor"] for k in self.keys]
        return np.interp(s, xs, fs)

    def speed(self, s):
        p = np.clip(s / self.length, 0.0, 1.0)
        return self.base * (1.0 + self.ramp * p) * self.factor(s)

    def s_at(self, t):
        return np.interp(t, self.t, self.s)

    def t_at(self, s):
        return np.interp(s, self.s, self.t)


def main():
    level_path, out_path = sys.argv[1], sys.argv[2]
    traces = sys.argv[3:]
    with open(level_path) as f:
        data = json.load(f)
    level = Level(level_path)
    clock = Clock(data)
    duration = clock.t_at(np.array([clock.length]))[0]
    columns = int(math.ceil(duration / SECONDS))
    height = int(SECONDS * PX_PER_S)
    width = columns * (COL_W + GUTTER)
    img = np.zeros((height + 40, width, 3), dtype=np.uint8) + 235

    ys = np.arange(height)
    xs = np.arange(COL_W)
    angles = (xs / COL_W - 0.5) * math.tau
    for c in range(columns):
        t = c * SECONDS + (height - 1 - ys) / PX_PER_S
        s = clock.s_at(t)
        S, A = np.meshgrid(s, angles, indexing="ij")
        d = level.floor_distance(S.ravel(), A.ravel()).reshape(S.shape)
        col = np.zeros((height, COL_W, 3), dtype=np.uint8)
        for y in range(height):
            p = min(max(s[y] / clock.length, 0.0), 1.0)
            wall = lerp_palette(data["palette"], p, "wall")
            void = lerp_palette(data["palette"], p, "void")
            row = np.where(d[y][:, None] >= 0.0, wall, void)
            row = np.where((np.abs(d[y]) < 0.12)[:, None], (10, 8, 16), row)
            if s[y] > clock.length:
                row[:] = (120, 120, 120)
            col[y] = row
        x0 = c * (COL_W + GUTTER)
        img[20:20 + height, x0:x0 + COL_W] = col

    im = Image.fromarray(img)
    draw = ImageDraw.Draw(im)

    def to_xy(t, angle):
        c = int(t // SECONDS)
        y = 20 + height - 1 - (t - c * SECONDS) * PX_PER_S
        a = ((angle + 180.0) % 360.0) - 180.0
        x = c * (COL_W + GUTTER) + (a / 360.0 + 0.5) * COL_W
        return c, x, y

    for c in range(columns):
        x0 = c * (COL_W + GUTTER)
        draw.line([(x0 + COL_W / 2, 20), (x0 + COL_W / 2, 20 + height)], fill=(0, 0, 0), width=1)
        for k in range(int(SECONDS) + 1):
            y = 20 + height - k * PX_PER_S
            draw.text((x0 + COL_W + 4, y - 6), "%ds" % (c * SECONDS + k), fill=(0, 0, 0))
    for hint in data.get("hints", []):
        t = clock.t_at(np.array([hint["s"]]))[0]
        c, x, y = to_xy(t, 0.0)
        draw.text((c * (COL_W + GUTTER) + COL_W + 30, y - 6), hint["text"][:18], fill=(30, 30, 160))
    for key in data.get("spin", []):
        t = clock.t_at(np.array([key["s"]]))[0]
        c, x, y = to_xy(t, 0.0)
        draw.text((c * (COL_W + GUTTER) + COL_W + 30, y + 4), "spin %+.0f" % key["rate"], fill=(160, 30, 30))
    for key in data.get("speed", []):
        t = clock.t_at(np.array([key["s"]]))[0]
        c, x, y = to_xy(t, 0.0)
        draw.text((c * (COL_W + GUTTER) + COL_W + 30, y + 14), "x%.2f" % key["factor"], fill=(30, 130, 30))

    for i, trace in enumerate(traces):
        colour = TRACE_COLOURS[i % len(TRACE_COLOURS)]
        rows = list(csv.DictReader(open(trace)))
        last = None
        for row in rows:
            t = float(row["t"])
            c, x, y = to_xy(t, float(row["angle"]))
            airborne = row["phase"] != "0"
            if last and last[0] == c and abs(last[1] - x) < COL_W / 2:
                if not airborne or int(t * 30) % 2 == 0:
                    draw.line([(last[1], last[2]), (x, y)], fill=colour, width=2)
            last = (c, x, y)
            ev = row["event"]
            if "ECHO" in ev:
                draw.polygon([(x, y - 5), (x + 5, y), (x, y + 5), (x - 5, y)], outline=colour)
            elif "JUMPED" in ev:
                draw.polygon([(x - 5, y + 4), (x + 5, y + 4), (x, y - 5)], outline=colour)
            if "FELL" in ev:
                draw.line([(x - 7, y - 7), (x + 7, y + 7)], fill=(255, 0, 0), width=3)
                draw.line([(x - 7, y + 7), (x + 7, y - 7)], fill=(255, 0, 0), width=3)
    draw.text((4, 2), "%s  %.0f m  %.1f s  base %.1f m/s" % (data["name"], clock.length, duration, clock.base), fill=(0, 0, 0))
    im.save(out_path)


if __name__ == "__main__":
    main()
