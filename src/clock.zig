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
const RenderPass = sdl3.gpu.RenderPass;
const Window = sdl3.video.Window;
const FixedSizeArray = @import("./FixedSizeArray.zig").FixedSizeArray;
const AtlasDrawSequence = @import("./AtlasDrawSequence.zig").AtlasDrawSequence;

const Circle = struct {
    radius: f32,
    color: sdl3.pixels.FColor,
};

const Quad = struct {
    polar_pos: struct {
        radius: f32,
        angle: f32,
    },
    sz: struct {
        width: f32,
        height: f32,
    },
    color: sdl3.pixels.FColor,
    round_radius: f32,
};

const NumberQuad = struct {
    // center position
    polar_pos: struct {
        radius: f32,
        angle: f32,
    },
    // square size
    size: struct { width: f32, height: f32 },
    color: sdl3.pixels.FColor,
};

const CharInfo = struct {
    xy: sdl3.c.SDL_FPoint,
    uv: sdl3.c.SDL_FPoint,
};

fn loadShader(allocator: Allocator, gpu: Device, file: [:0]const u8, entry_point: [:0]const u8, stage: ShaderStage, num_uniform_buffers: u32, num_samplers: u32) !Shader {
    const f = try std.fs.cwd().openFile(file, .{});
    defer f.close();

    const code = try f.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(code);

    return gpu.createShader(.{
        .code = code,
        .format = .{ .msl = true },
        .entry_point = entry_point,
        .stage = stage,
        .num_uniform_buffers = num_uniform_buffers,
        .num_samplers = num_samplers,
    });
}

const premultiplied_alpha_blending = ColorTargetBlendState{
    .enable_blend = true,
    .source_color = .src_alpha,
    .destination_color = .one_minus_src_alpha,

    .source_alpha = .one,
    .destination_alpha = .one_minus_src_alpha,
};

fn getCurrentLocalTime() !sdl3.time.DateTime {
    const current = try sdl3.time.Time.getCurrent();
    return try sdl3.time.DateTime.fromTime(current, true);
}

const CircleRender = struct {
    gpu: Device,
    pipeline: GraphicsPipeline,
    buffer: sdl3.gpu.Buffer,
    transfer_buffer: TransferBuffer,
    circles: []const Circle,

    fn createPipeline(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !GraphicsPipeline {
        const vs = try loadShader(allocator, gpu, "./clock_shaders/vertex.metal", "circle_main", .vertex, 1, 0);
        defer gpu.releaseShader(vs);
        const fs = try loadShader(allocator, gpu, "./clock_shaders/fragment.metal", "circle_main", .fragment, 0, 0);
        defer gpu.releaseShader(fs);
        return gpu.createGraphicsPipeline(.{
            .vertex_shader = vs,
            .primitive_type = .triangle_list,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]VertexBufferDescription{
                    .{ .slot = 0, .pitch = @sizeOf(Circle), .input_rate = .instance },
                },
                .vertex_attributes = &[_]VertexAttribute{
                    .{ .location = 0, .buffer_slot = 0, .offset = @offsetOf(Circle, "radius"), .format = VertexElementFormat.f32x1 },
                    .{ .location = 1, .buffer_slot = 0, .offset = @offsetOf(Circle, "color"), .format = VertexElementFormat.f32x4 },
                },
            },
            .fragment_shader = fs,
            .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{
                .format = texture_format,
                .blend_state = premultiplied_alpha_blending,
            }} },
        });
    }

    fn init(allocator: Allocator, gpu: Device, texture_format: TextureFormat, circles: []const Circle) !CircleRender {
        const buffer = try gpu.createBuffer(.{ .size = @intCast(circles.len * @sizeOf(Circle)), .usage = .{ .vertex = true } });
        const transfer_buffer = try TransferBuffer.initFromData(gpu, Circle, circles, .upload);
        return CircleRender{
            .gpu = gpu,
            .pipeline = try createPipeline(allocator, gpu, texture_format),
            .buffer = buffer,
            .transfer_buffer = transfer_buffer,
            .circles = circles,
        };
    }

    fn uploadToBuffer(self: *const CircleRender, pass: CopyPass) !void {
        self.transfer_buffer.uploadToBuffer(pass, self.buffer, false);
    }

    fn deinit(self: *const CircleRender) void {
        self.transfer_buffer.deinit();
        self.gpu.releaseGraphicsPipeline(self.pipeline);
        self.gpu.releaseBuffer(self.buffer);
    }

    fn draw(self: *const CircleRender, pass: RenderPass) void {
        pass.bindGraphicsPipeline(self.pipeline);
        pass.bindVertexBuffers(0, &[_]BufferBinding{.{
            .buffer = self.buffer,
            .offset = 0,
        }});
        pass.drawPrimitives(6, @intCast(self.circles.len), 0, 0);
    }
};

