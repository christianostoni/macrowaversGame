"""Writes `RideGlass.usda`: two RealityKit Shader Graph materials for the ride sky (`RideGlass` in the app).

`SkyPattern`: the lace painted by `make_glass_sky.py`, laid over the top of the sky: its colours times
`Strength`, added to the sky behind (premultiplied, opacity 0), so the painted sky stays as it is; and its glitter
(`GlitterStrength`), twinkling: a noise drifting through the sky (`TwinkleScale` cells per metre, `TwinkleSpeed`
per second, `TwinkleAmount` around `TwinkleBase`) turns each speck on and off in its own time.

`ShamsehGlass`: the shamseh's tiles as stained glass. Each tile is its glaze (`GlazeColor`) at `Ambient`, sprayed
with the airbrush's grain (`GrainScale`, `GrainAmount`) and mottled like hand-made glass (`MottleScale`,
`MottleAmount`). A light behind the medallion (`LightPosition`, world space, moved by the app) shines through:
around it the glass glows in its own colour (`HaloStrength`, out to `HaloRadius` metres), and the light itself is a
small bright point of `LightColor` (`CoreStrength`, `CoreRadius` metres).

Usage (no USD library needed; packaged with the lace's two images):
    python3 Assets/Blender/ride-sky/make_glass_material.py /tmp/RideGlass.usda
    sips -s format jpeg -s formatOptions 80 /tmp/RideGlass.png --out /tmp/RideGlass.jpg
    sips -s format jpeg -s formatOptions 80 /tmp/RideGlass_glitter.png --out /tmp/RideGlass_glitter.jpg
    cd /tmp && usdcat RideGlass.usda -o RideGlass.usdc
    usdzip RideGlass.usdz RideGlass.usdc RideGlass.jpg RideGlass_glitter.jpg
    cp /tmp/RideGlass.usdz Sources/Macrowavers/Resources/
"""
import sys

OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "RideGlass.usda"

SKY_INPUTS = """
            float inputs:Strength = 0.6
            float inputs:GlitterStrength = 1
            float inputs:TwinkleScale = 1.3
            float inputs:TwinkleSpeed = 0.6
            float inputs:TwinkleAmount = 2
            float inputs:TwinkleBase = 0.3
            asset inputs:GlassImage = @RideGlass.jpg@ (
                colorSpace = "srgb_texture"
            )
            asset inputs:GlitterImage = @RideGlass_glitter.jpg@ (
                colorSpace = "srgb_texture"
            )"""

