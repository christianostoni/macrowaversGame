"""Paints the ride's sky dome: an equirectangular airbrush night, almost black, a faint glow of colour on the
horizon, with stars, sparkles, far lantern lights and Persian clouds around the horizon: arches of
round lobes with long tails, in the game's colours, without outlines. Every cloud shape is a gradient from almost
clear to fully opaque, sprayed with grain like the fruit's airbrush.

Usage (numpy ships with Blender's Python; Blender itself is not used):
    /Applications/Blender/.../python3.11 Assets/Blender/ride-sky/make_ride_sky.py /tmp/RideSky.png
    sips -s format jpeg -s formatOptions 85 /tmp/RideSky.png --out Sources/Macrowavers/Resources/RideSky.jpg

The airbrush look is the shaders' own (`Airbrush_*`): a colour ramp whose position is jittered by grain, so the
bands melt into a fine speckle instead of a smooth digital gradient. Same seed, same sky.
"""
import math
import struct
import sys
import zlib

import numpy as np

OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "RideSky.png"
WIDTH, HEIGHT = 4096, 2048
DEGREES_PER_PIXEL = 360 / WIDTH
rng = np.random.default_rng(11)

# The game's own colours (the island's airbrush materials, linear sRGB, as in `RidePalette`), to sRGB.
def game(r, g, b, darken=1.0):
    return tuple(darken * channel ** (1 / 2.2) for channel in (r, g, b))


NIGHT = game(0.01, 0.01, 0.03)
SLATE = game(0.18, 0.15, 0.32)
VIOLET = game(0.36, 0.16, 0.75)
LILAC = game(0.65, 0.54, 0.86)
DRAGON_BLUE = game(0.11, 0.1, 1)
TEAL = game(0.03, 0.55, 0.42)
MINT = game(0.47, 0.75, 0.68)
GOLD = game(0.95, 0.75, 0.15)
PALE_GOLD = game(0.97, 0.86, 0.53)
MAGENTA = game(0.5, 0.09, 0.3)
PINK = game(0.98, 0.49, 0.81)

# The ramps (sRGB 0...1) by elevation (degrees): almost black, with a faint glow on the horizon, of the purple rocks
# and the pomegranate's pink on the side of the sunset, of the dragon's blue and the teal grass on the far side.
WARM = [
    (90, game(0.01, 0.01, 0.03, 0.12)),
    (30, game(0.18, 0.15, 0.32, 0.1)),
    (10, game(0.36, 0.16, 0.75, 0.16)),
    (3, game(0.5, 0.09, 0.3, 0.42)),
    (0, game(0.98, 0.49, 0.81, 0.5)),
    (-5, game(0.5, 0.09, 0.3, 0.3)),
    (-20, game(0.36, 0.16, 0.75, 0.1)),
    (-90, game(0.01, 0.01, 0.03, 0.1)),
]
COOL = [
    (90, game(0.01, 0.01, 0.03, 0.12)),
    (30, game(0.11, 0.1, 1, 0.08)),
    (10, game(0.11, 0.1, 1, 0.14)),
    (3, game(0.03, 0.55, 0.42, 0.28)),
    (0, game(0.47, 0.75, 0.68, 0.36)),
    (-5, game(0.03, 0.55, 0.42, 0.2)),
    (-20, game(0.11, 0.1, 1, 0.09)),
    (-90, game(0.01, 0.01, 0.03, 0.1)),
]
# Where the sun went down (longitude, degrees; 0 is the image's left edge, the ride starts looking at 180).
SUNSET = 200
# Grain: how far the ramp is jittered (degrees of elevation), per pixel and in soft patches; colour speckle on top.
GRAIN = 1.6
PATCHES = 2.5
SPECKLE = 0.02

STARS = 2600
# Big four-pointed sparkles, and their colours.
SPARKLES = 70
SPARKLE_COLOURS = [np.array(PALE_GOLD), np.array(PINK), np.array(MINT), np.array((1.0, 1.0, 1.0))]
LIGHTS = 140

# Persian clouds: how many, where (elevation of their base) and how long (degrees); the colour pairs their
# gradients run through (from the clear end to the opaque one), the game's.
CLOUDS = 26
CLOUD_BASE = (-7.0, 20.0)
CLOUD_LENGTH = (12.0, 34.0)
CLOUD_COLOURS = [
    (VIOLET, PINK), (DRAGON_BLUE, MINT), (MAGENTA, PALE_GOLD), (TEAL, LILAC), (VIOLET, GOLD), (DRAGON_BLUE, PINK),
]
# The airbrush gradient: how clear its clear end is, and the grain sprayed over it (like the fruit's).
FAINT = 0.04
SPRAY = 0.2


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


