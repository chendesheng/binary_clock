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

const Vertex = struct { x: f32, y: f32 };
const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

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

pub fn TransferBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        gpu: Device,
        buf: sdl3.gpu.TransferBuffer,
        mapped: []T,
        size: u32,

        pub fn init(gpu: Device, size: usize) !TransferBuffer(T) {
            const bytes_size: u32 = @intCast(size * @sizeOf(T));
            const buf = try gpu.createTransferBuffer(.{ .usage = .upload, .size = bytes_size });
            const mapped = try gpu.mapTransferBuffer(buf, false);

            const mapped_t: []T = @alignCast(std.mem.bytesAsSlice(T, mapped[0..bytes_size]));

            return .{
                .gpu = gpu,
                .buf = buf,
                .mapped = mapped_t,
                .size = bytes_size,
            };
        }

        pub fn initFromSurface(gpu: Device, surf: Surface) !TransferBuffer(u8) {
            const self = try TransferBuffer(u8).init(gpu, @intCast(surf.getPitch() * surf.getHeight()));
            if (surf.getPixels()) |pixels| {
                @memcpy(self.mapped, pixels);
            }
            return self;
        }

        pub fn deinit(self: *const Self) void {
            self.gpu.unmapTransferBuffer(self.buf);
        }

        pub fn uploadToBuffer(self: *const Self, buf: sdl3.gpu.Buffer, cycle: bool) !void {
            const cmd = try self.gpu.acquireCommandBuffer();
            const pass = cmd.beginCopyPass();

            pass.uploadToBuffer(.{ .offset = 0, .transfer_buffer = self.buf }, .{ .buffer = buf, .offset = 0, .size = self.size }, cycle);
            pass.end();
            try cmd.submit();
        }

        pub fn uploadToTexture(self: *const Self, dst: TextureRegion, cycle: bool) !void {
            const src = TextureTransferInfo{
                .transfer_buffer = self.buf,
                .offset = 0,
                .pixels_per_row = dst.width,
                .rows_per_layer = dst.height,
            };
            const cmd = try self.gpu.acquireCommandBuffer();
            const pass = cmd.beginCopyPass();
            pass.uploadToTexture(src, dst, cycle);
            pass.end();
            try cmd.submit();
        }
    };
}

fn setQuad(vetices: []Vertex, i: usize, x: f32, y: f32, w: f32, h: f32) void {
    const start = i * 6;
    vetices[start] = .{ .x = x, .y = y };
    vetices[start + 1] = .{ .x = x + w, .y = y };
    vetices[start + 2] = .{ .x = x + w, .y = y + h };
    vetices[start + 3] = .{ .x = x + w, .y = y + h };
    vetices[start + 4] = .{ .x = x, .y = y + h };
    vetices[start + 5] = .{ .x = x, .y = y };
}

const NUM_RECTS = 24;

fn createVertexBuffer(gpu: Device) !sdl3.gpu.Buffer {
    const transfer_buffer = try TransferBuffer(Rect).init(gpu, NUM_RECTS);
    defer transfer_buffer.deinit();

    for (0..NUM_RECTS) |i| {
        const x = i % 6;
        const y = i / 6;
        transfer_buffer.mapped[i] = .{
            .x = @floatFromInt(10 + x * (50 + 10)), //
            .y = @floatFromInt(10 + y * (50 + 10)),
            .w = 50,
            .h = 50,
        };
    }

    const vbo = try gpu.createBuffer(.{ .usage = .{ .vertex = true }, .size = transfer_buffer.size });
    try transfer_buffer.uploadToBuffer(vbo, false);
    return vbo;
}

fn createTexVertexBuffer(gpu: Device, i: usize) !sdl3.gpu.Buffer {
    const transfer_buffer = try TransferBuffer(Vertex).init(gpu, 6);
    defer transfer_buffer.deinit();

    setQuad(transfer_buffer.mapped, 0, @floatFromInt(10 + i * 60), 250, 50, 50);

    const vbo = try gpu.createBuffer(.{ .usage = .{ .vertex = true }, .size = transfer_buffer.size });
    try transfer_buffer.uploadToBuffer(vbo, false);
    return vbo;
}

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
        .num_uniform_buffers = 3,
        .num_samplers = 1,
    });
}

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
        .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{ .format = texture_format }} },
    });
}

