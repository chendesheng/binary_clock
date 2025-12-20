pub fn FixedSizeArray(comptime size: usize, comptime T: type) type {
    return struct {
        buffer: []T,
        len: usize,
        const Self = @This();

        pub fn init(buffer: []T) !Self {
            if (buffer.len != size) {
                return error.InvalidBufferSize;
            }

            return .{
                .buffer = buffer,
                .len = 0,
            };
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len + 1 > size) {
                return error.NotEnoughSpaceToAppend;
            }

            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, items: []const T) !void {
            if (self.len + items.len > size) {
                return error.NotEnoughSpaceToAppend;
            }

            @memcpy(self.buffer[self.len .. self.len + items.len], items);
            self.len += items.len;
        }
    };
}