def ramp(stops, elevation):
    positions = np.array([stop for stop, _ in stops][::-1], dtype=float)
    colours = np.array([colour for _, colour in stops][::-1])
    return np.stack([np.interp(elevation, positions, colours[:, channel]) for channel in range(3)], axis=-1)


def warmth(longitude):
    """1 facing the sunset, 0 on the far side."""
    return (0.5 + 0.5 * np.cos(np.radians(longitude - SUNSET))) ** 1.5


def block(longitude, elevation, half_width, half_height):
    """The pixels around a point (rows, wrapped columns) and their offsets from it in degrees (x shrunk with the
    elevation, so shapes stay round on the dome)."""
    row, column = int((90 - elevation) / DEGREES_PER_PIXEL), int(longitude / DEGREES_PER_PIXEL)
    stretch = 1 / max(math.cos(math.radians(elevation)), 0.2)
    half_x = int(half_width * stretch / DEGREES_PER_PIXEL) + 2
    half_y = int(half_height / DEGREES_PER_PIXEL) + 2
    rows = np.arange(max(row - half_y, 0), min(row + half_y + 1, HEIGHT))
    columns = np.arange(column - half_x, column + half_x + 1)
    dy = (90 - rows * DEGREES_PER_PIXEL - elevation)[:, None] * np.ones((1, columns.size))
    dx = ((columns * DEGREES_PER_PIXEL - longitude) / stretch)[None, :] * np.ones((rows.size, 1))
    return rows, columns % WIDTH, dx, dy


def paint(rows, columns, colour, alpha):
    region = image[rows[:, None], columns[None, :]]
    image[rows[:, None], columns[None, :]] = region * (1 - alpha[..., None]) + colour * alpha[..., None]


elevation = np.linspace(90, -90, HEIGHT)[:, None] * np.ones((1, WIDTH))
longitude = np.linspace(0, 360, WIDTH, endpoint=False)[None, :] * np.ones((HEIGHT, 1))
jittered = (elevation + rng.normal(0, GRAIN, (HEIGHT, WIDTH))
            + PATCHES * soft_noise(32, 16) + 0.5 * PATCHES * soft_noise(128, 64))
side = warmth(longitude)[..., None]
image = ramp(COOL, jittered) * (1 - side) + ramp(WARM, jittered) * side

# Stars: more and brighter higher up, a few golden ones with a glint.
for _ in range(STARS):
    star_elevation = math.degrees(math.asin(rng.uniform(math.sin(math.radians(6)), 1)))
    star_longitude = rng.uniform(0, 360)
    height = (star_elevation - 6) / 84
    brightness = rng.uniform(0.25, 0.7) * (0.4 + 0.6 * height) * (1 - 0.6 * warmth(star_longitude))
    is_gold = rng.uniform() < 0.06
    size = rng.uniform(0.06, 0.12) * (1.8 if is_gold else 1)
    rows, columns, dx, dy = block(star_longitude, star_elevation, size * 6, size * 6)
    distance = np.sqrt(dx * dx + dy * dy)
    alpha = np.clip(1 - distance / size, 0, 1) * brightness
    if is_gold:
        glint = np.clip(1 - np.minimum(np.abs(dx), np.abs(dy)) / 0.03, 0, 1) * np.clip(1 - distance / (size * 6), 0, 1)
        alpha = np.maximum(alpha, glint * brightness)
    colour = SPARKLE_COLOURS[int(rng.integers(len(SPARKLE_COLOURS)))] if is_gold else np.array((0.95, 0.95, 1.0))
    paint(rows, columns, colour, np.clip(alpha * 1.6, 0, 1))

# Four-pointed sparkles: thin rays crossing in a soft glow.
for _ in range(SPARKLES):
    star_elevation = math.degrees(math.asin(rng.uniform(math.sin(math.radians(10)), 0.95)))
    star_longitude = rng.uniform(0, 360)
    size = rng.uniform(0.6, 1.6)
    colour = SPARKLE_COLOURS[int(rng.integers(len(SPARKLE_COLOURS)))]
    rows, columns, dx, dy = block(star_longitude, star_elevation, size, size)
    # An astroid: four sharp points along the axes.
    shape = (np.abs(dx) / size) ** 0.45 + (np.abs(dy) / size) ** 0.45
    rays = np.clip((1 - shape) / 0.12, 0, 1)
    glow = 0.5 * np.clip(1 - np.sqrt(dx * dx + dy * dy) / (size * 0.35), 0, 1) ** 2
    paint(rows, columns, colour, np.clip(rays + glow, 0, 1) * rng.uniform(0.6, 1))

