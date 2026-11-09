"""Writes `ElixirLiquid.usda`: the RealityKit Shader Graph material of the elixir's liquid (`ElixirRig` in the app).

The liquid is the design team's whole liquid, the inside of the round flask, cut by a level surface: what lies above
the plane `LevelNormal` · position + `LevelOffset` = 0 (world space, set by the app every frame) is not drawn, with a
soft edge `Edge` metres wide. The app keeps the plane level with the world as the flask wobbles and tips to pour, so
the liquid stays in the glass and falls to its low side like a liquid, instead of turning with the glass like a solid.

Its look is the website's (`elixir.js`): lit from within in its colour (`Color`, linear, brighter by `Glow`), brighter
towards its rims where it curves away from the eye (the airbrush's facing, squared), with a faint white sheen there,
and a little see-through (`Opacity`). Drawn from both sides, the inside seen through the cut reads as the surface.

Usage (no USD library needed):
    python3 Assets/Blender/elixir-flask/make_liquid_material.py /tmp/ElixirLiquid.usda
    cd /tmp && usdcat ElixirLiquid.usda -o ElixirLiquid.usdc
    usdzip ElixirLiquid.usdz ElixirLiquid.usdc
    cp /tmp/ElixirLiquid.usdz Sources/Macrowavers/Resources/
"""
import sys

OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "ElixirLiquid.usda"
PATH = "/ElixirLiquid/Looks/Liquid"

INPUTS = """
            color3f inputs:Color = (0.79, 0.03, 0.07) (
                colorSpace = "lin_srgb"
            )
            float inputs:Glow = 0.35
            float inputs:Opacity = 0.9
            float3 inputs:LevelNormal = (0, 1, 0)
            float inputs:LevelOffset = 1000
            float inputs:Edge = 0.0015"""

# (name, id, inputs, output type): an input value '<Node' connects a node, '.Input' the material's input. Every node
# here already runs on the device in the team's other graphs (the airbrush's facing, the shamseh glass's world space).
NODES = [
    # How far the surface turns from the eye: 0 seen straight on, 1 at the rims (the airbrush's Facing), squared.
    ("Normal", "ND_normal_vector3", [("string", "space", '"world"')], "float3"),
    ("ViewDirection", "ND_realitykit_viewdirection_vector3", [("string", "space", '"world"')], "float3"),
    ("NdotV", "ND_dotproduct_vector3", [("float3", "in1", "<Normal"), ("float3", "in2", "<ViewDirection")], "float"),
    ("AbsNdotV", "ND_absval_float", [("float", "in", "<NdotV")], "float"),
    ("Facing", "ND_subtract_float", [("float", "in1", "1"), ("float", "in2", "<AbsNdotV")], "float"),
    ("Rim", "ND_power_float", [("float", "in1", "<Facing"), ("float", "in2", "2")], "float"),
    # Its colour, (0.55 + 0.9 Glow) × (0.75 + 0.8 Rim) times as bright, plus a sheen of 0.12 Rim.
    ("GlowLift", "ND_multiply_float", [("float", "in1", ".Glow"), ("float", "in2", "0.9")], "float"),
    ("Lit", "ND_add_float", [("float", "in1", "<GlowLift"), ("float", "in2", "0.55")], "float"),
    ("RimLift", "ND_multiply_float", [("float", "in1", "<Rim"), ("float", "in2", "0.8")], "float"),
    ("Shade", "ND_add_float", [("float", "in1", "<RimLift"), ("float", "in2", "0.75")], "float"),
    ("Brightness", "ND_multiply_float", [("float", "in1", "<Lit"), ("float", "in2", "<Shade")], "float"),
    ("Body", "ND_multiply_color3FA", [("color3f", "in1", ".Color"), ("float", "in2", "<Brightness")], "color3f"),
    ("Sheen", "ND_multiply_float", [("float", "in1", "<Rim"), ("float", "in2", "0.12")], "float"),
    ("SheenColour", "ND_multiply_color3FA", [("color3f", "in1", "(1, 1, 1)"), ("float", "in2", "<Sheen")],
     "color3f"),
    ("Colour", "ND_add_color3", [("color3f", "in1", "<Body"), ("color3f", "in2", "<SheenColour")], "color3f"),
    # The level: above the plane, nothing; a soft edge `Edge` wide.
    ("WorldPosition", "ND_position_vector3", [("string", "space", '"world"')], "float3"),
    ("Along", "ND_dotproduct_vector3", [("float3", "in1", "<WorldPosition"), ("float3", "in2", ".LevelNormal")],
     "float"),
    ("AboveBy", "ND_add_float", [("float", "in1", "<Along"), ("float", "in2", ".LevelOffset")], "float"),
    ("Above", "ND_smoothstep_float", [("float", "in", "<AboveBy"), ("float", "low", "0"), ("float", "high", ".Edge")],
     "float"),
    ("Below", "ND_subtract_float", [("float", "in1", "1"), ("float", "in2", "<Above")], "float"),
    ("Coverage", "ND_multiply_float", [("float", "in1", "<Below"), ("float", "in2", ".Opacity")], "float"),
    ("UnlitSurface", "ND_realitykit_unlit_surfaceshader",
     [("color3f", "color", "<Colour"), ("float", "opacity", "<Coverage"), ("bool", "applyPostProcessToneMap", "0"),
      ("bool", "hasPremultipliedAlpha", "0")], "token"),
]


def node(node_name, node_id, node_inputs, output):
    lines = [f'            def Shader "{node_name}"', "            {",
             f'                uniform token info:id = "{node_id}"']
    for kind, key, value in node_inputs:
        if value.startswith("<"):
            lines.append(f"                {kind} inputs:{key}.connect = <{PATH}/{value[1:]}.outputs:out>")
        elif value.startswith("."):
            lines.append(f"                {kind} inputs:{key}.connect = <{PATH}.inputs:{value[1:]}>")
        else:
            lines.append(f"                {kind} inputs:{key} = {value}")
    lines += [f"                {output} outputs:out", "            }"]
    return "\n".join(lines)


body = "\n\n".join(node(*n) for n in NODES)
usda = f'''#usda 1.0
(
    defaultPrim = "ElixirLiquid"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "ElixirLiquid"
{{
    def Scope "Looks"
    {{
        def Material "Liquid"
        {{{INPUTS}
            token outputs:mtlx:surface.connect = <{PATH}/UnlitSurface.outputs:out>
            token outputs:realitykit:vertex

{body}
        }}
    }}
}}
'''
with open(OUTPUT, "w") as file:
    file.write(usda)
print(f"wrote {OUTPUT}")
