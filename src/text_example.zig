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

const Color = sdl3.pixels.FColor;

const Vertex = struct {
    pos: Vec2,
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

fn BoundedArray(comptime size: usize, comptime T: type) type {
    return struct {
        buffer: []T,
        len: usize,
        const Self = @This();

        fn init(buffer: []T) Self {
            return .{
                .buffer = buffer,
                .len = 0,
            };
        }

        fn append(self: *Self, item: T) !void {
            if (self.len >= size) {
                return error.BoundedArrayIsFull;
            }

            self.buffer[self.len] = item;
            self.len += 1;
        }

        fn appendSlice(self: *Self, items: []const T) !void {
            if (self.len + items.len > size) {
                return error.BoundedArrayIsFull;
            }

            @memcpy(self.buffer[self.len .. self.len + items.len], items);
            self.len += items.len;
        }
    };
}

fn AtlasDrawSequence(comptime T: type) type {
    return struct {
        const Self = @This();
        _current: T,

        fn init(sequence: T) Self {
            return .{
                ._current = sequence,
            };
        }

        fn moveNext(self: *Self) void {
            if (self._current) |current| {
                self._current = current.*.next;
            }
        }

        fn getCurrent(self: *Self) ?ttf.GpuAtlasDrawSequence {
            if (self._current) |current| {
                return ttf.GpuAtlasDrawSequence.fromSdl(current);
            }
            return null;
        }
    };
}

fn setTransferBuffer(context: *Context, sequence: anytype, colour: *const Color) !struct { usize, usize } {
    const transfer_data = try context.device.mapTransferBuffer(context.transfer_buffer, false);
    defer context.device.unmapTransferBuffer(context.transfer_buffer);

    const mapped_vertices: []Vertex = @alignCast(std.mem.bytesAsSlice(Vertex, transfer_data[0 .. MAX_VERTEX_COUNT * @sizeOf(Vertex)]));
    var mapped_vertices_array = BoundedArray(MAX_VERTEX_COUNT, Vertex).init(mapped_vertices);

    const mapped_indices: []c_int = @alignCast(std.mem.bytesAsSlice(c_int, transfer_data[@sizeOf(Vertex) * MAX_VERTEX_COUNT .. (@sizeOf(Vertex) * MAX_VERTEX_COUNT + @sizeOf(c_int) * MAX_INDEX_COUNT)]));
    var mapped_indices_array = BoundedArray(MAX_INDEX_COUNT, c_int).init(mapped_indices);

    var iter = AtlasDrawSequence(@TypeOf(sequence)).init(sequence);
    while (iter.getCurrent()) |seq| {
        for (seq.xy, 0..) |pos, i| {
            try mapped_vertices_array.append(.{
                .pos = pos,
                .colour = colour.*,
                .uv = seq.uv[i],
            });
        }
        try mapped_indices_array.appendSlice(seq.indices);

        iter.moveNext();
    }

    return .{ mapped_vertices_array.len, mapped_indices_array.len };
}

fn transferData(context: *Context, num_vertices: usize, num_indices: usize) void {
    const pass = context.cmd_buf.beginCopyPass();
    pass.uploadToBuffer(.{
        .transfer_buffer = context.transfer_buffer,
        .offset = 0,
    }, .{
        .buffer = context.vertex_buffer,
        .offset = 0,
        .size = @intCast(@sizeOf(Vertex) * num_vertices),
    }, false);
    pass.uploadToBuffer(.{
        .transfer_buffer = context.transfer_buffer,
        .offset = @intCast(@sizeOf(Vertex) * MAX_VERTEX_COUNT),
    }, .{
        .buffer = context.index_buffer,
        .offset = 0,
        .size = @intCast(@sizeOf(c_int) * num_indices),
    }, false);
    pass.end();
}

fn draw(context: *Context, draw_sequence: anytype) !void {
    const swapchain_tex, const width, const height = try context.cmd_buf.waitAndAcquireSwapchainTexture(context.window);
    if (swapchain_tex) |swap| {
        context.cmd_buf.pushVertexUniformData(0, @ptrCast(&[_]f32{ @floatFromInt(width), @floatFromInt(height) }));

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

        var it = AtlasDrawSequence(@TypeOf(draw_sequence)).init(draw_sequence);
        var index_offset: usize = 0;
        var vertex_offset: usize = 0;
        while (it.getCurrent()) |seq| {
            pass.bindFragmentSamplers(0, &[_]TextureSamplerBinding{.{
                .texture = seq.atlas_texture,
                .sampler = context.sampler,
            }});
            pass.drawIndexedPrimitives(@intCast(seq.indices.len), 1, @intCast(index_offset), @intCast(vertex_offset), 0);
            index_offset += seq.indices.len;
            vertex_offset += seq.xy.len;
            it.moveNext();
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
    context.window = try sdl3.video.Window.init("Binary Clock", 800, 600, .{});
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

    const font = try ttf.Font.init("JetBrains Mono Regular Nerd Font Complete.ttf", 20);
    // font.setWrapAlignment(.center);
    const engine = try ttf.GpuTextEngine.init(context.device);
    const text = try ttf.Text.init(.{ .value = engine.value }, font, "The quick brown fox jumps\nover the lazy dog and runs away.");
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
        const num_vertices, const num_indices = try setTransferBuffer(&context, sequence, &colour);

        context.cmd_buf = try context.device.acquireCommandBuffer();
        transferData(&context, num_vertices, num_indices);
        try draw(&context, sequence);

        try context.cmd_buf.submit();
    }
}