const QuadRender = struct {
    gpu: Device,
    pipeline: GraphicsPipeline,
    buffer: sdl3.gpu.Buffer,
    transfer_buffer: TransferBuffer,
    count: usize,

    fn createPipeline(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !GraphicsPipeline {
        const vs = try loadShader(allocator, gpu, "./clock_shaders/vertex.metal", "quad_main", .vertex, 1, 0);
        defer gpu.releaseShader(vs);
        const fs = try loadShader(allocator, gpu, "./clock_shaders/fragment.metal", "quad_main", .fragment, 0, 0);
        defer gpu.releaseShader(fs);
        return gpu.createGraphicsPipeline(.{
            .vertex_shader = vs,
            .primitive_type = .triangle_list,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]VertexBufferDescription{
                    .{ .slot = 0, .pitch = @sizeOf(Quad), .input_rate = .instance },
                },
                .vertex_attributes = &[_]VertexAttribute{
                    .{ .location = 0, .buffer_slot = 0, .offset = @offsetOf(Quad, "polar_pos"), .format = VertexElementFormat.f32x2 },
                    .{ .location = 1, .buffer_slot = 0, .offset = @offsetOf(Quad, "sz"), .format = VertexElementFormat.f32x2 },
                    .{ .location = 2, .buffer_slot = 0, .offset = @offsetOf(Quad, "color"), .format = VertexElementFormat.f32x4 },
                    .{ .location = 3, .buffer_slot = 0, .offset = @offsetOf(Quad, "round_radius"), .format = VertexElementFormat.f32x1 },
                },
            },
            .fragment_shader = fs,
            .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{
                .format = texture_format,
                .blend_state = premultiplied_alpha_blending,
            }} },
        });
    }

    fn init(allocator: Allocator, gpu: Device, texture_format: TextureFormat, count: usize) !QuadRender {
        const buffer = try gpu.createBuffer(.{ .size = @intCast(count * @sizeOf(Quad)), .usage = .{ .vertex = true } });
        const transfer_buffer = try TransferBuffer.init(gpu, .{
            .size = @intCast(count * @sizeOf(Quad)),
            .usage = .upload,
        });
        return QuadRender{
            .gpu = gpu,
            .pipeline = try createPipeline(allocator, gpu, texture_format),
            .buffer = buffer,
            .transfer_buffer = transfer_buffer,
            .count = count,
        };
    }

    fn updateTransferBuffer(self: *const QuadRender, quads: []const Quad) !void {
        if (quads.len != self.count) {
            return error.InvalidQuadCount;
        }

        const mapped = try self.transfer_buffer.map(Quad, false);
        defer self.transfer_buffer.unmap();
        @memcpy(mapped, quads);
    }

    fn uploadToBuffer(self: *const QuadRender, pass: CopyPass) !void {
        self.transfer_buffer.uploadToBuffer(pass, self.buffer, false);
    }

    fn deinit(self: *const QuadRender) void {
        self.transfer_buffer.deinit();
        self.gpu.releaseGraphicsPipeline(self.pipeline);
        self.gpu.releaseBuffer(self.buffer);
    }

    fn draw(self: *const QuadRender, pass: RenderPass) void {
        pass.bindGraphicsPipeline(self.pipeline);
        pass.bindVertexBuffers(0, &[_]BufferBinding{.{
            .buffer = self.buffer,
            .offset = 0,
        }});
        pass.drawPrimitives(6, @intCast(self.count), 0, 0);
    }
};

fn createSampler(gpu: Device) !Sampler {
    return try gpu.createSampler(.{
        .min_filter = .nearest,
        .mag_filter = .nearest,
        .mipmap_mode = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    });
}

