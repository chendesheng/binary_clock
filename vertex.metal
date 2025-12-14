struct VSIn {
   float2 position [[attribute(0)]];
};

struct VSOut {
    float4 position [[position]];
    float4 color;
};

struct Colors {
   bool colors[24];
};

vertex VSOut s_main(VSIn in [[stage_in]], uint vid [[vertex_id]], constant float2& ss [[buffer(0)]], constant Colors& c [[buffer(1)]]) {
   VSOut o;

   float2 ndc;
   ndc.x = (in.position.x / ss.x) * 2.0 - 1.0;
   ndc.y = 1.0 - (in.position.y / ss.y) * 2.0;
   o.position = float4(ndc, 0.0, 1.0);

   uint quadIndex = vid / 6;
   o.color = c.colors[quadIndex]
              ? float4(1.0, 0.0, 0.0, 1.0)
              : float4(0.0, 0.0, 1.0, 1.0);

   return o;
}

