const std = @import("std");
const keys = @import("keys.zig");
const term = @import("term.zig");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const log = std.log;
const math = std.math;
const File = fs.File;
const assert = std.debug.assert;
const expect = std.testing.expect;

var debug: u8 = 0;
pub var events: File = undefined;

pub fn openEvents(device: []const u8) anyerror!fs.File {
    var buf: [255]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "/dev/input/{s}", .{device});
    if (debug > 0) {
        log.info("Events: {s}", .{path});
    }
    return try fs.openFileAbsolute(path, .{ .read = true });
}

const Type = enum(u16) {EV_SYN = 0, EV_KEY = 1, EV_ABS = 3};
const Code = enum(u16) {ABS_X = 0, ABS_Y = 1, ABS_PRESSURE = 24, 
    ABS_MT_SLOT = 47, ABS_MT_TOUCH_MAJOR = 48, ABS_MT_TOUCH_MINOR = 49, 
    ABS_MT_ORIENTATION = 52, ABS_MT_POSITION_X = 53, ABS_MT_POSITION_Y = 54, 
    ABS_MT_TRACKING_ID = 57, ABS_MT_PRESSURE = 58,
    BTN_LEFT = 272,
    BTN_TOOL_FINGER = 325, BTN_TOOL_QUITTAP = 328, BTN_TOUCH = 330, 
    BTN_TOOL_DOUBLETAP = 333, BTN_TOOL_TRIPLETAP = 334, BTN_TOOL_QUADTAP = 335, 
};
// ABS_MT_SLOT => multi touch finger {value}

pub const Finger = struct {
    col: u8,
    row: u8,
    dc: i8,
    dr: i8,
};

pub const Touch = struct {
    tv_sec: u64,
    tv_usec: u64,
    id: ?i32,
    slot: ?i32,
    pressure: ?i32,
    x: ?f32,
    y: ?f32,
};

pub const InputEvent = extern struct {
    tv_sec: u64,
    tv_usec: u64,
    itype: u16,
    code: u16,
    value: i32
};

inline fn isSlot(event: InputEvent) bool {
    return event.code == @enumToInt(Code.ABS_MT_SLOT);
}
inline fn isPressure(event: InputEvent) bool {
    return event.code == @enumToInt(Code.ABS_MT_PRESSURE);
}
inline fn isMtX(event: InputEvent) bool {
    return event.code == @enumToInt(Code.ABS_MT_POSITION_X);
}
inline fn isMtY(event: InputEvent) bool {
    return event.code == @enumToInt(Code.ABS_MT_POSITION_Y);
}
inline fn isId(event: InputEvent) bool {
    return event.code == @enumToInt(Code.ABS_MT_TRACKING_ID);
}
inline fn noPressure(event: InputEvent) bool {
    return event.code == @enumToInt(Code.ABS_MT_TRACKING_ID) and event.value == 0;
}

fn isSyn(event: InputEvent) bool {
    return event.itype == 0 and event.code == 0 and event.value == 0;
}

fn zeroPressure(touch: Touch) bool {
    return touch.pressure != null and touch.pressure.? == 0;
}

fn createTouch(event: InputEvent) ?Touch {
    if (isPressure(event)) {
        return Touch{.tv_sec = event.tv_sec, .tv_usec = event.tv_usec,
            .id = null, .slot = null,
            .pressure = event.value, .x = null, .y = null};
    }
    if (isMtX(event)) {
        return Touch{.tv_sec = event.tv_sec, .tv_usec = event.tv_usec, 
            .id = null, .slot = null,
            .pressure = null, .x = toNormalizedX(event.value), .y = null};
    }
    if (isMtY(event)) {
        return Touch{.tv_sec = event.tv_sec, .tv_usec = event.tv_usec, 
            .id = null, .slot = null,
            .pressure = null, .x = null, .y = toNormalizedX(event.value)};
    }
    if (isId(event)) {
        return Touch{.tv_sec = event.tv_sec, .tv_usec = event.tv_usec,
            .id = event.value, .slot = null,
            .pressure = null, .x = null, .y = null};
    }
    if (isSlot(event)) {
        return Touch{.tv_sec = event.tv_sec, .tv_usec = event.tv_usec,
            .id = null, .slot = event.value,
            .pressure = null, .x = null, .y = null};
    }
    return null;
}
fn updateTouch(event: InputEvent, tch: Touch) Touch {
    var t = tch;
    if (isPressure(event)) {
        t.pressure = event.value;
    }
    if (isMtX(event)) {
        t.x = event.value;
    }
    if (isMtY(event)) {
        t.y = event.value;
    }
    if (isId(event)) {
        t.id = event.value;
    }
    if (isSlot(event)) {
        t.slot = event.value;
    }
    return t;
}

