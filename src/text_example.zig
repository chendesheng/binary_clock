const sdl3 = @import("sdl3");
const ttf = sdl3.ttf;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Device = sdl3.gpu.Device;
const TextureFormat = sdl3.gpu.TextureFormat;
const VertexAttribute = sdl3.gpu.VertexAttribute;
const VertexElementFormat = sdl3.gpu.VertexElementFormat;
const VertexBufferDescription = sdl3.gpu.VertexBufferDescription;
const ColorTargetDescription = sdl3.gpu.ColorTargetDescription;
const Sampler = sdl3.gpu.Sampler;
const Texture = sdl3.gpu.Texture;
const BufferBinding = sdl3.gpu.BufferBinding;
const TextureRegion = sdl3.gpu.TextureRegion;
const TextureTransferInfo = sdl3.gpu.TextureTransferInfo;
const ShaderStage = sdl3.gpu.ShaderStage;
const Shader = sdl3.gpu.Shader;
const GraphicsPipeline = sdl3.gpu.GraphicsPipeline;
const ColorTargetBlendState = sdl3.gpu.ColorTargetBlendState;
const TextureSamplerBinding = sdl3.gpu.TextureSamplerBinding;
const ColorTargetInfo = sdl3.gpu.ColorTargetInfo;
const Surface = sdl3.surface.Surface;
const CommandBuffer = sdl3.gpu.CommandBuffer;
const TransferBuffer = @import("./TransferBufer.zig");
const CopyPass = sdl3.gpu.CopyPass;
const ArrayList = std.ArrayList;

const ShaderType = enum {
    VertexShader,
    PixelShader,
    PixelShader_SDF,
};

const Vec2 = sdl3.c.SDL_FPoint;

const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

const Color = sdl3.pixels.FColor;

const Vertex = struct {
    pos: Vec3,
    colour: Color,
    uv: Vec2,
};

const Context = struct {
    device: Device,
    window: sdl3.video.Window,
    pipeline: GraphicsPipeline,
    vertex_buffer: sdl3.gpu.Buffer,
    index_buffer: sdl3.gpu.Buffer,
    transfer_buffer: sdl3.gpu.TransferBuffer,
    sampler: sdl3.gpu.Sampler,
    cmd_buf: sdl3.gpu.CommandBuffer,
};

const MAX_VERTEX_COUNT = 4000;
const MAX_INDEX_COUNT = 6000;

const GeometryData = struct {
    allocator: Allocator,
    vertices: ArrayList(Vertex),
    indices: ArrayList(c_int),

    fn init(allocator: Allocator) !GeometryData {
        return GeometryData{
            .allocator = allocator,
            .vertices = try ArrayList(Vertex).initCapacity(allocator, MAX_VERTEX_COUNT),
            .indices = try ArrayList(c_int).initCapacity(allocator, MAX_INDEX_COUNT),
        };
    }

    fn deinit(self: *GeometryData) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }
};

fn loadShader(allocator: Allocator, gpu: Device, shaderType: ShaderType, sampler_count: u32, uniform_buffer_count: u32, storage_buffer_count: u32, storage_texture_count: u32) !Shader {
    var create_info: sdl3.gpu.ShaderCreateInfo = .{
        .format = .{ .msl = true },
        .num_samplers = sampler_count,
        .num_storage_buffers = storage_buffer_count,
        .num_storage_textures = storage_texture_count,
        .num_uniform_buffers = uniform_buffer_count,
        .entry_point = "s_main",
        .code = "",
        .stage = .vertex,
    };
    if (shaderType == ShaderType.VertexShader) {
        const f = try std.fs.cwd().openFile("./text_example_shaders/vertex.metal", .{});
        defer f.close();

        const code = try f.readToEndAlloc(allocator, 1024 * 1024);

        create_info.code = code;
        create_info.stage = .vertex;
    } else if (shaderType == ShaderType.PixelShader) {
        const f = try std.fs.cwd().openFile("./text_example_shaders/fragment.metal", .{});
        defer f.close();

        const code = try f.readToEndAlloc(allocator, 1024 * 1024);

        create_info.code = code;
        create_info.stage = .fragment;
    }
    defer allocator.free(create_info.code);
    return gpu.createShader(create_info);
}

// void queue_text_sequence(GeometryData *geometry_data, TTF_GPUAtlasDrawSequence *sequence, SDL_FColor *colour)
// {
//     for (int i = 0; i < sequence->num_vertices; i++) {
//         Vertex vert;
//         const SDL_FPoint pos = sequence->xy[i];
//         vert.pos = (Vec3){ pos.x, pos.y, 0.0f };
//         vert.colour = *colour;
//         vert.uv = sequence->uv[i];

