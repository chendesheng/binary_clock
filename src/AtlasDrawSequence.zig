const ttf = @import("sdl3").ttf;

pub fn AtlasDrawSequence(comptime T: type) type {
    return struct {
        const Self = @This();
        _current: T,

        pub fn init(sequence: T) Self {
            return .{
                ._current = sequence,
            };
        }

        pub fn moveNext(self: *Self) void {
            if (self._current) |current| {
                self._current = current.*.next;
            }
        }

        pub fn getCurrent(self: *Self) ?ttf.GpuAtlasDrawSequence {
            if (self._current) |current| {
                return ttf.GpuAtlasDrawSequence.fromSdl(current);
            }
            return null;
        }
    };
}
