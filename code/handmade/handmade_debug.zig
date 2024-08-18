//! Provides debug functionality
//!
//! __Requirements when importing:__
//! - `const debug = @import("handmade_debug.zig");` must be within the top two lines of the file.

const std = @import("std");
const platform = @import("handmade_platform");

const h = struct {
    usingnamespace @import("intrinsics");

    usingnamespace @import("handmade_asset.zig");
    usingnamespace @import("handmade_data.zig");
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

const debug_text_op = enum {
    DEBUGTextOp_DrawText,
    DEBUGTextOp_SizeText,
};

const debug_counter_snapshot = struct {
    hitCount: u32 = 0,
    cycleCount: u64 = 0,
};

const debug_counter_state = struct {
    fileName: ?[*:0]const u8,
    blockName: ?[*:0]const u8,

    lineNumber: u32,
};

const debug_frame_region = struct {
    record: *platform.debug_record,
    cycleCount: u64,
    laneIndex: u16,
    colourIndex: u16,
    maxT: f32,
    minT: f32,
};

const MAX_REGIONS_PER_FRAME = 4096 * 2; // NOTE (Manav): we need a bigger number
const debug_frame = struct {
    beginClock: u64,
    endClock: u64,
    wallSecondsElapsed: f32,

    regionCount: u32,
    regions: []debug_frame_region,
};

const open_debug_block = struct {
    startingFrameIndex: u32,
    openingEvent: *platform.debug_event,
    source: *platform.debug_record,
    parent: ?*open_debug_block,

    nextFree: ?*open_debug_block,
};

const debug_thread = struct {
    id: u32,
    laneIndex: u32,
    firstOpenBlock: ?*open_debug_block,
    next: ?*debug_thread,
};

const debug_state = struct {
    initialized: bool,

    highPriorityQueue: *platform.work_queue,

    debugArena: h.memory_arena,
    renderGroup: *h.render_group,
    debugFont: ?*h.loaded_font,
    debugFontInfo: *h.hha_font,

    menuP: h.v2,
    menuActive: bool,
    hotMenuIndex: u32,

    leftEdge: f32,
    atY: f32,
    fontScale: f32,
    fontID: h.font_id,
    globalWidth: f32,
    globalHeight: f32,

    scopeToRecord: ?*platform.debug_record,

    collateArena: h.memory_arena,
    collateTemp: h.temporary_memory,

    collationArrayIndex: u32,
    collationFrame: ?*debug_frame,
    frameBarLaneCount: u32,
    frameCount: u32,
    frameBarScale: f32,
    paused: bool,

    profileOn: bool,
    profileRect: h.rect2,

    frames: []debug_frame,
    firstThread: ?*debug_thread,
    firstFreeBlock: ?*open_debug_block,
};

/// sum of all counters (timed  + named)
pub const debugRecordsCount = __COUNTER__() + 2; // TOOD (Manav), one on Start and another on End

pub const TIMED_FUNCTION = platform.TIMED_FUNCTION;
pub const TIMED_FUNCTION__impl = platform.TIMED_FUNCTION__impl;

pub const TIMED_BLOCK = platform.TIMED_BLOCK;
pub const TIMED_BLOCK__impl = platform.TIMED_BLOCK__impl;

/// The function definition is replaced with
/// ```
/// {
///     return #counter;
/// }
/// ```
/// where #counter is the total no. of <...>_impl callsites.
pub inline fn __COUNTER__() comptime_int
// AUTOGENERATED ----------------------------------------------------------
{
    return 45;
}
// AUTOGENERATED ----------------------------------------------------------

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

inline fn DEBUGGetStateMem(memory: ?*platform.memory) ?*debug_state {
    if (memory) |_| {
        const debugState: *debug_state = @alignCast(@ptrCast(memory.?.debugStorage));
        platform.Assert(debugState.initialized);

        return debugState;
    } else {
        return null;
    }
}

inline fn DEBUGGetState() ?*debug_state {
    const result = DEBUGGetStateMem(platform.debugGlobalMemory);

    return result;
}

pub fn Start(assets: *h.game_assets, width: u32, height: u32) void {
    var block = TIMED_FUNCTION__impl(__COUNTER__(), @src()).Init(.{});
    defer block.End();

    if (@as(?*debug_state, @alignCast(@ptrCast(platform.debugGlobalMemory.?.debugStorage)))) |debugState| {
        if (!debugState.initialized) {
            debugState.highPriorityQueue = platform.debugGlobalMemory.?.highPriorityQueue;

            debugState.debugArena.Initialize(
                platform.debugGlobalMemory.?.debugStorageSize - @sizeOf(debug_state),
                @ptrCast(@as([*]debug_state, @ptrCast(debugState)) + 1),
            );

            debugState.renderGroup = h.render_group.Allocate(assets, &debugState.debugArena, platform.MegaBytes(16), false);

            debugState.paused = false;
            debugState.scopeToRecord = null;

            debugState.initialized = true;

            debugState.collateArena.SubArena(&debugState.debugArena, 4, platform.MegaBytes(32));
            debugState.collateTemp = h.BeginTemporaryMemory(&debugState.collateArena);

            RestartCollation(debugState, 0);
        }

        h.BeginRender(debugState.renderGroup);
        debugState.debugFont = debugState.renderGroup.PushFont(debugState.fontID);
        debugState.debugFontInfo = debugState.renderGroup.assets.GetFontInfo(debugState.fontID);

        debugState.globalWidth = @floatFromInt(width);
        debugState.globalHeight = @floatFromInt(height);

        var matchVectorFont = h.asset_vector{};
        var weightVectorFont = h.asset_vector{};

        matchVectorFont.e[@intFromEnum(h.asset_tag_id.Tag_FontType)] = @floatFromInt(@as(i32, @intFromEnum(h.asset_font_type.FontType_Debug)));
        weightVectorFont.e[@intFromEnum(h.asset_tag_id.Tag_FontType)] = 1.0;

        debugState.fontID = h.GetBestMatchFontFrom(
            assets,
            .Asset_Font,
            &matchVectorFont,
            &weightVectorFont,
        );

        debugState.fontScale = 1;
        debugState.renderGroup.Orthographic(width, height, 1);
        debugState.leftEdge = -0.5 * @as(f32, @floatFromInt(width));

        const info = assets.GetFontInfo(debugState.fontID);
        debugState.atY = 0.5 * @as(f32, @floatFromInt(height)) - h.GetStartingBaselineY(info) * debugState.fontScale;
    }
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

/// `colour = .{ 1, 1, 1, 1 }` by default
fn DEBUGTextOp(debugState: ?*debug_state, op: debug_text_op, p: h.v2, string: []const u8, colour_: h.v4) h.rect2 {
    var result: h.rect2 = h.rect2.InvertedInfinity();

    var colour = colour_;

    if (debugState) |_| {
        if (debugState.?.debugFont) |font| {
            const renderGroup: *h.render_group = debugState.?.renderGroup;
            const info: *h.hha_font = debugState.?.debugFontInfo;

            var prevCodePoint: u32 = 0;
            var charScale = debugState.?.fontScale;
            const atY: f32 = h.Y(p);
            var atX: f32 = h.X(p);

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
                    charScale = debugState.?.fontScale * h.Clampf01(cScale * @as(f32, @floatFromInt(at[2] - '0')));
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
                        const bitmapID = h.GetBitmapForGlyph(renderGroup.assets, info, font, codePoint);
                        const info_ = renderGroup.assets.GetBitmapInfo(bitmapID);

                        const bitmapScale = charScale * @as(f32, @floatFromInt(info_.dim[1]));
                        const bitmapOffset: h.v3 = .{ atX, atY, 0 };

                        switch (op) {
                            .DEBUGTextOp_DrawText => renderGroup.PushBitmap2(bitmapID, bitmapScale, bitmapOffset, colour),
                            .DEBUGTextOp_SizeText => {
                                if (renderGroup.assets.GetBitmap(bitmapID, renderGroup.generationID)) |bitmap| {
                                    const dim = h.GetBitmapDim(renderGroup, bitmap, bitmapScale, bitmapOffset);
                                    const glyphDim = h.rect2.InitMinDim(h.XY(dim.p), dim.size);

                                    result = h.rect2.Union(result, glyphDim);
                                }
                            },
                        }
                    }

                    prevCodePoint = @intCast(codePoint);

                    at += 1;
                }
            }
        }
    }

    return result;
}