// width: 7612
fn toNormalizedX(x: i32) f32 {
    return (@intToFloat(f32, x) + 3678.0) / 7612.0;
}
fn toX(col: u8) i32 {
    return @intCast(i32, col) * 60 - 3678;
}
// height: 5065
fn toNormalizedY(y: i32) f32 {
    return (@intToFloat(f32, y) + 2478.0) / 5065.0;
}
fn xToCol(comptime T: type, x: f32) T {
    return @floatToInt(T, (x * @intToFloat(f32, keys.width)));
}
test "xToCol test" {
    assert(xToCol(u8, colToX(u8, 1)) == 1);
}
fn yToRow(comptime T: type, y: f32) T {
    return @floatToInt(T, (y * @intToFloat(f32, keys.height)));
}
test "yToRow test" {
    assert(yToRow(u8, rowToY(u8, 2)) == 2);
}
fn toY(row: u8) i32 {
    return @intCast(i32, row) * 500 - 2478;
}
fn colToX(comptime T: type, col: T) f32 {
    return @intToFloat(f32, col) / @intToFloat(f32, keys.width);
}
test "colToX test" {
    assert(eq(f32, colToX(u8, 1), 0.00959, 0.0001));
}
fn rowToY(comptime T: type, row: T) f32 {
    return @intToFloat(f32, row) / @intToFloat(f32, keys.height);
}
test "rowToY test" {
    assert(eq(f32, rowToY(u8, 4), 0.667, 0.001));
}

fn setX(event: InputEvent) void {
    if (isMtX(event)) {
        ensureTouchExists(event);
        touches[slot].?.x = toNormalizedX(event.value);
    }
}
fn setY(event: InputEvent) void {
    if (isMtY(event)) {
        ensureTouchExists(event);
        touches[slot].?.y = toNormalizedY(event.value);
    }
}
fn setId(event: InputEvent) void {
    if (isId(event)) {
        if (event.value == -1) {
            touches[slot] = null;
        } else {
            ensureTouchExists(event);
            touches[slot].?.id = event.value;
        }
    }
}
var slot: usize = 0;
fn setSlot(event: InputEvent) void {
    if (isSlot(event)) {
        slot = @intCast(usize, event.value);
        ensureTouchExists(event);
        touches[slot].?.slot = event.value;
    }
}
fn setPressure(event: InputEvent) void {
    if (isPressure(event)) {
        ensureTouchExists(event);
        touches[slot].?.pressure = event.value;
    }
}

const start: usize = 1;
var touches = [15]?Touch{null, null, null, null, null, null, null, null, null, null, null, null, null, null, null};
inline fn ensureTouchExists(e: InputEvent) void {
    if (touches[slot] == null) {
        touches[slot] = createTouch(e);
    }
}

fn trackEvent(e: InputEvent) anyerror!void {
    setSlot(e);
    setX(e);
    setY(e);
    setId(e);
    setPressure(e);
}

fn writeTouches() anyerror!void {
    for (touches) | touch | {
        if (touch != null and touch.?.x != null and touch.?.y != null) {
            const x: usize = @floatToInt(usize, (touch.?.x.? * @intToFloat(f32, keys.width)));
            const y: usize = @floatToInt(usize, (touch.?.y.? * @intToFloat(f32, keys.height)));
            try term.writeAt(x, y, "*", .{});
        }
    }
}

