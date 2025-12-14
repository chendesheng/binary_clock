struct VSOut {
    float4 position [[position]];
    float4 color;
};

fragment float4 s_main(VSOut in [[stage_in]]) {
   return in.color;
}

