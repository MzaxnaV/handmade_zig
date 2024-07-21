//! Provides debug functionality
//!
//! __Requirements when importing:__
//! - `const debug = @import("handmade_debug.zig");` must be within the top two lines of the file.

const std = @import("std");
const platform = @import("handmade_platform");

const h = struct {
    usingnamespace @import("intrinsics");

    usingnamespace @import("handmade_asset.zig");
    usingnamespace @import("handmade_math.zig");
    usingnamespace @import("handmade_render_group.zig");

    usingnamespace @import("handmade_file_formats.zig");
};

const ignore = platform.ignore;

pub const perf_analyzer = struct {
    const method = enum {
        llvm_mca,
    };

    pub fn Start(comptime m: method, comptime region: []const u8) void {
        @fence(.seq_cst);
        switch (m) {
            .llvm_mca => asm volatile ("# LLVM-MCA-BEGIN " ++ region ::: "memory"),
        }
    }

    pub fn End(comptime m: method, comptime region: []const u8) void {
        switch (m) {
            .llvm_mca => asm volatile ("# LLVM-MCA-END " ++ region ::: "memory"),
        }
        @fence(.seq_cst);
    }
};

const debug_counter_snapshot = struct {
    hitCount: u32 = 0,
    cycleCount: u64 = 0,
};

const SNAPSHOT_COUNT = 128;

const debug_counter_state = struct {
    fileName: ?[*:0]const u8,
    functionName: ?[*:0]const u8,

    lineNumber: u32,

    snapshots: [SNAPSHOT_COUNT]debug_counter_snapshot,
};

const debug_state = struct {
    snapshotIndex: u32,
    counterCount: u32,
    counterStates: [512]debug_counter_state,
    frameEndInfos: [SNAPSHOT_COUNT]platform.debug_frame_end_info,
};

pub const debugRecordsCount = __COUNTER__();

pub const TIMED_BLOCK = platform.TIMED_BLOCK;
pub const TIMED_BLOCK__impl = platform.TIMED_BLOCK__impl;

/// The function definition is replaced with
/// ```
/// // AUTOGENERATED ----------------------------------------------------------
/// {
///     return #counter;
/// }
/// // AUTOGENERATED ----------------------------------------------------------
/// ```
/// where #counter is the total no. of TIMED_BLOCK callsites.
pub fn __COUNTER__() comptime_int {
    // AUTOGENERATED ----------------------------------------------------------
    const counters = 37; // TODO (Manav): for now this is hardcoded, use process_timed_block to remove it
    // AUTOGENERATED ----------------------------------------------------------

    return counters + 1; // because of timed block in DEBUGReset
}

fn UpdateDebugRecords(debugState: *debug_state, counters: []platform.debug_record) void {
    for (0..counters.len) |counterIndex| {
        const source: *platform.debug_record = &counters[counterIndex];
        const dest: *debug_counter_state = &debugState.counterStates[debugState.counterCount];
        debugState.counterCount += 1;

        const hitCount_CycleCount: u64 = h.AtomicExchange(u64, @ptrCast(&source.counts), 0);
        const counts: platform.debug_record.packed_counts = @bitCast(hitCount_CycleCount);

        dest.fileName = source.fileName;
        dest.functionName = source.functionName;
        dest.lineNumber = source.lineNumber;
        dest.snapshots[debugState.snapshotIndex].hitCount = counts.hit;
        dest.snapshots[debugState.snapshotIndex].cycleCount = counts.cycle;
    }
}

// 5c0f - 小
// 8033 - 耳
// 6728 - 木
// 514e - 兎

pub var renderGroup: ?*h.render_group = null;
var leftEdge: f32 = 0;
var atY: f32 = 0;
var fontScale: f32 = 0;
var fontID: h.font_id = .{ .value = 0 };

pub fn DEBUGReset(assets: *h.game_assets, width: u32, height: u32) void {
    var block = TIMED_BLOCK__impl(__COUNTER__() - 1, @src()).Init(.{});
    defer block.End();

    var matchVectorFont = h.asset_vector{};
    var weightVectorFont = h.asset_vector{};

    matchVectorFont.e[@intFromEnum(h.asset_tag_id.Tag_FontType)] = @floatFromInt(@as(i32, @intFromEnum(h.asset_font_type.FontType_Debug)));
    weightVectorFont.e[@intFromEnum(h.asset_tag_id.Tag_FontType)] = 1.0;

    fontID = h.GetBestMatchFontFrom(
        assets,
        .Asset_Font,
        &matchVectorFont,
        &weightVectorFont,
    );

    fontScale = 1;
    renderGroup.?.Orthographic(width, height, 1);
    leftEdge = -0.5 * @as(f32, @floatFromInt(width));

    const info = assets.GetFontInfo(fontID);
    atY = 0.5 * @as(f32, @floatFromInt(height)) - h.GetStartingBaselineY(info) * fontScale;
}

