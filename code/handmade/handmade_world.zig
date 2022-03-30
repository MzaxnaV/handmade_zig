const std = @import("std");
const assert = std.debug.assert;

const hi = @import("handmade_internals.zig");
const hm = @import("handmade_math.zig");
const he = @import("handmade_entity.zig");
const hsr = @import("handmade_sim_region.zig");

const RoundF32ToInt = @import("handmade_intrinsics.zig").RoundF32ToInt;

// constants ------------------------------------------------------------------------------------------------------------------------------

const TILE_CHUNK_SAFE_MARGIN = std.math.maxInt(i32) / 64;
const TILE_CHUNK_UNINITIALIZED = std.math.maxInt(i32);

const TILES_PER_CHUNK = 16;

// tile data types ------------------------------------------------------------------------------------------------------------------------

pub const world_difference = struct {
    dXY: hm.v2 = hm.v2{ 0, 0 },
    dZ: f32 = 0,
};

pub const world_position = struct {
    chunkX: i32 = 0,
    chunkY: i32 = 0,
    chunkZ: i32 = 0,

    offset_: hm.v2 = hm.v2{ 0, 0 },
};

pub const world_entity_block = struct {
    entityCount: u32,
    lowEntityIndex: [16]u32,
    next: ?*world_entity_block,
};

pub const world_chunk = struct {
    chunkX: i32,
    chunkY: i32,
    chunkZ: i32,

    firstBlock: world_entity_block,

    nextInHash: ?*world_chunk = null,
};

pub const world = struct {
    tileSideInMeters: f32,
    chunkSideInMeters: f32,

    firstFree: ?*world_entity_block,

    chunkHash: [4096]world_chunk,
};

// public inline functions ----------------------------------------------------------------------------------------------------------------

pub inline fn NullPosition() world_position {
    const result: world_position = .{
        .chunkX = TILE_CHUNK_UNINITIALIZED,
    };
    return result;
}

pub inline fn IsValid(p: world_position) bool {
    const result = p.chunkX != TILE_CHUNK_UNINITIALIZED;
    return result;
}

inline fn IsCanonicalCoord(w: *const world, tileRel: f32) bool {
    const epsilon = 0.0001;
    const result = (tileRel >= -(0.5 * w.chunkSideInMeters + epsilon)) and (tileRel <= (0.5 * w.chunkSideInMeters + epsilon));
    return result;
}

inline fn IsCanonical(w: *const world, offset: hm.v2) bool {
    const result = IsCanonicalCoord(w, offset[0]) and IsCanonicalCoord(w, offset[1]);
    return result;
}

inline fn AreInSameChunk(w: *const world, a: *const world_position, b: *const world_position) bool {
    assert(IsCanonical(w, a.offset_));
    assert(IsCanonical(w, b.offset_));

    const result = (a.chunkX == b.chunkX) and (a.chunkY == b.chunkY) and (a.chunkZ == b.chunkZ);
    return result;
}

pub fn GetWorldChunk(memoryArena: ?*hi.memory_arena, w: *world, chunkX: i32, chunkY: i32, chunkZ: i32) ?*world_chunk {
    assert(chunkX > -TILE_CHUNK_SAFE_MARGIN);
    assert(chunkY > -TILE_CHUNK_SAFE_MARGIN);
    assert(chunkZ > -TILE_CHUNK_SAFE_MARGIN);
    assert(chunkX < TILE_CHUNK_SAFE_MARGIN);
    assert(chunkY < TILE_CHUNK_SAFE_MARGIN);
    assert(chunkZ < TILE_CHUNK_SAFE_MARGIN);

    const hashValue = @bitCast(u32, 19 * chunkX + 7 * chunkY + 3 * chunkZ);
    const hashSlot = hashValue & (w.chunkHash.len - 1);
    assert(hashSlot < w.chunkHash.len);

    var worldChunk: ?*world_chunk = &w.chunkHash[hashSlot];

    while (worldChunk) |*chunk| {
        if ((chunkX == chunk.*.chunkX) and (chunkY == chunk.*.chunkY) and (chunkZ == chunk.*.chunkZ)) {
            break;
        }

        if (memoryArena) |arena| {
            if ((chunk.*.chunkX != TILE_CHUNK_UNINITIALIZED) and (chunk.*.nextInHash == null)) {
                chunk.*.nextInHash = arena.PushStruct(world_chunk);
                worldChunk = chunk.*.nextInHash;
                chunk.*.chunkX = TILE_CHUNK_UNINITIALIZED;
            }

            if (chunk.*.chunkX == TILE_CHUNK_UNINITIALIZED) {
                chunk.*.chunkX = chunkX;
                chunk.*.chunkY = chunkY;
                chunk.*.chunkZ = chunkZ;

                chunk.*.nextInHash = null;
                break;
            }
        }

        worldChunk = chunk.*.nextInHash;
    }

    return worldChunk;
}

