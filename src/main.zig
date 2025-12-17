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
const Buffer = @import("./GPUBufer.zig");
const CopyPass = sdl3.gpu.CopyPass;

const Vertex = struct { x: f32, y: f32 };
const Rect = struct { x: f32, y: f32, w: f32, h: f32 };
const Digit = struct {
    n: u32,
    font_size: struct { f32, f32 },
    fn init(n: u32, allDigits: [10]CharBuffer) Digit {
        return Digit{
            .n = n,
            .font_size = allDigits[n].size,
        };
    }
};

fn createShader(allocator: Allocator, gpu: Device, file: [:0]const u8, entry_point: [:0]const u8, stage: ShaderStage) !Shader {
    const f = try std.fs.cwd().openFile(file, .{});
    defer f.close();

    const code = try f.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(code);

    return gpu.createShader(.{
        .code = code,
        .format = .{ .msl = true },
        .entry_point = entry_point,
        .stage = stage,
        .num_uniform_buffers = 2,
    });
}

const NUM_RECTS = 24;
const NUM_DIGITS = 6;

fn createVertexBuffer(gpu: Device) !Buffer {
    const buf = try Buffer.init(gpu, .{ .size = NUM_RECTS * @sizeOf(Rect), .usage = .{ .vertex = true } });
    var mapped = try buf.mapTransferBuffer(Rect, false);
    for (0..NUM_RECTS) |i| {
        const x = i / 4;
        const y = i % 4;
        mapped[i] = .{
            .x = @floatFromInt(10 + x * (50 + 10)), //
            .y = @floatFromInt(10 + y * (50 + 10)),
            .w = 50,
            .h = 50,
        };
    }
    buf.unmapTransferBuffer();
    return buf;
}

fn createDigitsVertexBuffer(gpu: Device) !Buffer {
    const buf = try Buffer.init(gpu, .{ .size = NUM_DIGITS * @sizeOf(Rect), .usage = .{ .vertex = true } });
    var mapped = try buf.mapTransferBuffer(Rect, false);
    defer buf.unmapTransferBuffer();
    for (0..NUM_DIGITS) |i| {
        mapped[i] = .{ .x = @floatFromInt(10 + i * 60), .y = 250, .w = 50, .h = 50 };
    }
    return buf;
}

// fn createTexVertexBuffer(gpu: Device, i: usize) !Buffer {
//     const buf = try Buffer.initFromData(gpu, Rect, &[_]Rect{
//         .{ .x = @floatFromInt(10 + i * 60), .y = 250, .w = 50, .h = 50 },
//     }, .{ .vertex = true });
//     return buf;
// }

fn createTexShader(allocator: Allocator, gpu: Device, file: [:0]const u8, entry_point: [:0]const u8, stage: ShaderStage) !Shader {
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
        .num_samplers = 10,
    });
}

const premultiplied_alpha_blending = ColorTargetBlendState{
    .enable_blend = true,
    .source_color = .src_alpha,
    .destination_color = .one_minus_src_alpha,

    .source_alpha = .one,
    .destination_alpha = .one_minus_src_alpha,
};

fn createPipeline(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !GraphicsPipeline {
    const vs = try createShader(allocator, gpu, "vertex.metal", "s_main", .vertex);
    const fs = try createShader(allocator, gpu, "fragment.metal", "s_main", .fragment);
    return gpu.createGraphicsPipeline(.{
        .vertex_shader = vs,
        .primitive_type = .triangle_list,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]VertexBufferDescription{
                .{ .slot = 0, .pitch = @sizeOf(Rect), .input_rate = .instance },
            }, // please break line
            .vertex_attributes = &[_]VertexAttribute{
                .{ .location = 0, .buffer_slot = 0, .offset = @offsetOf(Rect, "x"), .format = VertexElementFormat.f32x2 },
                .{ .location = 1, .buffer_slot = 0, .offset = @offsetOf(Rect, "w"), .format = VertexElementFormat.f32x2 },
            },
        },
        .fragment_shader = fs,
        .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{
            .format = texture_format,
            .blend_state = premultiplied_alpha_blending,
        }} },
    });
}

