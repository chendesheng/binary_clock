#include <metal_stdlib>
using namespace metal;

struct CircleInput {
    float radius [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct CircleOutput {
    float4 position [[position]];
    float2 local;
    float radius [[flat]];
    float4 color [[flat]];
};

float lengthToNDC(float l, float2 viewport) {
    return l / viewport.x * 2.0;
}

vertex CircleOutput circle_main(CircleInput in [[stage_in]], uint vid [[vertex_id]], constant float2 &viewport [[buffer(0)]])
{
    CircleOutput out;
    out.color = in.color;
    float r = lengthToNDC(in.radius, viewport);
    out.radius = r;
    uint i = vid % 6;
    out.local = float2(0.0, 0.0);
    float quad_r = lengthToNDC(in.radius + 2.0, viewport);
    if (i == 0 || i == 5) {
        out.local = float2(-quad_r, quad_r);
    } else if (i == 1) {
        out.local = float2(quad_r, quad_r);
    } else if (i == 2 || i == 3) {
        out.local = float2(quad_r, -quad_r);
    } else if (i == 4) {
        out.local = float2(-quad_r, -quad_r);
    }
    out.position = float4(out.local, 0.0, 1.0);
    return out;
}


struct QuadInput {
    float2 polar_pos [[attribute(0)]];
    float2 sz [[attribute(1)]];
    float4 color [[attribute(2)]];
    float round_radius [[attribute(3)]];
};

struct QuadOutput {
    float4 position [[position]];
    float2 local;
    float4 color;

    float4 rect [[flat]];
    float round_radius [[flat]];
};

constant float DEG_TO_RAD = M_PI_F / 180.0f;

float3x3 rotation(float degrees) {
    float angle = degrees * DEG_TO_RAD;
    float c = cos(angle);
    float s = sin(angle);
    return float3x3(
        float3(c, -s, 0),
        float3(s, c, 0),
        float3(0, 0, 1)
    );
}

float2 transform(float3x3 m, float2 p) {
    return (m * float3(p, 1.0)).xy;
}

vertex QuadOutput quad_main(QuadInput in [[stage_in]], uint vid [[vertex_id]], uint iid [[instance_id]], constant float2& viewport [[buffer(0)]]) {
    QuadOutput o;

    float2 tl = float2(-in.sz.x / 2.0, in.polar_pos.x);

    float2 pos = tl;
    uint i = vid % 6;
    if (i == 0 || i == 5) {
        pos = tl;
    } else if (i == 1) {
        pos = float2(tl.x + in.sz.x, tl.y);
    } else if (i == 2 || i == 3) {
        pos = tl + in.sz;
    } else if (i == 4) {
        pos = float2(tl.x, tl.y + in.sz.y);
    }
    o.local = pos;

    pos = transform(rotation(in.polar_pos.y), pos);
    pos = floor(pos + 0.5);
    o.position = float4(pos / (viewport / 2.0), 0.0, 1.0);
    o.color = in.color;
    o.rect = float4(tl, in.sz);
    o.round_radius = in.round_radius;

    return o;
}

struct NumberInput {
    float2 xy [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float2 polar_pos [[attribute(2)]];
    float2 size [[attribute(3)]];
    float4 color [[attribute(4)]];
};

struct NumberOutput {
    float4 position [[position]];
    float2 uv;
    float4 color [[flat]];
};

vertex NumberOutput number_main(NumberInput in [[stage_in]], uint vid [[vertex_id]], constant float2& viewport [[buffer(0)]]) {
    NumberOutput o;
    o.color = in.color;
    o.uv = in.uv;

    float2 center = transform(rotation(in.polar_pos.y), float2(0.0, in.polar_pos.x));
    float2 half_size = in.size / 2.0;

    float2 local = float2(in.xy.x - half_size.x, in.xy.y + half_size.y);
    float2 pos = center + local;
    o.position = float4(pos / (viewport / 2.0), 0.0, 1.0);
    return o;
}
