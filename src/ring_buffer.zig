const std = @import("std");
pub fn FixedRingBuffer(comptime T: type, comptime size: u32) type {
    return struct {
        const Self = @This();
        data: [size]T = undefined,
        active: std.StaticBitSet(size) = std.StaticBitSet(size).initEmpty(),
        head: u32 = 0,
        tail: u32 = 0,
        count: u32 = 0,
        len: u32 = size,
        pub fn init(len: u32) Self {
            std.debug.assert(len <= size and len != 0);
            return .{ .len = len };
        }
        pub fn push(self: *Self, el: T) void {
            if (self.count == self.len) {
                self.head = (self.head + 1) % self.len;
            } else {
                self.count += 1;
            }
            self.data[self.tail] = el;
            self.active.set(self.tail);
            self.tail = (self.tail + 1) % self.len;
            
        }
        pub fn remove(self: *Self, i: u32) void {
            self.active.unset(i);
        }
        pub fn at(self: Self, i: u32) T {
            return self.data[(self.head + i) % self.len];
        }
        pub fn last(self: *Self) *T {
            return &self.data[self.tail];
        }
        pub fn is_full(self: Self) bool {
            return self.len == self.count;
        }
    };
}

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        data: []T,
        active: std.DynamicBitSetUnmanaged,
        head: u32 = 0,
        tail: u32 = 0,
        count: u32 = 0,
        pub fn init(len: u32, el: T, a: std.mem.Allocator) !Self {
            std.debug.assert(len != 0);
            const data = try a.alloc(T, len);
            @memset(data, el);
            return .{
                .data = data,
                .active = try std.DynamicBitSetUnmanaged.initEmpty(a, len),
            };
        }
        pub fn deinit(self: *Self, a: std.mem.Allocator) void {
            a.free(self.data);
            self.active.deinit(a);
        }
        pub fn push(self: *Self, el: T) void {
            if (self.count == self.data.len) {
                self.head = (self.head + 1) % @as(u32, @intCast(self.data.len));
            } else {
                self.count += 1;
            }
            self.data[self.tail] = el;
            self.active.set(self.tail);
            self.tail = (self.tail + 1) % @as(u32, @intCast(self.data.len));
        }
        pub fn remove(self: *Self, i: u32) void {
            self.active.unset(i);
        }
        pub fn at(self: Self, i: u32) T {
            return self.data[(self.head + i) % self.data.len];
        }
        pub fn last(self: *Self) *T {
            return &self.data[self.tail];
        }
        pub fn lenth(self: Self) u32 {
            return @intCast(self.data.len);
        }
        pub fn is_full(self: Self) bool {
            return self.data.len == self.count;
        }
    };
}