fn abs(comptime T: type, a: T) T {
    if (a < 0) return -a;
    return a;
}
test "abs test" {
    assert(abs(f32, -1) == 1);
    assert(abs(f32, 0.001) == 0.001);
}

fn eq(comptime T: type, a: T, b: T, eps: T) bool {
    return a < b + eps and a > b - eps;
}

test "eq test" {
    assert(eq(f32, 0.1, 0.09, 0.02) == true);
}

inline fn distance(t: Touch, f: Finger) f32 {
    const dx = abs(f32, (t.x.? + colToX(i8, f.dc)) - colToX(u8, f.col));
    const dy = abs(f32, (t.y.? + rowToY(i8, f.dr)) - rowToY(u8, f.row));
    return math.sqrt(dx*dx + dy*dy);
}
test "distance test" {
    const f = Finger{.col = 1, .row = 4, .dc = 0, .dr = 0};
    const t = Touch{.tv_sec = 1, .tv_usec = 2, .id = null, .slot = null, .pressure = null, 
        .x = toNormalizedX(-3605), .y = toNormalizedY(899)};
    assert(eq(f32, distance(t, f), 0.0, 0.0001));
}

var finger = [5]Finger{
    Finger{.col =  1, .row = 4, .dc = 0, .dr = 0}, 
    Finger{.col =  4, .row = 4, .dc = 0, .dr = 0}, 
    Finger{.col =  7, .row = 4, .dc = 0, .dr = 0}, 
    Finger{.col = 10, .row = 4, .dc = 0, .dr = 0}, 
    Finger{.col = 13, .row = 4, .dc = 0, .dr = 0}};
fn indexOfFingerNearestTo(t: Touch) usize {
    var dist: f32 = 8000.0;
    var index: usize = 0;
    for (finger) | f, i | {
        if (t.x != null and t.y != null) {
            const d = distance(t, f);
            if (d < dist) {
                dist = d;
                index = i;
            }
        }
    }
    return index;
}

test "indexOfFingerNearestTo() test" {
    for (finger) | f, i | {
        var t = Touch{.tv_sec = 1, .tv_usec = 2, .id = null, .slot = null, 
            .pressure = null, .x = colToX(u8, f.col), .y = rowToY(u8, f.row)};
        assert(indexOfFingerNearestTo(t) == i);
    }
}

fn resetFinger() void {
    for (finger) | _, i | {
        finger[i].dc = 0;
        finger[i].dr = 0;
    }
}

fn fingerDown() u8 {
    var count: u8 = 0;
    for (touches) | touch | {
        if (touch != null and touch.?.x != null and touch.?.y != null) {
            count += 1;
        }
    }
    return count;
}

fn updateFingerDelta() void {
    for (touches) | touch | {
        if (touch != null and touch.?.x != null and touch.?.y != null) {
            const t = touch.?;
            const i = indexOfFingerNearestTo(t);
            var f = finger[i];
            f.dc = xToCol(i8, t.x.?) - @intCast(i8, f.col);
            f.dr = yToRow(i8, t.y.?) - @intCast(i8, f.row);
            finger[i] = f;
        }
    }
}
test "updateFingerDelta() test" {
    touches[0] = Touch{.tv_sec = 1, .tv_usec = 2, .id = null, .slot = null, .pressure = null, 
        .x = colToX(u8, 5), .y = rowToY(u8, 4)};
    assert(indexOfFingerNearestTo(touches[0].?) == 1);
    updateFingerDelta();
    assert(eq(f32, colToX(u8, finger[1].col) + colToX(i8, finger[1].dc), touches[0].?.x.?, 0.000001));
    assert(eq(f32, rowToY(u8, finger[1].row) + rowToY(i8, finger[1].dr), touches[0].?.y.?, 0.000001));
}

var setDelta: bool = true;
fn updateFinger() void {
    var down = fingerDown();
    if (setDelta and down == 5) {
        updateFingerDelta();
        setDelta = false;
    }
    if (down == 0){
        resetFinger();
        setDelta = true;
    }
}

