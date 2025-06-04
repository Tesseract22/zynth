const std = @import("std");
pub fn FixedRingBuffer(comptime T: type, comptime size: u32) type {
    return struct {
        const Self = @This();
        data: [size]T = undefined,
        active: std.StaticBitSet(size) = std.StaticBitSet(size).initEmpty(),
        head: u32 = 0,
        tail: u32 = 0,
        pub fn push(self: *Self, el: T) void {
            self.data[self.tail] = el;
            self.active.set(self.tail);
            self.tail = (self.tail + 1) % size;
            if (self.tail == self.head) {
                self.head = (self.head + 1) % size;
            }
        }
        pub fn remove(self: *Self, i: u32) void {
            self.active.unset(i);
        }
        pub fn at(self: Self, i: u32) T {
            return self.data[(self.head + i) % size];
        }
        pub fn last(self: *Self) *T {
            return &self.data[self.tail];
        }
    };
}
