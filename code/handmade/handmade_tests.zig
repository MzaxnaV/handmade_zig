const std = @import("std");
const testing = std.testing;

const intrinsics = @import("handmade_intrinsics.zig");
const math = @import("handmade_math.zig");

test "intrinsics" {
    try testing.expectEqual(intrinsics.AbsoluteValue(-0.2), 0.2);
    try testing.expectEqual(intrinsics.AbsoluteValue(0.2), 0.2);

    try testing.expectEqual(intrinsics.RoundF32ToInt(u32, -0.2), 0);
    try testing.expectEqual(intrinsics.RoundF32ToInt(u32, 0.2), 0);

    try testing.expectEqual(intrinsics.TruncateF32ToI32(1.2), 1);
    try testing.expectEqual(intrinsics.TruncateF32ToI32(-0.2), 0);
    try testing.expectEqual(intrinsics.TruncateF32ToI32(-1.2), -1);

    try testing.expectEqual(intrinsics.FloorF32ToI32(1.2), 1);
    try testing.expectEqual(intrinsics.FloorF32ToI32(0.2), 0);
    try testing.expectEqual(intrinsics.FloorF32ToI32(-0.2), -1);

    try testing.expectEqual(intrinsics.FindLeastSignificantSetBit(0b00000010), 1);
    try testing.expectEqual(intrinsics.FindLeastSignificantSetBit(0b01000000), 6);

    // TODO (Manav): add RotateLeft tests when the issue is fixed

    try testing.expectEqual(intrinsics.SquareRoot(0.04), 0.2);
    try testing.expectEqual(intrinsics.SquareRoot(25.0), 5.0);
}

test "math" {
    var vec1 = math.v2{ .x = 1, .y = 2 };
    const vec2 = math.v2{ .x = 5, .y = 0 };

    try testing.expectEqual(math.add(vec1, vec2), .{ .x = 6, .y = 2 });
    try testing.expectEqual(math.sub(vec1, vec2), .{ .x = -4, .y = 2 });
    try testing.expectEqual(math.neg(vec1), .{ .x = -1, .y = -2 });
    try testing.expectEqual(math.scale(vec1, 2), .{ .x = 2, .y = 4} );
    
    try testing.expectEqual(math.inner(vec1, vec2), 5);

    try testing.expectEqual(math.add(vec1, vec2), vec1.add(vec2).*);
    try testing.expectEqual(math.sub(vec1, vec2), vec1.sub(vec2).*);
    try testing.expectEqual(math.neg(vec1), vec1.neg().*);
    try testing.expectEqual(math.scale(vec1, 2), vec1.scale(2).*);
}
