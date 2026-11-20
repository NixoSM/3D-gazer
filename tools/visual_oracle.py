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
wrong pixels, with what was drawn and what should have been. Thin stray
lines of ink on plain floor (often dotted, so no single cluster is big)
are counted over the whole frame instead.

    python3 tools/visual_oracle.py <audit_dir> [--report <dir>] [--min-cluster 12]

Exit status 1 if any frame has a cluster of wrong pixels, a pinhole or
stray ink.
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
# The ID view counts a floor pixel as outline where the ink darkens it by more
# than this (tunnel_floor.gdshader, INK_VISIBLE), so faint stray ink counts.
INK_VISIBLE = 0.1
# A frame fails with this many pixels of stray ink (see compare()). With
# MSAA a pixel counts by the share of its samples that drew it: a pixel a
# quarter covered is a quarter as dark, a quarter of a pixel of ink.
STRAY_INK = 4
# The edge distance's gradient is taken by central differences this far
# apart, as TunnelMesher.SLOPE_STEP gives it to the floor's vertices.
SLOPE_STEP = 1.0 / 256.0
# The expected picture is ray-cast this many pixels beyond the frame, so
# that an edge just off screen counts as near one at the border.
BORDER = 6


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


def camera_rays(info, jitter=(0.0, 0.0), pad=0):
    """One ray per pixel, through the pixel's centre moved by `jitter` pixels,
    for the frame and `pad` pixels beyond it on every side."""
    width, height = info["size"]
    gx, gy = np.meshgrid(np.arange(-pad, width + pad) + 0.5 + jitter[0],
                         np.arange(-pad, height + pad) + 0.5 + jitter[1])
    return pixel_rays(info, gx.reshape(-1), gy.reshape(-1))


def pixel_rays(info, px, py):
    """Rays through points of the frame, in pixels from its top left corner
    (pixel (x, y) spans x..x+1, y..y+1)."""
    width, height = info["size"]
    projection = np.array(info["projection"], dtype=np.float64).T  # columns -> matrix
    inverse = np.linalg.inv(projection)
    gx = np.asarray(px, dtype=np.float64) / width * 2.0 - 1.0
    gy = 1.0 - np.asarray(py, dtype=np.float64) / height * 2.0
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


def ink(info, level, rays, s, angle, d, shape):
    """How much black ink covers each floor pixel, by the floor shader's own
    rule (tunnel_floor.gdshader, ink()): a quarter metre of floor, at most a
    share of the screen height, at least a pixel and a half, softened on the
    inner side by up to a pixel. The rule needs how fast the edge distance
    changes per pixel, which the shader works out as this does: the true
    gradient of the distance field (TunnelMesher gives it to every vertex
    within ink reach; plain floor beyond has none) along the pixel's step
    across the floor to the next pixel."""
    height_px = info["size"][1]
    radius = level.radius
    grid_s = np.full(shape[0] * shape[1], np.nan)
    grid_a = np.full(shape[0] * shape[1], np.nan)
    grid_s[rays] = s
    grid_a[rays] = angle
    grid_s = grid_s.reshape(shape)
    grid_a = grid_a.reshape(shape)

    def step(axis):
        # To the next pixel, or from the previous one at the stretch's end.
        ds = np.diff(grid_s, axis=axis, append=np.nan)
        da = np.diff(grid_a, axis=axis, append=np.nan)
        back = np.isnan(ds)
        ds = np.where(back, np.diff(grid_s, axis=axis, prepend=np.nan), ds)
        da = np.where(back, np.diff(grid_a, axis=axis, prepend=np.nan), da)
        da = (da + math.pi) % math.tau - math.pi
        return np.nan_to_num(ds).reshape(-1)[rays], np.nan_to_num(da * radius).reshape(-1)[rays]

    x_s, x_arc = step(1)
    y_s, y_arc = step(0)
    per_pixel = np.full(d.shape, 0.00001)
    near = np.nonzero(d < info.get("plain_distance", 0.65))[0]
    if near.size:
        ns, na = s[near], angle[near]
        turn = SLOPE_STEP / radius
        g_s = (level.floor_distance(ns + SLOPE_STEP, na) - level.floor_distance(ns - SLOPE_STEP, na)) / (2 * SLOPE_STEP)
        g_arc = (level.floor_distance(ns, np.mod(na + turn, math.tau))
                 - level.floor_distance(ns, np.mod(na - turn, math.tau))) / (2 * SLOPE_STEP)
        across = np.abs(g_s * x_s[near] + g_arc * x_arc[near]) + np.abs(g_s * y_s[near] + g_arc * y_arc[near])
        per_pixel[near] = np.maximum(np.nan_to_num(across), 0.00001)
    outline = info["outline_width"]
    width = np.minimum(outline, info.get("outline_max_screen", 1.0) * height_px * per_pixel)
    width = np.maximum(width, np.minimum(info.get("outline_min_pixels", 0.0) * per_pixel,
                                         info.get("outline_max_width", outline * 1.6)))
    soft = np.minimum(per_pixel, width * 0.5)
    t = np.clip((d - (width - soft)) / np.maximum(2.0 * soft, 1e-9), 0.0, 1.0)
    return 1.0 - t * t * (3.0 - 2.0 * t)


