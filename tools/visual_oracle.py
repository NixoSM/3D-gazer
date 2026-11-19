#!/usr/bin/env python3
"""Pixel oracle for Gazer's tunnel renders.

tools/visual_audit.tscn renders views of every level with the tunnel drawn
as flat material IDs (floor, outline, cut face, back line, void) and saves
the camera next to each frame. This script works out, from the level file
alone, what every pixel *should* show, by ray-casting the tunnel exactly as
the game defines it (the same signed distance the ball falls by), and
reports every group of pixels that disagree.

It shares no code with the renderer: it does not use the meshes, the
shaders or TunnelMesher, only the definition of the level. A see-through
crack, a missing or stretched cut face, a black spike, a hole drawn in the
wrong place or a chunk that was not built all show up as a cluster of
wrong pixels, with what was drawn and what should have been.

    python3 tools/visual_oracle.py <audit_dir> [--report <dir>] [--min-cluster 12]

Exit status 1 if any frame has a cluster of wrong pixels.
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

# Material IDs, as tiles.gdshaderinc draws them.
VOID, FLOOR, OUTLINE, WALL, BACKLINE, BALL, FOREIGN = range(7)
NAMES = ["void", "floor", "outline", "cut face", "back line", "ball", "other"]
ID_COLORS = np.array([
    [0, 0, 255],
    [0, 255, 0],
    [255, 0, 0],
    [255, 255, 0],
    [255, 0, 255],
    [255, 255, 255],
], dtype=np.int32)

# The level definition (src/core/hole_data.gd, src/core/level_data.gd).
CORNER_RADIUS = 0.6
BLEND = 1.2
REACH = BLEND + CORNER_RADIUS + 1.0
# Bound on how fast the signed distance changes per metre (smooth blends
# and twisted holes stretch it a little beyond 1).
LIPSCHITZ = 1.5
# Distance at which the void backdrop sphere hides everything.
BACKDROP_RADIUS = 200.0
# Pinholes are looked for this close (m). Further on, edges are a pixel or
# two wide and deep in the fog, and the mesh's millimetres of difference
# from the exact curve move sub-pixel slivers of void by a pixel.
PINHOLE_RANGE = 60.0


class Hole:
    def __init__(self, entry):
        self.s_start = float(entry.get("s", 0.0))
        self.length = float(entry.get("length", 1.0))
        self.angle_center = math.radians(float(entry.get("angle", 0.0))) % math.tau
        self.angle_width = math.radians(float(entry.get("width", 45.0)))
        self.twist = math.radians(float(entry.get("twist", 0.0)))

    @property
    def s_end(self):
        return self.s_start + self.length

    def signed_distance(self, s, angle, radius):
        half = self.length * 0.5
        y = np.abs(s - (self.s_start + half)) - half
        if self.angle_width >= math.tau - 0.0001:
            return y
        slope = self.twist * radius
        slant = 1.0 / math.sqrt(1.0 + slope * slope)
        center = self.angle_center + self.twist * (s - self.s_start)
        diff = np.mod(angle - center + math.pi, math.tau) - math.pi
        x = (np.abs(diff) * radius - self.angle_width * 0.5 * radius) * slant
        corner = min(CORNER_RADIUS, min(self.angle_width * 0.5 * radius * slant, half) * 0.9)
        qx = x + corner
        qy = y + corner
        outside = np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0))
        return outside + np.minimum(np.maximum(qx, qy), 0.0) - corner


def smooth_min(a, b):
    h = np.maximum(BLEND - np.abs(a - b), 0.0) / BLEND
    result = np.minimum(a, b) - h * h * BLEND * 0.25
    return np.where(np.isinf(a), b, result)


class Level:
    def __init__(self, path):
        with open(path) as f:
            data = json.load(f)
        self.radius = float(data.get("tunnel_radius", 4.0))
        self.holes = sorted((Hole(e) for e in data.get("holes", [])), key=lambda h: h.s_start)

    def floor_distance(self, s, angle):
        """Signed distance to the nearest hole edge: + floor, - void."""
        d = np.full(s.shape, np.inf)
        if s.size == 0:
            return d
        lo, hi = s.min(), s.max()
        for hole in self.holes:
            if hole.s_start > hi + REACH or hole.s_end < lo - REACH:
                continue
            near = np.nonzero((s >= hole.s_start - REACH) & (s <= hole.s_end + REACH))[0]
            if near.size:
                d[near] = smooth_min(d[near], hole.signed_distance(s[near], angle[near], self.radius))
        return d


def camera_rays(info):
    width, height = info["size"]
    projection = np.array(info["projection"], dtype=np.float64).T  # columns -> matrix
    inverse = np.linalg.inv(projection)
    xs = (np.arange(width) + 0.5) / width * 2.0 - 1.0
    ys = 1.0 - (np.arange(height) + 0.5) / height * 2.0
    gx, gy = np.meshgrid(xs, ys)
    ndc = np.stack([gx, gy, np.full_like(gx, 0.5), np.ones_like(gx)], axis=-1).reshape(-1, 4)
    view = ndc @ inverse.T
    view = view[:, :3] / view[:, 3:4]
    view *= np.where(view[:, 2:3] > 0.0, -1.0, 1.0)  # point forwards (-z)
    basis = np.array(info["basis"], dtype=np.float64).T  # columns x, y, z
    directions = view @ basis.T
    directions /= np.linalg.norm(directions, axis=1, keepdims=True)
    origin = np.array(info["origin"], dtype=np.float64)
    return origin, directions


def exit_distance(origin, directions, radius):
    """Distance along each ray to where it crosses the cylinder of `radius`
    on its way out (the camera is inside)."""
    a = directions[:, 0] ** 2 + directions[:, 1] ** 2
    b = 2.0 * (origin[0] * directions[:, 0] + origin[1] * directions[:, 1])
    c = origin[0] ** 2 + origin[1] ** 2 - radius * radius
    disc = np.maximum(b * b - 4.0 * a * c, 0.0)
    with np.errstate(divide="ignore", invalid="ignore"):
        t = (-b + np.sqrt(disc)) / (2.0 * a)
    return np.where(a > 1e-12, t, np.inf)


def surface_coordinates(points):
    s = -points[:, 2]
    angle = np.mod(np.arctan2(points[:, 0], -points[:, 1]), math.tau)
    r = np.hypot(points[:, 0], points[:, 1])
    return s, angle, r


def expected_ids(info, level):
    """What each pixel should show, from the level definition alone."""
    origin, directions = camera_rays(info)
    radius = level.radius
    thickness = info["shell_thickness"]
    outline = info["outline_width"]
    back_line = info.get("back_line") or 0.1
    chunk = info["chunk_length"]
    built_from = info["chunks"][0] * chunk
    built_to = (info["chunks"][1] + 1) * chunk

    ids = np.full(directions.shape[0], VOID, dtype=np.int32)
    t_floor = exit_distance(origin, directions, radius)
    hit = np.isfinite(t_floor) & (t_floor < BACKDROP_RADIUS)
    rays = np.nonzero(hit)[0]
    points = origin + directions[rays] * t_floor[rays, None]
    s, angle, _ = surface_coordinates(points)
    inside = (s >= built_from) & (s <= built_to)
    rays, s, angle = rays[inside], s[inside], angle[inside]
    d = level.floor_distance(s, angle)
    solid = d >= 0.0
    ids[rays[solid]] = np.where(d[solid] < outline, OUTLINE, FLOOR)

    # Through a hole: follow the ray out through the shell until it meets a
    # cut face (solid floor above it) or leaves the shell into the void.
    # Sphere tracing on the signed distance, which changes at most LIPSCHITZ
    # metres per metre along the ray anywhere at or outside the floor.
    open_rays = rays[~solid]
    t = t_floor[open_rays].copy()
    dist = d[~solid].copy()
    t_out = exit_distance(origin, directions[open_rays], radius + thickness)
    active = np.ones(open_rays.size, dtype=bool)
    for _ in range(160):
        idx = np.nonzero(active)[0]
        if idx.size == 0:
            break
        t[idx] += np.maximum(-dist[idx] / LIPSCHITZ, 0.0015)
        gone = t[idx] >= t_out[idx]
        active[idx[gone]] = False
        idx = idx[~gone]
        if idx.size == 0:
            break
        p = origin + directions[open_rays[idx]] * t[idx, None]
        ps, pa, pr = surface_coordinates(p)
        outside = (ps < built_from) | (ps > built_to)
        active[idx[outside]] = False
        keep = ~outside
        idx, ps, pa, pr = idx[keep], ps[keep], pa[keep], pr[keep]
        dist[idx] = level.floor_distance(ps, pa)
        met = dist[idx] >= 0.0  # crossed into solid wall: the cut face
        if met.any():
            depth = (pr[met] - radius) / thickness
            ids[open_rays[idx[met]]] = np.where(depth > 1.0 - back_line, BACKLINE, WALL)
            active[idx[met]] = False
    unknown = np.zeros(ids.shape, dtype=bool)
    unknown[open_rays[active]] = True  # never settled: excluded from the comparison
    width, height = info["size"]
    distance = np.minimum(t_floor, BACKDROP_RADIUS).reshape(height, width)
    return ids.reshape(height, width), unknown.reshape(height, width), distance


def rendered_ids(path):
    pixels = np.asarray(Image.open(path).convert("RGB"), dtype=np.int32)
    flat = pixels.reshape(-1, 1, 3)
    distance = np.abs(flat - ID_COLORS[None, :, :]).sum(axis=2)
    ids = distance.argmin(axis=1)
    ids[distance.min(axis=1) > 60] = FOREIGN
    return ids.reshape(pixels.shape[:2]).astype(np.int32)


def compare(expected, unknown, rendered, distance, tolerance=2, min_cluster=12):
    """A rendered pixel is right if the expected ID map has its ID within
    `tolerance` pixels (edges can land a pixel either side). Returns the
    wrong-pixel mask and the clusters big enough to see, plus every pinhole:
    a pixel of void drawn where there is no void anywhere near (a crack in
    the floor or a cut face), which fails at any size because on the phone
    it flickers as the tunnel moves."""
    size = 2 * tolerance + 1
    footprint = np.ones((size, size), dtype=bool)
    accept = np.zeros(expected.shape, dtype=bool)
    for material in range(BALL + 1):
        near = ndimage.binary_dilation(expected == material, structure=footprint)
        accept |= near & (rendered == material)
    near_unknown = ndimage.binary_dilation(unknown, structure=footprint)
    wrong = ~accept & ~near_unknown
    labels, count = ndimage.label(wrong, structure=np.ones((3, 3), dtype=bool))
    clusters = []
    if count:
        sizes = ndimage.sum(wrong, labels, index=np.arange(1, count + 1))
        for label in np.nonzero(sizes >= min_cluster)[0] + 1:
            ys, xs = np.nonzero(labels == label)
            drawn = np.bincount(rendered[ys, xs], minlength=7).argmax()
            should = np.bincount(expected[ys, xs], minlength=7).argmax()
            clusters.append({
                "pixels": int(ys.size),
                "box": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                "drawn": NAMES[drawn],
                "expected": NAMES[should],
            })
    clusters.sort(key=lambda c: -c["pixels"])
    wide = np.ones((9, 9), dtype=bool)
    void_near = ndimage.binary_dilation(expected == VOID, structure=wide) | near_unknown
    pinholes = wrong & (rendered == VOID) & ~void_near & (distance < PINHOLE_RANGE)
    ys, xs = np.nonzero(pinholes)
    for y, x in zip(ys, xs):
        clusters.append({"pixels": 1, "box": [int(x), int(y), int(x), int(y)], "drawn": "void (pinhole)",
                         "expected": NAMES[expected[y, x]]})
    return wrong, clusters


def id_image(ids):
    palette = np.vstack([ID_COLORS, [[128, 128, 128]]]).astype(np.uint8)
    return palette[ids]


def save_report(path, rendered, expected, wrong, clusters):
    left = id_image(rendered)
    middle = id_image(expected)
    right = (left // 3).astype(np.uint8)
    right[wrong] = [255, 255, 255]
    sheet = Image.fromarray(np.hstack([left, middle, right]))
    from PIL import ImageDraw
    draw = ImageDraw.Draw(sheet)
    offset = left.shape[1] * 2
    for c in clusters:
        x0, y0, x1, y1 = c["box"]
        draw.rectangle([offset + x0 - 3, y0 - 3, offset + x1 + 3, y1 + 3], outline=(255, 40, 40), width=2)
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("audit_dir")
    parser.add_argument("--levels", default=os.path.join(os.path.dirname(__file__), "..", "levels"))
    parser.add_argument("--report", help="write side-by-side images of failing frames here")
    parser.add_argument("--min-cluster", type=int, default=12)
    parser.add_argument("--tolerance", type=int, default=2)
    args = parser.parse_args()

    frames = sorted(f[:-5] for f in os.listdir(args.audit_dir) if f.endswith(".json"))
    if not frames:
        print("no frames in", args.audit_dir)
        return 2
    levels = {}
    failures = 0
    total_wrong = 0
    summary = []
    for name in frames:
        with open(os.path.join(args.audit_dir, name + ".json")) as f:
            info = json.load(f)
        level_id = info["level"]
        if level_id not in levels:
            levels[level_id] = Level(os.path.join(args.levels, level_id + ".json"))
        expected, unknown, distance = expected_ids(info, levels[level_id])
        rendered = rendered_ids(os.path.join(args.audit_dir, name + ".png"))
        wrong, clusters = compare(expected, unknown, rendered, distance, args.tolerance, args.min_cluster)
        total_wrong += int(wrong.sum())
        summary.append({"frame": name, "wrong_pixels": int(wrong.sum()), "clusters": clusters})
        if clusters:
            failures += 1
            worst = ", ".join("%d px %s where %s should be" % (c["pixels"], c["drawn"], c["expected"]) for c in clusters[:3])
            print("FAIL %-32s %s" % (name, worst))
            if args.report:
                os.makedirs(args.report, exist_ok=True)
                save_report(os.path.join(args.report, name + ".png"), rendered, expected, wrong, clusters)
    if args.report:
        os.makedirs(args.report, exist_ok=True)
        with open(os.path.join(args.report, "summary.json"), "w") as f:
            json.dump(summary, f, indent=1)
    print("%d frames, %d with visible errors, %d wrong pixels in all" % (len(frames), failures, total_wrong))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
