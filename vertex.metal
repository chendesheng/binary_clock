struct VSIn {
   float2 xy [[attribute(0)]];
   float2 sz [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float4 color;

    float4 rect [[flat]];
};

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

    o.position = float4(pixelToNDC(pos, viewport), 0.0, 1.0);

    o.color = (colors & (1 << iid)) != 0
        ? float4(1.0, 0.0, 0.0, 1.0)
        : float4(0.0, 0.0, 1.0, 1.0);

    o.rect = float4(in.xy, in.sz);

    return o;
}
