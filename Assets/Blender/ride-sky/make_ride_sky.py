"""Paints the ride's sky dome: an equirectangular airbrush sky (deep blue overhead, a pale glow on the horizon, a
lilac haze below) with a band of far clouds around the horizon, white like the cloud asset.

Usage (numpy ships with Blender's Python; Blender itself is not used):
    /Applications/Blender/.../python3.11 Assets/Blender/ride-sky/make_ride_sky.py /tmp/RideSky.png
    sips -s format jpeg -s formatOptions 85 /tmp/RideSky.png --out Sources/Macrowavers/Resources/RideSky.jpg

The airbrush look is the shaders' own (`Airbrush_*`): a colour ramp whose position is jittered by grain, so the
bands melt into a fine speckle instead of a smooth digital gradient. The far clouds are drawn like the canopy's
low-poly puffs seen from afar: faceted polygons, lilac-grey in the middle, white at the rims. Same seed, same sky.
"""
import math
import struct
import sys
import zlib

import numpy as np

OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "RideSky.png"
WIDTH, HEIGHT = 4096, 2048
rng = np.random.default_rng(7)

# The ramp (sRGB 0...1) by elevation (degrees): zenith, high sky, low sky, horizon glow, peach, lilac haze, nadir.
SKY = [
    (90, (0.20, 0.36, 0.78)),
    (40, (0.40, 0.62, 0.95)),
    (10, (0.70, 0.84, 0.99)),
    (1, (0.92, 0.94, 0.99)),
    (-5, (0.99, 0.87, 0.86)),
    (-25, (0.80, 0.74, 0.94)),
    (-90, (0.50, 0.48, 0.82)),
]
# Grain: how far the ramp is jittered (degrees of elevation), per pixel and in soft patches.
GRAIN = 1.6
PATCHES = 2.5
# Colour speckle on top (fraction of the colour).
SPECKLE = 0.018
# Far clouds: how many clumps, where (elevation range, degrees) and how big their puffs are (degrees).
CLUMPS = 40
CLUMP_ELEVATION = (-14.0, 7.0)
PUFF_RADIUS = (1.2, 4.5)
CLOUD_SHADE = np.array((0.84, 0.85, 0.97))
CLOUD_RIM = np.array((1.0, 1.0, 1.0))


def soft_noise(cells_x, cells_y):
    """Smooth noise, -1...1, that wraps around horizontally."""
    grid = rng.uniform(-1, 1, (cells_y + 1, cells_x + 1))
    grid[:, -1] = grid[:, 0]
    xs = np.linspace(0, cells_x, WIDTH, endpoint=False)
    ys = np.linspace(0, cells_y, HEIGHT)
    x0, y0 = xs.astype(int), np.minimum(ys.astype(int), cells_y - 1)
    fx, fy = xs - x0, ys - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    top = grid[y0][:, x0] * (1 - fx) + grid[y0][:, x0 + 1] * fx
    bottom = grid[y0 + 1][:, x0] * (1 - fx) + grid[y0 + 1][:, x0 + 1] * fx
    return top * (1 - fy)[:, None] + bottom * fy[:, None]


elevation = np.linspace(90, -90, HEIGHT)[:, None] * np.ones((1, WIDTH))
jittered = (elevation + rng.normal(0, GRAIN, (HEIGHT, WIDTH))
            + PATCHES * soft_noise(32, 16) + 0.5 * PATCHES * soft_noise(128, 64))
stops = np.array([stop for stop, _ in SKY][::-1], dtype=float)
colours = np.array([colour for _, colour in SKY][::-1])
image = np.stack([np.interp(jittered, stops, colours[:, channel]) for channel in range(3)], axis=-1)

# Far clouds: clumps of round puffs, flat at the bottom, airbrushed from a lilac middle to white rims.
degrees_per_pixel = 360 / WIDTH
for _ in range(CLUMPS):
    longitude = rng.uniform(0, 360)
    base = rng.uniform(*CLUMP_ELEVATION)
    # Lower clouds look bigger (closer), the ones on the horizon small.
    nearness = 1 + 1.4 * max(0.0, -base) / abs(CLUMP_ELEVATION[0])
    for _ in range(rng.integers(4, 10)):
        radius = rng.uniform(*PUFF_RADIUS) * nearness
        centre_x = longitude + rng.normal(0, 2.2 * radius)
        centre_y = base + rng.uniform(0.2, 0.9) * radius
        # Squashed: puffs seen from the side, a little wider than tall.
        squash = 0.8
        half_x, half_y = int(radius / degrees_per_pixel) + 2, int(radius * squash / degrees_per_pixel) + 2
        row = int((90 - centre_y) / degrees_per_pixel)
        column = int(centre_x / degrees_per_pixel)
        rows = np.arange(row - half_y, row + half_y + 1)
        columns = np.arange(column - half_x, column + half_x + 1)
        rows = rows[(rows >= 0) & (rows < HEIGHT)]
        if rows.size == 0:
            continue
        dy = ((90 - rows * degrees_per_pixel) - centre_y)[:, None] / (radius * squash)
        dx = ((columns * degrees_per_pixel) - centre_x)[None, :] / radius
        # Low-poly, like the canopy's icospheres: a polygon, each facet a little lighter or darker.
        sides = int(rng.integers(6, 9))
        turn = rng.uniform(0, 2 * math.pi)
        angle = np.mod(np.arctan2(dy, dx) - turn, 2 * math.pi)
        sector = 2 * math.pi / sides
        distance = np.sqrt(dx * dx + dy * dy) * np.cos(np.mod(angle, sector) - sector / 2) / math.cos(sector / 2)
        facets = rng.uniform(-0.12, 0.12, sides + 1)
        facet = np.where(distance < 0.45, facets[-1], facets[np.minimum((angle / sector).astype(int), sides - 1)])
        # Below the clump's base: nothing (flat bottoms).
        below = (90 - rows * degrees_per_pixel)[:, None] < base
        inside = (distance < 1) & ~below
        rim = np.clip(distance, 0, 1) ** 0.8 + facet + rng.normal(0, 0.12, distance.shape)
        rim = np.clip(rim, 0, 1)[..., None]
        colour = CLOUD_SHADE * (1 - rim) + CLOUD_RIM * rim
        # Soft airbrushed edge.
        alpha = np.clip((1 - distance) / 0.04, 0, 1)[..., None] * inside[..., None]
        wrapped = columns % WIDTH
        block = image[rows[:, None], wrapped[None, :]]
        image[rows[:, None], wrapped[None, :]] = block * (1 - alpha) + colour * alpha

image *= 1 + rng.normal(0, SPECKLE, (HEIGHT, WIDTH, 1))
pixels = (np.clip(image, 0, 1) * 255 + 0.5).astype(np.uint8)


def write_png(path, rgb):
    height, width, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as file:
        file.write(b"\x89PNG\r\n\x1a\n")
        file.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        file.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        file.write(chunk(b"IEND", b""))


write_png(OUTPUT, pixels)
print(f"Sky written to {OUTPUT} ({WIDTH}x{HEIGHT})")
