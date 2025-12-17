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
const TransferBufferCreateInfo = sdl3.gpu.TransferBufferCreateInfo;
const BufferCreateInfo = sdl3.gpu.BufferCreateInfo;
const TransferBuffer = sdl3.gpu.TransferBuffer;
const Buffer = sdl3.gpu.Buffer;
const BufferUsageFlags = sdl3.gpu.BufferUsageFlags;
const CopyPass = sdl3.gpu.CopyPass;

const Self = @This();
gpu: Device,
buf: Buffer,
transfer_buf: TransferBuffer,
size: u32,

pub fn init(gpu: Device, createInfo: BufferCreateInfo) !Self {
    const buf = try gpu.createBuffer(createInfo);
    const transfer_buf = try gpu.createTransferBuffer(.{
        .usage = .upload,
        .size = createInfo.size,
    });

    return .{
        .gpu = gpu,
        .buf = buf,
        .transfer_buf = transfer_buf,
        .size = createInfo.size,
    };
}

pub fn deinit(self: *const Self) void {
    self.gpu.releaseTransferBuffer(self.transfer_buf);
    self.gpu.releaseBuffer(self.buf);
}

pub fn initFromData(gpu: Device, comptime T: type, data: []const T, useage: BufferUsageFlags) !Self {
    const self = try init(gpu, .{ .size = @intCast(data.len * @sizeOf(T)), .usage = useage });
    const mapped = try self.mapTransferBuffer(T, false);
    @memcpy(mapped, data);
    self.unmapTransferBuffer();
    return self;
}

pub fn initFromSurface(gpu: Device, surf: Surface, useage: BufferUsageFlags) !Self {
    const self = try init(gpu, .{ .size = @intCast(surf.getPitch() * surf.getHeight()), .usage = useage });
    try self.copySurfaceToMapped(surf);
    return self;
}

fn copySurfaceToMapped(self: *const Self, surf: Surface) !void {
    const mapped = try self.gpu.mapTransferBuffer(self.transfer_buf, false);
    defer self.gpu.unmapTransferBuffer(self.transfer_buf);
    if (surf.getPixels()) |pixels| {
        @memcpy(mapped, pixels);
    }
}

pub fn mapTransferBuffer(self: *const Self, comptime T: type, cycle: bool) ![]T {
    const mapped = try self.gpu.mapTransferBuffer(self.transfer_buf, cycle);
    return @alignCast(std.mem.bytesAsSlice(T, mapped[0..self.size]));
}

pub fn unmapTransferBuffer(self: *const Self) void {
    self.gpu.unmapTransferBuffer(self.transfer_buf);
}

pub fn uploadToBuffer(self: *const Self, pass: CopyPass, cycle: bool) void {
    pass.uploadToBuffer(.{ .offset = 0, .transfer_buffer = self.transfer_buf }, .{ .buffer = self.buf, .offset = 0, .size = self.size }, cycle);
}

pub fn uploadToTexture(self: *const Self, pass: CopyPass, dst: TextureRegion, cycle: bool) void {
    const src = TextureTransferInfo{
        .transfer_buffer = self.transfer_buf,
        .offset = 0,
        .pixels_per_row = dst.width,
        .rows_per_layer = dst.height,
    };
    pass.uploadToTexture(src, dst, cycle);
}

pub fn createBufferBinding(self: *const Self, offset: u32) BufferBinding {
    return BufferBinding{
        .buffer = self.buf,
        .offset = offset,
    };
}

pub fn createBufferBindings(self: *const Self, offset: u32) [1]BufferBinding {
    return [_]BufferBinding{
        BufferBinding{
            .buffer = self.buf,
            .offset = offset,
        },
    };
}