def expected_ids(info, level, jitter=(0.0, 0.0), pad=0):
    """What each pixel should show, from the level definition alone (and
    `pad` pixels beyond the frame on every side)."""
    origin, directions = camera_rays(info, jitter, pad)
    shape = (info["size"][1] + 2 * pad, info["size"][0] + 2 * pad)
    ids, unknown, t_floor = trace(info, level, origin, directions, shape)
    distance = np.minimum(t_floor, BACKDROP_RADIUS).reshape(shape)
    return ids.reshape(shape), unknown.reshape(shape), distance


def trace(info, level, origin, directions, shape=None):
    """What each ray should see. With `shape` (the rays are a frame's pixels,
    row by row) the floor's ink is worked out too; without it, all floor
    counts as FLOOR. Returns the IDs, the rays never settled, and how far
    each ray runs to the floor's cylinder."""
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
    if shape is None:
        ids[rays[solid]] = FLOOR
    else:
        covered = ink(info, level, rays, s, angle, d, shape) > INK_VISIBLE
        ids[rays[solid]] = np.where(covered[solid], OUTLINE, FLOOR)

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
    return ids, unknown, t_floor


def rendered_ids(path):
    """The rendered IDs, and how much of each pixel is not floor: the share
    of its MSAA samples that drew something else (0 or 1 without MSAA). The
    samples are blended in linear colour and stored as sRGB, so one sample
    of four outline next to three of floor reads (137, 225, 0)."""
    pixels = np.asarray(Image.open(path).convert("RGB"), dtype=np.int32)
    flat = pixels.reshape(-1, 1, 3)
    distance = np.abs(flat - ID_COLORS[None, :, :]).sum(axis=2)
    ids = distance.argmin(axis=1)
    ids[distance.min(axis=1) > 60] = FOREIGN
    c = pixels / 255.0
    linear = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    # Every other ID has red or blue where floor has none, or lacks its green.
    not_floor = np.maximum(np.maximum(linear[..., 0], linear[..., 2]), 1.0 - linear[..., 1])
    return ids.reshape(pixels.shape[:2]).astype(np.int32), not_floor


def compare(expected, unknown, rendered, distance, tolerance=2, min_cluster=12, msaa=False, may_be=None,
            pad=0, not_floor=None):
    """A rendered pixel is right if the expected ID map has its ID within
    `tolerance` pixels (edges can land a pixel either side). Returns the
    wrong-pixel mask and the clusters big enough to see, plus every pinhole:
    a pixel of void drawn where there is no void anywhere near (a crack in
    the floor or a cut face), which fails at any size because on the phone
    it flickers as the tunnel moves. `may_be` maps void, cut face and back
    line to the pixels each really covers part of (see subpixel_ids()):
    there a sliver thinner than a pixel may or may not land on the pixel's
    centre, so the pixel may show it. `not_floor` is how much of each
    pixel is not floor (see rendered_ids()), for weighing stray ink.

    The expected maps (`expected`, `unknown`, `distance`, `may_be`)
    reach `pad` pixels beyond the frame on every side, so that an edge just
    off screen still counts as near one at the frame's border."""
    def inner(a):
        return a[pad:a.shape[0] - pad, pad:a.shape[1] - pad] if pad else a

    size = 2 * tolerance + 1
    footprint = np.ones((size, size), dtype=bool)
    accept = np.zeros(rendered.shape, dtype=bool)
    for material in range(BALL + 1):
        near = inner(ndimage.binary_dilation(expected == material, structure=footprint))
        accept |= near & (rendered == material)
    if may_be is not None:
        for material, covered in may_be.items():
            accept |= inner(covered) & (rendered == material)
    near_unknown = inner(ndimage.binary_dilation(unknown, structure=footprint))
    if msaa:
        # With MSAA, pixels on an edge are a blend of the two sides: accept a
        # blend only where two materials really meet.
        edge = ndimage.maximum_filter(expected, footprint=footprint) != ndimage.minimum_filter(expected, footprint=footprint)
        accept |= (rendered == FOREIGN) & inner(edge)
    wrong = ~accept & ~near_unknown
    wide = np.ones((9, 9), dtype=bool)
    plain = inner(~ndimage.binary_dilation((expected != FLOOR) | unknown, structure=wide))
    void_near = inner(ndimage.binary_dilation(expected == VOID, structure=wide)) | near_unknown
    if may_be is not None:
        void_near |= inner(may_be[VOID])
    expected, distance = inner(expected), inner(distance)
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
    # Stray ink: outline (or, with MSAA, a blend of it) drawn on floor with
    # nothing but floor for 4 pixels around. It comes as thin, often dotted
    # lines (each dot a cluster too small to count), which the eye still
    # reads as black scratches, so it is counted over the whole frame. With
    # MSAA it is weighed by how much of each pixel it covers: a sample's
    # triangle is shaded at the pixel's centre, which can lie outside it, so
    # far away, where the outline's soft side fades out over a pixel, a lone
    # sample can tip over INK_VISIBLE. That pixel is a quarter covered.
    stray = plain & (rendered != FLOOR) & (rendered != VOID)
    amount = float(stray.sum()) if not msaa or not_floor is None else float(not_floor[stray].sum())
    if amount >= STRAY_INK:
        ys, xs = np.nonzero(stray)
        clusters.append({"pixels": int(round(amount)), "box": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                         "drawn": "outline (stray ink)", "expected": "floor"})
    pinholes = wrong & (rendered == VOID) & ~void_near & (distance < PINHOLE_RANGE)
    ys, xs = np.nonzero(pinholes)
    for y, x in zip(ys, xs):
        clusters.append({"pixels": 1, "box": [int(x), int(y), int(x), int(y)], "drawn": "void (pinhole)",
                         "expected": NAMES[expected[y, x]]})
    return wrong, clusters


