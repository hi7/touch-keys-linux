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
    dx: i8,
    dy: i8,
};

pub const Touch = struct {
    tv_sec: u64,
    tv_usec: u64,
    id: ?i32,
    slot: ?i32,
    pressure: ?i32,
    x: ?i32,
    y: ?i32,
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
            .pressure = null, .x = event.value, .y = null};
    }
    if (isMtY(event)) {
        return Touch{.tv_sec = event.tv_sec, .tv_usec = event.tv_usec, 
            .id = null, .slot = null,
            .pressure = null, .x = null, .y= event.value};
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

fn toColumn(x: i32) u8 {
    return @floatToInt(u8, (@intToFloat(f32, x) + 3678.0) / 60.0);
}
fn toRow(y: i32) u8 {
    return @floatToInt(u8, (@intToFloat(f32, y) + 2478.0) / 500.0);
}

fn setX(event: InputEvent) void {
    if (isMtX(event)) {
        ensureTouchExists(event);
        touches[slot].?.x = event.value;
    }
}
fn setY(event: InputEvent) void {
    if (isMtY(event)) {
        ensureTouchExists(event);
        touches[slot].?.y = event.value;
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
            try term.writeAt(toColumn(touch.?.x.?), toRow(touch.?.y.?), "*", .{});
        }
    }
}

fn abs(comptime T: type, a: T) T {
    if (a < 0) return -a;
    return a;
}

inline fn distance(t: Touch, f: Finger) f32 {
    const t_col = @intCast(i8, toColumn(t.x.?));
    const t_row = @intCast(i8, toRow(t.y.?));
    const dx = @intToFloat(f32, abs(i8, t_col - @intCast(i8, f.col)));
    const dy = @intToFloat(f32, abs(i8, t_row - @intCast(i8, f.row)));
    return math.sqrt(dx*dx + dy*dy);
}

var finger = [5]Finger{
    Finger{.col =  1, .row = 4, .dx = 0, .dy = 0}, Finger{.col =  4, .row = 4, .dx = 0, .dy = 0},
    Finger{.col =  7, .row = 4, .dx = 0, .dy = 0}, Finger{.col = 10, .row = 4, .dx = 0, .dy = 0},
    Finger{.col = 13, .row = 4, .dx = 0, .dy = 0}};
fn nearestTo(t: Touch) Finger {
    var dist: f32 = 8000.0;
    var result: Finger = finger[0];
    for (finger) | f | {
        if (t.x != null and t.y != null) {
            const d = distance(t, f);
            if (d < dist) {
                dist = d;
                result = f;
            }
        }
    }
    return result;
}

fn updateFingers() void {
    for (touches) | t | {
        if (t != null) {
            var f = nearestTo(t.?);
            const t_col = @intCast(i8, toColumn(t.?.x.?));
            const t_row = @intCast(i8, toRow(t.?.y.?));
            f.dx = @intCast(i8, f.col) - t_col;
            f.dy = @intCast(i8, f.row) - t_row;
        }
    }
}

fn writeFinger() anyerror!void {
    for (finger) | f | {
        try term.writeAt(keys.toColumn(f.col) - 1, f.row, "{d}:{d}", .{f.dx, f.dy});
    }
}

pub fn readEvents() anyerror!void {
    while (true) {
        var event = try events.reader().readStruct(InputEvent);
        try trackEvent(event);
        if (isSyn(event)) {
            updateFingers();
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