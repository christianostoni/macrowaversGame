"""Renders the game's loading animation: the stone dragon tangling into its knot and untangling into a ring, flat (2D).

Usage, from the repository's root:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/loading-dragon/make_loading_animation.py -- \
        Sources/Macrowavers/Resources/StoneDragon.usdz Sources/Macrowavers/Resources/DragonLoading.png

It replaces the system spinner wherever the game loads (`DragonLoadingView`: the launch window while the island is
built, the ride's space while the sky is built). What the script does, and why:
- Imports the game's own dragon (`StoneDragon.usdz`: `Head` and the stones `Stone_00` ... `Stone_18`, each with its
  origin at its centre, +Z along the body towards the tail, +Y up; the head's +Z is the snout) and keeps every
  stone's distance from the head along the body, as the game does (`StoneDragonLayout`).
- Lays the body along a curve that goes from the puzzle's knot (`TangleShape.trefoil`, the same parametric curve and
  the same gap between head and tail) to an open ring (`TangleShape.loop`) and back, holding each a moment, while the
  whole dragon turns once around: a loop with no seam. Each frame the curve is resampled to the body's length, so the
  dragon never stretches; the knot's height decides who passes over at a crossing.
- Draws it flat, like a 2D drawing: an orthographic camera straight above (closer to the knot, which is far smaller
  than the ring), Blender's Workbench with flat light (no
  shading), each part one colour and a dark outline. The colours are the dragon's own: its stones run from the head's
  orange through magenta to violet (the materials' body ramp), the horns blue, the outline the ramp's darkest navy.
- Writes every frame on a transparent background and lays them out in one sprite sheet, `COLUMNS` frames a row,
  left to right then top to bottom: `DragonLoadingView` plays it at `FPS`.
"""
import math
import os
import sys
import tempfile

import bpy
import numpy
from mathutils import Matrix, Vector

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <StoneDragon.usdz> <sprite sheet .png>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)

# The loop: frames, their rate, the sprite sheet's layout and each frame's size (px). DragonLoadingView reads the same.
FRAMES = 72
FPS = 24
COLUMNS = 9
FRAME_SIZE = 192
# Share of the loop spent holding the knot, untangling, holding the ring (the rest tangles it again).
HOLD_KNOT, UNTANGLE, HOLD_RING = 0.12, 0.38, 0.12
# The body's length from the head's centre to the tail stone's (m, the asset's) and the knot's height, exaggerated a
# little so the crossings read clearly from above.
HEIGHT = 1.6
# The ends of the open curves (radians), as `TangleShape.positions`: a gap between the head and the tail.
START, GAP = 0.2, 0.35
SAMPLES = 1200

# Linear colours (Workbench writes them as they are with the Standard view transform).
ORANGE = (1.0, 0.35, 0.05)
MAGENTA = (0.9, 0.05, 0.45)
VIOLET = (0.25, 0.1, 1.0)
BLUE = (0.11, 0.1, 1.0)
IVORY = (1.0, 0.93, 0.8)
NAVY = (0.016, 0.017, 0.044)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=False, import_cameras=False, import_lights=False)
objects = bpy.data.objects
head = objects["Head"]
stones = [objects[f"Stone_{index:02d}"] for index in range(19)]
for marker in ("mouth", "nostrils"):
    if marker in objects:
        bpy.data.objects.remove(objects[marker])


def material(name, colour):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*colour, 1)
    return result


def mix(first, second, amount):
    return tuple(a + (b - a) * amount for a, b in zip(first, second))


def ramp(amount):
    """The body's colours from the head (0) to the tail (1)."""
    return mix(ORANGE, MAGENTA, amount * 2) if amount < 0.5 else mix(MAGENTA, VIOLET, amount * 2 - 1)


def paint(entity, colour_material):
    entity.data.materials.clear()
    entity.data.materials.append(colour_material)


for part in head.children_recursive:
    if part.type != "MESH":
        continue
    colour = {"Horns": BLUE, "Teeth": IVORY}.get(part.name, ORANGE)
    paint(part, material(f"Flat_{part.name}", colour))
for index, stone in enumerate(stones):
    paint(stone, material(f"Flat_{stone.name}", ramp((index + 1) / len(stones))))

# Each stone's distance from the head along the body in the rest pose, and its size.
centres = [head.matrix_world.translation.copy()] + [stone.matrix_world.translation.copy() for stone in stones]
arcs = [0.0]
for previous, centre in zip(centres, centres[1:]):
    arcs.append(arcs[-1] + (centre - previous).length)
BODY_LENGTH = arcs[-1]
scales = {entity.name: entity.matrix_world.to_scale() for entity in [head] + stones}


def trefoil(angle):
    """`TangleShape.trefoil` in Blender's axes: (x, z) seen from above becomes (x, y), its height z."""
    return Vector((math.sin(angle) + 2 * math.sin(2 * angle),
                   math.cos(angle) - 2 * math.cos(2 * angle),
                   -math.sin(3 * angle) * HEIGHT))


def curve_length(curve):
    end = START + 2 * math.pi - GAP
    points = [curve(START + (end - START) * sample / SAMPLES) for sample in range(SAMPLES + 1)]
    return sum((point - previous).length for previous, point in zip(points, points[1:]))


# The ring is as long as the knot: halfway between the two, the body neither bunches up nor spreads out.
RING_RADIUS = curve_length(trefoil) / (2 * math.pi - GAP)