inline fn IsHex(char: u8) bool {
    const result = (((char >= '0') and (char <= '9')) or ((char >= 'A') and (char <= 'F')));

    return result;
}

inline fn GetHex(char: u8) u32 {
    var result: u32 = 0;

    if ((char >= '0') and (char <= '9')) {
        result = char - '0';
    } else if ((char >= 'A') and (char <= 'F')) {
        result = 0xA + (char - 'A');
    }

    return result;
}

fn DEBUGTextLine(string: []const u8) void {
    if (renderGroup) |debugRenderGroup| {
        if (debugRenderGroup.PushFont(fontID)) |font| {
            const info = debugRenderGroup.assets.GetFontInfo(fontID);
            var prevCodePoint: u32 = 0;
            var charScale = fontScale;
            var colour = h.v4{ 1, 1, 1, 1 };
            var atX: f32 = leftEdge;

            var at = string[0..].ptr;
            while (at[0] != 0) {
                if (at[0] == '\\' and at[1] == '#' and at[2] != 0 and at[3] != 0 and at[4] != 0) {
                    const cScale = 1.0 / 9.0;
                    colour = h.ClampV401(h.v4{
                        h.Clampf01(cScale * @as(f32, @floatFromInt(at[2] - '0'))),
                        h.Clampf01(cScale * @as(f32, @floatFromInt(at[3] - '0'))),
                        h.Clampf01(cScale * @as(f32, @floatFromInt(at[4] - '0'))),
                        1,
                    });
                    at += 5;
                } else if (at[0] == '\\' and at[1] == '^' and at[2] != 0) {
                    const cScale = 1.0 / 9.0;
                    charScale = fontScale * h.Clampf01(cScale * @as(f32, @floatFromInt(at[2] - '0')));
                    at += 3;
                } else {
                    var codePoint: u32 = at[0];

                    if ((at[0] == '\\') and
                        (IsHex(at[1])) and
                        (IsHex(at[2])) and
                        (IsHex(at[3])) and
                        (IsHex(at[4])))
                    {
                        codePoint = ((GetHex(at[1]) << 12) |
                            (GetHex(at[2]) << 8) |
                            (GetHex(at[3]) << 4) |
                            (GetHex(at[4]) << 0));

                        at += 4;
                    }

                    const advanceX: f32 = charScale * h.GetHorizontalAdvanceForPair(info, font, prevCodePoint, codePoint);
                    atX += advanceX;

                    if (codePoint != ' ') {
                        const bitmapID = h.GetBitmapForGlyph(debugRenderGroup.assets, info, font, codePoint);
                        const info_ = debugRenderGroup.assets.GetBitmapInfo(bitmapID);

                        // advanceX = charScale * @as(f32, @floatFromInt(info.dim[0] + 2));
                        debugRenderGroup.PushBitmap2(bitmapID, charScale * @as(f32, @floatFromInt(info_.dim[1])), .{ atX, atY, 0 }, colour);
                    }

                    prevCodePoint = @intCast(codePoint);

                    at += 1;
                }
            }

            atY -= h.GetLineAdvanceFor(info) * fontScale;
        }
    }
}

const debug_statistic = struct {
    min: f64,
    max: f64,
    avg: f64,
    count: u32,

    const Self = @This();

    fn BeginDebugStatistic(stat: *Self) void {
        stat.min = platform.F32MAXIMUM;
        stat.max = -platform.F32MAXIMUM;
        stat.avg = 0;
        stat.count = 0;
    }

    fn EndDebugStatistic(stat: *Self) void {
        if (stat.count != 0) {
            stat.avg /= @floatFromInt(stat.count);
        } else {
            stat.min = 0;
            stat.max = 0;
        }
    }

    fn AccumDebugStatistic(stat: *Self, value: f64) void {
        stat.count += 1;
        if (stat.min > value) {
            stat.min = value;
        }

        if (stat.max < value) {
            stat.max = value;
        }

        stat.avg += value;
    }
};

