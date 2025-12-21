#include <metal_stdlib>
using namespace metal;

struct TexInput {
    float4 color;
    float2 uv;
};

// fragment float4 tex_main(PSInput in [[stage_in]],
//                        texture2d<float> tex [[texture(0)]],
//                        sampler samp [[sampler(0)]])
// {
//     return in.color * tex.sample(samp, in.uv);
// }

struct QuadInput {
  float4 position [[position]];
  float2 local;
  float4 color;
  float4 rect [[flat]]; // x, y, w, h in pixels
  float round_radius [[flat]];
};

fragment float4 quad_main(QuadInput in [[stage_in]]) {
    float2 p = in.local;

    float2 tl = in.rect.xy;
    float2 br = tl + in.rect.zw;
    float2 halfSize = 0.5 * (br - tl);
    float2 center = 0.5 * (tl + br);

    float radius = min(in.round_radius, min(halfSize.x, halfSize.y));

    // local position relative to center (pixels)
    float2 local = p - center;

    // rounded-rect signed distance (pixels)
    float2 q = abs(local) - (halfSize - float2(radius));
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;

    // Anti-aliasing
    float2 g = float2(dfdx(dist), dfdy(dist));
    float aa = length(g) * 1.5;
    aa = clamp(aa, 1.0, 3.0);
    float alpha = smoothstep(aa, -aa, dist);
    // float alpha = step(dist, 0.0);

    return float4(in.color.rgb,
                  in.color.a * alpha);
}

struct CircleInput {
  float4 position [[position]];
  float2 local;
  float radius [[flat]];
  float4 color [[flat]];
};

fragment float4 circle_main(CircleInput in [[stage_in]]) {
  float d = length(in.local);
  float aa = fwidth(d);
  float alpha = 1.0 - smoothstep(in.radius - aa, in.radius + aa, d);

  return float4(in.color.rgb, in.color.a * alpha);
}

struct NumberInput {
  float4 position [[position]];
  float2 uv;
  float4 color [[flat]];
};

fragment float4 number_main(NumberInput in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) {
  return in.color * tex.sample(samp, in.uv);
}