fn createPipelineForDigits(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !GraphicsPipeline {
    const vs = try createTexShader(allocator, gpu, "tex_vertex.metal", "s_main", .vertex);
    const fs = try createTexShader(allocator, gpu, "tex_fragment.metal", "s_main", .fragment);
    return gpu.createGraphicsPipeline(.{
        .vertex_shader = vs,
        .primitive_type = .triangle_list,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]VertexBufferDescription{
                .{ .slot = 0, .pitch = @sizeOf(Rect), .input_rate = .instance },
                .{ .slot = 1, .pitch = @sizeOf(Digit), .input_rate = .instance },
            },
            .vertex_attributes = &[_]VertexAttribute{
                .{ .location = 0, .buffer_slot = 0, .offset = @offsetOf(Rect, "x"), .format = VertexElementFormat.f32x2 },
                .{ .location = 1, .buffer_slot = 0, .offset = @offsetOf(Rect, "w"), .format = VertexElementFormat.f32x2 },
                .{ .location = 2, .buffer_slot = 1, .offset = @offsetOf(Digit, "n"), .format = VertexElementFormat.u32x1 }, // FIXME: no u8?
                .{ .location = 3, .buffer_slot = 1, .offset = @offsetOf(Digit, "font_size"), .format = VertexElementFormat.f32x2 },
            },
        },
        .fragment_shader = fs,
        .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{
            .format = texture_format,
            .blend_state = premultiplied_alpha_blending,
        }} },
    });
}

fn createSampler(gpu: Device) !Sampler {
    return gpu.createSampler(.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
    });
}

fn createTexture(gpu: Device, surf: sdl3.surface.Surface) !Texture {
    return gpu.createTexture(.{
        .texture_type = .two_dimensional,
        .format = .b8g8r8a8_unorm,
        .width = @intCast(surf.getWidth()),
        .height = @intCast(surf.getHeight()),
        .num_levels = 1,
        .usage = .{ .sampler = true },
    });
}

fn getCurrentLocalTime() !sdl3.time.DateTime {
    const current = try sdl3.time.Time.getCurrent();
    return try sdl3.time.DateTime.fromTime(current, true);
}

fn updateDigitsToCurrentLocalTime(digits: *[NUM_DIGITS]Digit, allDigits: [10]CharBuffer) !void {
    const time = try getCurrentLocalTime();
    digits[0] = Digit.init(@intCast(time.hour / 10), allDigits);
    digits[1] = Digit.init(@intCast(time.hour % 10), allDigits);
    digits[2] = Digit.init(@intCast(time.minute / 10), allDigits);
    digits[3] = Digit.init(@intCast(time.minute % 10), allDigits);
    digits[4] = Digit.init(@intCast(time.second / 10), allDigits);
    digits[5] = Digit.init(@intCast(time.second % 10), allDigits);
}

fn setColorsFromDigits(digits: *const [NUM_DIGITS]Digit, colors: *u32) void {
    for (0..NUM_RECTS) |i| {
        const x = i / 4;
        const y = i % 4;
        const mask = @as(u32, 1) << @intCast(i);
        if (digits[x].n & (@as(u32, 1) << @intCast(3 - y)) != 0) {
            colors.* |= mask;
        } else {
            colors.* &= ~mask;
        }
    }
}

const CharBuffer = struct {
    gpu: Device,
    texture: Texture,
    size: struct { f32, f32 },
    buffer: Buffer,

    fn init(gpu: Device, char: u8) !CharBuffer {
        const font = try ttf.Font.init("test.ttf", 50);
        defer font.deinit();
        // font.setHinting(.mono);

        const surf, _ = try font.getGlyphImage(char);
        defer surf.deinit();

        const buf = try Buffer.initFromSurface(gpu, surf, .{ .vertex = true });
        const texture = try createTexture(gpu, surf);

        return .{
            .gpu = gpu,
            .texture = texture,
            .size = .{ @floatFromInt(surf.getWidth()), @floatFromInt(surf.getHeight()) },
            .buffer = buf,
        };
    }

    fn deinit(self: *const CharBuffer) void {
        self.gpu.releaseTexture(self.texture);
        self.buffer.deinit();
    }

    fn uploadToTexture(self: *const CharBuffer, cp_pass: CopyPass) void {
        const texture = self.texture;
        const width, const height = self.size;
        const tex_dst = TextureRegion{
            .texture = texture,
            .x = 0,
            .y = 0,
            .width = @intFromFloat(width),
            .height = @intFromFloat(height),
            .depth = 0,
        };
        self.buffer.uploadToTexture(cp_pass, tex_dst, false);
    }
};

