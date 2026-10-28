"""Paints the lace laid over the top of the ride sky (`RideGlass`), in chapter I's look: low poly, airbrushed, no
outlines. Persian geometry worked in rings around the zenith like a lace cap on a dome, ending in a scalloped edge
well above the horizon: a sixteen-point rosette; a ring of eight-point stars (khatam); a ring of larger stars with
low-poly flowers at their hearts; a net of diamonds; and the border, scallops of faceted segments around a flower,
with strings of glitter of different lengths hanging between them. Over the shamseh the border rises into a pointed
Persian arch, like a mihrab's, so the lace frames the medallion instead of crossing it (the app turns the lace to
put the arch over it).

Every shape is cut into flat facets (stars and flowers into triangles from their hearts, each diamond into a
four-sided pyramid, the scallops' segments into pairs of triangles), each shaded by a light from above, like the
island's low-poly meshes. The facets are airbrushed as the sky is (`make_ride_sky.py`): the lit ones opaque, the
ones in shadow melting into the grain to almost clear. Their colours are the night's own (violet, the dragon's
blue, teal, magenta, lilac, slate), dark, so the lace is part of the sky, not drawn over it; shapes are parted by a
hair of sky, never by an outline.

Where the lace's lines would be, glitter instead: specks along the shapes' edges, the rings, the arch, and strings
of them hanging from the border, with a little dust over it all. They go in their own image (`..._glitter.png`),
which the material makes twinkle, each speck in its own time.

Built in rings around the zenith (a whole number of motifs in each), the lace has no corners or seams anywhere.

Usage (numpy ships with Blender's Python; Blender itself is not used):
    /Applications/Blender.app/Contents/Resources/5.0/python/bin/python3.11 \\
        Assets/Blender/ride-sky/make_glass_sky.py /tmp/RideGlass.png
writes /tmp/RideGlass.png (the lace) and /tmp/RideGlass_glitter.png (the glitter). Same seed, same lace.
"""
import struct
import sys
import zlib

import numpy as np

OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "RideGlass.png"
GLITTER_OUTPUT = OUTPUT.rsplit(".", 1)[0] + "_glitter.png"
WIDTH, HEIGHT = 8192, 4096
# The hair of sky between two shapes (radians).
GAP = 0.0009
# Painted a band of rows at a time, to keep the memory down.
ROWS = 256
SEED = 7
# The airbrush (as the sky's, `make_ride_sky.py`): how clear its clear end is and the grain sprayed over it.
FAINT = 0.04
SPRAY = 0.2
# The light on the facets, across and down the sky: from above (towards the zenith) and a little to the side; how
# dark the facets turned away from it are and how bright those facing it.
LIGHT = np.array([-0.45, -0.9], dtype=np.float32) / np.float32(np.hypot(0.45, 0.9))
SHADE = (0.55, 1.05)

# From the zenith (degrees): the rings' edges, and the border's scallops hanging from the last one.
ROSETTE = 8
STARS = (8, 20)
BIG_STARS = (20.8, 36)
NET = (36.8, 52)
SCALLOPS_TOP = 52.8
# Motifs around each ring, and specks of glitter in each ring between the bands.
STAR_COUNT = 16
BIG_STAR_COUNT = 24
NET_COUNT = 48
SCALLOP_COUNT = 24
BEADS = 240
# The arch over the shamseh (degrees): where it stands around the sky (the app turns the lace to the shamseh), the
# height of its springing (the shamseh's heart: `ShamsehSky.elevation`), its half span, the radius of its two arcs
# (more than the half span: pointed), and its frame's width. Any point of its arcs is `ARCH_RADIUS` minus the
# arcs' offset (30 degrees) from the shamseh's heart: clear of its rays, swollen (about 27 degrees).
ARCH_AZIMUTH = 0
ARCH_SPRING = 17.2
ARCH_SPAN = 30
ARCH_RADIUS = 37.5
ARCH_FRAME = 1.4
# The strings of glitter hanging between the scallops: how many specks each, in turn, and their spacing (degrees).
PENDANTS = (4, 8, 6)
PENDANT_SPACING = 1.1
# Glitter along the lace's edges: cells of sky (radians), the share holding a speck, how near an edge (radians).
EDGE_CELL = 0.0022
EDGE_SHARE = 0.55
EDGE_REACH = 0.0011
# Dust over the lace: cells of sky (radians) and the share of them holding a speck.
DUST_CELL = 0.006
DUST_SHARE = 0.12


