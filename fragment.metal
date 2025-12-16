#include <metal_stdlib>
using namespace metal;

struct VSOut {
  float4 position;
  float2 local;
  float4 color;
  float4 rect [[flat]]; // x, y, w, h in pixels
};

fragment float4 s_main(VSOut in [[stage_in]]) // pixel coord
{
    float2 p = in.local;

    float2 tl = in.rect.xy;
    float2 br = tl + in.rect.zw;
    float2 halfSize = 0.5 * (br - tl);
    float2 center = 0.5 * (tl + br);

    float radius = 10.0;
    radius = min(radius, min(halfSize.x, halfSize.y));

    // local position relative to center (pixels)
    float2 local = p - center;

    // rounded-rect signed distance (pixels)
    float2 q = abs(local) - (halfSize - float2(radius));
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;

    // Anti-aliasing
    float2 g = float2(dfdx(dist), dfdy(dist));
    float aa = length(g);
    aa = clamp(aa, 0.75, 1.5);
    float alpha = smoothstep(aa, -aa, dist);

    return float4(in.color.rgb,
                  in.color.a * alpha);
}
