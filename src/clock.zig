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

fn loadShader(allocator: Allocator, gpu: Device, file: [:0]const u8, entry_point: [:0]const u8, stage: ShaderStage) !Shader {
    const f = try std.fs.cwd().openFile(file, .{});
    defer f.close();

    const code = try f.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(code);

    return gpu.createShader(.{
        .code = code,
        .format = .{ .msl = true },
        .entry_point = entry_point,
        .stage = stage,
        .num_uniform_buffers = 1,
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
        const vs = try loadShader(allocator, gpu, "./clock_shaders/vertex.metal", "circle_main", .vertex);
        defer gpu.releaseShader(vs);
        const fs = try loadShader(allocator, gpu, "./clock_shaders/fragment.metal", "circle_main", .fragment);
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
        const vs = try loadShader(allocator, gpu, "./clock_shaders/vertex.metal", "quad_main", .vertex);
        defer gpu.releaseShader(vs);
        const fs = try loadShader(allocator, gpu, "./clock_shaders/fragment.metal", "quad_main", .fragment);
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

    fn init(allocator: Allocator, gpu: Device, texture_format: TextureFormat, quads: []const Quad) !QuadRender {
        const buffer = try gpu.createBuffer(.{ .size = @intCast(quads.len * @sizeOf(Quad)), .usage = .{ .vertex = true } });
        const transfer_buffer = try TransferBuffer.initFromData(gpu, Quad, quads, .upload);
        return QuadRender{
            .gpu = gpu,
            .pipeline = try createPipeline(allocator, gpu, texture_format),
            .buffer = buffer,
            .transfer_buffer = transfer_buffer,
            .count = quads.len,
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

const Colors = struct {
    const white: sdl3.pixels.FColor = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    const black: sdl3.pixels.FColor = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    const orange: sdl3.pixels.FColor = .{ .r = 234.0 / 255.0, .g = 149.0 / 255.0, .b = 53.0 / 255.0, .a = 1.0 };
    const gray: sdl3.pixels.FColor = .{ .r = 179.0 / 255.0, .g = 179.0 / 255.0, .b = 179.0 / 255.0, .a = 1.0 };
};

const HandsQuads = struct {
    quads: [6]Quad,

    fn init() HandsQuads {
        return .{
            .quads = [_]Quad{
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
            },
        };
    }

    fn setClockTime(self: *HandsQuads, time: *const sdl3.time.DateTime) void {
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

    // Initial window setup.
    const window = try Window.init("Clock", 325, 325, .{});
    defer window.deinit();

    const gpu = try Device.init(.{ .msl = true }, false, "metal");
    defer gpu.deinit();

    try gpu.claimWindow(window);

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

    const scale_render = try QuadRender.init(allocator, gpu, swap_texture_format, &quads);
    defer scale_render.deinit();

    var hands_quads = HandsQuads.init();
    var now = try getCurrentLocalTime();
    hands_quads.setClockTime(&now);

    const hands_render = try QuadRender.init(allocator, gpu, swap_texture_format, &hands_quads.quads);
    defer hands_render.deinit();

    var cmd = try gpu.acquireCommandBuffer();
    const cp_pass = cmd.beginCopyPass();
    try circle_render.uploadToBuffer(cp_pass);
    try scale_render.uploadToBuffer(cp_pass);
    cp_pass.end();
    try cmd.submit();

    var last_tick: u64 = 0;

    var quit = false;
    while (!quit) {
        // Event logic.
        while (sdl3.events.poll()) |event|
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                else => {},
            };

        cmd = try gpu.acquireCommandBuffer();

        const current_tick = sdl3.timer.getMillisecondsSinceInit();
        if (last_tick == 0 or (current_tick - last_tick > 100)) {
            last_tick = last_tick;
            now = try getCurrentLocalTime();
            hands_quads.setClockTime(&now);

            try hands_render.updateTransferBuffer(&hands_quads.quads);
            const copy_pass = cmd.beginCopyPass();
            try hands_render.uploadToBuffer(copy_pass);
            copy_pass.end();
        }

        const texture, const width, const height = try cmd.acquireSwapchainTexture(window);
        const swap = texture orelse continue;

        const pass = cmd.beginRenderPass(&[_]ColorTargetInfo{.{
            .texture = swap,
            .load = .clear,
            .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }}, null);

        cmd.pushVertexUniformData(0, @ptrCast(&[_]f32{ @floatFromInt(width), @floatFromInt(height) }));
        circle_render.draw(pass);
        scale_render.draw(pass);
        hands_render.draw(pass);
        pass.end();
        try cmd.submit();
    }
}
