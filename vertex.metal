struct VSIn {
   float2 xy [[attribute(0)]];
   float2 sz [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float4 color;
};

struct Colors {
   bool colors[24];
};

vertex VSOut s_main(VSIn in [[stage_in]], uint vid [[vertex_id]], uint iid [[instance_id]], constant float2& ss [[buffer(0)]], constant Colors& c [[buffer(1)]]) {
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

   float2 ndc;
   ndc.x = (pos.x / ss.x) * 2.0 - 1.0;
   ndc.y = 1.0 - (pos.y / ss.y) * 2.0;
   o.position = float4(ndc, 0.0, 1.0);

   o.color = c.colors[iid]
              ? float4(1.0, 0.0, 0.0, 1.0)
              : float4(0.0, 0.0, 1.0, 1.0);

   return o;
}