def ring(angle):
    """`TangleShape.loop`: a circle open between the head and the tail."""
    return Vector((math.sin(angle), math.cos(angle), 0)) * RING_RADIUS


def smooth(value):
    value = min(max(value, 0), 1)
    return value * value * value * (value * (value * 6 - 15) + 10)


def untangled(phase):
    """0 (the knot) ... 1 (the ring) at `phase` (0...1) through the loop."""
    if phase < HOLD_KNOT:
        return 0
    if phase < HOLD_KNOT + UNTANGLE:
        return smooth((phase - HOLD_KNOT) / UNTANGLE)
    if phase < HOLD_KNOT + UNTANGLE + HOLD_RING:
        return 1
    return 1 - smooth((phase - HOLD_KNOT - UNTANGLE - HOLD_RING) / (1 - HOLD_KNOT - UNTANGLE - HOLD_RING))


def body(phase):
    """The curve at `phase`, resampled to the body's length: a point and a tangent at each of `arcs`."""
    amount = untangled(phase)
    end = START + 2 * math.pi - GAP
    dense = []
    for sample in range(SAMPLES + 1):
        angle = START + (end - START) * sample / SAMPLES
        dense.append(trefoil(angle).lerp(ring(angle), amount))
    lengths = [0.0]
    for previous, point in zip(dense, dense[1:]):
        lengths.append(lengths[-1] + (point - previous).length)
    scale = BODY_LENGTH / lengths[-1]
    # Centred on the curve's middle, turned once around over the loop.
    turn = Matrix.Rotation(-2 * math.pi * phase, 3, "Z")
    middle = sum(dense, Vector()) / len(dense)
    result = []
    cursor = 0
    for arc in arcs:
        distance = arc / scale
        while cursor < len(lengths) - 2 and lengths[cursor + 1] < distance:
            cursor += 1
        fraction = (distance - lengths[cursor]) / max(lengths[cursor + 1] - lengths[cursor], 1e-9)
        point = dense[cursor].lerp(dense[cursor + 1], fraction)
        tangent = (dense[cursor + 1] - dense[cursor]).normalized()
        result.append((turn @ ((point - middle) * scale), turn @ tangent))
    return result


def place(entity, position, along):
    """`entity`'s +Z along `along`, +Y as close to up (the camera) as it can, its own scale kept."""
    up = Vector((0, 0, 1))
    up = (up - along * up.dot(along)).normalized()
    side = up.cross(along)
    scale = scales[entity.name]
    basis = Matrix((side * scale.x, up * scale.y, along * scale.z)).transposed()
    world = basis.to_4x4()
    world.translation = position
    entity.matrix_world = world


def pose(phase):
    points = body(phase)
    # The head's snout points away from the body.
    place(head, points[0][0], -points[0][1])
    for stone, (position, tangent) in zip(stones, points[1:]):
        place(stone, position, tangent)


# The camera straight above. The knot is far smaller than the ring (the same body, bunched up): the camera comes
# closer to it, by `ZOOM` of the difference, so it reads at a spinner's size and the dragon still seems to breathe.
ZOOM = 0.6
MARGIN = 0.18


def reach(phase):
    return max(max(abs(point.x), abs(point.y)) for point, _ in body(phase))


widest = max(reach(frame / FRAMES) for frame in range(FRAMES))
camera_data = bpy.data.cameras.new("Camera")
camera_data.type = "ORTHO"
camera = bpy.data.objects.new("Camera", camera_data)
camera.location = (0, 0, 10)
scene = bpy.context.scene
scene.collection.objects.link(camera)
scene.camera = camera

# Flat, outlined, transparent: a 2D drawing.
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_object_outline = True
scene.display.shading.object_outline_color = NAVY
scene.display.render_aa = "16"
scene.view_settings.view_transform = "Standard"
scene.render.film_transparent = True
scene.render.resolution_x = FRAME_SIZE
scene.render.resolution_y = FRAME_SIZE
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

rows = math.ceil(FRAMES / COLUMNS)
sheet = numpy.zeros((rows * FRAME_SIZE, COLUMNS * FRAME_SIZE, 4), dtype=numpy.float32)
folder = tempfile.mkdtemp(prefix="dragon-loading-")
for frame in range(FRAMES):
    pose(frame / FRAMES)
    camera_data.ortho_scale = 2 * (widest + (reach(frame / FRAMES) - widest) * ZOOM + MARGIN)
    path = os.path.join(folder, f"frame_{frame:03d}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(path)
    pixels = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(FRAME_SIZE, FRAME_SIZE, 4)
    bpy.data.images.remove(image)
    os.remove(path)
    # Blender's rows go bottom to top; the sheet's top row is the first.
    row, column = divmod(frame, COLUMNS)
    top = (rows - 1 - row) * FRAME_SIZE
    sheet[top:top + FRAME_SIZE, column * FRAME_SIZE:(column + 1) * FRAME_SIZE] = pixels
os.rmdir(folder)

output = bpy.data.images.new("DragonLoading", COLUMNS * FRAME_SIZE, rows * FRAME_SIZE, alpha=True)
output.pixels = sheet.ravel()
output.filepath_raw = OUTPUT
output.file_format = "PNG"
output.save()
print(f"{FRAMES} frames, {COLUMNS} x {rows} of {FRAME_SIZE} px at {FPS} fps -> {OUTPUT}")