inline fn fingerX(tx: f32, fdx: f32) usize {
    var ix = tx + fdx;
    if (ix < 0) {
        ix = 0;
    }
    return @floatToInt(usize, (ix * @intToFloat(f32, keys.width)));
}
test "fingerX test" {
    assert(fingerX(colToX(u8, 1), 0) == 1);
}
inline fn fingerY(ty: f32, fdy: f32) usize {
    var iy = ty + fdy;
    if (iy < 0) {
        iy = 0;
    }
    return @floatToInt(usize, (iy * @intToFloat(f32, keys.height)));
}
test "fingerY test" {
    assert(fingerY(rowToY(u8, 4), 0) == 4);
}
fn writeFinger() anyerror!void {
    for (finger) | f, i | {
        try term.writeAt(keys.toColumn(usize, f.col), f.row + 4, "{d}({d:.2},{d:.2})", .{i, f.dc, f.dr});
    }
    for (touches) | touch | {
        if (touch != null and touch.?.x != null and touch.?.y != null) {
            const t = touch.?;
            const i = indexOfFingerNearestTo(t);
            const f = finger[i];
            try term.writeAt(keys.toColumn(usize, 
                @intCast(usize, xToCol(i8, t.x.?) + f.dc)), 
                @intCast(usize, (yToRow(i8, t.y.?) + f.dr)), "T{d}", .{i});
        }
    }
}

pub fn readEvents() anyerror!void {
    while (true) {
        var event = try events.reader().readStruct(InputEvent);
        try trackEvent(event);
        if (isSyn(event)) {
            updateFinger();
            try term.clear();
            try keys.write();
            try writeTouches();
            try writeFinger();
        }
    }
}

const ExtractPropertyError = error{
    NoStartIndex,
    MatchNotFound,
    LineDelimiterNotFound,
};

fn extractWithMatchToEOL(match: []const u8, text: []const u8, start_index: ?usize) anyerror![]const u8 {
    return extractToEOL(match, text, start_index, true);
}
fn extractWithoutMatchToEOL(match: []const u8, text: []const u8, start_index: ?usize) anyerror![]const u8 {
    return extractToEOL(match, text, start_index, false);
}

fn extractToEOL(match: []const u8, text: []const u8, start_index: ?usize, include_match: bool) anyerror![]const u8 {
    if (start_index == null) {
        return ExtractPropertyError.NoStartIndex;
    }
    var index1 = mem.indexOfPos(u8, text, start_index.?, match);
    if (index1 == null) {
        return ExtractPropertyError.NoStartIndex;
    }
    if (!include_match) {
        index1.? = index1.? + match.len;
    }
    if (text[index1.?] == '"') {
        index1.? += 1;
    }

    var index2 = mem.indexOfPos(u8, text, index1.?, "\n");
    if (index2 == null) {
        return ExtractPropertyError.NoStartIndex;
    }
    return text[(index1.?)..(index2.? - 1)];
}

fn previousEOL(text: []const u8, start_index: usize) ?usize {
    var i: usize = start_index;
    while (i > 0 and text[i] != '\n') {
        i -= 1;
    }
    return i;
}

const ReadDeviceError = error{
    DeviceNotFound,
};

pub fn readDevice() anyerror![]const u8 {
    var devices: File = try fs.openFileAbsolute("/proc/bus/input/devices", .{ .read = true });
    var buf: [10240]u8 = undefined;
    const bytes_read = try devices.readAll(&buf);
    devices.close();

    const devices_text = buf[0..bytes_read];
    const i = mem.lastIndexOf(u8, devices_text, "Trackpad");
    if (i != null) {
        if (debug > 0) {
            const name = extractWithoutMatchToEOL("Name=", devices_text, previousEOL(devices_text, i.?));
            if (debug > 1) {
                const handlers = extractWithoutMatchToEOL("Handlers=", devices_text, i.?);
                log.info("Trackpad: {s}, Handlers: {s}", .{name, handlers});
            } else {
                log.info("Trackpad: {s}", .{name});
            }
        }
        return extractWithMatchToEOL("event", devices_text, i.?);
    }
    return error.DeviceNotFound;
}

test "events file test" {
    const d = try readDevice();
    const e = try openEvents(d);
    assert(@TypeOf(e) == fs.File);
    e.close();
}