SUBPIXEL = (VOID, WALL, BACKLINE)


def subpixel_ids(info, level, pad=0):
    """For void, cut faces and back lines: the pixels each covers any part
    of (the view ray-cast again through a 3 x 3 grid of points inside each
    pixel), and their neighbours. A sliver thinner than a pixel may or may
    not land on a pixel's centre, and far away, the mesh's edges being
    chords of the true curve, its tip can run a pixel further. Seen edge on,
    a cut face's back line is often such a sliver. A crack in solid floor
    has no void anywhere near and is still a pinhole."""
    covered = {}
    for jx in (-0.4, 0.0, 0.4):
        for jy in (-0.4, 0.0, 0.4):
            ids = expected_ids(info, level, (jx, jy), pad)[0]
            for material in SUBPIXEL:
                covered[material] = covered.get(material, False) | (ids == material)
    return {m: ndimage.binary_dilation(c, structure=np.ones((3, 3), dtype=bool)) for m, c in covered.items()}


def void_within(info, level, x, y, reach=1.0, samples=31):
    """Whether real void covers any part of pixel (x, y) or of the pixels
    within `reach` of it: the view ray-cast through a fine grid of points
    over them (a tenth of a pixel apart). Along a back line, seen edge on,
    the void beyond the shell can be a sliver too thin for subpixel_ids()'s
    grid; the mesh's chords then show it a pixel off."""
    grid = np.linspace(-reach, 1.0 + reach, samples)
    gx, gy = np.meshgrid(x + grid, y + grid)
    origin, directions = pixel_rays(info, gx.reshape(-1), gy.reshape(-1))
    ids, unknown, _ = trace(info, level, origin, directions)
    return bool((ids == VOID).any() or unknown.any())


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
        expected, unknown, distance = expected_ids(info, levels[level_id], pad=BORDER)
        rendered, not_floor = rendered_ids(os.path.join(args.audit_dir, name + ".png"))
        msaa = info.get("msaa", False)
        wrong, clusters = compare(expected, unknown, rendered, distance, args.tolerance, args.min_cluster,
                                  msaa, pad=BORDER, not_floor=not_floor)
        if any(c["drawn"] in ("void (pinhole)", NAMES[WALL], NAMES[BACKLINE]) for c in clusters):
            # Before calling these wrong, make sure no sliver of the real
            # thing crosses the pixel off its centre.
            wrong, clusters = compare(expected, unknown, rendered, distance, args.tolerance, args.min_cluster,
                                      msaa, subpixel_ids(info, levels[level_id], BORDER), BORDER, not_floor)
            # And a pinhole must be in solid floor or cut face for real:
            # no void at all, looked for finely, in or right beside it.
            clusters = [c for c in clusters if c["drawn"] != "void (pinhole)"
                        or not void_within(info, levels[level_id], c["box"][0], c["box"][1], reach=0.5)]
        total_wrong += int(wrong.sum())
        summary.append({"frame": name, "wrong_pixels": int(wrong.sum()), "clusters": clusters})
        if clusters:
            failures += 1
            worst = ", ".join("%d px %s where %s should be" % (c["pixels"], c["drawn"], c["expected"]) for c in clusters[:3])
            print("FAIL %-32s %s" % (name, worst))
            if args.report:
                os.makedirs(args.report, exist_ok=True)
                save_report(os.path.join(args.report, name + ".png"), rendered,
                            expected[BORDER:-BORDER, BORDER:-BORDER], wrong, clusters)
    if args.report:
        os.makedirs(args.report, exist_ok=True)
        with open(os.path.join(args.report, "summary.json"), "w") as f:
            json.dump(summary, f, indent=1)
    print("%d frames, %d with visible errors, %d wrong pixels in all" % (len(frames), failures, total_wrong))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
