const sdl3 = @import("sdl3");
const ttf = sdl3.ttf;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = sdl3.gpu.Buffer;
const BufferBinding = sdl3.gpu.BufferBinding;
const BufferCreateInfo = sdl3.gpu.BufferCreateInfo;
const BufferUsageFlags = sdl3.gpu.BufferUsageFlags;
const ColorTargetBlendState = sdl3.gpu.ColorTargetBlendState;
const ColorTargetDescription = sdl3.gpu.ColorTargetDescription;
const ColorTargetInfo = sdl3.gpu.ColorTargetInfo;
const CommandBuffer = sdl3.gpu.CommandBuffer;
const CopyPass = sdl3.gpu.CopyPass;
const Device = sdl3.gpu.Device;
const GraphicsPipeline = sdl3.gpu.GraphicsPipeline;
const Sampler = sdl3.gpu.Sampler;
const Shader = sdl3.gpu.Shader;
const ShaderStage = sdl3.gpu.ShaderStage;
const Surface = sdl3.surface.Surface;
const Texture = sdl3.gpu.Texture;
const TextureFormat = sdl3.gpu.TextureFormat;
const TextureRegion = sdl3.gpu.TextureRegion;
const TextureSamplerBinding = sdl3.gpu.TextureSamplerBinding;
const TextureTransferInfo = sdl3.gpu.TextureTransferInfo;
const TransferBuffer = sdl3.gpu.TransferBuffer;
const TransferBufferCreateInfo = sdl3.gpu.TransferBufferCreateInfo;
const TransferBufferUsage = sdl3.gpu.TransferBufferUsage;
const VertexAttribute = sdl3.gpu.VertexAttribute;
const VertexBufferDescription = sdl3.gpu.VertexBufferDescription;
const VertexElementFormat = sdl3.gpu.VertexElementFormat;

const Self = @This();
gpu: Device,
transfer_buf: TransferBuffer,
size: u32,

pub fn init(gpu: Device, createInfo: TransferBufferCreateInfo) !Self {
    const transfer_buf = try gpu.createTransferBuffer(.{
        .usage = .upload,
        .size = createInfo.size,
    });

    return .{
        .gpu = gpu,
        .transfer_buf = transfer_buf,
        .size = createInfo.size,
    };
}

pub fn deinit(self: *const Self) void {
    self.gpu.releaseTransferBuffer(self.transfer_buf);
}

pub fn initFromData(gpu: Device, comptime T: type, data: []const T, useage: TransferBufferUsage) !Self {
    const self = try init(gpu, .{ .size = @intCast(data.len * @sizeOf(T)), .usage = useage });
    const mapped = try self.map(T, false);
    @memcpy(mapped, data);
    self.unmap();
    return self;
}

pub fn initFromSurface(gpu: Device, surf: Surface, useage: TransferBufferUsage) !Self {
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

pub fn map(self: *const Self, comptime T: type, cycle: bool) ![]T {
    const mapped = try self.gpu.mapTransferBuffer(self.transfer_buf, cycle);
    return @alignCast(std.mem.bytesAsSlice(T, mapped[0..self.size]));
}

pub fn unmap(self: *const Self) void {
    self.gpu.unmapTransferBuffer(self.transfer_buf);
}

pub fn uploadToBuffer(self: *const Self, pass: CopyPass, buffer: Buffer, cycle: bool) void {
    pass.uploadToBuffer(.{ .offset = 0, .transfer_buffer = self.transfer_buf }, .{ .buffer = buffer, .offset = 0, .size = self.size }, cycle);
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