fn updateDigitsBuffer(digits: *const [NUM_DIGITS]Digit, buffer: Buffer) !void {
    const mapped = try buffer.mapTransferBuffer(Digit, false);
    defer buffer.unmapTransferBuffer();
    @memcpy(mapped, digits);
}

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
    const window = try sdl3.video.Window.init("Binary Clock", 50 * 6 + 10 * 7, 50 * 5 + 10 * 6, .{});
    defer window.deinit();

    const gpu = try Device.init(.{ .msl = true }, false, "metal");
    defer gpu.deinit();

    try gpu.claimWindow(window);

    const vbo = try createVertexBuffer(gpu);
    defer vbo.deinit();

    const swap_texture_format = try gpu.getSwapchainTextureFormat(window);
    const pipeline = try createPipeline(allocator, gpu, swap_texture_format);

    var allDigits = [_]CharBuffer{undefined} ** 10;
    for (0..allDigits.len) |i| {
        allDigits[i] = try CharBuffer.init(gpu, '0' + @as(u8, @intCast(i)));
    }
    defer for (allDigits) |digit| {
        digit.deinit();
    };

    var vbo_digits = try createDigitsVertexBuffer(gpu);
    defer vbo_digits.deinit();

    var cmd = try gpu.acquireCommandBuffer();
    const cp_pass = cmd.beginCopyPass();
    vbo.uploadToBuffer(cp_pass, false);
    vbo_digits.uploadToBuffer(cp_pass, false);
    for (allDigits) |digit| {
        digit.uploadToTexture(cp_pass);
    }
    cp_pass.end();
    try cmd.submit();

    const tex_pipeline = try createPipelineForDigits(allocator, gpu, swap_texture_format);
    const sampler = try createSampler(gpu);
    var last_tick: u64 = 0;

    var digits = [_]Digit{undefined} ** NUM_DIGITS;
    var digits_buffer = try Buffer.init(gpu, .{ .size = NUM_DIGITS * @sizeOf(Digit), .usage = .{ .vertex = true } });
    defer digits_buffer.deinit();

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

        const now = sdl3.timer.getMillisecondsSinceInit();
        if (last_tick == 0 or (now - last_tick > 1000)) {
            last_tick = now;
            try updateDigitsToCurrentLocalTime(&digits, allDigits);
            try updateDigitsBuffer(&digits, digits_buffer);
            const copy_pass = cmd.beginCopyPass();
            digits_buffer.uploadToBuffer(copy_pass, false);
            copy_pass.end();
        }

        const texture, const width, const height = try cmd.acquireSwapchainTexture(window);
        const swap = texture orelse continue;

        const ct = [_]ColorTargetInfo{.{
            .texture = swap,
            .load = .clear,
            .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }};

        const pass = cmd.beginRenderPass(&ct, null);

        cmd.pushVertexUniformData(0, @ptrCast(&[_]f32{ @floatFromInt(width), @floatFromInt(height) }));

        // render quads
        var colors: u32 = 0;
        setColorsFromDigits(&digits, &colors);
        cmd.pushVertexUniformData(1, @ptrCast(&colors));
        pass.bindGraphicsPipeline(pipeline);
        pass.bindVertexBuffers(0, &vbo.createBufferBindings(0));
        pass.drawPrimitives(6, NUM_RECTS, 0, 0);

        // render digits
        pass.bindGraphicsPipeline(tex_pipeline);
        pass.bindVertexBuffers(0, &[_]BufferBinding{
            vbo_digits.createBufferBinding(0),
            digits_buffer.createBufferBinding(0),
        });
        for (0..allDigits.len) |i| {
            pass.bindFragmentSamplers(@intCast(i), &[_]TextureSamplerBinding{.{
                .texture = allDigits[i].texture,
                .sampler = sampler,
            }});
        }
        pass.drawPrimitives(6, NUM_DIGITS, 0, 0);

        pass.end();
        try cmd.submit();
    }
}