def game(r, g, b, darken=1.0):
    """The game's colours (linear sRGB, as in `RidePalette`), to sRGB, darkened."""
    return [darken * channel ** (1 / 2.2) for channel in (r, g, b)]


# The night's colours (the sky's own ramps), dark: each ring of the lace takes a few of them in turn.
VIOLET = game(0.36, 0.16, 0.75, 0.55)
BLUE = game(0.11, 0.1, 1, 0.5)
TEAL = game(0.03, 0.55, 0.42, 0.45)
MAGENTA = game(0.5, 0.09, 0.3, 0.55)
LILAC = game(0.65, 0.54, 0.86, 0.5)
SLATE = game(0.18, 0.15, 0.32, 0.6)
ROSETTE_COLOURS = np.array([VIOLET, LILAC], dtype=np.float32)
STAR_COLOURS = np.array([BLUE, VIOLET], dtype=np.float32)
BIG_STAR_COLOURS = np.array([VIOLET, MAGENTA, BLUE], dtype=np.float32)
FLOWER_COLOURS = np.array([LILAC, MAGENTA, TEAL], dtype=np.float32)
NET_COLOURS = np.array([SLATE, VIOLET], dtype=np.float32)
SCALLOP_COLOURS = np.array([TEAL, VIOLET, BLUE], dtype=np.float32)
FRAME_COLOUR = np.array(VIOLET, dtype=np.float32)
# The glitter: the flowers' pale gold and the petals' lilac, almost white.
GLITTER = np.array([game(0.97, 0.86, 0.53), game(0.8, 0.74, 0.95)], dtype=np.float32)


def box(px, py, half):
    """Signed distance to a square of half side `half`."""
    qx, qy = np.abs(px) - half, np.abs(py) - half
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    return outside + np.minimum(np.maximum(qx, qy), 0)


def star(px, py, half):
    """Signed distance to an eight-point star: two squares, one turned by 45 degrees."""
    r = np.float32(np.sqrt(0.5))
    return np.minimum(box(px, py, half), box((px + py) * r, (px - py) * r, half))


def pointed(px, py, outer, inner, points):
    """About the signed distance to a low-poly star: `points` straight-sided points from `inner` to `outer`."""
    rho, phi = np.hypot(px, py), np.arctan2(py, px)
    tip = np.abs((phi / (2 * np.pi) * points) % 1 - 0.5) * 2              # 1 at the points, 0 between
    return (rho - (inner + (outer - inner) * tip)) * 0.75


def sectors(px, py, count):
    """Facets cut from a shape's heart: the direction each one faces (the middle of its sector), and its parity."""
    step = 2 * np.pi / count
    index = np.floor(np.arctan2(py, px) / step)
    middle = (index + 0.5) * step
    return np.stack([np.cos(middle), np.sin(middle)], -1).astype(np.float32), (index % 2).astype(np.float32)


def ring_cell(azimuth, polar, count, centre):
    """Local flat coordinates (radians of sky) in the ring's cell: across, and down from `centre`; the cell's width
    at `centre`; and the cell's index."""
    turns = (azimuth / (2 * np.pi) + 0.5) * count
    index = np.floor(turns)
    across = (turns - index - 0.5) * 2 * np.pi / count * np.sin(polar)
    width = 2 * np.pi / count * np.sin(centre)
    return across, polar - centre, width, index


def band(polar, top, bottom):
    """Between two polar angles (degrees)."""
    return (polar >= np.radians(top)) & (polar < np.radians(bottom))


