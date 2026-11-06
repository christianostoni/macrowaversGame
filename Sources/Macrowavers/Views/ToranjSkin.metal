#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The game's airbrush shader (the design team's `Airbrush_*` materials) on its name, ترنج (`ToranjTitleView`): the
// letters and dots wear the pomegranate's skin (`Airbrush_Skin`, Pomegranate.usdz), the leaf the fruits' leaf
// (`Airbrush_Leaf`, Apple.usdz and Orange.usdz). On a fruit the shader reads how far the surface turns away from
// the eye and runs a four-colour ramp along it, darker where it faces the eye, with a fine grain. The letters are
// flat, so the turn comes from how deep a point lies inside its shape: the layer arrives as the shape in white,
// blurred, and its alpha says how deep (0.5 on the edge, 1 deep inside), read as a dome's slope.

namespace {
    float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

    /// Smooth value noise in [-1, 1], like MaterialX's noise3d sliced flat.
    float valueNoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3 - 2 * f);
        float bottom = mix(hash(i), hash(i + float2(1, 0)), u.x);
        float top = mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x);
        return mix(bottom, top, u.y) * 2 - 1;
    }

    float3 linearToSRGB(float3 c) {
        c = max(c, 0);
        return select(1.055 * pow(c, 1 / 2.4) - 0.055, 12.92 * c, c <= 0.0031308);
    }
}

/// `grainSize`: the grain's cell in points. `grainAmount`: how strong it is (the fruits' 0.25 reads as coarse
/// blotches on a flat shape, a pixel wide at most). `edgePower`: the material's EdgePower. `stops`: its four ramp
/// colours (linear sRGB, 12 floats), at 0, 0.289, 0.732 and 1 as in every `Airbrush_*`.
[[ stitchable ]] half4 airbrush(float2 position, half4 color, float grainSize, float grainAmount, float edgePower,
                                device const float *stops, int count) {
    if (count < 12) { return color; }
    float3 s0 = float3(stops[0], stops[1], stops[2]), s1 = float3(stops[3], stops[4], stops[5]);
    float3 s2 = float3(stops[6], stops[7], stops[8]), s3 = float3(stops[9], stops[10], stops[11]);
    // How deep inside the shape, as a dome: 0 on the edge (the rim), 1 in the middle (facing the eye). A letter is
    // flat and wide where a fruit curves away: its middle stops short of the fruit's black core (`r` 0.3), or the big
    // fruit of ج would be a black disc.
    float depth = saturate((float(color.a) - 0.5) * 2);
    float r = 1 - 0.7 * depth;
    float facing = 1 - sqrt(max(1 - r * r, 0.0));
    float f = saturate(pow(facing, edgePower) + grainAmount * valueNoise(position / grainSize));

    float3 c = mix(s0, s1, saturate(f / 0.2886));
    c = mix(c, s2, saturate((f - 0.2886) / (0.7318 - 0.2886)));
    c = mix(c, s3, saturate((f - 0.7318) / (1 - 0.7318)));
    // EmissionBase 1, EmissionBoost -1.2: darker where it faces the eye.
    c *= max(1 - 1.2 * (1 - f), 0.0);
    return half4(half3(linearToSRGB(c)), 1);
}