//         geometry_data->vertices[geometry_data->vertex_count + i] = vert;
//     }

//     SDL_memcpy(geometry_data->indices + geometry_data->index_count, sequence->indices, sequence->num_indices * sizeof(int));

//     geometry_data->vertex_count += sequence->num_vertices;
//     geometry_data->index_count += sequence->num_indices;
// }
//
fn queueTextSequence(geometry_data: *GeometryData, sequence: ttf.GpuAtlasDrawSequence, colour: *const Color) !void {
    for (sequence.xy, 0..) |pos, i| {
        try geometry_data.vertices.append(geometry_data.allocator, .{
            .pos = Vec3{ .x = pos.x, .y = pos.y, .z = 0.0 },
            .colour = colour.*,
            .uv = sequence.uv[i],
        });
    }

    try geometry_data.indices.appendSlice(geometry_data.allocator, sequence.indices);
}

// void queue_text(GeometryData *geometry_data, TTF_GPUAtlasDrawSequence *sequence, SDL_FColor *colour)
// {
//     for ( ; sequence; sequence = sequence->next) {
//         queue_text_sequence(geometry_data, sequence, colour);
//     }
// }
//
fn queueText(geometry_data: *GeometryData, sequence: anytype, colour: *const Color) !void {
    var it = sequence;
    while (it != null) {
        try queueTextSequence(geometry_data, ttf.GpuAtlasDrawSequence.fromSdl(it.?), colour);
        it = it.?.*.next;
    }
}

// void set_geometry_data(Context *context, GeometryData *geometry_data)
// {
//     Vertex *transfer_data = SDL_MapGPUTransferBuffer(context->device, context->transfer_buffer, false);
//
//     SDL_memcpy(transfer_data, geometry_data->vertices, sizeof(Vertex) * geometry_data->vertex_count);
//     SDL_memcpy(transfer_data + MAX_VERTEX_COUNT, geometry_data->indices, sizeof(int) * geometry_data->index_count);
//
//     SDL_UnmapGPUTransferBuffer(context->device, context->transfer_buffer);
// }
//
fn setGeometryData(context: *Context, geometry_data: *GeometryData) !void {
    const transfer_data = try context.device.mapTransferBuffer(context.transfer_buffer, false);
    const mapped: []Vertex = @alignCast(std.mem.bytesAsSlice(Vertex, transfer_data[0 .. @sizeOf(Vertex) * geometry_data.vertices.items.len]));
    defer context.device.unmapTransferBuffer(context.transfer_buffer);

    @memcpy(mapped, geometry_data.vertices.items);
    const mapped2: []c_int = @alignCast(std.mem.bytesAsSlice(c_int, transfer_data[@sizeOf(Vertex) * MAX_VERTEX_COUNT .. (@sizeOf(Vertex) * MAX_VERTEX_COUNT + @sizeOf(c_int) * geometry_data.indices.items.len)]));
    @memcpy(mapped2, geometry_data.indices.items);
}

// void transfer_data(Context *context, GeometryData *geometry_data)
// {
//     SDL_GPUCopyPass *copy_pass = check_error_ptr(SDL_BeginGPUCopyPass(context->cmd_buf));
//     SDL_UploadToGPUBuffer(
//         copy_pass,
//         &(SDL_GPUTransferBufferLocation){
//             .transfer_buffer = context->transfer_buffer,
//             .offset = 0 },
//         &(SDL_GPUBufferRegion){
//             .buffer = context->vertex_buffer,
//             .offset = 0,
//             .size = sizeof(Vertex) * geometry_data->vertex_count },
//         false);
//     SDL_UploadToGPUBuffer(
//         copy_pass,
//         &(SDL_GPUTransferBufferLocation){
//             .transfer_buffer = context->transfer_buffer,
//             .offset = sizeof(Vertex) * MAX_VERTEX_COUNT },
//         &(SDL_GPUBufferRegion){
//             .buffer = context->index_buffer,
//             .offset = 0,
//             .size = sizeof(int) * geometry_data->index_count },
//         false);
//     SDL_EndGPUCopyPass(copy_pass);
// }
fn transferData(context: *Context, geometry_data: *GeometryData) void {
    const pass = context.cmd_buf.beginCopyPass();
    pass.uploadToBuffer(.{
        .transfer_buffer = context.transfer_buffer,
        .offset = 0,
    }, .{
        .buffer = context.vertex_buffer,
        .offset = 0,
        .size = @intCast(@sizeOf(Vertex) * geometry_data.vertices.items.len),
    }, false);
    pass.uploadToBuffer(.{
        .transfer_buffer = context.transfer_buffer,
        .offset = @intCast(@sizeOf(Vertex) * MAX_VERTEX_COUNT),
    }, .{
        .buffer = context.index_buffer,
        .offset = 0,
        .size = @intCast(@sizeOf(c_int) * geometry_data.indices.items.len),
    }, false);
    pass.end();
}

