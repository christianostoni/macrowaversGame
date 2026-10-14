#include <metal_stdlib>
using namespace metal;

// Spiral-cut apple: the vertices of the mesh are rewritten for every opening value.
// Same maths as AppleShape.swift (used on the CPU for the stem, the worms and as a fallback).

// Fixed parameters of each vertex (generated once on the CPU). Layout matches AppleVertexParams.
// surface: 0 = top face of the slice (flesh)
//          1 = bottom face of the slice (flesh)
//          2 = skin (outer wall)
struct VertexParams {
    float theta;     // angle along the spiral
    float radial;    // 0 = axis, 1 = edge (flesh faces)
    float vertical;  // 0 = bottom, 1 = top of the slice (skin)
    uint  surface;
};

// Matches AppleVertex in Swift (float3 = 16 bytes).
struct OutVertex {
    float3 position;
    float3 normal;
};

// Matches AppleUniforms in Swift.
struct Uniforms {
    float opening;     // 0 = closed, 1 = fully open
    float height;
    float maxRadius;
    float turns;
    float gapPerTurn;
    uint  vertexCount;
};

// Apple profile: radius as a function of height.
static float appleRadius(float h, constant Uniforms& u) {
    float t = clamp(h / u.height, 0.0, 1.0);
    return u.maxRadius * (0.12 + 0.88 * sqrt(max(sin(M_PI_F * t), 0.0)));
}

// Position of a surface point for the current opening.
static float3 applePoint(float theta, float radial, float vertical, uint surface, constant Uniforms& u) {
    float pitch = u.height / (u.turns + 1.0);
    float turn  = theta / (2.0 * M_PI_F);

    // Height of the bottom and top of the slice at this angle (closed apple).
    float yb = clamp(turn * pitch, 0.0, u.height);
    float yt = clamp((turn + 1.0) * pitch, 0.0, u.height);

    // How much the slice rises when the apple opens: more for every turn.
    float lift = u.opening * u.gapPerTurn * clamp(turn, 0.0, u.turns);

    float h, r;
    if (surface == 0)      { h = yt;                   r = appleRadius(h, u) * radial; }
    else if (surface == 1) { h = yb;                   r = appleRadius(h, u) * radial; }
    else                   { h = mix(yb, yt, vertical); r = appleRadius(h, u); }

    return float3(r * cos(theta), h + lift, r * sin(theta));
}

kernel void deformApple(device const VertexParams* params [[buffer(0)]],
                        device OutVertex*          out    [[buffer(1)]],
                        constant Uniforms&         u      [[buffer(2)]],
                        uint id [[thread_position_in_grid]])
{
    if (id >= u.vertexCount) return;
    VertexParams p = params[id];

    float3 pos = applePoint(p.theta, p.radial, p.vertical, p.surface, u);

    // Normal by finite differences of the same function around the point.
    // On the axis (radial = 0) the derivative degenerates, so evaluate a little further out.
    const float e = 0.002;
    float radialEval = (p.surface == 2) ? p.radial : max(p.radial, 0.05);

    float3 dTheta = applePoint(p.theta + e, radialEval, p.vertical, p.surface, u)
                  - applePoint(p.theta - e, radialEval, p.vertical, p.surface, u);
    float3 dOther = (p.surface == 2)
        ? applePoint(p.theta, radialEval, p.vertical + e, p.surface, u) - applePoint(p.theta, radialEval, p.vertical - e, p.surface, u)
        : applePoint(p.theta, radialEval + e, p.vertical, p.surface, u) - applePoint(p.theta, radialEval - e, p.vertical, p.surface, u);

    float3 n = cross(dTheta, dOther);
    float3 outward = float3(pos.x, 0.0, pos.z);

    if (length(n) < 1e-8) {
        // Fallback where the slice has zero thickness (ends of the spiral).
        n = (p.surface == 0) ? float3(0, 1, 0)
          : (p.surface == 1) ? float3(0, -1, 0)
          : outward;
    }
    n = normalize(n);

    // Make sure the normal points out of the slice.
    if (p.surface == 0 && n.y < 0) n = -n;
    if (p.surface == 1 && n.y > 0) n = -n;
    if (p.surface == 2 && dot(n, outward) < 0) n = -n;

    out[id].position = pos;
    out[id].normal   = n;
}
