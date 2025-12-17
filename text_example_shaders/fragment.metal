#include <metal_stdlib>
using namespace metal;

struct PSInput {
    float4 color;
    float2 tex_coord;
};

fragment float4 s_main(PSInput in [[stage_in]],
                       texture2d<float> tex [[texture(0)]],
                       sampler samp [[sampler(0)]])
{
    return in.color * tex.sample(samp, in.tex_coord);
}
