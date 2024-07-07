//! Provides debug functionality
//!
//! __Requirements when importing:__
//! - `const debug = @import("handmade_debug.zig");` must be within the top two lines of the file.

const std = @import("std");
const platform = @import("handmade_platform");

const SourceLocation = std.builtin.SourceLocation;

const h = struct {
    usingnamespace @import("intrinsics");

    usingnamespace @import("handmade_asset.zig");
    usingnamespace @import("handmade_math.zig");
    usingnamespace @import("handmade_render_group.zig");

    usingnamespace @import("handmade_file_formats.zig");
};

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

const record = struct {
    fileName: []const u8 = "",
    functionName: []const u8 = "",

    lineNumber: u32 = 0,

    counts: packed struct(u64) {
        hit: u32 = 0,
        cycle: u32 = 0,
    } = .{},
};

const counter_snapshot = struct {
    hitCount: u32 = 0,
    cycleCount: u32 = 0,
};

const SNAPSHOT_COUNT = 128;

const counter_state = struct {
    fileName: []const u8,
    functionName: []const u8,

    lineNumber: u32,

    snapshots: [SNAPSHOT_COUNT]counter_snapshot,
};

const state = struct {
    snapshotIndex: u32,
    counterCount: u32,
    counterStates: [512]counter_state,
    frameEndInfos: [SNAPSHOT_COUNT]platform.debug_frame_end_info,
};

/// NOTE (Manav): We don't need two sets of theses because of how `TIMED_BLOCK()` works
pub var recordArray = [1]record{.{}} ** __COUNTER__();

/// The function at call site  will be replaced, using a preprocesing tool, with
/// ```
/// debug.TIMED_BLOCK(...);
/// // AUTOGENERATED ----------------------------------------------------------
/// var __t_blk__#counter = debug.TIMED_BLOCK__impl(#counter, @src()).Init(...);
/// defer __t_blk__#counter.End()
/// // AUTOGENERATED ----------------------------------------------------------
/// ```
/// - #counter will be generated based on `TIMED_BLOCK` call sites.
/// - debug is assumed to be imported at the very top.
pub inline fn TIMED_BLOCK(_: struct { hitCount: u32 = 1 }) void {}

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
    const counters = 36; // TODO (Manav): for now this is hardcoded, use process_timed_block to remove it
    // AUTOGENERATED ----------------------------------------------------------

    return counters + 1;
}

/// It relies on `__counter__` is to be supplied at build time using a preprocessing tool,
/// called everytime lib is built. For now use this with hardcoded `__counter__` values until we have one
// NOTE (Manav): zig (0.13) by design, doesn't allow for a way to have a global comptime counter and we don't have unity build.
pub fn TIMED_BLOCK__impl(comptime __counter__: usize, comptime source: SourceLocation) type {
    return struct {
        const Self = @This();

        pub inline fn Init(args: struct { hitCount: u32 = 1 }) Self {
            var self = Self{
                .record = &recordArray[__counter__],
                .startCycles = 0,
                .hitCount = args.hitCount,
            };

            self.record.fileName = source.file;
            self.record.lineNumber = source.line;
            self.record.functionName = source.fn_name;

            self.startCycles = h.__rdtsc();

            return self;
        }

        pub inline fn End(self: *Self) void {
            const delta: u64 = h.__rdtsc() - self.startCycles | @as(u64, self.hitCount) << 32;
            _ = @atomicRmw(u64, @as(*u64, @ptrCast(&self.record.counts)), .Add, delta, .seq_cst);
        }

        record: *record,
        startCycles: u64,
        hitCount: u32,
    };
}

fn UpdateDebugRecords(debugState: *state, counters: []record) void {
    for (0..recordArray.len) |counterIndex| {
        const source: *record = &counters[counterIndex];
        const dest: *counter_state = &debugState.counterStates[debugState.counterCount];
        debugState.counterCount += 1;

        const hitCount_CycleCount = h.AtomicExchange(u64, @as(*u64, @ptrCast(&source.counts)), 0);

        dest.fileName = source.fileName;
        dest.functionName = source.functionName;
        dest.lineNumber = source.lineNumber;
        dest.snapshots[debugState.snapshotIndex].hitCount = @intCast(hitCount_CycleCount >> 32);
        dest.snapshots[debugState.snapshotIndex].cycleCount = @intCast(hitCount_CycleCount & 0xffffffff); //TODO (Manav): use @truncate() ?
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
    if (@as(?*state, @alignCast(@ptrCast(memory.debugStorage)))) |debugState| {
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
                        hitCount.AccumDebugStatistic(@floatFromInt(snapshot.hitCount));
                        cycleCount.AccumDebugStatistic(@floatFromInt(snapshot.cycleCount));

                        var coh: f64 = 0;
                        if (snapshot.hitCount != 0) {
                            coh = @as(f64, @floatFromInt(snapshot.cycleCount)) / @as(f64, @floatFromInt(snapshot.hitCount));
                        }
                        cycleOverHit.AccumDebugStatistic(coh);
                    }

                    hitCount.EndDebugStatistic();
                    cycleCount.EndDebugStatistic();
                    cycleOverHit.EndDebugStatistic();

                    if (counter.functionName.len != 0) {
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
                                counter.functionName,
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
                const chartMinY = atY - (chartHeight + 10);
                const scale = 1.0 / 0.03333;

                for (0..SNAPSHOT_COUNT) |snapshotIndex| {
                    const frameEndInfo = &debugState.frameEndInfos[snapshotIndex];
                    var previousTimestampSeconds: f32 = 0;
                    for (0..frameEndInfo.timestampCount) |timestampIndex| {
                        const timestamp = &frameEndInfo.timestamps[timestampIndex];
                        const thisSecondElapsed = timestamp.seconds - previousTimestampSeconds;
                        previousTimestampSeconds = timestamp.seconds;

                        const thisProportion = scale * thisSecondElapsed;
                        const thisHeight = chartHeight * thisProportion;
                        debugRenderGroup.PushRect(
                            .{ chartLeft + @as(f32, @floatFromInt(snapshotIndex)) * barSpacing + 0.5 * barWidth, chartMinY + 0.5 * thisHeight, 0 },
                            .{ barWidth, thisHeight },
                            .{ thisProportion, 1, 0, 1 },
                        );
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

pub export fn DEBUGFrameEnd(memory: *platform.memory, info: *platform.debug_frame_end_info) void {
    comptime {
        // NOTE (Manav): This is hacky atm. Need to check as we're using win32.LoadLibrary()
        if (@typeInfo(platform.DEBUGFrameEndsFnPtrType).Pointer.child != @TypeOf(DEBUGFrameEnd)) {
            @compileError("Function signature mismatch!");
        }
    }
    if (@as(?*state, @alignCast(@ptrCast(memory.debugStorage)))) |debugState| {
        debugState.counterCount = 0;
        UpdateDebugRecords(debugState, recordArray[0..]);

        debugState.frameEndInfos[debugState.snapshotIndex] = info.*;

        debugState.snapshotIndex += 1;
        if (debugState.snapshotIndex >= SNAPSHOT_COUNT) {
            debugState.snapshotIndex = 0;
        }
    }
}