# (name, id, inputs, output type): an input value '<Node' connects a node, '.Input' the material's input.
SKY_NODES = [
    ("UV", "ND_texcoord_vector2", [("int", "index", "0")], "float2"),
    ("Pattern", "ND_image_color3", [("asset", "file", ".GlassImage"), ("float2", "texcoord", "<UV"),
                                    ("string", "uaddressmode", '"periodic"'), ("string", "vaddressmode", '"clamp"'),
                                    ("string", "filtertype", '"linear"')], "color3f"),
    ("Faint", "ND_multiply_color3FA", [("color3f", "in1", "<Pattern"), ("float", "in2", ".Strength")], "color3f"),
    # The glitter twinkles: a noise drifting through the sky turns each speck on and off in its own time.
    ("Glitter", "ND_image_color3", [("asset", "file", ".GlitterImage"), ("float2", "texcoord", "<UV"),
                                    ("string", "uaddressmode", '"periodic"'), ("string", "vaddressmode", '"clamp"'),
                                    ("string", "filtertype", '"linear"')], "color3f"),
    ("Position", "ND_position_vector3", [("string", "space", '"object"')], "float3"),
    ("TwinklePosition", "ND_multiply_vector3FA", [("float3", "in1", "<Position"), ("float", "in2", ".TwinkleScale")],
     "float3"),
    ("Time", "ND_time_float", [], "float"),
    ("Drift", "ND_multiply_float", [("float", "in1", "<Time"), ("float", "in2", ".TwinkleSpeed")], "float"),
    ("TwinkleAt", "ND_add_vector3FA", [("float3", "in1", "<TwinklePosition"), ("float", "in2", "<Drift")], "float3"),
    ("TwinkleNoise", "ND_noise3d_float", [("float3", "position", "<TwinkleAt"),
                                          ("float", "amplitude", ".TwinkleAmount"),
                                          ("float", "pivot", ".TwinkleBase")], "float"),
    ("Twinkle", "ND_clamp_float", [("float", "in", "<TwinkleNoise"), ("float", "low", "0"), ("float", "high", "2")],
     "float"),
    ("TwinkleStrength", "ND_multiply_float", [("float", "in1", "<Twinkle"), ("float", "in2", ".GlitterStrength")],
     "float"),
    ("Sparkle", "ND_multiply_color3FA", [("color3f", "in1", "<Glitter"), ("float", "in2", "<TwinkleStrength")],
     "color3f"),
    ("Colour", "ND_add_color3", [("color3f", "in1", "<Faint"), ("color3f", "in2", "<Sparkle")], "color3f"),
    # Opacity 0 with premultiplied colour: added to the sky behind.
    ("Clear", "ND_multiply_float", [("float", "in1", ".Strength"), ("float", "in2", "0")], "float"),
    ("UnlitSurface", "ND_realitykit_unlit_surfaceshader",
     [("color3f", "color", "<Colour"), ("float", "opacity", "<Clear"), ("bool", "applyPostProcessToneMap", "0"),
      ("bool", "hasPremultipliedAlpha", "1")], "token"),
]

GLASS_INPUTS = """
            color3f inputs:GlazeColor = (0.65, 0.54, 0.86) (
                colorSpace = "lin_srgb"
            )
            float inputs:Ambient = 0.6
            float inputs:GrainScale = 260
            float inputs:GrainAmount = 0.12
            float inputs:MottleScale = 30
            float inputs:MottleAmount = 0.35
            float3 inputs:LightPosition = (0, 0, -1000)
            color3f inputs:LightColor = (1, 0.93, 0.78) (
                colorSpace = "lin_srgb"
            )
            float inputs:HaloStrength = 1.3
            float inputs:HaloRadius = 40
            float inputs:CoreStrength = 3
            float inputs:CoreRadius = 6"""