// void draw(Context *context, SDL_Mat4X4 *matrices, int num_matrices, TTF_GPUAtlasDrawSequence *draw_sequence)
// {
//     SDL_GPUTexture *swapchain_texture;
//     check_error_bool(SDL_WaitAndAcquireGPUSwapchainTexture(context->cmd_buf, context->window, &swapchain_texture, NULL, NULL));

//     if (swapchain_texture != NULL) {
//         SDL_GPUColorTargetInfo colour_target_info = { 0 };
//         colour_target_info.texture = swapchain_texture;
//         colour_target_info.clear_color = (SDL_FColor){ 0.3f, 0.4f, 0.5f, 1.0f };
//         colour_target_info.load_op = SDL_GPU_LOADOP_CLEAR;
//         colour_target_info.store_op = SDL_GPU_STOREOP_STORE;

//         SDL_GPURenderPass *render_pass = SDL_BeginGPURenderPass(context->cmd_buf, &colour_target_info, 1, NULL);

//         SDL_BindGPUGraphicsPipeline(render_pass, context->pipeline);
//         SDL_BindGPUVertexBuffers(
//             render_pass, 0,
//             &(SDL_GPUBufferBinding){
//                 .buffer = context->vertex_buffer, .offset = 0 },
//            1);
//        SDL_BindGPUIndexBuffer(
//            render_pass,
//            &(SDL_GPUBufferBinding){
//                .buffer = context->index_buffer, .offset = 0 },
//            SDL_GPU_INDEXELEMENTSIZE_32BIT);
//        SDL_PushGPUVertexUniformData(context->cmd_buf, 0, matrices, sizeof(SDL_Mat4X4) * num_matrices);
//        int index_offset = 0, vertex_offset = 0;
//        for (TTF_GPUAtlasDrawSequence *seq = draw_sequence; seq != NULL; seq = seq->next) {
//            SDL_BindGPUFragmentSamplers(
//                render_pass, 0,
//                &(SDL_GPUTextureSamplerBinding){
//                    .texture = seq->atlas_texture, .sampler = context->sampler },
//                1);
//            SDL_DrawGPUIndexedPrimitives(render_pass, seq->num_indices, 1, index_offset, vertex_offset, 0);
//            index_offset += seq->num_indices;
//            vertex_offset += seq->num_vertices;
//        }
//        SDL_EndGPURenderPass(render_pass);
//    }

fn draw(context: *Context, draw_sequence: anytype) !void {
    const swapchain_tex, _, _ = try context.cmd_buf.waitAndAcquireSwapchainTexture(context.window);
    if (swapchain_tex) |swap| {
        const pass = context.cmd_buf.beginRenderPass(&[_]ColorTargetInfo{.{
            .texture = swap,
            .load = .clear,
            .clear_color = .{ .r = 0.3, .g = 0.4, .b = 0.5, .a = 1.0 },
        }}, null);
        pass.bindGraphicsPipeline(context.pipeline);
        pass.bindVertexBuffers(0, &[_]BufferBinding{.{
            .buffer = context.vertex_buffer,
            .offset = 0,
        }});
        pass.bindIndexBuffer(.{
            .buffer = context.index_buffer,
            .offset = 0,
        }, .indices_32bit);

        var it = draw_sequence;
        var index_offset: usize = 0;
        var vertex_offset: usize = 0;
        while (it != null) {
            const seq = ttf.GpuAtlasDrawSequence.fromSdl(it.?);
            pass.bindFragmentSamplers(0, &[_]TextureSamplerBinding{.{
                .texture = seq.atlas_texture,
                .sampler = context.sampler,
            }});
            pass.drawIndexedPrimitives(@intCast(seq.indices.len), 1, @intCast(index_offset), @intCast(vertex_offset), 0);
            index_offset += seq.indices.len;
            vertex_offset += seq.xy.len;
            it = it.?.*.next;
        }
        pass.end();
    }
}

