using namespace metal;

struct VSIn {
    float2 xy [[attribute(0)]];
    float2 sz [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float2 local;
    float4 color;

    float4 rect [[flat]];
};

float3x3 translate(float2 offset) {
    return float3x3(
        float3(1, 0, 0),
        float3(0, 1, 0),
        float3(offset.x, offset.y, 1)
    );
}

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

float3x3 rotationAt(float2 center, float degrees) {
    return translate(center) * rotation(degrees) * translate(-center);
}

float3x3 scale(float2 factor) {
    return float3x3(
        float3(factor.x, 0, 0),
        float3(0, factor.y, 0),
        float3(0, 0, 1)
    );
}

float2 transform(float3x3 m, float2 p) {
    return (m * float3(p, 1.0)).xy;
}

float2 pixelToNDC(float2 p, float2 viewport) {
    return float2((p.x / viewport.x) * 2.0 - 1.0 ,1.0 - (p.y / viewport.y) * 2.0);
}

vertex VSOut s_main(VSIn in [[stage_in]], uint vid [[vertex_id]], uint iid [[instance_id]], constant float2& viewport [[buffer(0)]], constant uint& colors [[buffer(1)]]) {
    VSOut o;

    float2 pos;
    uint i = vid % 6;
    if (i == 0 || i == 5) {
        pos = in.xy;
    } else if (i == 1) {
        pos = float2(in.xy.x + in.sz.x, in.xy.y);
    } else if (i == 2 || i == 3) {
        pos = float2(in.xy.x + in.sz.x, in.xy.y + in.sz.y);
    } else if (i == 4) {
        pos = float2(in.xy.x, in.xy.y + in.sz.y);
    }

    o.local = pos;

    float2 center = in.xy + in.sz / 2.0;

    pos = transform(rotationAt(center, 15.0), pos);

    o.position = float4(pixelToNDC(pos, viewport), 0.0, 1.0);

    o.color = (colors & (1 << iid)) != 0
        ? float4(1.0, 0.0, 0.0, 1.0)
        : float4(0.0, 0.0, 1.0, 1.0);

    o.rect = float4(in.xy, in.sz);

    return o;
}