const NumbersRender = struct {
    engine: ttf.GpuTextEngine,
    gpu: Device,
    pipeline: GraphicsPipeline,
    font: ttf.Font,
    numbers: [12]NumberRender,
    sampler: Sampler,

    const NumberRender = struct {
        text: ttf.Text,
        buffer: sdl3.gpu.Buffer,
        transfer_buffer: TransferBuffer,
        char_info_buffer: sdl3.gpu.Buffer,
        char_info_transfer_buffer: TransferBuffer,
        index_buffer: sdl3.gpu.Buffer,
        index_transfer_buffer: TransferBuffer,
        sequence: ttf.GpuAtlasDrawSequence,

        fn init(gpu: Device, engine: ttf.GpuTextEngine, font: ttf.Font, i: usize, str: [:0]const u8) !NumberRender {
            const text = try ttf.Text.init(.{ .value = engine.value }, font, str);

            if (ttf.getGpuTextDrawData(text)) |d| {
                const sequence = ttf.GpuAtlasDrawSequence.fromSdl(d);

                const buffer = try gpu.createBuffer(.{ .size = @intCast(@sizeOf(NumberQuad)), .usage = .{ .vertex = true } });
                const w, const h = try text.getSize();
                const quads: NumberQuad = .{
                    .polar_pos = .{ .radius = 100.0, .angle = @as(f32, @floatFromInt(i)) * 30.0 }, //
                    .size = .{ .width = @floatFromInt(w), .height = @floatFromInt(h) },
                    .color = Colors.black,
                };
                const transfer_buffer = try TransferBuffer.initFromData(gpu, NumberQuad, &[_]NumberQuad{quads}, .upload);

                const char_info_buffer = try gpu.createBuffer(.{ .size = @intCast(@sizeOf(CharInfo) * sequence.xy.len), .usage = .{ .vertex = true } });
                const char_info_transfer_buffer = try TransferBuffer.init(gpu, .{
                    .size = @intCast(@sizeOf(CharInfo) * sequence.xy.len),
                    .usage = .upload,
                });
                var char_info_mapped = try char_info_transfer_buffer.map(CharInfo, false);
                for (0..sequence.xy.len) |j| {
                    char_info_mapped[j] = .{ .xy = sequence.xy[j], .uv = sequence.uv[j] };
                }
                char_info_transfer_buffer.unmap();

                const index_buffer = try gpu.createBuffer(.{ .size = @intCast(@sizeOf(c_int) * sequence.indices.len), .usage = .{ .vertex = true } });
                const index_transfer_buffer = try TransferBuffer.initFromData(gpu, c_int, sequence.indices, .upload);

                return .{
                    .text = text, //
                    .buffer = buffer,
                    .transfer_buffer = transfer_buffer,
                    .char_info_buffer = char_info_buffer,
                    .char_info_transfer_buffer = char_info_transfer_buffer,
                    .index_buffer = index_buffer,
                    .index_transfer_buffer = index_transfer_buffer,
                    .sequence = sequence,
                };
            } else {
                return error.NoDrawData;
            }
        }

        fn deinit(self: *const NumberRender, gpu: Device) void {
            self.text.deinit();
            self.transfer_buffer.deinit();
            gpu.releaseBuffer(self.buffer);
            self.char_info_transfer_buffer.deinit();
            gpu.releaseBuffer(self.char_info_buffer);
            self.index_transfer_buffer.deinit();
            gpu.releaseBuffer(self.index_buffer);
        }

        fn draw(self: *const NumberRender, pass: RenderPass, sampler: Sampler) void {
            pass.bindVertexBuffers(0, &[_]BufferBinding{.{
                .buffer = self.char_info_buffer,
                .offset = 0,
            }});
            pass.bindVertexBuffers(1, &[_]BufferBinding{.{
                .buffer = self.buffer,
                .offset = 0,
            }});
            pass.bindIndexBuffer(.{
                .buffer = self.index_buffer,
                .offset = 0,
            }, .indices_32bit);
            pass.bindFragmentSamplers(0, &[_]TextureSamplerBinding{.{
                .texture = self.sequence.atlas_texture,
                .sampler = sampler,
            }});
            pass.drawIndexedPrimitives(@intCast(self.sequence.indices.len), 1, 0, 0, 0);
        }

        fn uploadToBuffer(self: *const NumberRender, pass: CopyPass) !void {
            self.transfer_buffer.uploadToBuffer(pass, self.buffer, false);
            self.char_info_transfer_buffer.uploadToBuffer(pass, self.char_info_buffer, false);
            self.index_transfer_buffer.uploadToBuffer(pass, self.index_buffer, false);
        }
    };

    fn createPipeline(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !GraphicsPipeline {
        const vs = try loadShader(allocator, gpu, "./clock_shaders/vertex.metal", "number_main", .vertex, 1, 0);
        defer gpu.releaseShader(vs);
        const fs = try loadShader(allocator, gpu, "./clock_shaders/fragment.metal", "number_main", .fragment, 0, 1);
        defer gpu.releaseShader(fs);
        return gpu.createGraphicsPipeline(.{
            .vertex_shader = vs,
            .primitive_type = .triangle_list,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]VertexBufferDescription{
                    .{ .slot = 0, .pitch = @sizeOf(CharInfo), .input_rate = .vertex },
                    .{ .slot = 1, .pitch = @sizeOf(NumberQuad), .input_rate = .instance },
                },
                .vertex_attributes = &[_]VertexAttribute{
                    .{ .location = 0, .buffer_slot = 0, .offset = @offsetOf(CharInfo, "xy"), .format = VertexElementFormat.f32x2 },
                    .{ .location = 1, .buffer_slot = 0, .offset = @offsetOf(CharInfo, "uv"), .format = VertexElementFormat.f32x2 },
                    .{ .location = 2, .buffer_slot = 1, .offset = @offsetOf(NumberQuad, "polar_pos"), .format = VertexElementFormat.f32x2 },
                    .{ .location = 3, .buffer_slot = 1, .offset = @offsetOf(NumberQuad, "size"), .format = VertexElementFormat.f32x2 },
                    .{ .location = 4, .buffer_slot = 1, .offset = @offsetOf(NumberQuad, "color"), .format = VertexElementFormat.f32x4 },
                },
            },
            .fragment_shader = fs,
            .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{
                .format = texture_format,
                .blend_state = premultiplied_alpha_blending,
            }} },
        });
    }

    fn init(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !NumbersRender {
        const font = try ttf.Font.init("JetBrains Mono Regular Nerd Font Complete.ttf", 30);
        const engine = try ttf.GpuTextEngine.init(gpu);

        const strs = [_][:0]const u8{ "12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11" };
        var numbers = [_]NumberRender{undefined} ** strs.len;
        for (strs, 0..) |str, i| {
            numbers[i] = try NumberRender.init(gpu, engine, font, i, str);
        }

        return NumbersRender{
            .gpu = gpu,
            .font = font,
            .engine = engine,
            .pipeline = try createPipeline(allocator, gpu, texture_format),
            .numbers = numbers,
            .sampler = try createSampler(gpu),
        };
    }

    fn uploadToBuffer(self: *const NumbersRender, pass: CopyPass) !void {
        for (self.numbers) |number| {
            try number.uploadToBuffer(pass);
        }
    }

    fn deinit(self: *const NumbersRender) void {
        for (self.numbers) |number| {
            number.deinit(self.gpu);
        }
        self.gpu.releaseSampler(self.sampler);
        self.engine.deinit();
        self.font.deinit();
        self.gpu.releaseGraphicsPipeline(self.pipeline);
    }

    fn draw(self: *const NumbersRender, pass: RenderPass) void {
        pass.bindGraphicsPipeline(self.pipeline);
        for (self.numbers) |number| {
            number.draw(pass, self.sampler);
        }
    }
};

