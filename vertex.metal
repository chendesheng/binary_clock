struct VSIn {
   float2 xy [[attribute(0)]];
   float2 sz [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float4 color;

    float4 rect [[flat]];
};

vertex VSOut s_main(VSIn in [[stage_in]], uint vid [[vertex_id]], uint iid [[instance_id]], constant float2& ss [[buffer(0)]], constant uint& colors [[buffer(1)]]) {
    VSOut o;

    float2 pos;
    uint i = vid % 6;
    uint corner = 0;
    if (i == 0 || i == 5) {
        pos = in.xy;
        corner = 0;
    } else if (i == 1) {
        pos = float2(in.xy.x + in.sz.x, in.xy.y);
        corner = 1;
    } else if (i == 2 || i == 3) {
        pos = float2(in.xy.x + in.sz.x, in.xy.y + in.sz.y);
        corner = 2;
    } else if (i == 4) {
        pos = float2(in.xy.x, in.xy.y + in.sz.y);
        corner = 3;
    }

    float2 ndc;
    ndc.x = (pos.x / ss.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pos.y / ss.y) * 2.0;
    o.position = float4(ndc, 0.0, 1.0);

    o.color = (colors & (1 << iid)) != 0
        ? float4(1.0, 0.0, 0.0, 1.0)
        : float4(0.0, 0.0, 1.0, 1.0);

    o.rect = float4(in.xy, in.sz);

    return o;
}