def hash01(*keys):
    """A repeatable random number 0...1 per integer key."""
    h = np.zeros_like(keys[0], dtype=np.uint64)
    for k, key in enumerate(keys):
        h ^= (key.astype(np.int64).astype(np.uint64) + np.uint64(0x9E3779B97F4A7C15 * (k + 1) % 2 ** 64))
        h = (h ^ (h >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        h = (h ^ (h >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        h ^= h >> np.uint64(31)
    return (h >> np.uint64(11)).astype(np.float64) / 2 ** 53


def specks(direction, cell_size, share, pixel, salt):
    """Glitter specks in some cells of the sky (cells of the direction, so no seam): their cover 0...1."""
    cell = np.floor(direction / cell_size)
    keys = [cell[..., k].astype(np.int64) for k in range(3)]
    salted = np.full_like(keys[0], salt)
    chance = hash01(*keys, salted)
    spot = cell + 0.25 + 0.5 * np.stack([hash01(*keys, salted + k + 1) for k in range(3)], -1)
    distance = np.linalg.norm(direction - spot * cell_size, axis=-1).astype(np.float32)
    size = (0.08 + 0.14 * hash01(*keys, salted + 9) ** 2).astype(np.float32) * cell_size
    return np.where(chance < share, np.clip((size - distance) / pixel + 0.5, 0, 1), 0).astype(np.float32)


def paint(first, last, rng):
    """The lace's colour and its glitter's for rows `first`..<`last`."""
    rows = np.arange(first, last, dtype=np.float32) + 0.5
    polar = (rows / HEIGHT * np.pi)[:, None] * np.ones((1, WIDTH), dtype=np.float32)
    azimuth = ((np.arange(WIDTH, dtype=np.float32) + 0.5) / WIDTH * 2 * np.pi - np.pi)[None, :]
    azimuth = azimuth * np.ones_like(polar)
    pixel = np.float32(np.pi / HEIGHT)
    degree = np.float32(np.radians(1))
    lace = np.zeros(polar.shape + (3,), dtype=np.float32)
    frame = np.zeros(polar.shape + (3,), dtype=np.float32)
    edges = np.full(polar.shape, np.inf, dtype=np.float32)      # distance to the nearest edge of the lace
    beads = np.full(polar.shape, np.inf, dtype=np.float32)      # signed distance to the nearest glitter bead

    # The arch: signed distance (degrees) to its opening, < 0 inside; the lace is kept outside it and its frame.
    elevation = 90 - np.degrees(polar)
    across_arch = np.abs((np.degrees(azimuth) - ARCH_AZIMUTH + 180) % 360 - 180) * np.cos(np.radians(elevation))
    centre_x = ARCH_SPAN - ARCH_RADIUS
    arc = np.hypot(across_arch - centre_x, elevation - ARCH_SPRING) - ARCH_RADIUS
    opening = np.where(elevation >= ARCH_SPRING, arc, across_arch - ARCH_SPAN).astype(np.float32)
    keep = np.clip((opening - ARCH_FRAME) * degree / pixel + 0.5, 0, 1)

    def edge(distance, where=None):
        if where is not None:
            distance = np.where(where, distance, np.inf)
        np.minimum(edges, distance, out=edges)

    def facets(sdf, colour, facing, parity, where=None, into=None):
        """A low-poly shape inside `sdf` (< 0), parted from the others by a hair of sky: each facet shaded by the
        light (`facing`: the direction it faces, across and down the sky), every other one a touch darker, and
        airbrushed: the lit facets opaque, the shaded ones melting into the grain."""
        inside = np.clip((-sdf - GAP) / pixel + 0.5, 0, 1)
        if where is not None:
            inside = inside * where
        light = np.clip((facing[..., 0] * LIGHT[0] + facing[..., 1] * LIGHT[1] + 1) / 2 - 0.08 * parity, 0, 1)
        shade = SHADE[0] + (SHADE[1] - SHADE[0]) * light
        opacity = np.clip(FAINT + (1 - FAINT) * light + rng.normal(0, SPRAY, sdf.shape), 0, 1)
        jitter = 1 + rng.normal(0, SPRAY * 0.25, sdf.shape)
        target = lace if into is None else into
        np.add(target, colour * (shade * jitter * opacity * inside)[..., None], out=target)
        edge(np.abs(sdf), where)

    def bead_row(degrees, size=0.12):
        across, down, width, _ = ring_cell(azimuth, polar, BEADS, np.radians(degrees))
        np.minimum(beads, np.hypot(across, down) - size * width, out=beads)

    # The rosette at the zenith: a sixteen-point star cut into 32 facets, a ring of glitter around.
    x, y = polar * np.cos(azimuth), polar * np.sin(azimuth)
    facing, parity = sectors(x, y, 32)
    facets(pointed(x, y, np.radians(6.8), np.radians(3.2), 16), ROSETTE_COLOURS[parity.astype(int)], facing,
           parity)
    bead_row(ROSETTE)

    # A ring of eight-point stars, each cut into 16 facets.
    centre = np.radians(sum(STARS) / 2)
    across, down, width, index = ring_cell(azimuth, polar, STAR_COUNT, centre)
    inside = band(polar, *STARS)
    facing, parity = sectors(across, down, 16)
    facets(star(across, down, 0.3 * width), STAR_COLOURS[index.astype(int) % len(STAR_COLOURS)], facing, parity,
           inside)
    bead_row(STARS[1] + 0.4)

    # Larger stars with low-poly flowers at their hearts.
    centre = np.radians(sum(BIG_STARS) / 2)
    across, down, width, index = ring_cell(azimuth, polar, BIG_STAR_COUNT, centre)
    inside = band(polar, *BIG_STARS)
    flower = pointed(across, down, 0.15 * width, 0.07 * width, 8)
    facing, parity = sectors(across, down, 16)
    facets(np.maximum(star(across, down, 0.3 * width), -flower),
           BIG_STAR_COLOURS[index.astype(int) % len(BIG_STAR_COLOURS)], facing, parity, inside)
    facets(flower, FLOWER_COLOURS[index.astype(int) % len(FLOWER_COLOURS)], facing, parity, inside)
    bead_row(BIG_STARS[1] + 0.4)

    # The net: diamonds parted by a hair of sky, each a four-sided pyramid.
    centre = np.radians(sum(NET) / 2)
    across, _, width, _ = ring_cell(azimuth, polar, NET_COUNT, centre)
    inside = band(polar, *NET)
    u = across / width
    v = (polar - np.radians(NET[0])) / width
    p, q = u + v, u - v
    dp, dq = p - np.floor(p) - 0.5, q - np.floor(q) - 0.5
    diamond = (np.maximum(np.abs(dp), np.abs(dq)) - 0.5) * width * np.sqrt(0.5)
    by_p = np.abs(dp) > np.abs(dq)
    # The facet's direction (across, down): along p it is (1, 1), along q (1, -1), signed by the side.
    facing = np.where(by_p[..., None], np.stack([np.sign(dp), np.sign(dp)], -1),
                      np.stack([np.sign(dq), -np.sign(dq)], -1)) * np.float32(np.sqrt(0.5))
    facets(diamond, NET_COLOURS[((np.floor(p) + np.floor(q)) % 2).astype(int)], facing.astype(np.float32),
           by_p.astype(np.float32), inside)
    bead_row(SCALLOPS_TOP)

    # The border: scallops hanging from the last ring, each a band of faceted segments around a low-poly flower.
    top = np.radians(SCALLOPS_TOP)
    across, down, width, index = ring_cell(azimuth, polar, SCALLOP_COUNT, top)
    radius = width / 2
    rho = np.hypot(across, down)
    hanging = down > 0
    angle = np.arctan2(across, down)                                   # 0 straight down
    segment = np.pi / 8
    start = np.floor(angle / segment)
    along = angle / segment - start
    outward = np.clip((rho - 0.72 * radius) / (0.28 * radius), 0, 1)
    upper = along > outward                                            # which triangle of the segment
    middle = (start + 0.5) * segment
    facing = np.stack([np.sin(middle), np.cos(middle)], -1) * np.where(upper, 1.0, -1.0)[..., None]
    arcs = np.maximum(rho - radius, 0.72 * radius - rho)
    spokes = np.minimum(along, 1 - along) * segment * rho
    facets(np.maximum(arcs, -spokes + GAP), SCALLOP_COLOURS[index.astype(int) % len(SCALLOP_COLOURS)],
           facing.astype(np.float32), (start % 2).astype(np.float32), hanging)
    heart_x, heart_y = across, down - 0.36 * radius
    facing, parity = sectors(heart_x, heart_y, 16)
    facets(pointed(heart_x, heart_y, 0.26 * radius, 0.12 * radius, 8),
           FLOWER_COLOURS[index.astype(int) % len(FLOWER_COLOURS)], facing, parity, hanging)
    picot_angle = np.clip(np.round(angle / (np.pi / 10)) * (np.pi / 10), -np.pi / 2, np.pi / 2)
    picot = np.hypot(across - 1.1 * radius * np.sin(picot_angle), down - 1.1 * radius * np.cos(picot_angle))
    np.minimum(beads, np.where(hanging, picot - 0.05 * radius, np.inf), out=beads)

    # Strings of glitter hanging between the scallops, of different lengths in turn, finer towards their ends.
    turns = (azimuth / (2 * np.pi) + 0.5) * SCALLOP_COUNT + 0.5
    joint = np.floor(turns)
    joint_x = (turns - joint - 0.5) * 2 * np.pi / SCALLOP_COUNT * np.sin(polar)
    count = np.choose(joint.astype(int) % len(PENDANTS), PENDANTS).astype(np.float32)
    spacing = np.radians(PENDANT_SPACING)
    step = np.clip(np.round(down / spacing), 1, count)
    np.minimum(beads, np.hypot(joint_x, down - step * spacing) - 0.16 * spacing * (1 - step / (count + 2)),
               out=beads)

    # The arch's frame, where the lace is: faceted pieces along it, glitter down its middle and inner edge; at its
    # feet, below the scallops, it melts away in the airbrush's grain.
    feet = np.radians(SCALLOPS_TOP + 7)
    fade = np.clip((feet - polar) / np.radians(3), 0, 1)
    framed = np.clip(FAINT + (1 - FAINT) * fade + rng.normal(0, SPRAY, polar.shape), 0, 1) * (fade > 0)
    frame_band = np.maximum(-opening, opening - ARCH_FRAME) * degree             # < 0 inside the band
    around = np.arctan2(elevation - ARCH_SPRING, across_arch - centre_x) * ARCH_RADIUS     # along the arc (degrees)
    pitch = 1.8
    piece = np.floor(around / pitch)
    in_piece = around / pitch - piece
    upper = in_piece > opening / ARCH_FRAME
    facing = np.stack([np.where(upper, 1.0, -1.0), np.where(piece % 2 > 0, -1.0, 1.0)], -1) * np.sqrt(0.5)
    parts = np.minimum(in_piece, 1 - in_piece) * pitch * degree
    facets(np.maximum(frame_band, -parts + GAP), FRAME_COLOUR, facing.astype(np.float32),
           (piece % 2).astype(np.float32), fade > 0, into=frame)
    beat = 0.9
    along_arch = (around - np.round(around / beat) * beat) * degree
    frame_beads = np.minimum(np.hypot(along_arch, (opening - ARCH_FRAME / 2) * degree) - 0.1 * degree,
                             np.hypot(along_arch, (opening + 0.4) * degree) - 0.07 * degree)

    # Glitter: specks along the lace's edges, the beads, the arch's, and dust; all kept out of the arch.
    direction = np.stack([np.sin(polar) * np.cos(azimuth), np.cos(polar), np.sin(polar) * np.sin(azimuth)], -1)
    along_edges = specks(direction, EDGE_CELL, EDGE_SHARE, pixel, 1) * (edges < EDGE_REACH)
    bead = np.clip(-beads / pixel + 0.5, 0, 1)
    reach = np.clip((np.radians(SCALLOPS_TOP + 14) - polar) / np.radians(14), 0, 1)
    dust = specks(direction, DUST_CELL, DUST_SHARE, pixel, 20) * reach
    sparkle = np.maximum.reduce([along_edges, bead, dust]) * keep
    sparkle = np.maximum(sparkle, np.clip(-frame_beads / pixel + 0.5, 0, 1) * framed)
    warm = hash01(np.floor(direction[..., 0] / EDGE_CELL).astype(np.int64),
                  np.floor(direction[..., 2] / EDGE_CELL).astype(np.int64)) < 0.5
    glitter = GLITTER[warm.astype(int)] * sparkle[..., None]
    lace = lace * keep[..., None] + frame * framed[..., None]
    return np.clip(lace, 0, 1), np.clip(glitter, 0, 1)


def write_png(path, image):
    """A PNG without any library: 8-bit RGB, unfiltered rows."""
    data = (image * 255 + 0.5).astype(np.uint8)
    raw = b"".join(b"\x00" + row.tobytes() for row in data)

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", data.shape[1], data.shape[0], 8, 2, 0, 0, 0)
    with open(path, "wb") as file:
        file.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 6))
                   + chunk(b"IEND", b""))


if __name__ == "__main__":
    rng = np.random.default_rng(SEED)
    # Only the top of the sky holds lace (and dust a little below it): the rows further down stay black.
    lace_rows = int(np.ceil((SCALLOPS_TOP + 16) / 180 * HEIGHT))
    painted = [paint(first, min(first + ROWS, lace_rows), rng) for first in range(0, lace_rows, ROWS)]
    below = np.zeros((HEIGHT - lace_rows, WIDTH, 3), dtype=np.float32)
    write_png(OUTPUT, np.concatenate([lace for lace, _ in painted] + [below]))
    write_png(GLITTER_OUTPUT, np.concatenate([glitter for _, glitter in painted] + [below]))
    print(f"wrote {OUTPUT} and {GLITTER_OUTPUT} ({WIDTH}x{HEIGHT})")