GLASS_NODES = [
    # The glass itself: the glaze, sprayed with grain and mottled.
    ("Position", "ND_position_vector3", [("string", "space", '"object"')], "float3"),
    ("GrainPosition", "ND_multiply_vector3FA", [("float3", "in1", "<Position"), ("float", "in2", ".GrainScale")],
     "float3"),
    ("Grain", "ND_noise3d_float", [("float3", "position", "<GrainPosition"), ("float", "amplitude", ".GrainAmount"),
                                   ("float", "pivot", "0")], "float"),
    ("MottlePosition", "ND_multiply_vector3FA", [("float3", "in1", "<Position"), ("float", "in2", ".MottleScale")],
     "float3"),
    ("Mottle", "ND_noise3d_float", [("float3", "position", "<MottlePosition"),
                                    ("float", "amplitude", ".MottleAmount"), ("float", "pivot", "0")], "float"),
    ("Speckle", "ND_add_float", [("float", "in1", "<Grain"), ("float", "in2", "<Mottle")], "float"),
    ("Glassiness", "ND_add_float", [("float", "in1", "<Speckle"), ("float", "in2", "1")], "float"),
    ("Base", "ND_multiply_float", [("float", "in1", "<Glassiness"), ("float", "in2", ".Ambient")], "float"),
    # The light behind: a halo through the glass, in the glass's colour, and its bright point.
    ("WorldPosition", "ND_position_vector3", [("string", "space", '"world"')], "float3"),
    ("FromLight", "ND_subtract_vector3", [("float3", "in1", "<WorldPosition"), ("float3", "in2", ".LightPosition")],
     "float3"),
    ("Distance", "ND_magnitude_vector3", [("float3", "in", "<FromLight")], "float"),
    ("HaloFar", "ND_smoothstep_float", [("float", "in", "<Distance"), ("float", "low", "0"),
                                        ("float", "high", ".HaloRadius")], "float"),
    ("HaloNear", "ND_subtract_float", [("float", "in1", "1"), ("float", "in2", "<HaloFar")], "float"),
    ("Halo", "ND_multiply_float", [("float", "in1", "<HaloNear"), ("float", "in2", "<HaloNear")], "float"),
    ("HaloLight", "ND_multiply_float", [("float", "in1", "<Halo"), ("float", "in2", ".HaloStrength")], "float"),
    ("HaloThroughGlass", "ND_multiply_float", [("float", "in1", "<HaloLight"), ("float", "in2", "<Glassiness")],
     "float"),
    ("Lit", "ND_add_float", [("float", "in1", "<Base"), ("float", "in2", "<HaloThroughGlass")], "float"),
    ("Pane", "ND_multiply_color3FA", [("color3f", "in1", ".GlazeColor"), ("float", "in2", "<Lit")], "color3f"),
    ("CoreFar", "ND_smoothstep_float", [("float", "in", "<Distance"), ("float", "low", "0"),
                                        ("float", "high", ".CoreRadius")], "float"),
    ("CoreNear", "ND_subtract_float", [("float", "in1", "1"), ("float", "in2", "<CoreFar")], "float"),
    ("Core", "ND_power_float", [("float", "in1", "<CoreNear"), ("float", "in2", "3")], "float"),
    ("CoreLight", "ND_multiply_float", [("float", "in1", "<Core"), ("float", "in2", ".CoreStrength")], "float"),
    ("Point", "ND_multiply_color3FA", [("color3f", "in1", ".LightColor"), ("float", "in2", "<CoreLight")],
     "color3f"),
    ("Colour", "ND_add_color3", [("color3f", "in1", "<Pane"), ("color3f", "in2", "<Point")], "color3f"),
    ("UnlitSurface", "ND_realitykit_unlit_surfaceshader",
     [("color3f", "color", "<Colour"), ("float", "opacity", "1"), ("bool", "applyPostProcessToneMap", "0"),
      ("bool", "hasPremultipliedAlpha", "0")], "token"),
]


def material(name, inputs, nodes):
    path = f"/RideGlass/Looks/{name}"

    def node(node_name, node_id, node_inputs, output):
        lines = [f'            def Shader "{node_name}"', "            {",
                 f'                uniform token info:id = "{node_id}"']
        for kind, key, value in node_inputs:
            if value.startswith("<"):
                lines.append(f"                {kind} inputs:{key}.connect = <{path}/{value[1:]}.outputs:out>")
            elif value.startswith("."):
                lines.append(f"                {kind} inputs:{key}.connect = <{path}.inputs:{value[1:]}>")
            else:
                lines.append(f"                {kind} inputs:{key} = {value}")
        lines += [f"                {output} outputs:out", "            }"]
        return "\n".join(lines)

    body = "\n\n".join(node(*n) for n in nodes)
    return f'''        def Material "{name}"
        {{{inputs}
            token outputs:mtlx:surface.connect = <{path}/UnlitSurface.outputs:out>
            token outputs:realitykit:vertex

{body}
        }}'''


usda = f'''#usda 1.0
(
    defaultPrim = "RideGlass"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "RideGlass"
{{
    def Scope "Looks"
    {{
{material("SkyPattern", SKY_INPUTS, SKY_NODES)}

{material("ShamsehGlass", GLASS_INPUTS, GLASS_NODES)}
    }}
}}
'''
with open(OUTPUT, "w") as file:
    file.write(usda)
print(f"wrote {OUTPUT}")
