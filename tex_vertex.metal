struct VSIn {
  float2 position[[attribute(0)]];
  float2 size[[attribute(1)]];
};

struct VSOut {
  float4 position [[position]];
  float2 uv;
  uint digit [[flat]];
};

vertex VSOut s_main(VSIn in [[stage_in]], uint vid [[vertex_id]],
                    constant float2 &ss [[buffer(0)]],
                    constant uint &digit [[buffer(1)]],
                    constant float2 &offset [[buffer(2)]]) {
  VSOut o;

  uint i = vid % 6;

  o.digit = digit;

  float x, y;

  if (i == 0 || i == 5) {
    x = in.position.x + offset.x;
    y = in.position.y + offset.y;
  } else if (i == 1) {
    x = in.position.x + in.size.x - offset.x;
    y = in.position.y + offset.y;
  } else if (i == 2 || i == 3) {
    x = in.position.x + in.size.x - offset.x;
    y = in.position.y + in.size.y - offset.y;
  } else if (i == 4) {
    x = in.position.x + offset.x;
    y = in.position.y + in.size.y - offset.y;
  }

  float2 ndc;
  ndc.x = (x / ss.x) * 2.0 - 1.0;
  ndc.y = 1.0 - (y / ss.y) * 2.0;
  o.position = float4(ndc, 0.0, 1.0);

  if (i == 0) {
    o.uv = float2(0.0, 0.0);
  } else if (i == 1) {
    o.uv = float2(1.0, 0.0);
  } else if (i == 2) {
    o.uv = float2(1.0, 1.0);
  } else if (i == 3) {
    o.uv = float2(1.0, 1.0);
  } else if (i == 4) {
    o.uv = float2(0.0, 1.0);
  } else if (i == 5) {
    o.uv = float2(0.0, 0.0);
  }
  return o;
}
