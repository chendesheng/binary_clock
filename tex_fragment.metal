using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
    uint digit [[flat]];
};

fragment float4 s_main(VSOut in [[stage_in]],
                       array<texture2d<float>, 10> texes [[texture(0)]],
                       sampler samp        [[sampler(0)]]) {

    return texes[in.digit].sample(samp, in.uv);
}