inline fn RecanonicalizeCoord(w: *const world, tile: *i32, tileRel: *f32) void {
    var offSet = RoundF32ToInt(i32, tileRel.* / w.chunkSideInMeters);
    tile.* +%= offSet;
    tileRel.* -= @intToFloat(f32, offSet) * w.chunkSideInMeters;

    assert(IsCanonicalCoord(w, tileRel.*));
}

pub inline fn MapIntoChunkSpace(w: *const world, basePos: world_position, offset: hm.v2) world_position {
    var result = basePos;

    result.offset_ += offset; // NOTE (Manav): result.offset_ += offset

    var tileRel = .{ .x = result.offset_[0], .y = result.offset_[1] };

    RecanonicalizeCoord(w, &result.chunkX, &tileRel.x);
    RecanonicalizeCoord(w, &result.chunkY, &tileRel.y);

    result.offset_ = .{ tileRel.x, tileRel.y };

    return result;
}

pub inline fn ChunkPosFromTilePos(w: *world, absTileX: i32, absTileY: i32, absTileZ: i32) world_position {
    var result: world_position = .{
        .chunkX = @divTrunc(absTileX, TILES_PER_CHUNK),
        .chunkY = @divTrunc(absTileY, TILES_PER_CHUNK),
        .chunkZ = @divTrunc(absTileZ, TILES_PER_CHUNK),
    };

    if (absTileX < 0) {
        result.chunkX -= 1;
    }
    if (absTileY < 0) {
        result.chunkY -= 1;
    }
    if (absTileZ < 0) {
        result.chunkZ -= 1;
    }

    result.offset_ = .{
        // check against mod use
        @intToFloat(f32, (absTileX - TILES_PER_CHUNK / 2) - (result.chunkX * TILES_PER_CHUNK)) * w.tileSideInMeters,
        @intToFloat(f32, (absTileY - TILES_PER_CHUNK / 2) - (result.chunkY * TILES_PER_CHUNK)) * w.tileSideInMeters,
    };

    std.debug.assert(IsCanonical(w, result.offset_));

    return result;
}

pub inline fn Substract(w: *const world, a: *const world_position, b: *const world_position) world_difference {
    const dTileXY = hm.v2{
        @intToFloat(f32, a.chunkX) - @intToFloat(f32, b.chunkX),
        @intToFloat(f32, a.chunkY) - @intToFloat(f32, b.chunkY),
    };
    const dTileZ = @intToFloat(f32, a.chunkZ) - @intToFloat(f32, b.chunkZ);

    const result = world_difference{
        .dXY = (@splat(2, w.chunkSideInMeters) * dTileXY) + (a.offset_ - b.offset_),
        .dZ = w.chunkSideInMeters * dTileZ,
    };

    return result;
}

inline fn CenteredChunkPoint(chunkX: u32, chunkY: u32, chunkZ: u32) world_position {
    const result = world_position{
        .chunkX = @intCast(i32, chunkX),
        .chunkY = @intCast(i32, chunkY),
        .chunkZ = @intCast(i32, chunkZ),
    };

    return result;
}