fn freeContext(context: *Context) void {
    context.device.releaseTransferBuffer(context.transfer_buffer);
    context.device.releaseSampler(context.sampler);
    context.device.releaseBuffer(context.vertex_buffer);
    context.device.releaseBuffer(context.index_buffer);
    context.device.releaseGraphicsPipeline(context.pipeline);
    context.device.releaseWindow(context.window);
    context.device.deinit();
    context.window.deinit();
}

// int main(int argc, char *argv[])
// {
//     const char *font_filename = NULL;
//     bool use_SDF = false;
//
//     (void)argc;
//     for (int i = 1; argv[i]; ++i) {
//         if (SDL_strcasecmp(argv[i], "--sdf") == 0) {
//             use_SDF = true;
//         } else if (*argv[i] == '-') {
//             break;
//         } else {
//             font_filename = argv[i];
//             break;
//         }
//     }
//     if (!font_filename) {
//         SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "Usage: testgputext [--sdf] FONT_FILENAME");
//         return 2;
//     }
//
//     check_error_bool(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS));
//
//     bool running = true;
//     Context context = { 0 };
//
//     context.window = check_error_ptr(SDL_CreateWindow("GPU text test", 800, 600, 0));
//
//     context.device = check_error_ptr(SDL_CreateGPUDevice(SUPPORTED_SHADER_FORMATS, true, NULL));
//     check_error_bool(SDL_ClaimWindowForGPUDevice(context.device, context.window));
//
//     SDL_GPUShader *vertex_shader = check_error_ptr(load_shader(context.device, VertexShader, 0, 1, 0, 0));
//     SDL_GPUShader *fragment_shader = check_error_ptr(load_shader(context.device, use_SDF ? PixelShader_SDF : PixelShader, 1, 0, 0, 0));
//
//     SDL_GPUGraphicsPipelineCreateInfo pipeline_create_info = {
//         .target_info = {
//             .num_color_targets = 1,
//             .color_target_descriptions = (SDL_GPUColorTargetDescription[]){{
//                 .format = SDL_GetGPUSwapchainTextureFormat(context.device, context.window),
//                 .blend_state = (SDL_GPUColorTargetBlendState){
//                     .enable_blend = true,
//                     .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
//                     .color_blend_op = SDL_GPU_BLENDOP_ADD,
//                     .color_write_mask = 0xF,
//                     .src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA,
//                     .dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_DST_ALPHA,
//                     .src_color_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA,
//                     .dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
//                 }
//             }},
//             .has_depth_stencil_target = false,
//             .depth_stencil_format = SDL_GPU_TEXTUREFORMAT_INVALID /* Need to set this to avoid missing initializer for field error */
//         },
//         .vertex_input_state = (SDL_GPUVertexInputState){
//             .num_vertex_buffers = 1,
//             .vertex_buffer_descriptions = (SDL_GPUVertexBufferDescription[]){{
//                 .slot = 0,
//                 .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX,
//                 .instance_step_rate = 0,
//                 .pitch = sizeof(Vertex)
//             }},
//             .num_vertex_attributes = 3,
//             .vertex_attributes = (SDL_GPUVertexAttribute[]){{
//                 .buffer_slot = 0,
//                 .format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
//                 .location = 0,
//                 .offset = 0
//             }, {
//                 .buffer_slot = 0,
//                 .format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
//                 .location = 1,
//                 .offset = sizeof(float) * 3
//             }, {
//                 .buffer_slot = 0,
//                 .format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
//                 .location = 2,
//                 .offset = sizeof(float) * 7
//             }}
//         },
//         .primitive_type = SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
//         .vertex_shader = vertex_shader,
//         .fragment_shader = fragment_shader
//     };
//     context.pipeline = check_error_ptr(SDL_CreateGPUGraphicsPipeline(context.device, &pipeline_create_info));
//
//     SDL_ReleaseGPUShader(context.device, vertex_shader);
//     SDL_ReleaseGPUShader(context.device, fragment_shader);
//
//     SDL_GPUBufferCreateInfo vbf_info = {
//         .usage = SDL_GPU_BUFFERUSAGE_VERTEX,
//         .size = sizeof(Vertex) * MAX_VERTEX_COUNT
//     };
//     context.vertex_buffer = check_error_ptr(SDL_CreateGPUBuffer(context.device, &vbf_info));
//
//     SDL_GPUBufferCreateInfo ibf_info = {
//         .usage = SDL_GPU_BUFFERUSAGE_INDEX,
//         .size = sizeof(int) * MAX_INDEX_COUNT
//     };
//     context.index_buffer = check_error_ptr(SDL_CreateGPUBuffer(context.device, &ibf_info));
//
//     SDL_GPUTransferBufferCreateInfo tbf_info = {
//         .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
//         .size = (sizeof(Vertex) * MAX_VERTEX_COUNT) + (sizeof(int) * MAX_INDEX_COUNT)
//     };
//     context.transfer_buffer = check_error_ptr(SDL_CreateGPUTransferBuffer(context.device, &tbf_info));
//
//     SDL_GPUSamplerCreateInfo sampler_info = {
//         .min_filter = SDL_GPU_FILTER_LINEAR,
//         .mag_filter = SDL_GPU_FILTER_LINEAR,
//         .mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
//         .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
//         .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
//         .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
//     };
//     context.sampler = check_error_ptr(SDL_CreateGPUSampler(context.device, &sampler_info));
//
//     GeometryData geometry_data = { 0 };
//     geometry_data.vertices = SDL_calloc(MAX_VERTEX_COUNT, sizeof(Vertex));
//     geometry_data.indices = SDL_calloc(MAX_INDEX_COUNT, sizeof(int));
//
//     check_error_bool(TTF_Init());
//     TTF_Font *font = check_error_ptr(TTF_OpenFont(font_filename, 50)); /* Preferably use a Monospaced font */
//     if (!font) {
//         running = false;
//     }
//     SDL_Log("SDF %s", use_SDF ? "enabled" : "disabled");
//     TTF_SetFontSDF(font, use_SDF);
//     TTF_SetFontWrapAlignment(font, TTF_HORIZONTAL_ALIGN_CENTER);
//     TTF_TextEngine *engine = check_error_ptr(TTF_CreateGPUTextEngine(context.device));
//
//     char str[] = "     \nSDL is cool";
//     TTF_Text *text = check_error_ptr(TTF_CreateText(engine, font, str, 0));
//
//     SDL_Mat4X4 *matrices = (SDL_Mat4X4[]){
//         SDL_MatrixPerspective(SDL_PI_F / 2.0f, 800.0f / 600.0f, 0.1f, 100.0f),
//         SDL_MatrixIdentity()
//     };
//
//     float rot_angle = 0;
//     SDL_FColor colour = {1.0f, 1.0f, 0.0f, 1.0f};
//
//     while (running) {
//         SDL_Event event;
//         while (SDL_PollEvent(&event)) {
//             switch (event.type) {
//             case SDL_EVENT_KEY_UP:
//                 if (event.key.key == SDLK_ESCAPE) {
//                     running = false;
//                 }
//                 break;
//             case SDL_EVENT_QUIT:
//                 running = false;
//                 break;
//             }
//         }
//
//         for (int i = 0; i < 5; i++) {
//             str[i] = 65 + SDL_rand(26);
//         }
//         TTF_SetTextString(text, str, 0);
//
//         int tw, th;
//         check_error_bool(TTF_GetTextSize(text, &tw, &th));
//
//         rot_angle = SDL_fmodf(rot_angle + 0.01, 2 * SDL_PI_F);
//
//         // Create a model matrix to make the text rotate
//         SDL_Mat4X4 model;
//         model = SDL_MatrixIdentity();
//         model = SDL_MatrixMultiply(model, SDL_MatrixTranslation((SDL_Vec3){ 0.0f, 0.0f, -80.0f }));
//         model = SDL_MatrixMultiply(model, SDL_MatrixScaling((SDL_Vec3){ 0.3f, 0.3f, 0.3f}));
//         model = SDL_MatrixMultiply(model, SDL_MatrixRotationY(rot_angle));
//         model = SDL_MatrixMultiply(model, SDL_MatrixTranslation((SDL_Vec3){ -tw / 2.0f, th / 2.0f, 0.0f }));
//         matrices[1] = model;
//
//         // Get the text data and queue the text in a buffer for drawing later
//         TTF_GPUAtlasDrawSequence *sequence = TTF_GetGPUTextDrawData(text);
//         queue_text(&geometry_data, sequence, &colour);
//
//         set_geometry_data(&context, &geometry_data);
//
//         context.cmd_buf = check_error_ptr(SDL_AcquireGPUCommandBuffer(context.device));
//         transfer_data(&context, &geometry_data);
//         draw(&context, matrices, 2, sequence);
//         SDL_SubmitGPUCommandBuffer(context.cmd_buf);
//
//         geometry_data.vertex_count = 0;
//         geometry_data.index_count = 0;
//     }
//
//     SDL_free(geometry_data.vertices);
//     SDL_free(geometry_data.indices);
//     TTF_DestroyText(text);
//     TTF_DestroyGPUTextEngine(engine);
//     TTF_CloseFont(font);
//     TTF_Quit();
//     free_context(&context);
//     SDL_Quit();
//
//     return 0;
// }