fn createTexPipeline(allocator: Allocator, gpu: Device, texture_format: TextureFormat) !GraphicsPipeline {
    const vs = try createTexShader(allocator, gpu, "tex_vertex.metal", "s_main", .vertex);
    const fs = try createTexShader(allocator, gpu, "tex_fragment.metal", "s_main", .fragment);
    return gpu.createGraphicsPipeline(.{
        .vertex_shader = vs,
        .primitive_type = .triangle_list,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]VertexBufferDescription{.{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = .vertex }}, // please break line
            .vertex_attributes = &[_]VertexAttribute{.{ .location = 0, .buffer_slot = 0, .offset = 0, .format = VertexElementFormat.f32x2 }},
        },
        .fragment_shader = fs,
        .target_info = .{ .color_target_descriptions = &[_]ColorTargetDescription{.{
            .format = texture_format,
            .blend_state = ColorTargetBlendState{
                .source_color = .src_alpha,
                .source_alpha = .one,
                .destination_color = .one_minus_src_alpha,
                .destination_alpha = .one_minus_src_alpha,
                .color_blend = .add,
                .alpha_blend = .add,
                .enable_blend = true,
            },
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

fn createTexBuffer(gpu: Device, char: u8) !struct { Texture, Surface } {
    const font = try ttf.Font.init("test.ttf", 50);
    defer font.deinit();
    font.setHinting(.mono);

    const surf, _ = try font.getGlyphImage(char);
    // std.debug.print("surf.getWidth(): {any}\n", .{surf.getWidth()});
    // std.debug.print("surf.getHeight(): {any}\n", .{surf.getHeight()});
    // std.debug.print("surf.getPitch(): {any}\n", .{surf.getPitch()});
    // std.debug.print("surf.getFormat(): {any}\n", .{surf.getFormat()});
    // defer surf.deinit();

    // const surf = try sdl3.surface.Surface.initFromBmpFile("test.bmp");
    // defer surf.deinit();

    const transfer_buffer = try TransferBuffer(u8).initFromSurface(gpu, surf);
    defer transfer_buffer.deinit();

    const texture = try createTexture(gpu, surf);
    const tex_dst = TextureRegion{
        .texture = texture,
        .x = 0,
        .y = 0,
        .width = @intCast(surf.getWidth()),
        .height = @intCast(surf.getHeight()),
        .depth = 0,
    };

    try transfer_buffer.uploadToTexture(tex_dst, false);

    return .{ texture, surf };
}

fn getCurrentLocalTime() !sdl3.time.DateTime {
    const current = try sdl3.time.Time.getCurrent();
    return try sdl3.time.DateTime.fromTime(current, true);
}

fn updateDigitsToCurrentLocalTime(digits: *[6]u8) !void {
    const time = try getCurrentLocalTime();
    digits[0] = @intCast(time.hour / 10);
    digits[1] = @intCast(time.hour % 10);
    digits[2] = @intCast(time.minute / 10);
    digits[3] = @intCast(time.minute % 10);
    digits[4] = @intCast(time.second / 10);
    digits[5] = @intCast(time.second % 10);
}

fn setColorsFromDigits(digits: *const [6]u8, colors: *[NUM_RECTS]bool) void {
    for (0..6) |i| {
        for (0..4) |j| {
            colors[i + j * 6] = (digits[i] & (@as(u8, 1) << @intCast(3 - j))) != 0;
        }
    }
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
    const swap_texture_format = try gpu.getSwapchainTextureFormat(window);
    const pipeline = try createPipeline(allocator, gpu, swap_texture_format);

    var bmp_textures = [_]Texture{undefined} ** 10;
    var surfes = [_]Surface{undefined} ** 10;
    var digitOffsets = [_]struct { f32, f32 }{undefined} ** 10;
    for (0..surfes.len) |i| {
        const texture, const surf = try createTexBuffer(gpu, '0' + @as(u8, @intCast(i)));
        bmp_textures[i] = texture;
        surfes[i] = surf;
        digitOffsets[i] = .{
            @floatFromInt((50 - surf.getWidth()) / 2), //
            @floatFromInt((50 - surf.getHeight()) / 2),
        };
    }

    defer for (0..surfes.len) |i| {
        surfes[i].deinit();
    };

    var tex_vboes = [_]sdl3.gpu.Buffer{undefined} ** 6;
    for (0..tex_vboes.len) |i| {
        tex_vboes[i] = try createTexVertexBuffer(gpu, i);
    }

    const tex_pipeline = try createTexPipeline(allocator, gpu, swap_texture_format);
    const sampler = try createSampler(gpu);
    var last_tick = sdl3.timer.getMillisecondsSinceInit();

    var digits = [6]u8{ 0, 0, 0, 0, 0, 0 };
    try updateDigitsToCurrentLocalTime(&digits);

    var quit = false;
    while (!quit) {
        // Event logic.
        while (sdl3.events.poll()) |event|
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                else => {},
            };

        const now = sdl3.timer.getMillisecondsSinceInit();
        if (now - last_tick > 1000) {
            last_tick = now;
            try updateDigitsToCurrentLocalTime(&digits);
        }

        const cmd = try gpu.acquireCommandBuffer();
        const texture, const width, const height = try cmd.acquireSwapchainTexture(window);
        const swap = texture orelse continue;

        const ct = [_]ColorTargetInfo{.{
            .texture = swap,
            .load = .clear,
            .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }};
        const pass = cmd.beginRenderPass(&ct, null);

        cmd.pushVertexUniformData(0, @ptrCast(&[_]f32{ @floatFromInt(width), @floatFromInt(height) }));

        var colors = [_]bool{false} ** NUM_RECTS;
        setColorsFromDigits(&digits, &colors);
        cmd.pushVertexUniformData(1, @ptrCast(&colors));
        pass.bindGraphicsPipeline(pipeline);
        pass.bindVertexBuffers(0, &[_]BufferBinding{.{ .buffer = vbo, .offset = 0 }});
        pass.drawPrimitives(6, NUM_RECTS, 0, 0);

        pass.bindGraphicsPipeline(tex_pipeline);
        for (0..digits.len) |i| {
            const digit = digits[i];
            cmd.pushVertexUniformData(1, @ptrCast(&digit));
            cmd.pushVertexUniformData(2, @ptrCast(&digitOffsets[digit]));
            pass.bindVertexBuffers(0, &[_]BufferBinding{.{ .buffer = tex_vboes[i], .offset = 0 }});
            pass.bindFragmentSamplers(0, &[_]TextureSamplerBinding{.{
                .texture = bmp_textures[digit],
                .sampler = sampler,
            }});
            pass.drawPrimitives(6, 1, 0, 0);
        }

        pass.end();
        try cmd.submit();
    }
}