pub fn ChangeEntityLocationRaw(arena: *hi.memory_arena, w: *world, lowEntityIndex: u32, oldP: ?*const world_position, newP: ?*const world_position) void {
    std.debug.assert((oldP == null) or IsValid(oldP.?.*));
    std.debug.assert((newP == null) or IsValid(newP.?.*));

    if ((oldP != null) and (newP != null) and AreInSameChunk(w, oldP.?, newP.?)) {} else {
        if (oldP) |p| {
            if (GetWorldChunk(null, w, p.chunkX, p.chunkY, p.chunkZ)) |chunk| {
                var notFound = true;
                var firstBlock = &chunk.firstBlock;
                var entityBlock: ?*world_entity_block = firstBlock;
                while (entityBlock) |block| : (entityBlock = block.next) {
                    if (!notFound) {
                        break;
                    }
                    var index = @as(u32, 0);
                    while ((index < block.entityCount) and notFound) : (index += 1) {
                        if ((block.lowEntityIndex[index] == lowEntityIndex)) {
                            assert(firstBlock.entityCount > 0);
                            firstBlock.entityCount -= 1;
                            block.lowEntityIndex[index] = firstBlock.lowEntityIndex[firstBlock.entityCount];
                            if (firstBlock.entityCount == 0) {
                                if (firstBlock.next) |_| {
                                    const nextBlock = firstBlock.next;
                                    firstBlock.* = nextBlock.?.*;

                                    nextBlock.?.next = w.firstFree;
                                    w.firstFree = nextBlock;
                                }
                            }

                            notFound = false;
                        }
                    }
                }
            } else {
                unreachable;
            }
        }

        if (newP) |p| {
            if (GetWorldChunk(arena, w, p.chunkX, p.chunkY, p.chunkZ)) |chunk| {
                var block = &chunk.firstBlock;
                if (block.entityCount == block.lowEntityIndex.len) {
                    var oldBlock = w.firstFree;
                    if (oldBlock) |b| {
                        w.firstFree = b.next;
                    } else {
                        oldBlock = arena.PushStruct(world_entity_block);
                    }

                    oldBlock.?.* = block.*;
                    block.next = oldBlock;
                    block.entityCount = 0;
                }

                std.debug.assert(block.entityCount < block.lowEntityIndex.len);
                block.lowEntityIndex[block.entityCount] = lowEntityIndex;
                block.entityCount += 1;
            } else {
                unreachable;
            }
        }
    }
}

// public functions -----------------------------------------------------------------------------------------------------------------------

pub fn ChangeEntityLocation(arena: *hi.memory_arena, w: *world, lowEntityIndex: u32, lowEntity: *hi.low_entity, newPInit: world_position) void {
    var oldP: ?*const world_position = null;
    var newP: ?*const world_position = null;

    if (!he.IsSet(&lowEntity.sim, @enumToInt(hsr.sim_entity_flags.NonSpatial)) and IsValid(lowEntity.p)) {
        oldP = &lowEntity.p;
    }

    if (IsValid(newPInit)) {
        newP = &newPInit;
    }

    ChangeEntityLocationRaw(arena, w, lowEntityIndex, oldP, newP);

    if (newP) |p| {
        lowEntity.p = p.*;
        he.ClearFlag(&lowEntity.sim, @enumToInt(hsr.sim_entity_flags.NonSpatial));
    } else {
        lowEntity.p = NullPosition();
        he.AddFlag(&lowEntity.sim, @enumToInt(hsr.sim_entity_flags.NonSpatial));
    }
}

pub fn InitializeWorld(w: *world, tileSideInMeters: f32) void {
    w.tileSideInMeters = tileSideInMeters;
    w.chunkSideInMeters = TILES_PER_CHUNK * tileSideInMeters;
    w.firstFree = null;

    for (w.chunkHash) |*chunk| {
        chunk.chunkX = TILE_CHUNK_UNINITIALIZED;
        chunk.firstBlock.entityCount = 0;
    }
}