pub fn Overlay(memory: *platform.memory) void {
    if (@as(?*debug_state, @alignCast(@ptrCast(memory.debugStorage)))) |debugState| {
        if (renderGroup) |debugRenderGroup| {
            if (debugRenderGroup.PushFont(fontID)) |_| {
                const info = debugRenderGroup.assets.GetFontInfo(fontID);

                for (0..debugState.counterCount) |counterIndex| {
                    const counter = &debugState.counterStates[counterIndex];

                    var hitCount: debug_statistic = undefined;
                    var cycleCount: debug_statistic = undefined;
                    var cycleOverHit: debug_statistic = undefined;

                    hitCount.BeginDebugStatistic();
                    cycleCount.BeginDebugStatistic();
                    cycleOverHit.BeginDebugStatistic();

                    for (counter.snapshots) |snapshot| {
                        const cycles: u32 = @truncate(snapshot.cycleCount);
                        hitCount.AccumDebugStatistic(@floatFromInt(snapshot.hitCount));
                        cycleCount.AccumDebugStatistic(@floatFromInt(cycles));

                        var coh: f64 = 0;
                        if (snapshot.hitCount != 0) {
                            coh = @as(f64, @floatFromInt(snapshot.cycleCount)) / @as(f64, @floatFromInt(snapshot.hitCount));
                        }
                        cycleOverHit.AccumDebugStatistic(coh);
                    }

                    hitCount.EndDebugStatistic();
                    cycleCount.EndDebugStatistic();
                    cycleOverHit.EndDebugStatistic();

                    if (counter.functionName) |functionName| {
                        if (cycleCount.max > 0) {
                            const barWidth = 4;
                            const chartLeft = 0;
                            const chartMinY = atY;
                            const chartHeight = info.ascenderHeight * fontScale;

                            const scale: f32 = @floatCast(1 / cycleCount.max);
                            for (0..counter.snapshots.len) |snapshotIndex| {
                                const thisProportion = scale * @as(f32, @floatFromInt(counter.snapshots[snapshotIndex].cycleCount));
                                const thisHeight = chartHeight * thisProportion;
                                debugRenderGroup.PushRect(
                                    .{ chartLeft + @as(f32, @floatFromInt(snapshotIndex)) * barWidth + 0.5 * barWidth, chartMinY + 0.5 * thisHeight, 0 },
                                    .{ barWidth, thisHeight },
                                    .{ thisProportion, 1, 0, 1 },
                                );
                            }
                        }

                        if (!platform.ignore) {
                            var textBuffer = [1]u8{0} ** 256;
                            const buffer = std.fmt.bufPrint(textBuffer[0..], "{s:32}({:4}) - {:10}cy {:8}h {:10}cy/h\n", .{
                                functionName,
                                counter.lineNumber,
                                @as(u32, @intFromFloat(cycleCount.avg)),
                                @as(u32, @intFromFloat(hitCount.avg)),
                                @as(u32, @intFromFloat(cycleOverHit.avg)),
                            }) catch |err| {
                                std.debug.print("{}\n", .{err});
                                return;
                            };

                            DEBUGTextLine(buffer);
                        }
                    }
                }

                const barWidth = 8;
                const barSpacing = 10;
                const chartLeft = leftEdge + 10;
                const chartHeight = 300.0;
                const chartWidth = barSpacing * SNAPSHOT_COUNT;
                const chartMinY = atY - (chartHeight + 80);
                const scale = 1.0 / 0.03333;

                const colours = [_]h.v3{
                    .{ 1, 0, 0 }, // ExecutableReady
                    .{ 0, 1, 0 }, // InputProcessed
                    .{ 0, 0, 1 }, // GameUpdated
                    .{ 1, 1, 0 }, // AudioUpdated
                    .{ 0, 1, 1 }, // FramerateWaitComplete
                    .{ 1, 0, 1 }, // EndOfFrame
                    .{ 1, 0.5, 0 },
                    .{ 1, 0, 0.5 },
                    .{ 0.5, 1, 0 },
                    .{ 0, 1, 0.5 },
                    .{ 0.5, 0, 1 },
                    .{ 0, 0.5, 1 },
                };

                for (0..SNAPSHOT_COUNT) |snapshotIndex| {
                    const frameEndInfo = &debugState.frameEndInfos[snapshotIndex];

                    var stackY: f32 = chartMinY;
                    var previousTimestampSeconds: f32 = 0;
                    for (0..frameEndInfo.timestampCount) |timestampIndex| {
                        const timestamp = &frameEndInfo.timestamps[timestampIndex];
                        const thisSecondElapsed = timestamp.seconds - previousTimestampSeconds;
                        previousTimestampSeconds = timestamp.seconds;

                        const colour = colours[timestampIndex % colours.len];
                        const thisProportion = scale * thisSecondElapsed;
                        const thisHeight = chartHeight * thisProportion;
                        debugRenderGroup.PushRect(
                            .{ chartLeft + @as(f32, @floatFromInt(snapshotIndex)) * barSpacing + 0.5 * barWidth, stackY + 0.5 * thisHeight, 0 },
                            .{ barWidth, thisHeight },
                            h.ToV4(colour, 1),
                        );

                        stackY += thisHeight;
                    }
                }

                debugRenderGroup.PushRect(
                    .{ chartLeft + 0.5 * chartWidth, chartMinY + chartHeight, 0 },
                    .{ chartWidth, 1 },
                    .{ 1, 1, 1, 1 },
                );
            }
        }

        // DEBUGTextLine("\\5C0F\\8033\\6728\\514E");
        // DEBUGTextLine("111111");
        // DEBUGTextLine("999999");
        // DEBUGTextLine("AVA WA Ta");
    }
}