pub fn main() !void {
    defer sdl3.shutdown();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize SDL with subsystems you need here.
    const init_flags = sdl3.InitFlags{ .video = true, .events = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    try ttf.init();
    defer ttf.quit();

    var running = true;
    var context: Context = undefined;

    // Initial window setup.
    context.window = try sdl3.video.Window.init("Binary Clock", 50 * 6 + 10 * 7, 50 * 5 + 10 * 6, .{});
    context.device = try Device.init(.{ .msl = true }, true, "metal");
    try context.device.claimWindow(context.window);

    const vertex_shader = try loadShader(allocator, context.device, .VertexShader, 0, 1, 0, 0);
    const fragment_shader = try loadShader(allocator, context.device, .PixelShader, 1, 0, 0, 0);

    context.pipeline = try context.device.createGraphicsPipeline(.{
        .target_info = .{
            .color_target_descriptions = &[_]ColorTargetDescription{.{
                .format = try context.device.getSwapchainTextureFormat(context.window),
                .blend_state = .{
                    .enable_blend = true,
                    .alpha_blend = .add,
                    .color_blend = .add,
                    // .color_write_mask = .{ .red = true },
                    // .color_write_mask = .{ .red = true, .green = true, .blue = true, .alpha = true },
                    // .source_alpha = .src_alpha,
                    // .destination_alpha = .dst_alpha,
                    // .source_color = .src_alpha,
                    // .destination_color = .one_minus_src_alpha,

                    .source_color = .src_alpha,
                    .destination_color = .one_minus_src_alpha,
                    .source_alpha = .one,
                    .destination_alpha = .one_minus_src_alpha,
                },
            }},
        },
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]VertexBufferDescription{.{
                .slot = 0,
                .input_rate = .vertex,
                .pitch = @sizeOf(Vertex),
            }},
            .vertex_attributes = &[_]VertexAttribute{ .{
                .buffer_slot = 0,
                .format = .f32x3,
                .offset = @offsetOf(Vertex, "pos"),
                .location = 0,
            }, .{
                .buffer_slot = 0,
                .format = .f32x4,
                .location = 1,
                .offset = @offsetOf(Vertex, "colour"),
            }, .{
                .buffer_slot = 0,
                .format = .f32x2,
                .location = 2,
                .offset = @offsetOf(Vertex, "uv"),
            } },
        },
        .primitive_type = .triangle_list,
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
    });
    context.device.releaseShader(vertex_shader);
    context.device.releaseShader(fragment_shader);

    context.vertex_buffer = try context.device.createBuffer(.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(Vertex) * MAX_VERTEX_COUNT,
    });
    context.index_buffer = try context.device.createBuffer(.{
        .usage = .{ .index = true },
        .size = @sizeOf(c_int) * MAX_INDEX_COUNT,
    });
    context.transfer_buffer = try context.device.createTransferBuffer(.{
        .usage = .upload,
        .size = @sizeOf(Vertex) * MAX_VERTEX_COUNT + @sizeOf(c_int) * MAX_INDEX_COUNT,
    });
    context.sampler = try context.device.createSampler(.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    });

    var geometry_data = try GeometryData.init(allocator);
    defer geometry_data.deinit();

    const font = try ttf.Font.init("test.ttf", 50);
    font.setWrapAlignment(.center);
    const engine = try ttf.GpuTextEngine.init(context.device);
    const text = try ttf.Text.init(.{ .value = engine.value }, font, "test");
    const colour: Color = .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };

    while (running) {
        // Event logic.
        while (sdl3.events.poll()) |event|
            switch (event) {
                .quit => running = false,
                .terminating => running = false,
                else => {},
            };

        const sequence = ttf.getGpuTextDrawData(text);
        try queueText(&geometry_data, sequence, &colour);
        try setGeometryData(&context, &geometry_data);

        context.cmd_buf = try context.device.acquireCommandBuffer();
        transferData(&context, &geometry_data);
        try draw(&context, sequence);

        try context.cmd_buf.submit();

        geometry_data.indices.clearRetainingCapacity();
        geometry_data.vertices.clearRetainingCapacity();
    }
}
