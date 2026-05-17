const std = @import("std");

pub fn Mmio(comptime PackedT: type) type {
    const size = @bitSizeOf(PackedT);
    const IntT = std.meta.Int(.unsigned, size);

    return extern struct {
        raw: IntT,

        pub const underlying_type = PackedT;

        pub fn read(addr: *volatile @This()) PackedT {
            return @bitCast(addr.raw);
        }

        pub fn write(addr: *volatile @This(), val: PackedT) void {
            addr.raw = @bitCast(val);
        }

        pub fn write_raw(addr: *volatile @This(), val: IntT) void {
            addr.raw = val;
        }

        pub fn read_raw(addr: *volatile @This()) IntT {
            return addr.raw;
        }

        pub fn modify_one(addr: *volatile @This(), comptime field_name: []const u8, value: @FieldType(underlying_type, field_name)) void {
            var val = addr.read();
            @field(val, field_name) = value;
            addr.write(val);
        }

        pub fn modify(addr: *volatile @This(), fields: anytype) void {
            var val = addr.read();
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                @field(val, field.name) = @field(fields, field.name);
            }
            addr.write(val);
        }
    };
}