fn CollateDebugRecords(debugState: *debug_state, events: []platform.debug_event) void {
    debugState.counterCount = debugRecordsCount;

    for (0..debugState.counterCount) |counterIndex| {
        const dest: *debug_counter_state = &debugState.counterStates[counterIndex];

        dest.snapshots[debugState.snapshotIndex].hitCount = 0;
        dest.snapshots[debugState.snapshotIndex].cycleCount = 0;
    }

    // const counterArray = .{debugState.counterStates};
    var debugRecords = platform.globalDebugTable.records;

    for (0..events.len) |eventIndex| {
        const event = &events[eventIndex];

        var dest: *debug_counter_state = &debugState.counterStates[event.debugRecordIndex];
        const source: *platform.debug_record = &debugRecords[event.translationUnit][event.debugRecordIndex];

        dest.fileName = source.fileName;
        dest.functionName = source.functionName;
        dest.lineNumber = source.lineNumber;

        switch (event.eventType) {
            .DebugEvent_BeginBlock => {
                dest.snapshots[debugState.snapshotIndex].hitCount += 1;
                // NOTE (Manav): ignore overflow issues for now.
                dest.snapshots[debugState.snapshotIndex].cycleCount -%= event.clock;
            },
            .DebugEvent_EndBlock => {
                dest.snapshots[debugState.snapshotIndex].cycleCount +%= event.clock;
            },
        }
    }
}

pub export fn DEBUGFrameEnd(memory: *platform.memory, info: *platform.debug_frame_end_info) void {
    comptime {
        // NOTE (Manav): This is hacky atm. Need to check as we're using win32.LoadLibrary()
        if (@typeInfo(platform.DEBUGFrameEndsFnPtrType).Pointer.child != @TypeOf(DEBUGFrameEnd)) {
            @compileError("Function signature mismatch!");
        }
    }

    // NOTE (Manav): no need to switch since we don't need it.
    platform.globalDebugTable.currentEventArrayIndex = 0; // !platform.globalDebugTable.currentEventArrayIndex;

    const arrayIndex_eventIndex = h.AtomicExchange(
        u64,
        @ptrCast(&platform.globalDebugTable.indices),
        @as(u64, platform.globalDebugTable.currentEventArrayIndex) << 32,
    );

    const indices: platform.debug_table.packed_indices = @bitCast(arrayIndex_eventIndex);

    const eventArrayIndex = indices.eventArrayIndex;
    const eventCount = indices.eventIndex;

    if (@as(?*debug_state, @alignCast(@ptrCast(memory.debugStorage)))) |debugState| {
        debugState.counterCount = 0;

        CollateDebugRecords(debugState, platform.globalDebugTable.events[eventArrayIndex][0..eventCount]);

        debugState.frameEndInfos[debugState.snapshotIndex] = info.*;

        debugState.snapshotIndex += 1;
        if (debugState.snapshotIndex >= SNAPSHOT_COUNT) {
            debugState.snapshotIndex = 0;
        }
    }
}