# Far lantern lights, low over the horizon.
for _ in range(LIGHTS):
    light_longitude, light_elevation = rng.uniform(0, 360), rng.uniform(-6, 9)
    size = rng.uniform(0.08, 0.2)
    rows, columns, dx, dy = block(light_longitude, light_elevation, size * 5, size * 5)
    distance = np.sqrt(dx * dx + dy * dy)
    glow = np.clip(1 - distance / (size * 5), 0, 1) ** 2 * 0.45 + np.clip(1 - distance / size, 0, 1)
    colour = np.array([GOLD, PINK, MINT, LILAC][int(rng.integers(4))])
    paint(rows, columns, colour, np.clip(glow, 0, 1))


def airbrush(t):
    """Opacity along a gradient `t` (0 almost clear ... 1 opaque), sprayed with grain like the fruit's airbrush:
    a fine speckle that melts the gradient instead of a smooth digital fade."""
    return np.clip(FAINT + (1 - FAINT) * t + rng.normal(0, SPRAY, t.shape), 0, 1)


def gradient(colours, t):
    """The colour along `t` from the first colour to the second, jittered by the same grain."""
    jittered = np.clip(t + rng.normal(0, SPRAY * 0.5, t.shape), 0, 1)[..., None]
    return np.array(colours[0]) * (1 - jittered) + np.array(colours[1]) * jittered


def colour_cloud(cloud_longitude, base, length):
    """A Persian cloud without outlines: an arch of round lobes on a flat base, each lobe its own gradient from
    almost clear at the bottom to opaque at the top, the outer ones under the middle ones, and a long tail on either
    side, opaque by the cloud and clearing towards its tip."""
    lobes = int(rng.integers(3, 7))
    radii = length / lobes * rng.uniform(0.6, 0.85, lobes)
    radii *= 1 - 0.35 * np.abs(np.linspace(-1, 1, lobes))
    xs = np.linspace(-length / 2 + radii[0], length / 2 - radii[-1], lobes) + rng.normal(0, 0.4, lobes)
    # An arch: the middle lobes ride higher, over the others.
    ys = radii * np.minimum(rng.uniform(0.3, 0.55, lobes) + 0.4 * (1 - np.abs(np.linspace(-1, 1, lobes))), 0.8)
    tails = [(sign, rng.uniform(0.6, 1.3) * length, rng.uniform(0.25, 0.4) * radii.min()) for sign in (-1, 1)]
    top = float((ys + radii).max())
    span = length / 2 + max(tail for _, tail, _ in tails)
    rows, columns, dx, dy = block(cloud_longitude, base, span, top + 2)
    colours = CLOUD_COLOURS[int(rng.integers(len(CLOUD_COLOURS)))]

    # The tails first, under the lobes.
    for sign, tail_length, thickness in tails:
        # From under the end lobe, fading in, out to the tip, clearing.
        start = sign * (length / 2 - radii[0 if sign < 0 else -1] * 1.2)
        along = (dx - start) * sign
        taper = np.clip(1 - along / tail_length, 0, 1)
        fade_in = np.clip(along / (0.2 * tail_length), 0, 1)
        centre = thickness * 1.2 + 0.5 * thickness * np.sin(along / tail_length * 2 * math.pi)
        inside = (np.abs(dy - centre) < thickness * taper) & (along > 0)
        edge = np.clip((thickness * taper - np.abs(dy - centre)) / 0.08, 0, 1)
        paint(rows, columns, gradient(colours, taper), airbrush(taper ** 1.5 * fade_in) * edge * inside)

    # Lobes from the smallest (outer, behind) to the biggest (the arch's middle, in front).
    for index in np.argsort(radii):
        cx, cy, radius = xs[index], ys[index], radii[index]
        distance = np.sqrt((dx - cx) ** 2 + (dy - cy) ** 2) - radius
        edge = np.clip(-distance / 0.08, 0, 1) * (dy > 0)
        t = np.clip(dy / (cy + radius), 0, 1) ** 0.8
        paint(rows, columns, gradient(colours, t), airbrush(t) * edge)


for _ in range(CLOUDS):
    cloud_base = rng.uniform(*CLOUD_BASE)
    # Lower clouds look bigger (closer).
    nearness = 1 + 0.8 * max(0.0, -cloud_base) / abs(CLOUD_BASE[0])
    colour_cloud(rng.uniform(0, 360), cloud_base, rng.uniform(*CLOUD_LENGTH) * nearness)

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
