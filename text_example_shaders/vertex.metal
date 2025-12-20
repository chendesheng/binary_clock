#include <metal_stdlib>
using namespace metal;

struct VSInput {
    float2 position  [[attribute(0)]];
    float4 color     [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct VSOutput {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

vertex VSOutput s_main(VSInput in [[stage_in]], constant float2 &viewport [[buffer(0)]])
{
    VSOutput out;
    out.color = in.color;
    out.uv = in.uv;

    float2 ndc;
    ndc.x = (in.position.x / viewport.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (-in.position.y / viewport.y) * 2.0; // flip Y (pixel Y-down to NDC Y-up)

    out.position = float4(ndc, 0.0, 1.0);
    return out;
}