/// `colour = .{ 1, 1, 1, 1 }` by default
fn DEBUGTextOutAt(p: h.v2, string: []const u8, colour: h.v4) void {
    if (DEBUGGetState()) |debugState| {
        const renderGroup: *h.render_group = debugState.renderGroup;
        _ = renderGroup;

        _ = DEBUGTextOp(debugState, .DEBUGTextOp_DrawText, p, string, colour);
    }
}

fn DEBUGGetTextSize(debugState: *debug_state, string: []const u8) h.rect2 {
    const result: h.rect2 = DEBUGTextOp(debugState, .DEBUGTextOp_SizeText, .{ 0, 0 }, string, .{ 1, 1, 1, 1 });

    return result;
}

fn DEBUGTextLine(string: []const u8) void {
    if (DEBUGGetState()) |debugState| {
        const renderGroup: *h.render_group = debugState.renderGroup;
        if (renderGroup.PushFont(debugState.fontID)) |_| {
            const info = renderGroup.assets.GetFontInfo(debugState.fontID);

            DEBUGTextOutAt(.{ debugState.leftEdge, debugState.atY }, string, .{ 1, 1, 1, 1 });

            debugState.atY -= h.GetLineAdvanceFor(info) * debugState.fontScale;
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

fn DrawDebugMainMenu(debugState: *debug_state, renderGroup: *h.render_group, mouseP: h.v2) void {
    _ = renderGroup;
    const menuItems = [_][]const u8{
        "Toggle Profile Graph",
        "Toggle Debug Collation",
        "Toggle Framerate Counter",
        "Mark Loop Point",
        "Toggle Entity Bounds",
        "Toggle World Chunk Bounds",
    };

    var newHotMenuIndex: u32 = menuItems.len;
    var bestDistanceSq: f32 = platform.F32MAXIMUM;

    const menuRadius = 200.0;
    const angleStep: f32 = platform.Tau32 / @as(f32, @floatFromInt(menuItems.len));
    for (0..menuItems.len) |menuItemIndex| {
        const text: []const u8 = menuItems[menuItemIndex];

        var itemColour: h.v4 = .{ 1, 1, 1, 1 };
        if (menuItemIndex == debugState.hotMenuIndex) {
            itemColour = .{ 1, 1, 0, 1 };
        }
        const angle = @as(f32, @floatFromInt(menuItemIndex)) * angleStep;

        // const textP: h.v2 = debugState.menuP + menuRadius * h.Arm2(angle);
        const textP: h.v2 = h.Add(debugState.menuP, h.Scale(h.Arm2(angle), menuRadius));

        const thisDistanceSq = h.LengthSq(h.Sub(textP, mouseP));
        if (bestDistanceSq > thisDistanceSq) {
            newHotMenuIndex = @intCast(menuItemIndex);
            bestDistanceSq = thisDistanceSq;
        }

        const textBounds: h.rect2 = DEBUGGetTextSize(debugState, text);
        DEBUGTextOutAt(h.Sub(textP, h.Scale(textBounds.GetDim(), 0.5)), text, itemColour);
    }

    debugState.hotMenuIndex = newHotMenuIndex;
}

pub fn End(input: *platform.input, drawBuffer: *h.loaded_bitmap) void {
    TIMED_FUNCTION(.{});
    var block = TIMED_FUNCTION__impl(__COUNTER__() + 1, @src()).Init(.{});
    defer block.End();

    if (DEBUGGetState()) |debugState| {
        const renderGroup: *h.render_group = debugState.renderGroup;
        var hotRecord: ?*platform.debug_record = null;

        const mouseP: h.v2 = h.V2(input.mouseX, input.mouseY);

        if (input.mouseButtons[@intFromEnum(platform.input_mouse_button.PlatformMouseButton_Right)].endedDown > 0) {
            if (input.mouseButtons[@intFromEnum(platform.input_mouse_button.PlatformMouseButton_Right)].halfTransitionCount > 0) {
                debugState.menuP = mouseP;
            }
            DrawDebugMainMenu(debugState, renderGroup, mouseP);
        } else if (input.mouseButtons[@intFromEnum(platform.input_mouse_button.PlatformMouseButton_Right)].halfTransitionCount > 0) {
            DrawDebugMainMenu(debugState, renderGroup, mouseP);
            switch (debugState.hotMenuIndex) {
                0 => debugState.profileOn = !debugState.profileOn,
                1 => debugState.paused = !debugState.paused,

                else => {},
            }
        }

        const info = debugState.debugFontInfo;
        if (debugState.debugFont) |_| {
            if (platform.ignore) {
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

                    if (counter.blockName) |blockName| {
                        if (cycleCount.max > 0) {
                            const barWidth = 4;
                            const chartLeft = 0;
                            const chartMinY = debugState.atY;
                            const chartHeight = info.ascenderHeight * debugState.fontScale;

                            const scale: f32 = @floatCast(1 / cycleCount.max);
                            for (0..counter.snapshots.len) |snapshotIndex| {
                                const thisProportion = scale * @as(f32, @floatFromInt(counter.snapshots[snapshotIndex].cycleCount));
                                const thisHeight = chartHeight * thisProportion;
                                renderGroup.PushRect(
                                    .{ chartLeft + @as(f32, @floatFromInt(snapshotIndex)) * barWidth + 0.5 * barWidth, chartMinY + 0.5 * thisHeight, 0 },
                                    .{ barWidth, thisHeight },
                                    .{ thisProportion, 1, 0, 1 },
                                );
                            }
                        }

                        if (!platform.ignore) {
                            var textBuffer = [1]u8{0} ** 256;
                            const buffer = std.fmt.bufPrint(textBuffer[0..], "{s:32}({:4}) - {:10}cy {:8}h {:10}cy/h\n", .{
                                blockName,
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
            }

            if (debugState.frameCount != 0) {
                var textBuffer = [1]u8{0} ** 256;
                const buffer = std.fmt.bufPrint(textBuffer[0..], "Last Frame Time: {d:5.2}ms\n", .{
                    debugState.frames[debugState.frameCount - 1].wallSecondsElapsed * 1000,
                }) catch |err| {
                    std.debug.print("{}\n", .{err});
                    return;
                };

                DEBUGTextLine(buffer);
            }

            if (debugState.profileOn) {
                debugState.renderGroup.Orthographic(@intFromFloat(debugState.globalWidth), @intFromFloat(debugState.globalHeight), 1);

                debugState.profileRect = h.rect2.InitMinMax(.{ 50, 50 }, .{ 200, 200 });
                renderGroup.PushRect2(debugState.profileRect, 0, .{ 0, 0, 0, 0.25 });

                var laneHeight: f32 = 20.0;
                const laneCount: f32 = @floatFromInt(debugState.frameBarLaneCount);

                const barSpacing = 4.0;
                var maxFrame = debugState.frameCount;
                if (maxFrame > 10) {
                    maxFrame = 10;
                }

                if (laneCount > 0 and maxFrame > 0) {
                    const pixelsPerFramePlusSpacing = h.Y(debugState.profileRect.GetDim()) / @as(f32, @floatFromInt(maxFrame));
                    const pixelsPerFrame = pixelsPerFramePlusSpacing - barSpacing;
                    laneHeight = pixelsPerFrame / laneCount;
                }

                const barHeight = laneHeight * laneCount;
                const barPlusSpacing = barHeight + barSpacing;
                const chartLeft = h.X(debugState.profileRect.min);
                const chartHeight = barPlusSpacing * @as(f32, @floatFromInt(maxFrame));
                _ = chartHeight;
                const chartWidth = h.X(debugState.profileRect.GetDim());
                const chartTop = h.Y(debugState.profileRect.max);
                const scale = chartWidth * debugState.frameBarScale;

                const colours = [_]h.v3{
                    .{ 1, 0, 0 },
                    .{ 0, 1, 0 },
                    .{ 0, 0, 1 },
                    .{ 1, 1, 0 },
                    .{ 0, 1, 1 },
                    .{ 1, 0, 1 },
                    .{ 1, 0.5, 0 },
                    .{ 1, 0, 0.5 },
                    .{ 0.5, 1, 0 },
                    .{ 0, 1, 0.5 },
                    .{ 0.5, 0, 1 },
                    .{ 0, 0.5, 1 },
                };

                for (0..maxFrame) |frameIndex| {
                    const frame: *debug_frame = &debugState.frames[debugState.frameCount - (frameIndex + 1)];

                    const stackX: f32 = chartLeft;
                    const stackY: f32 = chartTop - @as(f32, @floatFromInt(frameIndex)) * barPlusSpacing;

                    for (0..frame.regionCount) |regionIndex| {
                        const region: *debug_frame_region = &frame.regions[regionIndex];

                        // const colour = colours[regionIndex % colours.len];
                        const colour = colours[region.colourIndex % colours.len];
                        const thisMinX = stackX + scale * region.minT;
                        const thisMaxX = stackX + scale * region.maxT;
                        const regionRect = h.rect2.InitMinMax(
                            .{ thisMinX, stackY - laneHeight * @as(f32, @floatFromInt(region.laneIndex + 1)) },
                            .{ thisMaxX, stackY - laneHeight * @as(f32, @floatFromInt(region.laneIndex)) },
                        );
                        renderGroup.PushRect2(regionRect, 0, h.ToV4(colour, 1));

                        if (regionRect.IsInRect(mouseP)) {
                            const record: *platform.debug_record = region.record;

                            var textBuffer = [1]u8{0} ** 256;
                            const buffer = std.fmt.bufPrint(textBuffer[0..], "{s}: {:10}cy [{s}({d})]\n", .{
                                record.blockName.?,
                                region.cycleCount,
                                record.fileName.?,
                                record.lineNumber,
                            }) catch |err| {
                                std.debug.print("{}\n", .{err});
                                return;
                            };

                            DEBUGTextOutAt(h.Add(mouseP, .{ 0, 10 }), buffer, .{ 1, 1, 1, 1 });

                            hotRecord = record;
                        }
                    }
                }

                // renderGroup.PushRect(
                //     .{ chartLeft + 0.5 * chartWidth, chartMinY + chartHeight, 0 },
                //     .{ chartWidth, 1 },
                //     .{ 1, 1, 1, 1 },
                // );
            }
        }
        if (platform.WasPressed(&input.mouseButtons[@intFromEnum(platform.input_mouse_button.PlatformMouseButton_Left)])) {
            if (hotRecord) |_| {
                debugState.scopeToRecord = hotRecord;
            } else {
                debugState.scopeToRecord = null;
            }
            RefreshCollation(debugState);
        }

        renderGroup.TiledRenderGroupToOutput(debugState.highPriorityQueue, drawBuffer);
        h.EndRender(renderGroup);
    }
}

inline fn GetLaneFromThreadIndex(debugState: *debug_state, threadIndex: u32) u32 {
    const result: u32 = 0;

    _ = debugState;
    _ = threadIndex;

    return result;
}

fn GetDebugThread(debugState: *debug_state, threadID: u32) *debug_thread {
    var result: ?*debug_thread = null;
    var thread = debugState.firstThread;
    while (thread != null) : (thread = thread.?.next) {
        if (thread.?.id == threadID) {
            result = thread;
            break;
        }
    }

    if (result == null) {
        result = debugState.collateArena.PushStruct(debug_thread);
        result.?.id = threadID;
        result.?.laneIndex = debugState.frameBarLaneCount;
        debugState.frameBarLaneCount += 1;
        result.?.firstOpenBlock = null;
        result.?.next = debugState.firstThread;
        debugState.firstThread = result;
    }

    return result.?;
}

fn AddRegion(_: *debug_state, currentFrame: *debug_frame) *debug_frame_region {
    platform.Assert(currentFrame.regionCount < MAX_REGIONS_PER_FRAME);
    const result: *debug_frame_region = &currentFrame.regions[currentFrame.regionCount];
    currentFrame.regionCount += 1;

    return result;
}

fn StringsAreEqual(strA: [*:0]const u8, strB: [*:0]const u8) bool {
    var a = strA;
    var b = strB;

    while ((a[0] != 0 and b[0] != 0) and (a[0] == b[0])) {
        a += 1;
        b += 1;
    }

    const result = a[0] == 0 and b[0] == 0;

    return result;
}

fn RestartCollation(debugState: *debug_state, invalidArrayIndex: u32) void {
    h.EndTemporaryMemory(debugState.collateTemp);
    debugState.collateTemp = h.BeginTemporaryMemory(&debugState.collateArena);

    debugState.firstThread = null;
    debugState.firstFreeBlock = null;

    debugState.frames = debugState.collateArena.PushSlice(debug_frame, platform.MAX_DEBUG_EVENT_ARRAY_COUNT * 4);
    debugState.frameBarLaneCount = 0;
    debugState.frameCount = 0;
    debugState.frameBarScale = 1.0 / 60000000.0;

    debugState.collationArrayIndex = invalidArrayIndex + 1;
    debugState.collationFrame = null;
}

inline fn GetRecordFrom(block: ?*open_debug_block) ?*platform.debug_record {
    const result = if (block) |_| block.?.source else null;

    return result;
}

fn CollateDebugRecords(debugState: *debug_state, invalidArrayIndex: u32) void {
    while (true) : (debugState.collationArrayIndex += 1) {
        if (debugState.collationArrayIndex == platform.MAX_DEBUG_EVENT_ARRAY_COUNT) {
            debugState.collationArrayIndex = 0;
        }
        const eventArrayIndex = debugState.collationArrayIndex;

        if (eventArrayIndex == invalidArrayIndex) {
            break;
        }

        for (0..platform.globalDebugTable.eventCount[eventArrayIndex]) |eventIndex| {
            const event: *platform.debug_event = &platform.globalDebugTable.events[eventArrayIndex][eventIndex];
            const source: *platform.debug_record = &platform.globalDebugTable.records[event.translationUnit][event.debugRecordIndex];

            if (event.eventType == .DebugEvent_FrameMarker) {
                if (debugState.collationFrame) |_| {
                    debugState.collationFrame.?.endClock = event.clock;
                    debugState.collationFrame.?.wallSecondsElapsed = event.data.secondsElapsed;
                    debugState.frameCount += 1; // NOTE (Manav): this can increase beyond the debugState.frames.len

                    // const clockRange: f32 = @floatFromInt(debugState.collationFrame.?.endClock - debugState.collationFrame.?.beginClock);

                    // if (clockRange > 0) {
                    //     const frameBarScale = 1 / clockRange;
                    //     if (debugState.frameBarScale > frameBarScale) {
                    //         debugState.frameBarScale = frameBarScale;
                    //     }
                    // }
                }

                debugState.collationFrame = &debugState.frames[debugState.frameCount];
                debugState.collationFrame.?.beginClock = event.clock;
                debugState.collationFrame.?.endClock = 0;
                debugState.collationFrame.?.regionCount = 0;
                debugState.collationFrame.?.regions = debugState.collateArena.PushSlice(debug_frame_region, MAX_REGIONS_PER_FRAME);
                debugState.collationFrame.?.wallSecondsElapsed = 0;
            } else if (debugState.collationFrame) |_| {
                const frameIndex: u32 = debugState.frameCount -% 1; // TODO (Manav): ignore this for now.
                const thread: *debug_thread = GetDebugThread(debugState, event.data.tc.threadID);
                const relativeClock = event.clock -% debugState.collationFrame.?.beginClock;
                _ = relativeClock;

                if (StringsAreEqual("DrawRectangle", source.blockName.?)) {
                    // @breakpoint();
                }

                if (event.eventType == .DebugEvent_BeginBlock) {
                    var debugBlock = debugState.firstFreeBlock;
                    if (debugBlock) |_| {
                        debugState.firstFreeBlock = debugBlock.?.nextFree;
                    } else {
                        debugBlock = debugState.collateArena.PushStruct(open_debug_block);
                    }

                    debugBlock.?.startingFrameIndex = frameIndex;
                    debugBlock.?.openingEvent = event;
                    debugBlock.?.parent = thread.firstOpenBlock;
                    debugBlock.?.source = source;
                    thread.firstOpenBlock = debugBlock;
                    debugBlock.?.nextFree = null;
                } else if (event.eventType == .DebugEvent_EndBlock) {
                    if (thread.firstOpenBlock) |_| {
                        const matchingBlock: *open_debug_block = thread.firstOpenBlock.?;
                        const openingEvent: *platform.debug_event = matchingBlock.openingEvent;
                        if (openingEvent.data.tc.threadID == event.data.tc.threadID and
                            openingEvent.debugRecordIndex == event.debugRecordIndex and
                            openingEvent.translationUnit == event.translationUnit)
                        {
                            if (matchingBlock.startingFrameIndex == frameIndex) {
                                if (GetRecordFrom(matchingBlock.parent) == debugState.scopeToRecord) {
                                    const minT: f32 = @floatFromInt(openingEvent.clock -% debugState.collationFrame.?.beginClock);
                                    const maxT: f32 = @floatFromInt(event.clock -% debugState.collationFrame.?.beginClock);
                                    const thresholdT = 0.01;

                                    if ((maxT - minT) > thresholdT) {
                                        const region: *debug_frame_region = AddRegion(debugState, debugState.collationFrame.?);
                                        region.record = source;
                                        region.cycleCount = event.clock - openingEvent.clock;
                                        region.laneIndex = @intCast(thread.laneIndex);
                                        region.minT = minT;
                                        region.maxT = maxT;
                                        region.colourIndex = openingEvent.debugRecordIndex;
                                    }
                                }
                            } else {
                                // record all frames in between and begin/end spans
                            }

                            thread.firstOpenBlock.?.nextFree = debugState.firstFreeBlock;
                            debugState.firstFreeBlock = thread.firstOpenBlock;
                            thread.firstOpenBlock = matchingBlock.parent;
                        } else {
                            // record span that goes to the beginning of the frames series?
                        }
                    }
                } else {
                    platform.InvalidCodePath("Invalid event type");
                }
            }
        }
    }
}

fn RefreshCollation(debugState: *debug_state) void {
    RestartCollation(debugState, platform.globalDebugTable.currentEventArrayIndex);
    CollateDebugRecords(debugState, platform.globalDebugTable.currentEventArrayIndex);
}

pub export fn DEBUGFrameEnd(memory: *platform.memory) *platform.debug_table {
    comptime {
        // NOTE (Manav): This is hacky atm. Need to check as we're using win32.LoadLibrary()
        if (@typeInfo(platform.DEBUGFrameEndsFnPtrType).Pointer.child != @TypeOf(DEBUGFrameEnd)) {
            @compileError("Function signature mismatch!");
        }
    }

    platform.globalDebugTable.recordCount[0] = debugRecordsCount;

    platform.globalDebugTable.currentEventArrayIndex += 1;
    if (platform.globalDebugTable.currentEventArrayIndex >= platform.globalDebugTable.events.len) {
        platform.globalDebugTable.currentEventArrayIndex = 0;
    }

    const arrayIndex_eventIndex = h.AtomicExchange(
        u64,
        @ptrCast(&platform.globalDebugTable.indices),
        @as(u64, platform.globalDebugTable.currentEventArrayIndex) << 32,
    );

    const indices: platform.debug_table.packed_indices = @bitCast(arrayIndex_eventIndex);

    const eventArrayIndex = indices.eventArrayIndex;
    const eventCount = indices.eventIndex;
    platform.globalDebugTable.eventCount[eventArrayIndex] = eventCount;

    if (DEBUGGetStateMem(memory)) |debugState| {
        if (!debugState.paused) {
            if (debugState.frameCount >= platform.MAX_DEBUG_EVENT_ARRAY_COUNT * 4 - 1) { // NOTE (Manav): check note in CollateDebugRecords
                RestartCollation(debugState, platform.globalDebugTable.currentEventArrayIndex);
            }
            CollateDebugRecords(debugState, platform.globalDebugTable.currentEventArrayIndex);
        }
    }

    return platform.globalDebugTable;
}