const Colors = struct {
    const white: sdl3.pixels.FColor = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    const black: sdl3.pixels.FColor = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    const orange: sdl3.pixels.FColor = .{ .r = 234.0 / 255.0, .g = 149.0 / 255.0, .b = 53.0 / 255.0, .a = 1.0 };
    const gray: sdl3.pixels.FColor = .{ .r = 179.0 / 255.0, .g = 179.0 / 255.0, .b = 179.0 / 255.0, .a = 1.0 };
};

const Hands = struct {
    quads: [6]Quad,
    render: QuadRender,

    fn init(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !Hands {
        const quads = [_]Quad{
            // hour hand
            .{
                .polar_pos = .{ .radius = 6.0, .angle = 0 }, //
                .sz = .{ .width = 8.0, .height = 20.0 },
                .color = Colors.black,
                .round_radius = 0,
            },
            .{
                .polar_pos = .{ .radius = 24.0, .angle = 0 }, //
                .sz = .{ .width = 16.0, .height = 80.0 },
                .color = Colors.black,
                .round_radius = 8.0,
            },
            // minute hand
            .{
                .polar_pos = .{ .radius = 6.0, .angle = 0 }, //
                .sz = .{ .width = 8.0, .height = 20.0 },
                .color = Colors.black,
                .round_radius = 0,
            },
            .{
                .polar_pos = .{ .radius = 24.0, .angle = 0 }, //
                .sz = .{ .width = 16.0, .height = 106.0 },
                .color = Colors.black,
                .round_radius = 8.0,
            },

            // second hand
            .{
                .polar_pos = .{ .radius = 5.0, .angle = 0 }, //
                .sz = .{ .width = 2.0, .height = 20.0 },
                .color = Colors.orange,
                .round_radius = 1.0,
            },
            .{
                .polar_pos = .{ .radius = 5.0, .angle = 0 }, //
                .sz = .{ .width = 2.0, .height = 128.0 },
                .color = Colors.orange,
                .round_radius = 1.0,
            },
        };
        const render = try QuadRender.init(allocator, gpu, texture_format, quads.len);
        return .{
            .quads = quads,
            .render = render,
        };
    }

    fn deinit(self: *const Hands) void {
        self.render.deinit();
    }

    fn uploadToBuffer(self: *const Hands, pass: CopyPass) !void {
        try self.render.uploadToBuffer(pass);
    }

    fn draw(self: *const Hands, pass: RenderPass) void {
        self.render.draw(pass);
    }

    fn updateByTime(self: *Hands) !void {
        const time = try getCurrentLocalTime();
        const hour_angle = @as(f32, @floatFromInt(time.hour % 12)) * 30.0 + //
            @as(f32, @floatFromInt(time.minute)) * 0.5 + //
            @as(f32, @floatFromInt(time.second)) * 0.008333333333333333;

        self.quads[0].polar_pos.angle = hour_angle;
        self.quads[1].polar_pos.angle = hour_angle;

        const minute_angle = @as(f32, @floatFromInt(time.minute)) * 6.0 + @as(f32, @floatFromInt(time.second)) * 0.1;
        self.quads[2].polar_pos.angle = minute_angle;
        self.quads[3].polar_pos.angle = minute_angle;

        const milliseconds = time.nanosecond / 1000000;
        const second_angle = @as(f32, @floatFromInt(time.second)) * 6.0 + @as(f32, @floatFromInt(milliseconds)) * 0.006;
        self.quads[4].polar_pos.angle = second_angle + 180;
        self.quads[5].polar_pos.angle = second_angle;

        try self.render.updateTransferBuffer(&self.quads);
    }
};

fn drawScene(allocator: Allocator, gpu: Device, window: Window) !Texture {
    const swap_texture_format = try gpu.getSwapchainTextureFormat(window);
    const circle_render = try CircleRender.init(allocator, gpu, swap_texture_format, &[_]Circle{
        .{ .radius = 142.0, .color = Colors.white },
        .{ .radius = 9.0, .color = Colors.black },
        .{ .radius = 6.0, .color = Colors.orange },
        .{ .radius = 3.0, .color = Colors.white },
    });
    defer circle_render.deinit();

    var quads = [_]Quad{undefined} ** 60;
    for (0..quads.len) |i| {
        const angle = @as(f32, @floatFromInt(i)) * 6.0;
        quads[i] = .{
            .polar_pos = .{ .radius = 120.0, .angle = angle }, //
            .sz = .{ .width = 4.0, .height = 12.0 },
            .color = if (i % 5 == 0) Colors.black else Colors.gray,
            .round_radius = 2.0,
        };
    }

    const scale_render = try QuadRender.init(allocator, gpu, swap_texture_format, quads.len);
    defer scale_render.deinit();
    try scale_render.updateTransferBuffer(&quads);

    const numbers_render = try NumbersRender.init(allocator, gpu, swap_texture_format);
    defer numbers_render.deinit();

    const cmd = try gpu.acquireCommandBuffer();
    _, const width, const height = try cmd.waitAndAcquireSwapchainTexture(window);
    const bg_tex = try gpu.createTexture(.{
        .width = width,
        .height = height,
        .format = swap_texture_format,
        .num_levels = 1,
        .usage = .{ .sampler = true, .color_target = true },
    });

    const cp_pass = cmd.beginCopyPass();
    try circle_render.uploadToBuffer(cp_pass);
    try scale_render.uploadToBuffer(cp_pass);
    try numbers_render.uploadToBuffer(cp_pass);
    cp_pass.end();

    const r_pass = cmd.beginRenderPass(&[_]ColorTargetInfo{.{
        .texture = bg_tex,
        .load = .clear,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    }}, null);

    cmd.pushVertexUniformData(0, @ptrCast(&[_]f32{ @floatFromInt(width), @floatFromInt(height) }));
    circle_render.draw(r_pass);
    scale_render.draw(r_pass);
    numbers_render.draw(r_pass);
    r_pass.end();
    try cmd.submit();
    return bg_tex;
}

const FrameThrottle = struct {
    frame_ms: u64,
    last_tick: u64,
    fn init(frame_ms: u64) FrameThrottle {
        return .{
            .frame_ms = frame_ms,
            .last_tick = sdl3.timer.getMillisecondsSinceInit(),
        };
    }

    fn waitNextFrame(self: *FrameThrottle) void {
        const now = sdl3.timer.getMillisecondsSinceInit();
        if (now - self.last_tick < self.frame_ms) {
            _ = sdl3.events.waitTimeout(@intCast(self.frame_ms - (now - self.last_tick)));
        }
        self.last_tick = now;
    }
};

pub fn main() !void {
    defer sdl3.shutdown();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize SDL with subsystems you need here.
    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    try ttf.init();
    defer ttf.quit();

    const WIDTH = 160;
    const HEIGHT = 160;
    // Initial window setup.
    const window = try Window.init("Clock", WIDTH, HEIGHT, .{
        .high_pixel_density = true,
        .metal = true,
    });
    defer window.deinit();

    const gpu = try Device.init(.{ .msl = true }, false, "metal");
    defer gpu.deinit();

    try gpu.claimWindow(window);

    const bg_tex = try drawScene(allocator, gpu, window);
    defer gpu.releaseTexture(bg_tex);

    const swap_texture_format = try gpu.getSwapchainTextureFormat(window);

    var hands = try Hands.init(allocator, gpu, swap_texture_format);
    defer hands.deinit();

    var quit = false;
    var frame_throttle = FrameThrottle.init(50);
    while (!quit) {
        frame_throttle.waitNextFrame();

        while (sdl3.events.poll()) |event|
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                else => {},
            };

        const cmd = try gpu.acquireCommandBuffer();
        const texture, const swap_w, const swap_h = try cmd.waitAndAcquireSwapchainTexture(window);
        const swap = texture orelse continue;

        try hands.updateByTime();
        const copy_pass = cmd.beginCopyPass();
        try hands.uploadToBuffer(copy_pass);
        copy_pass.end();

        cmd.blitTexture(.{
            .source = .{
                .texture = bg_tex,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .region = .{
                    .x = 0,
                    .y = 0,
                    .w = swap_w,
                    .h = swap_h,
                },
            },
            .destination = .{
                .texture = swap,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .region = .{
                    .x = 0,
                    .y = 0,
                    .w = swap_w,
                    .h = swap_h,
                },
            },
            .load_op = .load,
            .flip_mode = .{ .horizontal = false, .vertical = false },
            .clear_color = Colors.black,
            .filter = .nearest,
            .cycle = false,
        });

        const pass = cmd.beginRenderPass(&[_]ColorTargetInfo{.{
            .texture = swap,
            .load = .load,
            .clear_color = Colors.black,
        }}, null);

        cmd.pushVertexUniformData(0, @ptrCast(&[_]f32{ @floatFromInt(swap_w), @floatFromInt(swap_h) }));
        hands.draw(pass);
        pass.end();
        try cmd.submit();
    }
}
