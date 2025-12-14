using namespace metal;

struct VSOut {
    float2 uv;
    uint digit [[flat]];
};

fragment float4 s_main(VSOut in [[stage_in]],
                       texture2d<float> tex [[texture(0)]],
                       sampler samp        [[sampler(0)]]) {

    return tex.sample(samp, in.uv);
}


